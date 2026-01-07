<#
.SYNOPSIS
	YubiKey Tool for Windows - GPG Agent & Touch Detection

.DESCRIPTION
	Detects GPG + YubiKey touch operations and displays Windows Toast notifications.
	Manages gpg-agent and gpg-bridge together, cleaning up and restarting processes on launch.

	Detection method:
	- Periodically runs 'gpg --card-status' (polling)
	- If the command hangs (over 1 second), it's considered waiting for touch
	- Displays a Toast notification to prompt the user to touch

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
	- BurntToast module (Install-Module BurntToast)
	- YubiKey with touch policy enabled
	- Windows 10 1903 or later
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
			New-BurntToastNotification -Text $Title, $Message
			Write-Log "BurntToast notification displayed: $Title - $Message" -Level DEBUG
			return
		}
	}
	catch {
		Write-Log "BurntToast module unavailable: $($_.Exception.Message)" -Level DEBUG
	}

	# Fallback: Windows.UI.Notifications (PowerShell 7+)
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
		Write-Log "Windows.UI.Notifications unavailable: $($_.Exception.Message)" -Level DEBUG
	}

	Write-Log "Failed to display notification: $Title - $Message" -Level WARN
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

	Copy-Item -Path $scriptPath -Destination $installedScript -Force
	Write-Host "Script installed: $installedScript" -ForegroundColor Green

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
	$shortcut.Save()

	Write-Host "Registered to startup: $startupShortcut" -ForegroundColor Green

	# 2. Create .cmd for manual execution in .local\bin
	$cmdFile = Join-Path $installDir "yubikey-tool.cmd"
	$cmdContent = @"
@echo off
"$pwshPath" -ExecutionPolicy Bypass -File "%~dp0yubikey-tool.ps1"
timeout /t 10

"@
	Set-Content -Path $cmdFile -Value $cmdContent -Encoding ASCII

	Write-Host "Manual execution cmd created: $cmdFile" -ForegroundColor Green
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

	# Ask whether to delete files in .local\bin
	$installDir = Join-Path $env:USERPROFILE ".local\bin"
	$installedScript = Join-Path $installDir "yubikey-tool.ps1"
	$cmdFile = Join-Path $installDir "yubikey-tool.cmd"

	if ((Test-Path $installedScript) -or (Test-Path $cmdFile)) {
		Write-Host ""
		Write-Host "Installed files:" -ForegroundColor Cyan
		if (Test-Path $installedScript) { Write-Host "  - $installedScript" }
		if (Test-Path $cmdFile) { Write-Host "  - $cmdFile" }
		Write-Host ""

		$response = Read-Host "Delete these files as well? (y/N)"
		if ($response -eq "y" -or $response -eq "Y") {
			if (Test-Path $installedScript) {
				Remove-Item -Path $installedScript -Force
				Write-Host "Deleted: $installedScript" -ForegroundColor Green
			}
			if (Test-Path $cmdFile) {
				Remove-Item -Path $cmdFile -Force
				Write-Host "Deleted: $cmdFile" -ForegroundColor Green
			}
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
		Run gpg --card-status and detect hang
	.OUTPUTS
		Boolean: $true = hang (waiting for touch), $false = completed normally
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
			# Completed normally
			$exitCode = $process.ExitCode
			Write-Log "gpg --card-status completed (elapsed: ${elapsed}ms, exit code: $exitCode)" -Level DEBUG

			# Cleanup process
			$process.Dispose()

			return $false
		}
		else {
			# Timeout = hang
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

			return $true
		}
	}
	catch {
		Write-Log "Error during gpg --card-status execution: $_" -Level ERROR
		Write-Log "  Error details: $($_.Exception.Message)" -Level ERROR
		return $false
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

	$isHanging = Test-GpgCardStatus

	Write-Host ""
	if ($isHanging) {
		Write-Host "[OK] Hang detected! Waiting for touch" -ForegroundColor Green
		Write-Host "  Testing Toast notification..." -ForegroundColor Yellow
		Show-ToastNotification -Title "gpg-agent" -Message "Please touch or PIN your YubiKey"
		Write-Host "  Check if the notification appeared" -ForegroundColor Yellow
	}
	else {
		Write-Host "[NG] Hang not detected" -ForegroundColor Red
		Write-Host ""
		Write-Host "Possible causes:" -ForegroundColor Yellow
		Write-Host "  1. YubiKey touch policy is disabled" -ForegroundColor Yellow
		Write-Host "     -> Check with: ykman openpgp info" -ForegroundColor Yellow
		Write-Host "  2. Timeout setting is too short" -ForegroundColor Yellow
		Write-Host "     -> Try: -HangTimeout 2000" -ForegroundColor Yellow
		Write-Host "  3. GPG operation already completed" -ForegroundColor Yellow
		Write-Host "     -> Try again with better timing" -ForegroundColor Yellow
	}

	Write-Host ""
}

