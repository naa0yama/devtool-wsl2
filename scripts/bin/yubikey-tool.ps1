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

	System tray menu:
	- Restart Agents: Restart gpg-agent and gpg-bridge
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

.PARAMETER TestMode
	Mode for manually testing touch detection

.PARAMETER AddStartup
	Register shortcut to Windows startup (shell:startup)

.PARAMETER RemoveStartup
	Remove shortcut from Windows startup

.EXAMPLE
	.\yubikey-tool.ps1

.EXAMPLE
	.\yubikey-tool.ps1 -GpgBridgeArgs "--extra 127.0.0.1:4321 --ssh \\.\pipe\gpg-bridge-ssh"

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
	[switch]$TestMode = $false,

	[Parameter()]
	[switch]$AddStartup = $false,

	[Parameter()]
	[switch]$RemoveStartup = $false
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

#region Configuration

# GPG executable path
$GpgPath = (Get-Command gpg.exe -ErrorAction SilentlyContinue).Source
if (-not $GpgPath) {
	Write-Error "gpg.exe not found. Please install GnuPG."
	Write-Error "PS:> winget install GnuPG.Gpg4win"
	exit 1
}

# Log file (with date suffix, keep 5 files)
$LogFileBase = "yubikey-tool"
$LogFileDate = Get-Date -Format "yyyyMMdd"
$LogFile = Join-Path $env:TEMP "${LogFileBase}-${LogFileDate}.log"

# Cleanup old log files (keep only 5)
$logFiles = Get-ChildItem -Path $env:TEMP -Filter "${LogFileBase}-*.log" -ErrorAction SilentlyContinue |
	Sort-Object LastWriteTime -Descending
