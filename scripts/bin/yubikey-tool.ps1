<#
.SYNOPSIS
	YubiKey Tool for Windows - GPG Agent & Touch Detection

.DESCRIPTION
	Detects GPG + YubiKey touch operations and displays Windows Toast notifications.
	Manages gpg-agent and gpg-bridge together, cleaning up and restarting processes on launch.
	Runs with a system tray icon for easy access to restart, log viewing, and exit.

	Detection method:
	- Periodically runs 'gpg --card-status' (polling)
	- If the command hangs (over 2 seconds), it's considered waiting for touch
	- Displays a Toast notification to prompt the user to touch

	Tray icon states:
	- Normal: Monitoring state (imageres.dll index 321)
	- Touch: Touch required (imageres.dll index 300)
	- NoCard: YubiKey not detected (imageres.dll index 54)
	- Error: Connection error, auto-restart (imageres.dll index 270)
	- Stopped: Agents stopped (imageres.dll index 93)

	System tray menu:
	- Restart Agents: Restart gpg-agent and gpg-bridge
	- Stop Agents: Stop gpg-agent and gpg-bridge
	- Show Log: Open log file in Notepad
	- Exit: Stop the tool

.PARAMETER CheckInterval
	Interval for gpg --card-status checks (milliseconds)

.PARAMETER HangTimeout
	Time until gpg --card-status is considered hanging (milliseconds)

.PARAMETER GpgBridgePath
	Path to gpg-bridge.exe (required, default: $env:USERPROFILE\.local\bin\gpg-bridge.exe)

.PARAMETER GpgBridgeArgs
	Arguments to pass to gpg-bridge (default: --extra 127.0.0.1:4321)

.PARAMETER AddStartup
	Register shortcut to Windows startup (shell:startup)

.PARAMETER RemoveStartup
	Remove shortcut from Windows startup

.PARAMETER Stop
	Stop all running yubikey-tool instances and GPG processes

.EXAMPLE
	.\yubikey-tool.ps1

.EXAMPLE
	.\yubikey-tool.ps1 -Stop

.EXAMPLE
	.\yubikey-tool.ps1 -GpgBridgeArgs "--extra 127.0.0.1:4321"

.EXAMPLE
	.\yubikey-tool.ps1 -AddStartup

.NOTES
	Created: 2026-01-07
	gpg-bridge: https://github.com/BusyJay/gpg-bridge

	Requirements:
	- PowerShell 7 or later
	- Gpg4Win 4.4.x
	- GnuPG 2.4.x (gpg.exe)
	- gpg-bridge.exe 0.1.1 ($env:USERPROFILE\.local\bin\gpg-bridge.exe)
	- YubiKey with touch policy enabled
	- Windows 10 1903 or later

	Optional:
	- BurntToast module (Install-Module BurntToast) for enhanced notifications
#>

[CmdletBinding()]
param(
	[Parameter()]
	[int]$CheckInterval = 2000,  # 2 seconds

	[Parameter()]
	[int]$HangTimeout = 2000,    # 2 seconds

	[Parameter()]
	[string]$GpgBridgePath = (Join-Path $env:USERPROFILE ".local\bin\gpg-bridge.exe"),

	[Parameter()]
	[string]$GpgBridgeArgs = "--extra 127.0.0.1:4321",

	[Parameter()]
	[switch]$AddStartup = $false,

	[Parameter()]
	[switch]$RemoveStartup = $false,

	[Parameter()]
	[switch]$Stop = $false
)

# Error action preference
$ErrorActionPreference = "Stop"

# PowerShell 7+ check
if ($PSVersionTable.PSVersion.Major -lt 7) {
	Write-Error "This script requires PowerShell 7 or later. Current version: $($PSVersionTable.PSVersion)"
	exit 1
}