function Start-PollingMode {
	<#
	.SYNOPSIS
		Polling-based touch detection (no FileSystemWatcher needed)
	#>

	Write-Log "Starting polling mode"
	Write-Log "Check interval: ${CheckInterval}ms"

	$script:touchWaiting = $false
	$script:consecutiveNormalChecks = 0
	$touchDetectedTime = $null
	$loopCount = 0

	Write-Log "Polling mode running (Ctrl+C to exit)"

	try {
		while ($true) {
			$timestamp = Get-Date -Format "HH:mm:ss.fff"
			$loopCount++

			# Cleanup completed jobs every 10 iterations
			if ($loopCount % 10 -eq 0) {
				Get-Job | Where-Object { $_.State -eq 'Completed' } | Remove-Job -Force -ErrorAction SilentlyContinue
			}

			try {
				$isHanging = Test-GpgCardStatus
			}
			catch {
				Write-Log "Error during check: $_" -Level ERROR
				$isHanging = $false
			}

			if ($isHanging) {
				# Hang detected
				$script:consecutiveNormalChecks = 0

				if (-not $script:touchWaiting) {
					# New touch waiting state
					$script:touchWaiting = $true
					$touchDetectedTime = Get-Date

					Write-Log "YubiKey touch waiting detected"
					Show-ToastNotification -Title "gpg-agent" -Message "Please touch or PIN your YubiKey"
				}
				else {
					# Already in touch waiting state (continuing)
					$elapsed = ((Get-Date) - $touchDetectedTime).TotalSeconds
					Write-Log "   ... touch waiting continues (${elapsed}s)"
				}
			}
			else {
				# Normal (no hang)
				$script:consecutiveNormalChecks++

				if ($script:touchWaiting) {
					# Returned to normal from touch waiting state
					Write-Log "YubiKey touch completed"

					# Reset state
					$script:touchWaiting = $false
					$touchDetectedTime = $null
					$script:consecutiveNormalChecks = 0
				}
				else {
					# Normal state (do nothing)
					if ($script:consecutiveNormalChecks % 10 -eq 0) {
						Write-Log " - Normal (checks: $script:consecutiveNormalChecks)"
					}
				}
			}

			# Timeout handling (force reset if touch waiting state continues for over 30 seconds)
			if ($script:touchWaiting -and $touchDetectedTime) {
				$elapsed = ((Get-Date) - $touchDetectedTime).TotalSeconds
				if ($elapsed -gt 30) {
					Write-Log "Touch waiting state timed out (30s), resetting state" -Level WARN
					$script:touchWaiting = $false
					$touchDetectedTime = $null
					$script:consecutiveNormalChecks = 0
				}
			}

			Start-Sleep -Milliseconds $CheckInterval
		}
	}
	catch {
		# Catch Ctrl+C or other interrupt signals
		Write-Log "Exiting polling loop: $_"
	}
	finally {
		Write-Log "Stopping polling mode..."

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