if ($logFiles.Count -gt 5) {
	$logFiles | Select-Object -Skip 5 | ForEach-Object {
		Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
	}
}

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
	Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
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
		Stop-Agents
		Start-GpgAgent | Out-Null
		Start-GpgBridge | Out-Null
		$script:TrayIcon.ShowBalloonTip(2000, "YubiKey Tool", "Agents restarted", [System.Windows.Forms.ToolTipIcon]::Info)
	})
	$contextMenu.Items.Add($menuRestart) | Out-Null

	# Menu item: Show Log
	$menuShowLog = New-Object System.Windows.Forms.ToolStripMenuItem
	$menuShowLog.Text = "Show Log"
	$menuShowLog.Add_Click({
		Write-Log "Opening log file from tray menu..."
		if (Test-Path $LogFile) {
			Start-Process notepad.exe -ArgumentList $LogFile
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
		$script:TrayIcon.Visible = $false
		$script:TrayIcon.Dispose()
		[System.Windows.Forms.Application]::Exit()
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
		[ref]$script:IconError
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
		Icon state: "Normal", "Touch", "NoCard", "Error"
	#>
	param(
		[Parameter(Mandatory)]
		[ValidateSet("Normal", "Touch", "NoCard", "Error")]
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

function Stop-Agents {
	<#
	.SYNOPSIS
		Safely stop gpg-agent and gpg-bridge processes
	#>

	Write-Log "Stopping existing GPG processes..."

	# Stop gpg-agent
	$gpgAgentProcesses = Get-Process -Name "gpg-agent" -ErrorAction SilentlyContinue
	if ($gpgAgentProcesses) {
		Write-Log "Terminating gpg-agent processes: $($gpgAgentProcesses.Count)"
		$gpgAgentProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
		Start-Sleep -Milliseconds 500
	}

	# Stop gpg-bridge
	$processes = Get-Process -Name "gpg-bridge" -ErrorAction SilentlyContinue
	if ($processes) {
		Write-Log "Terminating gpg-bridge processes: $($processes.Count)"
		$processes | Stop-Process -Force -ErrorAction SilentlyContinue
	}

	Start-Sleep -Milliseconds 500
	Write-Log "GPG processes stopped"
}

function Start-GpgAgent {
	<#
	.SYNOPSIS
		Start gpg-agent
	#>

	Write-Log "Starting gpg-agent..."

	try {
		# Start via gpg-connect-agent
		$result = & gpg-connect-agent "/bye" 2>&1
		if ($LASTEXITCODE -ne 0) {
			Write-Log "gpg-connect-agent exited abnormally (exit code: $LASTEXITCODE): $result" -Level WARN
		}
		else {
			Write-Log "gpg-agent started: $result" -Level DEBUG
		}

		# Verify startup
		Start-Sleep -Milliseconds 500
		$agentProcess = Get-Process -Name "gpg-agent" -ErrorAction SilentlyContinue
		if ($agentProcess) {
			Write-Log "gpg-agent started (PID: $($agentProcess.Id))"
			return $true
		}
		else {
			Write-Log "Could not verify gpg-agent startup" -Level WARN
			return $false
		}
	}
	catch {
		Write-Log "Failed to start gpg-agent: $_" -Level ERROR
		return $false
	}
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

function Test-GpgCardStatus {
	<#
	.SYNOPSIS
		Run gpg --card-status and detect hang or error
	.OUTPUTS
		String: "Normal" = completed successfully
		        "Touch" = hang (waiting for touch)
		        "NoCard" = card not present or error (exit code 2)
		        "Error" = other error
	#>

	$startTime = Get-Date
	Write-Log "gpg --card-status check started (timeout: ${HangTimeout}ms)" -Level DEBUG

	try {
		# Start as Process (lighter and more reliable than Job)
		$psi = New-Object System.Diagnostics.ProcessStartInfo
		$psi.FileName = $GpgPath
		$psi.Arguments = "--card-status"
		$psi.UseShellExecute = $false
		$psi.RedirectStandardOutput = $true
		$psi.RedirectStandardError = $true
		$psi.CreateNoWindow = $true

		$process = New-Object System.Diagnostics.Process
		$process.StartInfo = $psi

		$process.Start() | Out-Null

		# Wait with timeout
		$completed = $process.WaitForExit($HangTimeout)

		$elapsed = ((Get-Date) - $startTime).TotalMilliseconds

		if ($completed) {
			# Completed (check exit code)
			$exitCode = $process.ExitCode
			# Read both stdout and stderr to prevent buffer deadlock
			$null = $process.StandardOutput.ReadToEnd()
			$stderr = $process.StandardError.ReadToEnd()
			Write-Log "gpg --card-status completed (elapsed: ${elapsed}ms, exit code: $exitCode)" -Level DEBUG

			# Cleanup process
			$process.Dispose()

			if ($exitCode -eq 0) {
				return "Normal"
			}
			elseif ($exitCode -eq 2) {
				# Card not present or similar error
				if ($stderr -match "No such device|card not present|Card not present") {
					Write-Log "No card detected: $stderr" -Level DEBUG
					return "NoCard"
				}
				return "Error"
			}
			else {
				Write-Log "gpg --card-status failed with exit code $exitCode : $stderr" -Level WARN
				return "Error"
			}
		}
		else {
			# Timeout = hang (waiting for touch)
			Write-Log "gpg --card-status hang detected! (timeout: ${elapsed}ms)" -Level INFO

			# Force terminate process
			try {
				if (-not $process.HasExited) {
					$process.Kill()
					$process.WaitForExit(1000) | Out-Null
				}
			}
			catch {
				Write-Log "Error while terminating process: $_" -Level DEBUG
			}
			finally {
				$process.Dispose()
			}

			return "Touch"
		}
	}
	catch {
		Write-Log "Error during gpg --card-status execution: $_" -Level ERROR
		Write-Log "  Error details: $($_.Exception.Message)" -Level ERROR
		return "Error"
	}
}

#endregion

#region Main Processing

function Test-ManualGpgCardStatus {
	<#
	.SYNOPSIS
		Manually test gpg --card-status hang detection
	#>

	Write-Host "========================================" -ForegroundColor Cyan
	Write-Host "gpg --card-status Manual Test Mode" -ForegroundColor Cyan
	Write-Host "========================================" -ForegroundColor Cyan
	Write-Host ""
	Write-Host "Please perform a GPG operation (e.g., git commit -S)"
	Write-Host "Press Enter immediately when YubiKey is waiting for touch"
	Write-Host ""

	Read-Host "Press Enter when ready"

	Write-Host ""
	Write-Host "Checking gpg --card-status..." -ForegroundColor Yellow

	$status = Test-GpgCardStatus

	Write-Host ""
	switch ($status) {
		"Touch" {
			Write-Host "[OK] Hang detected! Waiting for touch" -ForegroundColor Green
			Write-Host "  Testing Toast notification..." -ForegroundColor Yellow
			Show-ToastNotification -Title "gpg-agent" -Message "Please touch or PIN your YubiKey"
			Write-Host "  Check if the notification appeared" -ForegroundColor Yellow
		}
		"NoCard" {
			Write-Host "[INFO] No card detected" -ForegroundColor Yellow
			Write-Host "  YubiKey is not inserted or not recognized" -ForegroundColor Yellow
		}
		"Normal" {
			Write-Host "[OK] Card status check completed normally" -ForegroundColor Green
			Write-Host "  YubiKey is connected and responding" -ForegroundColor Green
		}
		default {
			Write-Host "[NG] Error or unexpected state: $status" -ForegroundColor Red
			Write-Host ""
			Write-Host "Possible causes:" -ForegroundColor Yellow
			Write-Host "  1. YubiKey touch policy is disabled" -ForegroundColor Yellow
			Write-Host "     -> Check with: ykman openpgp info" -ForegroundColor Yellow
			Write-Host "  2. Timeout setting is too short" -ForegroundColor Yellow
			Write-Host "     -> Try: -HangTimeout 2000" -ForegroundColor Yellow
			Write-Host "  3. GPG operation already completed" -ForegroundColor Yellow
			Write-Host "     -> Try again with better timing" -ForegroundColor Yellow
		}
	}

	Write-Host ""
}

function Update-CardState {
	<#
	.SYNOPSIS
		Process GPG card status and update state machine
	.PARAMETER Status
		Card status from Test-GpgCardStatus
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
				Write-Log "GPG error detected, restarting agents..." -Level WARN
				Set-TrayIconState -State "Error"
				$script:currentState = "Error"
				$script:touchDetectedTime = $null

				try {
					Stop-Agents
					Start-Sleep -Milliseconds 500
					Start-GpgAgent | Out-Null
					Start-GpgBridge | Out-Null
					Write-Log "Agents restarted automatically"
					$script:TrayIcon.ShowBalloonTip(3000, "YubiKey Tool", "Agents restarted due to error", [System.Windows.Forms.ToolTipIcon]::Warning)
				}
				catch {
					Write-Log "Failed to restart agents: $_" -Level ERROR
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
		Polling-based touch detection with system tray icon
	#>

	Write-Log "Starting polling mode"
	Write-Log "Check interval: ${CheckInterval}ms"

	$script:currentState = "Normal"
	$script:touchDetectedTime = $null
	$script:loopCount = 0

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

			# Cleanup completed jobs periodically
			if ($script:loopCount % 10 -eq 0) {
				Get-Job | Where-Object { $_.State -eq 'Completed' } | Remove-Job -Force -ErrorAction SilentlyContinue
			}

			$status = try { Test-GpgCardStatus } catch { Write-Log "Error during check: $_" -Level ERROR; "Error" }
			Update-CardState -Status $status
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

		# Unregister exit event handler
		if ($exitEventJob) {
			Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
			Remove-Job -Job $exitEventJob -Force -ErrorAction SilentlyContinue
		}

		# Cleanup tray icon
		Remove-TrayIcon

		# Cleanup all remaining jobs
		try {
			$jobs = Get-Job -ErrorAction SilentlyContinue
			if ($jobs) {
				Write-Log "Cleaning up remaining jobs: $($jobs.Count)"
				$jobs | Stop-Job -ErrorAction SilentlyContinue
				$jobs | Remove-Job -Force -ErrorAction SilentlyContinue
			}
		}
		catch {
			Write-Log "Error during job cleanup: $_" -Level WARN
		}

		Write-Log "Polling mode stopped"
	}
}

#endregion

#region Entry Point

# Script start
Write-Log "========================================"
Write-Log "YubiKey Tool for Windows"
Write-Log "========================================"

# TestMode: Manual test
if ($TestMode) {
	Test-ManualGpgCardStatus
	exit 0
}

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

# Restart gpg-agent / gpg-bridge
Stop-Agents
Start-GpgAgent | Out-Null
Start-GpgBridge | Out-Null

# Start touch detection
Start-PollingMode

#endregion