# Load Windows Forms for system tray icon
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Import ExtractIconEx from shell32.dll
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class IconExtractor {
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern int ExtractIconEx(string lpszFile, int nIconIndex, IntPtr[] phiconLarge, IntPtr[] phiconSmall, int nIcons);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
"@

# Global variables for tray icon
$script:TrayIcon = $null
$script:IconNormal = $null    # Padlock (normal state)
$script:IconTouch = $null     # Key (touch required)
$script:IconNoCard = $null    # Warning (no card)
$script:IconError = $null     # Error (connection error)
$script:IconStopped = $null   # Stopped (agents stopped)

#region Configuration

# GPG executable path
$GpgPath = (Get-Command gpg.exe -ErrorAction SilentlyContinue).Source
if (-not $GpgPath) {
	Write-Error "gpg.exe not found. Please install GnuPG."
	Write-Error "PS:> winget install GnuPG.Gpg4win"
	exit 1
}

# Log file (with date suffix, rotate daily, keep 5 files)
$script:LogFileBase = "yubikey-tool"
$script:LogFileDate = Get-Date -Format "yyyyMMdd"
$script:LogFile = Join-Path $env:TEMP "${script:LogFileBase}-${script:LogFileDate}.log"

# Cleanup old log files (keep only 5)
Get-ChildItem -Path $env:TEMP -Filter "${script:LogFileBase}-*.log" -ErrorAction SilentlyContinue |
	Sort-Object LastWriteTime -Descending |
	Select-Object -Skip 5 |
	ForEach-Object { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue }

#endregion

#region Utility Functions

function Write-Log {
	param(
		[Parameter(Mandatory)]
		[string]$Message,

		[Parameter()]
		[ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
		[string]$Level = "INFO"
	)

	# Date-based log rotation (switch to new file at midnight)
	$currentDate = Get-Date -Format "yyyyMMdd"
	if ($currentDate -ne $script:LogFileDate) {
		$script:LogFileDate = $currentDate
		$script:LogFile = Join-Path $env:TEMP "${script:LogFileBase}-${currentDate}.log"

		# Cleanup old log files (keep only 5)
		Get-ChildItem -Path $env:TEMP -Filter "${script:LogFileBase}-*.log" -ErrorAction SilentlyContinue |
			Sort-Object LastWriteTime -Descending |
			Select-Object -Skip 5 |
			ForEach-Object { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue }
	}

	$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$logMessage = "[$timestamp] [$Level] $Message"

	# Output to console
	switch ($Level) {
		"ERROR" { Write-Host $logMessage -ForegroundColor Red }
		"WARN" { Write-Host $logMessage -ForegroundColor Yellow }
		"DEBUG" { if ($VerbosePreference -eq "Continue") { Write-Host $logMessage -ForegroundColor Gray } }
		default { Write-Host $logMessage }
	}

	# Output to file
	Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

function Show-ToastNotification {
	param(
		[Parameter(Mandatory)]
		[string]$Title,

		[Parameter(Mandatory)]
		[string]$Message
	)

	# BurntToast module (most reliable for startup scripts)
	try {
		if (Get-Module -ListAvailable -Name BurntToast) {
			Import-Module BurntToast -ErrorAction Stop
			New-BurntToastNotification -Text $Title, $Message -Sound Default
			Write-Log "BurntToast notification displayed: $Title - $Message" -Level DEBUG
			return
		}
	}
	catch {
		Write-Log "BurntToast module error: $($_.Exception.Message)" -Level DEBUG
	}

	# Fallback 1: Use existing tray icon for balloon notification
	if ($script:TrayIcon -and $script:TrayIcon.Visible) {
		try {
			$script:TrayIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
			$script:TrayIcon.BalloonTipTitle = $Title
			$script:TrayIcon.BalloonTipText = $Message
			$script:TrayIcon.ShowBalloonTip(15000)
			Write-Log "TrayIcon balloon displayed: $Title - $Message" -Level DEBUG
			return
		}
		catch {
			Write-Log "TrayIcon balloon error: $($_.Exception.Message)" -Level DEBUG
		}
	}

	# Fallback 2: Windows.UI.Notifications (PowerShell 7+)
	try {
		$runtimePath = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
		$winmdPath = Join-Path $runtimePath "WinMetadata\Windows.winmd"

		if (Test-Path $winmdPath) {
			[void][Windows.Foundation.Metadata.ApiInformation, Windows.Foundation.UniversalApiContract, ContentType = WindowsRuntime]
		}

		[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
		[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

		$template = @"
<toast>
	<visual>
		<binding template="ToastGeneric">
			<text>$Title</text>
			<text>$Message</text>
		</binding>
	</visual>
	<audio src="ms-winsoundevent:Notification.Default" />
</toast>
"@

		$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
		$xml.LoadXml($template)
		$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
		$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("YubiKey Tool")
		$notifier.Show($toast)

		Write-Log "Toast notification displayed: $Title - $Message" -Level DEBUG
		return
	}
	catch {
		Write-Log "Windows.UI.Notifications error: $($_.Exception.Message)" -Level DEBUG
	}

	Write-Log "All notification methods failed: $Title - $Message" -Level WARN
}

function Get-IconFromDll {
	<#
	.SYNOPSIS
		Extract icon from DLL file
	.PARAMETER DllPath
		Path to DLL file
	.PARAMETER Index
		Icon index in DLL
	.PARAMETER Name
		Icon name for logging
	#>
	param(
		[string]$DllPath,
		[int]$Index,
		[string]$Name
	)

	$largeIcons = New-Object IntPtr[] 1
	$smallIcons = New-Object IntPtr[] 1

	try {
		$count = [IconExtractor]::ExtractIconEx($DllPath, $Index, $largeIcons, $smallIcons, 1)
		if ($count -gt 0 -and $largeIcons[0] -ne [IntPtr]::Zero) {
			$icon = [System.Drawing.Icon]::FromHandle($largeIcons[0]).Clone()
			[IconExtractor]::DestroyIcon($largeIcons[0]) | Out-Null
			Write-Log "$Name icon loaded (index $Index)" -Level DEBUG
			return $icon
		}
		Write-Log "$Name icon extraction returned null (index $Index)" -Level WARN
	}
	catch {
		Write-Log "Failed to load $Name icon: $($_.Exception.Message)" -Level WARN
	}
	return $null
}

function Initialize-TrayIcon {
	<#
	.SYNOPSIS
		Initialize system tray icon with context menu
	#>

	Write-Log "Initializing system tray icon..."

	# Create tray icon
	$script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon

	# Load icons for different states (all from imageres.dll)
	$imageresPath = Join-Path $env:SystemRoot "System32\imageres.dll"

	$script:IconNormal = Get-IconFromDll -DllPath $imageresPath -Index 321 -Name "Normal"
	$script:IconTouch = Get-IconFromDll -DllPath $imageresPath -Index 300 -Name "Touch"
	$script:IconNoCard = Get-IconFromDll -DllPath $imageresPath -Index 54 -Name "NoCard"
	$script:IconError = Get-IconFromDll -DllPath $imageresPath -Index 270 -Name "Error"
	$script:IconStopped = Get-IconFromDll -DllPath $imageresPath -Index 93 -Name "Stopped"

	# Set initial icon (normal state)
	if ($script:IconNormal) {
		$script:TrayIcon.Icon = $script:IconNormal
	}
	elseif ($script:IconTouch) {
		$script:TrayIcon.Icon = $script:IconTouch
	}
	else {
		$script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Shield
		Write-Log "Using fallback Shield icon" -Level DEBUG
	}

	$script:TrayIcon.Text = "YubiKey Tool"
	$script:TrayIcon.Visible = $true

	# Create context menu
	$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

	# Menu item: Restart
	$menuRestart = New-Object System.Windows.Forms.ToolStripMenuItem
	$menuRestart.Text = "Restart Agents"
	$menuRestart.Add_Click({
		Write-Log "Restarting agents from tray menu..."
		$script:autoRestartCount = 0
		Start-AsyncRestart
	})
	$contextMenu.Items.Add($menuRestart) | Out-Null

	# Menu item: Stop Agents
	$menuStop = New-Object System.Windows.Forms.ToolStripMenuItem
	$menuStop.Text = "Stop Agents"
	$menuStop.Add_Click({
		Write-Log "Stopping agents from tray menu..."
		Start-AsyncStop
	})
	$contextMenu.Items.Add($menuStop) | Out-Null

	# Menu item: Show Log
	$menuShowLog = New-Object System.Windows.Forms.ToolStripMenuItem
	$menuShowLog.Text = "Show Log"
	$menuShowLog.Add_Click({
		Write-Log "Opening log file from tray menu..."
		if (Test-Path $script:LogFile) {
			Invoke-Item $script:LogFile
		}
		else {
			$script:TrayIcon.ShowBalloonTip(2000, "YubiKey Tool", "Log file not found", [System.Windows.Forms.ToolTipIcon]::Warning)
		}
	})
	$contextMenu.Items.Add($menuShowLog) | Out-Null

	# Separator
	$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

	# Menu item: Exit
	$menuExit = New-Object System.Windows.Forms.ToolStripMenuItem
	$menuExit.Text = "Exit"
	$menuExit.Add_Click({
		Write-Log "Exiting from tray menu..."

		# Hide icon immediately for visual feedback
		$script:TrayIcon.Visible = $false

		# Cancel in-progress check process
		if ($script:gpgCheckProcess) {
			if (-not $script:gpgCheckProcess.HasExited) {
				try { $script:gpgCheckProcess.Kill() } catch { }
			}
			try { $script:gpgCheckProcess.Dispose() } catch { }
			$script:gpgCheckProcess = $null
		}

		# Cancel background restart
		if ($script:bgRestart) {
			try { $script:bgRestart.PowerShell.Stop() } catch { }
			try { $script:bgRestart.PowerShell.Dispose() } catch { }
			try { $script:bgRestart.Runspace.Close() } catch { }
			try { $script:bgRestart.Runspace.Dispose() } catch { }
			$script:bgRestart = $null
		}

		# Cancel background stop
		if ($script:bgStop) {
			try { $script:bgStop.PowerShell.Stop() } catch { }
			try { $script:bgStop.PowerShell.Dispose() } catch { }
			try { $script:bgStop.Runspace.Close() } catch { }
			try { $script:bgStop.Runspace.Dispose() } catch { }
			$script:bgStop = $null
		}

		# Graceful shutdown in background runspace (icon is hidden, blocking is acceptable)
		$exitRunspace = [runspacefactory]::CreateRunspace()
		$exitRunspace.Open()
		$exitPs = [powershell]::Create()
		$exitPs.Runspace = $exitRunspace
		[void]$exitPs.AddScript({
			# Stop gpg-bridge
			Get-Process -Name "gpg-bridge" -ErrorAction SilentlyContinue |
				Stop-Process -Force -ErrorAction SilentlyContinue

			# killagent
			try {
				$psi = New-Object System.Diagnostics.ProcessStartInfo
				$psi.FileName = "gpg-connect-agent"
				$psi.Arguments = "killagent /bye"
				$psi.UseShellExecute = $false
				$psi.RedirectStandardOutput = $true
				$psi.RedirectStandardError = $true
				$psi.CreateNoWindow = $true

				$p = New-Object System.Diagnostics.Process
				$p.StartInfo = $psi
				$p.Start() | Out-Null
				if (-not $p.WaitForExit(5000)) {
					try { $p.Kill() } catch { }
				}
				$p.Dispose()
			}
			catch { }
		})
		$exitPs.Invoke()
		$exitPs.Dispose()
		$exitRunspace.Close()
		$exitRunspace.Dispose()

		$script:TrayIcon.Dispose()
		[Environment]::Exit(0)
	})
	$contextMenu.Items.Add($menuExit) | Out-Null

	$script:TrayIcon.ContextMenuStrip = $contextMenu

	Write-Log "System tray icon initialized"
}

function Remove-TrayIcon {
	<#
	.SYNOPSIS
		Cleanup tray icon
	#>

	if ($script:TrayIcon) {
		$script:TrayIcon.Visible = $false
		$script:TrayIcon.Dispose()
		$script:TrayIcon = $null
	}

	# Dispose all icons
	foreach ($iconRef in @(
		[ref]$script:IconNormal,
		[ref]$script:IconTouch,
		[ref]$script:IconNoCard,
		[ref]$script:IconError,
		[ref]$script:IconStopped
	)) {
		if ($iconRef.Value) {
			$iconRef.Value.Dispose()
			$iconRef.Value = $null
		}
	}

	Write-Log "System tray icon removed"
}

function Set-TrayIconState {
	<#
	.SYNOPSIS
		Change tray icon based on state
	.PARAMETER State
		Icon state: "Normal", "Touch", "NoCard", "Error", "Stopped"
	#>
	param(
		[Parameter(Mandatory)]
		[ValidateSet("Normal", "Touch", "NoCard", "Error", "Stopped")]
		[string]$State
	)

	if (-not $script:TrayIcon) { return }

	switch ($State) {
		"Touch" {
			if ($script:IconTouch) {
				$script:TrayIcon.Icon = $script:IconTouch
				$script:TrayIcon.Text = "YubiKey Tool - Touch Required!"
			}
		}
		"NoCard" {
			if ($script:IconNoCard) {
				$script:TrayIcon.Icon = $script:IconNoCard
				$script:TrayIcon.Text = "YubiKey Tool - No Card"
			}
		}
		"Error" {
			if ($script:IconError) {
				$script:TrayIcon.Icon = $script:IconError
				$script:TrayIcon.Text = "YubiKey Tool - Error (Restarting...)"
			}
		}
		"Stopped" {
			if ($script:IconStopped) {
				$script:TrayIcon.Icon = $script:IconStopped
				$script:TrayIcon.Text = "YubiKey Tool - Agents Stopped"
			}
		}
		default {
			if ($script:IconNormal) {
				$script:TrayIcon.Icon = $script:IconNormal
				$script:TrayIcon.Text = "YubiKey Tool"
			}
		}
	}
}

function Register-Startup {
	<#
	.SYNOPSIS
		Register shortcut to Windows startup
	#>

	$scriptPath = $PSCommandPath
	if (-not $scriptPath) {
		Write-Error "Cannot get script path"
		exit 1
	}

	# Copy script to fixed path
	$installDir = Join-Path $env:USERPROFILE ".local\bin"
	$installedScript = Join-Path $installDir "yubikey-tool.ps1"

	if (-not (Test-Path $installDir)) {
		New-Item -ItemType Directory -Path $installDir -Force | Out-Null
	}

	# Skip copy if already running from installed location
	$scriptFullPath = (Resolve-Path $scriptPath).Path
	$installedFullPath = $installedScript
	if (Test-Path $installedScript) {
		$installedFullPath = (Resolve-Path $installedScript).Path
	}

	if ($scriptFullPath -ne $installedFullPath) {
		Copy-Item -Path $scriptPath -Destination $installedScript -Force
		Write-Host "Script installed: $installedScript" -ForegroundColor Green
	}
	else {
		Write-Host "Script already at installed location: $installedScript" -ForegroundColor Cyan
	}

	# Get pwsh.exe path
	$pwshPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
	if (-not $pwshPath) {
		Write-Error "pwsh.exe not found"
		exit 1
	}

	# 1. Create shortcut in startup folder (hidden launch)
	$startupFolder = [Environment]::GetFolderPath("Startup")
	$startupShortcut = Join-Path $startupFolder "yubikey-tool.lnk"

	$shell = New-Object -ComObject WScript.Shell
	$shortcut = $shell.CreateShortcut($startupShortcut)
	$shortcut.TargetPath = $pwshPath
	$shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installedScript`""
	$shortcut.WorkingDirectory = $installDir
	$shortcut.Description = "YubiKey Tool - GPG Agent & Touch Detection (Startup)"
	$shortcut.WindowStyle = 7  # 7 = Minimized (prevents window flash)
	$shortcut.Save()

	Write-Host "Registered to startup: $startupShortcut" -ForegroundColor Green

	# Cleanup old files
	$oldCmdFile = Join-Path $installDir "yubikey-tool.cmd"
	$oldVbsFile = Join-Path $installDir "yubikey-tool.vbs"
	$oldLnkFile = Join-Path $installDir "yubikey-tool.lnk"
	foreach ($oldFile in @($oldCmdFile, $oldVbsFile, $oldLnkFile)) {
		if (Test-Path $oldFile) {
			Remove-Item -Path $oldFile -Force
			Write-Host "Removed old file: $oldFile" -ForegroundColor Yellow
		}
	}
}

function Unregister-Startup {
	<#
	.SYNOPSIS
		Remove shortcut from Windows startup
	#>

	$startupFolder = [Environment]::GetFolderPath("Startup")
	$startupShortcut = Join-Path $startupFolder "yubikey-tool.lnk"

	if (Test-Path $startupShortcut) {
		Remove-Item -Path $startupShortcut -Force
		Write-Host "Removed from startup: $startupShortcut" -ForegroundColor Green
	}
	else {
		Write-Host "Startup shortcut not found" -ForegroundColor Yellow
	}

	# Cleanup old files in .local\bin
	$installDir = Join-Path $env:USERPROFILE ".local\bin"
	$installedScript = Join-Path $installDir "yubikey-tool.ps1"
	$oldFiles = @(
		(Join-Path $installDir "yubikey-tool.cmd"),
		(Join-Path $installDir "yubikey-tool.vbs"),
		(Join-Path $installDir "yubikey-tool.lnk")
	)

	foreach ($oldFile in $oldFiles) {
		if (Test-Path $oldFile) {
			Remove-Item -Path $oldFile -Force
			Write-Host "Removed old file: $oldFile" -ForegroundColor Yellow
		}
	}

	if (Test-Path $installedScript) {
		Write-Host ""
		Write-Host "Installed script: $installedScript" -ForegroundColor Cyan
		Write-Host ""

		$response = Read-Host "Delete this file as well? (y/N)"
		if ($response -eq "y" -or $response -eq "Y") {
			Remove-Item -Path $installedScript -Force
			Write-Host "Deleted: $installedScript" -ForegroundColor Green
		}
	}
}

function Stop-ProcessByName {
	<#
	.SYNOPSIS
		Helper function to stop processes by name
	.PARAMETER Name
		Process name to stop
	.OUTPUTS
		Number of processes terminated
	#>
	param(
		[Parameter(Mandatory)]
		[string]$Name
	)

	$procs = Get-Process -Name $Name -ErrorAction SilentlyContinue
	if ($procs) {
		$count = @($procs).Count
		Write-Log "Terminating $Name processes: $count"
		$procs | Stop-Process -Force -ErrorAction SilentlyContinue
		return $count
	}
	return 0
}

function Stop-ExistingInstances {
	<#
	.SYNOPSIS
		Stop any existing yubikey-tool.ps1 instances
	#>

	$currentPid = $PID
	Write-Log "Checking for existing yubikey-tool instances (current PID: $currentPid)..."

	try {
		$procs = Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe' OR Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
			Where-Object {
				$_.ProcessId -ne $currentPid -and
				$_.CommandLine -match "yubikey-tool\.ps1"
			}

		if ($procs) {
			Write-Log "Found $(@($procs).Count) existing instance(s), terminating..."
			foreach ($proc in $procs) {
				try {
					Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
					Write-Log "Terminated PID: $($proc.ProcessId)"
				}
				catch {
					Write-Log "Failed to terminate PID $($proc.ProcessId): $_" -Level WARN
				}
			}
		}
		else {
			Write-Log "No existing instances found" -Level DEBUG
		}
	}
	catch {
		Write-Log "Error checking for existing instances: $_" -Level WARN
	}
}

function Write-DiagnosticLog {
	<#
	.SYNOPSIS
		Record diagnostic information at startup for troubleshooting
	#>

	Write-Log "=== Diagnostic Information ===" -Level INFO

	# 1. Smart Card Service status
	try {
		$scardService = Get-Service -Name "SCardSvr" -ErrorAction SilentlyContinue
		if ($scardService) {
			Write-Log "Smart Card Service (SCardSvr): $($scardService.Status)" -Level INFO
		}
		else {
			Write-Log "Smart Card Service (SCardSvr): NOT FOUND" -Level WARN
		}
	}
	catch {
		Write-Log "Failed to check Smart Card Service: $_" -Level WARN
	}

	# 2. Existing GPG-related processes
	try {
		$gpgProcs = Get-Process -Name "gpg" -ErrorAction SilentlyContinue
		$agentProcs = Get-Process -Name "gpg-agent" -ErrorAction SilentlyContinue
		$scdProcs = Get-Process -Name "scdaemon" -ErrorAction SilentlyContinue
		$bridgeProcs = Get-Process -Name "gpg-bridge" -ErrorAction SilentlyContinue

		Write-Log "Existing processes: gpg=$(@($gpgProcs).Count), gpg-agent=$(@($agentProcs).Count), scdaemon=$(@($scdProcs).Count), gpg-bridge=$(@($bridgeProcs).Count)" -Level INFO

		# Log scdaemon details if exists
		if ($scdProcs) {
			foreach ($proc in $scdProcs) {
				$uptime = (Get-Date) - $proc.StartTime
				Write-Log "  scdaemon PID=$($proc.Id), Uptime=$([int]$uptime.TotalSeconds)s, CPU=$($proc.CPU)s" -Level INFO
			}
		}
	}
	catch {
		Write-Log "Failed to check existing processes: $_" -Level WARN
	}

	Write-Log "=== End Diagnostic Information ===" -Level INFO
}

function Stop-Agents {
	<#
	.SYNOPSIS
		Safely stop gpg-agent, gpg-bridge, scdaemon and gpg processes
		Uses "gpg-connect-agent killagent /bye" (Yubico official method) with fallback to process kill
	#>

	Write-Log "Stopping existing GPG processes..."

	# Cancel in-progress check process (if called during polling)
	if ($script:gpgCheckProcess) {
		if (-not $script:gpgCheckProcess.HasExited) {
			try { $script:gpgCheckProcess.Kill() } catch { }
		}
		try { $script:gpgCheckProcess.Dispose() } catch { }
		$script:gpgCheckProcess = $null
		$script:gpgCheckStartTime = $null
	}

	# Cancel background restart if running
	if ($script:bgRestart) {
		try { $script:bgRestart.PowerShell.Stop() } catch { }
		try { $script:bgRestart.PowerShell.Dispose() } catch { }
		try { $script:bgRestart.Runspace.Close() } catch { }
		try { $script:bgRestart.Runspace.Dispose() } catch { }
		$script:bgRestart = $null
		$script:restartInProgress = $false
	}

	# Cancel background stop if running
	if ($script:bgStop) {
		try { $script:bgStop.PowerShell.Stop() } catch { }
		try { $script:bgStop.PowerShell.Dispose() } catch { }
		try { $script:bgStop.Runspace.Close() } catch { }
		try { $script:bgStop.Runspace.Dispose() } catch { }
		$script:bgStop = $null
	}

	# Stop gpg-bridge first
	Stop-ProcessByName -Name "gpg-bridge"

	# Try official method first: gpg-connect-agent killagent /bye
	Write-Log "Stopping gpg-agent via 'gpg-connect-agent killagent /bye'..." -Level DEBUG
	try {
		$psi = New-Object System.Diagnostics.ProcessStartInfo
		$psi.FileName = "gpg-connect-agent"
		$psi.Arguments = "killagent /bye"
		$psi.UseShellExecute = $false
		$psi.RedirectStandardOutput = $true
		$psi.RedirectStandardError = $true
		$psi.CreateNoWindow = $true

		$process = New-Object System.Diagnostics.Process
		$process.StartInfo = $psi
		$process.Start() | Out-Null
		$completed = $process.WaitForExit(5000)

		if ($completed) {
			Write-Log "gpg-connect-agent killagent /bye: exit=$($process.ExitCode)" -Level DEBUG
		}
		else {
			Write-Log "gpg-connect-agent killagent /bye: TIMEOUT, falling back to process kill" -Level DEBUG
			try { $process.Kill() } catch { }
		}
		$process.Dispose()
	}
	catch {
		Write-Log "gpg-connect-agent killagent /bye failed: $_, falling back to process kill" -Level DEBUG
	}

	Write-Log "GPG processes stopped"
}

function Restart-Agents {
	<#
	.SYNOPSIS
		Stop and restart gpg-agent, scdaemon, and gpg-bridge using official GnuPG methods
		Reference: https://developers.yubico.com/PGP/SSH_authentication/Windows.html
	.OUTPUTS
		Boolean indicating success
	#>

	Write-Log "Restarting agents..." -Level INFO

	# Step 1: Stop all agents (uses gpg-connect-agent killagent /bye + fallback + lock cleanup)
	Stop-Agents

	# Step 2: Wait for processes to fully terminate
	Write-Log "Waiting for processes to terminate..." -Level DEBUG
	Start-Sleep -Seconds 2

	# Step 3: Start gpg-agent via "gpg-connect-agent /bye" (official method)
	# This automatically starts gpg-agent if not running, and scdaemon when needed
	Write-Log "Starting gpg-agent via 'gpg-connect-agent /bye'..." -Level INFO
	try {
		$psi = New-Object System.Diagnostics.ProcessStartInfo
		$psi.FileName = "gpg-connect-agent"
		$psi.Arguments = "/bye"
		$psi.UseShellExecute = $false
		$psi.RedirectStandardOutput = $true
		$psi.RedirectStandardError = $true
		$psi.CreateNoWindow = $true

		$process = New-Object System.Diagnostics.Process
		$process.StartInfo = $psi

		$startTime = Get-Date
		$process.Start() | Out-Null
		$completed = $process.WaitForExit(30000)  # 30 second timeout
		$elapsed = [int]((Get-Date) - $startTime).TotalMilliseconds

		if ($completed) {
			$exitCode = $process.ExitCode
			$stderr = $process.StandardError.ReadToEnd()
			$process.Dispose()

			if ($exitCode -eq 0) {
				Write-Log "gpg-connect-agent /bye: OK (${elapsed}ms)" -Level INFO
			}
			else {
				Write-Log "gpg-connect-agent /bye: exit=$exitCode (${elapsed}ms)" -Level WARN
				if ($stderr) { Write-Log "  stderr: $($stderr.Trim())" -Level DEBUG }
				return $false
			}
		}
		else {
			Write-Log "gpg-connect-agent /bye: TIMEOUT (30000ms)" -Level WARN
			try {
				$process.Kill()
				$process.WaitForExit(1000) | Out-Null
			}
			catch { }
			$process.Dispose()
			return $false
		}
	}
	catch {
		Write-Log "gpg-connect-agent /bye failed: $_" -Level ERROR
		return $false
	}

	# Step 4: Initialize card access with long timeout (first gpg command triggers initialization)
	# GPG performs various initialization on first command, which can take 15-30 seconds
	Write-Log "Initializing card access (this may take up to 60 seconds on first run)..." -Level INFO
	try {
		$psi = New-Object System.Diagnostics.ProcessStartInfo
		$psi.FileName = $GpgPath
		$psi.Arguments = "--card-status"
		$psi.UseShellExecute = $false
		$psi.RedirectStandardOutput = $true
		$psi.RedirectStandardError = $true
		$psi.CreateNoWindow = $true

		$process = New-Object System.Diagnostics.Process
		$process.StartInfo = $psi

		$startTime = Get-Date
		$process.Start() | Out-Null
		$completed = $process.WaitForExit(60000)  # 60 second timeout for initial card access
		$elapsed = [int]((Get-Date) - $startTime).TotalMilliseconds

		if ($completed) {
			$exitCode = $process.ExitCode
			$stderr = $process.StandardError.ReadToEnd()
			$process.Dispose()

			if ($exitCode -eq 0) {
				Write-Log "Card initialization: OK (${elapsed}ms)" -Level INFO
			}
			elseif ($exitCode -eq 2 -and $stderr -match "No such device|card not present|Card not present") {
				Write-Log "Card initialization: No card detected, but GPG ready (${elapsed}ms)" -Level INFO
			}
			else {
				Write-Log "Card initialization: exit=$exitCode (${elapsed}ms)" -Level WARN
				if ($stderr) { Write-Log "  stderr: $($stderr.Trim())" -Level DEBUG }
				# Continue anyway - card might not be inserted
			}
		}
		else {
			Write-Log "Card initialization: TIMEOUT (60000ms)" -Level WARN
			try {
				$process.Kill()
				$process.WaitForExit(1000) | Out-Null
			}
			catch { }
			$process.Dispose()
			# Continue anyway - will retry on next polling cycle
		}
	}
	catch {
		Write-Log "Card initialization failed: $_" -Level WARN
		# Continue anyway
	}

	# Step 5: Start gpg-bridge
	$bridgeOk = Start-GpgBridge
	if (-not $bridgeOk) {
		Write-Log "gpg-bridge failed to start" -Level WARN
		return $false
	}

	Write-Log "Agents started successfully" -Level INFO
	return $true
}

function Test-StalePipes {
	<#
	.SYNOPSIS
		Check for stale SSH named pipes and warn if found
	#>

	Write-Log "Checking for stale named pipes..." -Level DEBUG

	$stalePipes = @()

	try {
		# Get all named pipes
		$pipes = Get-ChildItem "\\.\pipe\" -ErrorAction SilentlyContinue |
			Where-Object {
				$_.Name -match "^(openssh-ssh-agent)"
			}

		if ($pipes) {
			foreach ($pipe in $pipes) {
				$stalePipes += $pipe.Name
				Write-Log "Stale pipe detected: $($pipe.Name)" -Level WARN
			}
		}
	}
	catch {
		Write-Log "Error checking named pipes: $_" -Level WARN
	}

	if ($stalePipes.Count -gt 0) {
		$pipeList = $stalePipes -join ", "
		$message = "Stale pipes detected: $pipeList. This may cause connection issues."
		Write-Log $message -Level WARN
		Show-ToastNotification -Title "YubiKey Tool Warning" -Message $message
	}
	else {
		Write-Log "No stale pipes found" -Level DEBUG
	}

	return $stalePipes
}

function Start-GpgBridge {
	<#
	.SYNOPSIS
		Start gpg-bridge
	#>

	if (-not (Test-Path $GpgBridgePath)) {
		Write-Error "gpg-bridge not found: $GpgBridgePath"
		exit 1
	}

	Write-Log "Starting gpg-bridge: $GpgBridgePath $GpgBridgeArgs"

	try {
		$psi = New-Object System.Diagnostics.ProcessStartInfo
		$psi.FileName = $GpgBridgePath
		$psi.Arguments = $GpgBridgeArgs
		$psi.UseShellExecute = $false
		$psi.CreateNoWindow = $true
		$psi.RedirectStandardOutput = $false
		$psi.RedirectStandardError = $false

		$process = New-Object System.Diagnostics.Process
		$process.StartInfo = $psi
		$process.Start() | Out-Null

		Start-Sleep -Milliseconds 500

		$bridgeProcess = Get-Process -Name "gpg-bridge" -ErrorAction SilentlyContinue
		if ($bridgeProcess) {
			Write-Log "gpg-bridge started (PID: $($bridgeProcess.Id))"
			return $true
		}
		else {
			Write-Log "Could not verify gpg-bridge startup" -Level WARN
			return $false
		}
	}
	catch {
		Write-Log "Failed to start gpg-bridge: $_" -Level ERROR
		return $false
	}
}

function Start-AsyncStop {
	<#
	.SYNOPSIS
		Non-blocking stop: cancel UI-thread tasks, then run graceful shutdown in background Runspace
	#>

	Write-Log "Starting async stop..." -Level INFO

	# Cancel in-progress check process on UI thread
	if ($script:gpgCheckProcess) {
		if (-not $script:gpgCheckProcess.HasExited) {
			try { $script:gpgCheckProcess.Kill() } catch { }
		}
		try { $script:gpgCheckProcess.Dispose() } catch { }
		$script:gpgCheckProcess = $null
		$script:gpgCheckStartTime = $null
	}

	# Cancel background restart if running
	if ($script:bgRestart) {
		try { $script:bgRestart.PowerShell.Stop() } catch { }
		try { $script:bgRestart.PowerShell.Dispose() } catch { }
		try { $script:bgRestart.Runspace.Close() } catch { }
		try { $script:bgRestart.Runspace.Dispose() } catch { }
		$script:bgRestart = $null
		$script:restartInProgress = $false
	}

	# Cancel previous background stop if running
	if ($script:bgStop) {
		try { $script:bgStop.PowerShell.Stop() } catch { }
		try { $script:bgStop.PowerShell.Dispose() } catch { }
		try { $script:bgStop.Runspace.Close() } catch { }
		try { $script:bgStop.Runspace.Dispose() } catch { }
		$script:bgStop = $null
	}

	# Update state immediately on UI thread
	Set-TrayIconState -State "Stopped"
	$script:currentState = "Stopped"

	# Run graceful shutdown in background Runspace
	$runspace = [runspacefactory]::CreateRunspace()
	$runspace.Open()
	$ps = [powershell]::Create()
	$ps.Runspace = $runspace

	[void]$ps.AddScript({
		# Stop gpg-bridge
		Get-Process -Name "gpg-bridge" -ErrorAction SilentlyContinue |
			Stop-Process -Force -ErrorAction SilentlyContinue

		# killagent via official method
		try {
			$psi = New-Object System.Diagnostics.ProcessStartInfo
			$psi.FileName = "gpg-connect-agent"
			$psi.Arguments = "killagent /bye"
			$psi.UseShellExecute = $false
			$psi.RedirectStandardOutput = $true
			$psi.RedirectStandardError = $true
			$psi.CreateNoWindow = $true

			$p = New-Object System.Diagnostics.Process
			$p.StartInfo = $psi
			$p.Start() | Out-Null
			if (-not $p.WaitForExit(5000)) {
				try { $p.Kill() } catch { }
			}
			$p.Dispose()
		}
		catch { }
	})

	$handle = $ps.BeginInvoke()

	$script:bgStop = @{
		PowerShell = $ps
		Handle     = $handle
		Runspace   = $runspace
	}
}

function Start-AsyncRestart {
	<#
	.SYNOPSIS
		Non-blocking restart: cancel UI-thread tasks, then run full restart sequence in background Runspace
	#>

	Write-Log "Starting async restart..." -Level INFO

	# Cancel in-progress check process on UI thread
	if ($script:gpgCheckProcess) {
		if (-not $script:gpgCheckProcess.HasExited) {
			try { $script:gpgCheckProcess.Kill() } catch { }
		}
		try { $script:gpgCheckProcess.Dispose() } catch { }
		$script:gpgCheckProcess = $null
		$script:gpgCheckStartTime = $null
	}

	# Cancel background restart if already running
	if ($script:bgRestart) {
		try { $script:bgRestart.PowerShell.Stop() } catch { }
		try { $script:bgRestart.PowerShell.Dispose() } catch { }
		try { $script:bgRestart.Runspace.Close() } catch { }
		try { $script:bgRestart.Runspace.Dispose() } catch { }
		$script:bgRestart = $null
	}

	# Cancel background stop if running
	if ($script:bgStop) {
		try { $script:bgStop.PowerShell.Stop() } catch { }
		try { $script:bgStop.PowerShell.Dispose() } catch { }
		try { $script:bgStop.Runspace.Close() } catch { }
		try { $script:bgStop.Runspace.Dispose() } catch { }
		$script:bgStop = $null
	}

	# Update state immediately on UI thread
	$script:restartInProgress = $true
	$script:gpgReady = $false
	$script:gpgNotReadySince = $null
	Set-TrayIconState -State "Error"
	$script:currentState = "Error"

	# Run full restart sequence in background Runspace
	$runspace = [runspacefactory]::CreateRunspace()
	$runspace.Open()
	$ps = [powershell]::Create()
	$ps.Runspace = $runspace

	[void]$ps.AddScript({
		param($GpgBridgePath, $GpgBridgeArgs, $GpgPath)

		# Step 1: Stop gpg-bridge
		Get-Process -Name "gpg-bridge" -ErrorAction SilentlyContinue |
			Stop-Process -Force -ErrorAction SilentlyContinue

		# Step 2: killagent via official method
		try {
			$psi = New-Object System.Diagnostics.ProcessStartInfo
			$psi.FileName = "gpg-connect-agent"
			$psi.Arguments = "killagent /bye"
			$psi.UseShellExecute = $false
			$psi.RedirectStandardOutput = $true
			$psi.RedirectStandardError = $true
			$psi.CreateNoWindow = $true

			$p = New-Object System.Diagnostics.Process
			$p.StartInfo = $psi
			$p.Start() | Out-Null
			if (-not $p.WaitForExit(5000)) {
				try { $p.Kill() } catch { }
			}
			$p.Dispose()
		}
		catch { }

		# Step 3: Wait for processes to terminate
		Start-Sleep -Seconds 2

		# Step 4: Start gpg-agent via gpg-connect-agent /bye
		try {
			$psi = New-Object System.Diagnostics.ProcessStartInfo
			$psi.FileName = "gpg-connect-agent"
			$psi.Arguments = "/bye"
			$psi.UseShellExecute = $false
			$psi.RedirectStandardOutput = $true
			$psi.RedirectStandardError = $true
			$psi.CreateNoWindow = $true

			$p = New-Object System.Diagnostics.Process
			$p.StartInfo = $psi
			$p.Start() | Out-Null
			if (-not $p.WaitForExit(30000)) {
				try { $p.Kill(); $p.WaitForExit(1000) | Out-Null } catch { }
			}
			$p.Dispose()
		}
		catch { }

		# Step 5: Initialize card access
		try {
			$psi = New-Object System.Diagnostics.ProcessStartInfo
			$psi.FileName = $GpgPath
			$psi.Arguments = "--card-status"
			$psi.UseShellExecute = $false
			$psi.RedirectStandardOutput = $true
			$psi.RedirectStandardError = $true
			$psi.CreateNoWindow = $true

			$p = New-Object System.Diagnostics.Process
			$p.StartInfo = $psi
			$p.Start() | Out-Null
			if (-not $p.WaitForExit(60000)) {
				try { $p.Kill(); $p.WaitForExit(1000) | Out-Null } catch { }
			}
			$p.Dispose()
		}
		catch { }

		# Step 6: Start gpg-bridge
		try {
			$psi = New-Object System.Diagnostics.ProcessStartInfo
			$psi.FileName = $GpgBridgePath
			$psi.Arguments = $GpgBridgeArgs
			$psi.UseShellExecute = $false
			$psi.CreateNoWindow = $true
			$psi.RedirectStandardOutput = $false
			$psi.RedirectStandardError = $false

			$p = New-Object System.Diagnostics.Process
			$p.StartInfo = $psi
			$p.Start() | Out-Null
		}
		catch { }
	})
	[void]$ps.AddArgument($GpgBridgePath)
	[void]$ps.AddArgument($GpgBridgeArgs)
	[void]$ps.AddArgument($GpgPath)

	$handle = $ps.BeginInvoke()

	$script:bgRestart = @{
		PowerShell = $ps
		Handle     = $handle
		Runspace   = $runspace
	}
}

#endregion

#region Main Processing

function Update-CardState {
	<#
	.SYNOPSIS
		Process GPG card status and update state machine
	.PARAMETER Status
		Card status: "Normal", "Touch", "NoCard", "Error"
	#>
	param(
		[Parameter(Mandatory)]
		[string]$Status
	)

	switch ($Status) {
		"Touch" {
			if ($script:currentState -ne "Touch") {
				$script:currentState = "Touch"
				$script:touchDetectedTime = Get-Date
				Write-Log "YubiKey touch waiting detected"
				Set-TrayIconState -State "Touch"
				Show-ToastNotification -Title "gpg-agent" -Message "Please touch or PIN your YubiKey"
			}
			else {
				$elapsed = ((Get-Date) - $script:touchDetectedTime).TotalSeconds
				Write-Log "   ... touch waiting continues (${elapsed}s)"
			}
		}
		"NoCard" {
			if ($script:currentState -ne "NoCard") {
				Write-Log "YubiKey not detected (No card)"
				Set-TrayIconState -State "NoCard"
				$script:currentState = "NoCard"
				$script:touchDetectedTime = $null
			}
		}
		"Error" {
			if ($script:currentState -ne "Error") {
				if (-not $script:gpgReady -and $script:autoRestartCount -ge 3) {
					Write-Log "GPG error detected but max auto-restarts reached. Manual restart required." -Level ERROR
					$script:touchDetectedTime = $null
					Set-TrayIconState -State "Error"
					$script:currentState = "Error"
					$script:TrayIcon.Text = "YubiKey Tool - GPG Error (Manual restart required)"
				}
				else {
					if (-not $script:gpgReady) { $script:autoRestartCount++ }
					Write-Log "GPG error detected, initiating auto-restart..." -Level WARN
					$script:touchDetectedTime = $null
					Start-AsyncRestart
				}
			}
		}
		default {
			if ($script:currentState -eq "Touch") {
				Write-Log "YubiKey touch completed"
			}
			elseif ($script:currentState -eq "NoCard") {
				Write-Log "YubiKey detected"
			}
			elseif ($script:currentState -eq "Error") {
				Write-Log "GPG connection restored"
			}

			if ($script:currentState -ne "Normal") {
				Set-TrayIconState -State "Normal"
				$script:currentState = "Normal"
				$script:touchDetectedTime = $null
			}
			elseif ($script:loopCount % 30 -eq 0) {
				Write-Log "Monitoring... (loop: $script:loopCount)" -Level DEBUG
			}
		}
	}

	# Timeout handling (force reset after 30 seconds)
	if ($script:currentState -eq "Touch" -and $script:touchDetectedTime) {
		$elapsed = ((Get-Date) - $script:touchDetectedTime).TotalSeconds
		if ($elapsed -gt 30) {
			Write-Log "Touch waiting state timed out (30s), resetting state" -Level WARN
			Set-TrayIconState -State "Normal"
			$script:currentState = "Normal"
			$script:touchDetectedTime = $null
		}
	}
}

function Start-PollingMode {
	<#
	.SYNOPSIS
		Polling-based touch detection with system tray icon (non-blocking)
	#>

	Write-Log "Starting polling mode"
	Write-Log "Check interval: ${CheckInterval}ms"

	$script:currentState = "Normal"
	$script:touchDetectedTime = $null
	$script:loopCount = 0

	# Non-blocking polling state
	$script:gpgCheckProcess = $null
	$script:gpgCheckStartTime = $null
	$script:bgRestart = $null
	$script:bgStop = $null
	$script:restartInProgress = $false
	$script:gpgReady = $false
	$script:gpgNotReadySince = $null
	$script:autoRestartCount = 0

	# Suppress unhandled exception dialogs
	try {
		[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
	}
	catch {
		Write-Log "SetUnhandledExceptionMode skipped (controls already exist)" -Level DEBUG
	}
	[System.Windows.Forms.Application]::add_ThreadException({
		param($sender, $e)
		if ($e.Exception -is [System.Management.Automation.PipelineStoppedException]) {
			[System.Windows.Forms.Application]::Exit()
		}
		else {
			Write-Log "Unhandled thread exception: $($e.Exception.Message)" -Level ERROR
		}
	})

	Initialize-TrayIcon
	Write-Log "Polling mode running (use tray icon to exit)"

	[Console]::TreatControlCAsInput = $false
	$exitEventJob = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
		[System.Windows.Forms.Application]::Exit()
	}

	$timer = New-Object System.Windows.Forms.Timer
	$timer.Interval = $CheckInterval
	$timer.Add_Tick({
		try {
			$script:loopCount++

			# 1. Check background restart completion (non-blocking)
			if ($script:bgRestart -and $script:bgRestart.Handle.IsCompleted) {
				try { $script:bgRestart.PowerShell.EndInvoke($script:bgRestart.Handle) } catch { }
				try { $script:bgRestart.PowerShell.Dispose() } catch { }
				try { $script:bgRestart.Runspace.Close() } catch { }
				try { $script:bgRestart.Runspace.Dispose() } catch { }
				$script:bgRestart = $null
				$script:restartInProgress = $false
				Set-TrayIconState -State "Normal"
				$script:currentState = "Normal"
				Write-Log "Agents restarted (async)" -Level INFO
				$script:TrayIcon.ShowBalloonTip(2000, "YubiKey Tool", "Agents restarted", [System.Windows.Forms.ToolTipIcon]::Info)
			}

			# Check background stop completion (non-blocking)
			if ($script:bgStop -and $script:bgStop.Handle.IsCompleted) {
				try { $script:bgStop.PowerShell.EndInvoke($script:bgStop.Handle) } catch { }
				try { $script:bgStop.PowerShell.Dispose() } catch { }
				try { $script:bgStop.Runspace.Close() } catch { }
				try { $script:bgStop.Runspace.Dispose() } catch { }
				$script:bgStop = $null
				Write-Log "Agents stopped (async)" -Level INFO
				$script:TrayIcon.ShowBalloonTip(2000, "YubiKey Tool", "Agents stopped", [System.Windows.Forms.ToolTipIcon]::Info)
			}

			# 2. Skip polling when agents are stopped or restart is in progress
			if ($script:currentState -eq "Stopped" -or $script:restartInProgress) {
				return
			}

			# 3. Check existing gpg --card-status process
			if ($script:gpgCheckProcess) {
				if ($script:gpgCheckProcess.HasExited) {
					# Process completed — read results
					$exitCode = $script:gpgCheckProcess.ExitCode
					$stderr = $script:gpgCheckProcess.StandardError.ReadToEnd()
					$null = $script:gpgCheckProcess.StandardOutput.ReadToEnd()
					$elapsed = [int]((Get-Date) - $script:gpgCheckStartTime).TotalMilliseconds
					$script:gpgCheckProcess.Dispose()
					$script:gpgCheckProcess = $null
					$script:gpgCheckStartTime = $null

					Write-Log "gpg --card-status completed (elapsed: ${elapsed}ms, exit: $exitCode)" -Level DEBUG

					if ($exitCode -eq 0) {
						if (-not $script:gpgReady) {
							Write-Log "GPG is now ready (first successful response)" -Level INFO
							$script:gpgReady = $true
							$script:gpgNotReadySince = $null
							$script:autoRestartCount = 0
						}
						Update-CardState -Status "Normal"
					}
					elseif ($exitCode -eq 2 -and $stderr -match "No such device|card not present|Card not present") {
						Write-Log "No card detected: $($stderr.Trim())" -Level DEBUG
						if (-not $script:gpgReady) {
							Write-Log "GPG is now ready (card not present but GPG responding)" -Level INFO
							$script:gpgReady = $true
							$script:gpgNotReadySince = $null
							$script:autoRestartCount = 0
						}
						Update-CardState -Status "NoCard"
					}
					else {
						Write-Log "gpg --card-status failed: exit=$exitCode stderr=$($stderr.Trim())" -Level WARN
						Update-CardState -Status "Error"
					}
				}
				elseif (((Get-Date) - $script:gpgCheckStartTime).TotalMilliseconds -gt $HangTimeout) {
					Write-Log "gpg --card-status hang detected (timeout: ${HangTimeout}ms)" -Level INFO
					try {
						$script:gpgCheckProcess.Kill()
						$script:gpgCheckProcess.WaitForExit(1000) | Out-Null
					}
					catch { }
					$script:gpgCheckProcess.Dispose()
					$script:gpgCheckProcess = $null
					$script:gpgCheckStartTime = $null

					if ($script:gpgReady) {
						# GPG was previously working — genuine touch waiting
						Update-CardState -Status "Touch"
					}
					else {
						# GPG has never responded — still initializing, not a touch
						if (-not $script:gpgNotReadySince) {
							$script:gpgNotReadySince = Get-Date
						}
						$notReadyElapsed = [int]((Get-Date) - $script:gpgNotReadySince).TotalSeconds
						Write-Log "GPG still initializing (not ready for ${notReadyElapsed}s)" -Level DEBUG

						if ($script:currentState -ne "Error") {
							Set-TrayIconState -State "Error"
							$script:currentState = "Error"
							$script:TrayIcon.Text = "YubiKey Tool - GPG Initializing..."
						}

						# Auto-recovery after 60s of continuous failure
						if ($notReadyElapsed -gt 60) {
							if ($script:autoRestartCount -lt 3) {
								$script:autoRestartCount++
								$script:gpgNotReadySince = $null
								Write-Log "GPG not ready for 60s, triggering auto-restart ($($script:autoRestartCount)/3)..." -Level WARN
								Start-AsyncRestart
							}
							else {
								Write-Log "GPG not ready after 3 auto-restarts, manual restart required" -Level ERROR
								$script:gpgNotReadySince = $null
								$script:TrayIcon.Text = "YubiKey Tool - GPG Error (Manual restart required)"
							}
						}
					}
				}
				# else: still running, wait for next tick
			}
			else {
				# 4. Start new gpg --card-status check (non-blocking)
				try {
					$psi = New-Object System.Diagnostics.ProcessStartInfo
					$psi.FileName = $GpgPath
					$psi.Arguments = "--card-status"
					$psi.UseShellExecute = $false
					$psi.RedirectStandardOutput = $true
					$psi.RedirectStandardError = $true
					$psi.CreateNoWindow = $true

					$proc = New-Object System.Diagnostics.Process
					$proc.StartInfo = $psi
					$proc.Start() | Out-Null

					$script:gpgCheckProcess = $proc
					$script:gpgCheckStartTime = Get-Date

					Write-Log "gpg --card-status started (PID: $($proc.Id))" -Level DEBUG
				}
				catch {
					Write-Log "Failed to start gpg --card-status: $_" -Level ERROR
					Update-CardState -Status "Error"
				}
			}
		}
		catch [System.Management.Automation.PipelineStoppedException] {
			[System.Windows.Forms.Application]::Exit()
		}
		catch {
			Write-Log "Error in timer tick: $_" -Level ERROR
		}
	})

	try {
		$timer.Start()

		# Run Windows Forms message loop
		[System.Windows.Forms.Application]::Run()
	}
	catch [System.Management.Automation.PipelineStoppedException] {
		# Ctrl+C pressed - exit gracefully
		Write-Log "Ctrl+C detected, exiting..." -Level INFO
	}
	catch {
		Write-Log "Error in message loop: $_" -Level ERROR
	}
	finally {
		$timer.Stop()
		$timer.Dispose()

		Write-Log "Stopping polling mode..."

		# Cleanup check process
		if ($script:gpgCheckProcess) {
			if (-not $script:gpgCheckProcess.HasExited) {
				try { $script:gpgCheckProcess.Kill() } catch { }
			}
			try { $script:gpgCheckProcess.Dispose() } catch { }
			$script:gpgCheckProcess = $null
		}

		# Cleanup background restart
		if ($script:bgRestart) {
			try { $script:bgRestart.PowerShell.Stop() } catch { }
			try { $script:bgRestart.PowerShell.Dispose() } catch { }
			try { $script:bgRestart.Runspace.Close() } catch { }
			try { $script:bgRestart.Runspace.Dispose() } catch { }
			$script:bgRestart = $null
		}

		# Cleanup background stop
		if ($script:bgStop) {
			try { $script:bgStop.PowerShell.Stop() } catch { }
			try { $script:bgStop.PowerShell.Dispose() } catch { }
			try { $script:bgStop.Runspace.Close() } catch { }
			try { $script:bgStop.Runspace.Dispose() } catch { }
			$script:bgStop = $null
		}

		# Unregister exit event handler
		if ($exitEventJob) {
			Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
			Remove-Job -Job $exitEventJob -Force -ErrorAction SilentlyContinue
		}

		# Cleanup tray icon
		Remove-TrayIcon

		Write-Log "Polling mode stopped"
	}
}

#endregion

#region Entry Point

# Script start
Write-Log "========================================"
Write-Log "YubiKey Tool for Windows"
Write-Log "========================================"

# AddStartup: Register to startup
if ($AddStartup) {
	Register-Startup
	exit 0
}

# RemoveStartup: Remove from startup
if ($RemoveStartup) {
	Unregister-Startup
	exit 0
}

# Stop: Terminate all instances and GPG processes
if ($Stop) {
	Write-Host "Stopping all yubikey-tool instances and GPG processes..." -ForegroundColor Yellow
	Stop-ExistingInstances
	Stop-Agents
	Write-Host "All processes stopped." -ForegroundColor Green
	exit 0
}

# Stop existing yubikey-tool instances first
Stop-ExistingInstances

# Record diagnostic information before stopping agents
Write-DiagnosticLog

# Restart gpg-agent / gpg-bridge
Restart-Agents | Out-Null

# Start touch detection
Start-PollingMode

#endregion
