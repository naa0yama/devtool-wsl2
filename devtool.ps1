#!/usr/bin/env powershell

param (
	[switch]$skipWSLImport,
	[switch]$skipWSLDefault,
	[switch]$ImportForce,
	[switch]$Debug
)
$env:WSL_UTF8=1

# TLS 1.2を有効化（セキュアな通信のため）
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# エラーハンドリングの設定
$ErrorActionPreference = "Stop"

# エラーログファイルのパス
$logFile = "$env:USERPROFILE\devtool-error.log"

# ログ出力関数
function Write-Log {
	param (
		[string]$Message,
		[string]$Level = "INFO"
	)
	$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$logMessage = "[$timestamp] [$Level] $Message"
	Add-Content -Path $logFile -Value $logMessage
	Write-Host $logMessage
}

# エラーログをクリア
if (Test-Path $logFile) {
	Remove-Item $logFile -Force
}
Write-Log "Script execution begins"

function Get-LatestReleaseInfo {
	param (
		[string]$owner,
		[string]$repo
	)
	Write-Log "[DEBUG] Calling GitHub API for $owner/$repo"
	$apiUrl = "https://api.github.com/repos/$owner/$repo/releases/latest"
	$headers = @{
		"User-Agent" = "PowerShell"
	}
	$response = Invoke-RestMethod -Uri $apiUrl -Headers $headers
	return $response
}

function Download-Assets {
	param (
		[array]$assets,
		[string]$downloadPath,
		[int]$maxRetries = 5,
		[int]$retryDelaySeconds = 15
	)
	Write-Log "[DEBUG] Starting download of assets to $downloadPath using direct download method"
	$totalAssets = $assets.Count
	$currentAssetIndex = 0

	foreach ($asset in $assets) {
		if ($asset.name -like "*.tar.gz.part*" -or $asset.name -eq "sha256sum.txt") {
			$currentAssetIndex++
			$assetUrl = $asset.browser_download_url
			$outputFile = Join-Path $downloadPath $asset.name
			Write-Log "Downloading $($asset.name)"

			$retryCount = 0
			$downloadSuccess = $false

			while (-not $downloadSuccess -and $retryCount -lt $maxRetries) {
				try {
					if ($retryCount -gt 0) {
						Write-Log "Retry attempt $retryCount for $($asset.name)" -Level "INFO"
						Start-Sleep -Seconds ($retryDelaySeconds * $retryCount) # 指数バックオフ
					}

					# 一時ファイル名を使用（ファイルロック問題を回避）
					$tempFile = "$outputFile.tmp"

					# 既存のファイルがある場合は削除
					if (Test-Path $tempFile) {
						try {
							Remove-Item $tempFile -Force -ErrorAction Stop
							Write-Log "Removed existing temp file: $tempFile" -Level "INFO"
						} catch {
							Write-Log "Failed to remove temp file: $tempFile. Error: $_" -Level "ERROR"
							$retryCount++
							continue
						}
					}

					# 既存の出力ファイルがある場合は削除
					if (Test-Path $outputFile) {
						try {
							Remove-Item $outputFile -Force -ErrorAction Stop
							Write-Log "Removed existing output file: $outputFile" -Level "INFO"
						} catch {
							Write-Log "Failed to remove output file: $outputFile. Error: $_" -Level "ERROR"
							$retryCount++
							continue
						}
					}

					# curlを使用してダウンロード（最初から最も信頼性の高い方法を使用）
					Write-Log "Starting download using curl to temp file: $tempFile" -Level "INFO"

					try {
						# curl.exeが存在するか確認
						$curlPath = "curl.exe"
						if (-not (Get-Command $curlPath -ErrorAction SilentlyContinue)) {
							Write-Log "curl.exe not found in PATH. Trying Windows built-in curl..." -Level "INFO"
							$curlPath = "$env:SystemRoot\System32\curl.exe"

							if (-not (Test-Path $curlPath)) {
								Write-Log "Windows built-in curl.exe not found. Cannot proceed with download." -Level "ERROR"
								throw "curl.exe not found"
							}
						}

						# curlを使用してダウンロード
						$curlArgs = @(
							"-L", # リダイレクトに従う
							"-o", $tempFile, # 出力ファイル
							"--retry", "5", # リトライ回数
							"--retry-delay", "5", # リトライ間隔（秒）
							"--retry-max-time", "60", # 最大リトライ時間（秒）
							"--connect-timeout", "30", # 接続タイムアウト（秒）
							"--max-time", "3600", # 最大実行時間（秒）
							"--keepalive-time", "60", # キープアライブ時間（秒）
							$assetUrl # URL
						)

						Write-Log "Executing curl command: $curlPath $($curlArgs -join ' ')" -Level "INFO"
						Write-Log "Download started at $(Get-Date)" -Level "INFO"

						# curlプロセスを開始
						$curlProcess = Start-Process -FilePath $curlPath -ArgumentList $curlArgs -NoNewWindow -PassThru -Wait

						Write-Log "Download completed at $(Get-Date) with exit code: $($curlProcess.ExitCode)" -Level "INFO"

						if ($curlProcess.ExitCode -ne 0) {
							Write-Log "curl failed with exit code: $($curlProcess.ExitCode)" -Level "ERROR"
							throw "curl download failed with exit code: $($curlProcess.ExitCode)"
						}
					} catch {
						Write-Log "Error during curl download: $_" -Level "ERROR"
						throw
					}

					# ダウンロード完了の確認
					if (Test-Path $tempFile) {
						$downloadedFileSize = (Get-Item $tempFile).Length
						if ($downloadedFileSize -gt 0) {
							# 一時ファイルを最終ファイルにリネーム
							try {
								Move-Item -Path $tempFile -Destination $outputFile -Force -ErrorAction Stop
								Write-Log "Download Complete: $($asset.name) (Size: $downloadedFileSize bytes)" -Level "INFO"
								$downloadSuccess = $true
							} catch {
								Write-Log "Failed to rename temp file to output file: $_" -Level "ERROR"
								$retryCount++
							}
						} else {
							Write-Log "Download resulted in empty file" -Level "ERROR"
							$retryCount++
						}
					} else {
						Write-Log "Download failed: Temp file not found" -Level "ERROR"
						$retryCount++
					}
				} catch {
					Write-Log "An error occurred while downloading $($asset.name): $_" -Level "ERROR"
					$retryCount++
				}
			}

			if (-not $downloadSuccess) {
				Write-Log "Failed to download $($asset.name) after $maxRetries attempts" -Level "ERROR"

				# 最後の手段として、Invoke-WebRequestを使用してダウンロードを試みる
				try {
					Write-Log "Attempting to download $($asset.name) using Invoke-WebRequest as fallback" -Level "INFO"

					# 一時ファイル名を使用
					$tempFile = "$outputFile.iwr.tmp"

					# 既存のファイルがある場合は削除
					if (Test-Path $tempFile) {
						try {
							Remove-Item $tempFile -Force -ErrorAction Stop
						} catch {
							Write-Log "Failed to remove Invoke-WebRequest temp file: $_" -Level "ERROR"
							continue
						}
					}

					# Invoke-WebRequestを使用してダウンロード
					Write-Log "Download started at $(Get-Date) using Invoke-WebRequest" -Level "INFO"
					Invoke-WebRequest -Uri $assetUrl -OutFile $tempFile -UseBasicParsing -TimeoutSec 3600
					Write-Log "Download completed at $(Get-Date) using Invoke-WebRequest" -Level "INFO"

					if (Test-Path $tempFile) {
						$fileSize = (Get-Item $tempFile).Length
						if ($fileSize -gt 0) {
							# 一時ファイルを最終ファイルにリネーム
							try {
								Move-Item -Path $tempFile -Destination $outputFile -Force -ErrorAction Stop
								Write-Log "Fallback download complete using Invoke-WebRequest: $($asset.name) (Size: $fileSize bytes)" -Level "INFO"
								$downloadSuccess = $true
							} catch {
								Write-Log "Failed to rename Invoke-WebRequest temp file to output file: $_" -Level "ERROR"
							}
						} else {
							Write-Log "Fallback download with Invoke-WebRequest produced empty file" -Level "ERROR"
						}
					} else {
						Write-Log "Fallback download with Invoke-WebRequest failed: temp file not found" -Level "ERROR"
					}
				} catch {
					Write-Log "Fallback download with Invoke-WebRequest also failed for $($asset.name): $_" -Level "ERROR"
				}
			}
		}
	}
}

function Verify-Hashes {
	param (
		[string]$downloadPath,
		[switch]$skipMissingFiles
	)
	$sha256sumFile = Join-Path $downloadPath "sha256sum.txt"
	if (Test-Path $sha256sumFile) {
		$hashes = @(Get-Content $sha256sumFile | Where-Object { $_.Trim() -ne "" } | ForEach-Object {
			$parts = $_ -split '  '  # Note the double space
			@{
				Hash = $parts[0]
				File = $parts[1].Trim()
			}
		})

		$totalFiles = $hashes.Count
		$matchedFiles = 0
		$missingFiles = 0

		for ($i = 0; $i -lt $totalFiles; $i++) {
			$hash = $hashes[$i]
			$filePath = Join-Path $downloadPath $hash.File
			if (Test-Path $filePath) {
				$fileHash = Get-FileHash -Path $filePath -Algorithm SHA256
				if ($fileHash.Hash -eq $hash.Hash) {
					Write-Log "[$($i + 1)/$totalFiles] $($hash.File) hash matches."
					$matchedFiles++
				} else {
					Write-Log "[$($i + 1)/$totalFiles] $($hash.File) hash does not match."
				}
			} else {
				Write-Log "[$($i + 1)/$totalFiles] $($hash.File) not found."
				$missingFiles++
			}
		}

		if ($matchedFiles -eq $totalFiles) {
			Write-Log "`nAll file hashes match."
			return $true
		} elseif ($skipMissingFiles -and $matchedFiles + $missingFiles -eq $totalFiles) {
			Write-Log "`nSome files are missing, but all existing files match their hashes." -ForegroundColor Yellow
			return $true
		} else {
			Write-Log "`nSome file hashes do not match." -ForegroundColor Red
			return $false
		}
	} else {
		Write-Log "`nsha256sum.txt file not found." -ForegroundColor Red
		return $false
	}
}

function Combine-Parts {
	param (
		[string]$downloadPath
	)
	$partFiles = Get-ChildItem -Path $downloadPath -Filter "*.tar.gz.part*" | Sort-Object Name
	if ($partFiles.Count -gt 0) {
		$baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($partFiles[0].Name).Replace(".part", "")
		$outputFile = Join-Path $downloadPath $baseFileName
		Write-Log "Combining parts into $outputFile"

		$outputStream = [System.IO.File]::Create($outputFile)
		foreach ($partFile in $partFiles) {
			$inputStream = [System.IO.File]::OpenRead($partFile.FullName)
			$buffer = New-Object byte[] 8388608 # 8MB
			$read = 0
			while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
				$outputStream.Write($buffer, 0, $read)
			}
			$inputStream.Close()
		}
		$outputStream.Close()
		Write-Log "Combination Complete"
		return $outputFile
	} else {
		Write-Log "No part files found to combine."
		return $null
	}
}

function Import-WSL {
	param (
		[string]$wslPath,
		[string]$tag_name,
		[string]$tarGzFile,
		[bool]$skipWSLDefault = $false,
		[bool]$ImportForce    = $false
	)

	Write-Log "`nExecuting backup script on current default WSL distribution..."
	try {
		$wslListOutput = wsl --list --verbose
		$defaultDistro = $null

		foreach ($line in $wslListOutput) {
			if ($line -match '^\s*\*\s*(\S+)') {
				$defaultDistro = $matches[1]
				break
			}
		}

		if ($defaultDistro) {
			Write-Log "Current default WSL distribution: $defaultDistro"
			Write-Log "Running backup script on $defaultDistro..."
			wsl -d $defaultDistro bash /usr/local/bin/backup.sh
			Write-Log "Backup script executed successfully on $defaultDistro."
		} else {
			Write-Log "No default WSL distribution found." -ForegroundColor Yellow
		}
	} catch {
		Write-Log "Error executing backup script on default WSL distribution: $_" -ForegroundColor Red
	}

	if ($ImportForce) {
		Write-Log "[ImportForce] is enabled. Listing WSL instances..."

		$wslOutput = wsl --list --quiet
		$wslLines = $wslOutput -split "`n"
		foreach ($line in $wslLines) {
			$_line = $line.Trim()
			if ($_line -match '^dwsl2-*') {
				try {
					wsl --unregister $_line | Out-Null
					Write-Log "[ImportForce] Successfully unregistered [$_line]"
				} catch {
					Write-Log "[ImportForce] Failed to unregister [$_line] : $_"
				}
			}
		}
	}

	$importPath = Join-Path $wslPath $tag_name
	if (-Not (Test-Path -Path $importPath)) {
		New-Item -ItemType Directory -Path $importPath | Out-Null
	}

	Write-Log "`nImporting WSL"
	wsl --import dwsl2-$tag_name $importPath $tarGzFile --version 2
	Write-Log "`nWSL imported successfully."

	if (-not $skipWSLDefault) {
		Write-Log "`nSetting WSL default Distribution"
		wsl --set-default dwsl2-$tag_name
	}
}

function Create-Dir {
	param (
		[string]$wslPath,
		[string]$downloadPath
	)
	if (-Not (Test-Path -Path $wslPath)) {
		Write-Log "Create WSL2 path $wslPath"
		New-Item -ItemType Directory -Path $wslPath | Out-Null
	}

	if (-Not (Test-Path -Path $downloadPath)) {
		Write-Log "Create downloaded path $downloadPath"
		New-Item -ItemType Directory -Path $downloadPath | Out-Null
	}
}

function Cleanup-DownloadPath {
	param (
		[string]$downloadPath
	)

	Write-Log "Cleanup ..."
	Remove-Item -Path $downloadPath -Recurse
	Write-Log "`nCleaned up parent directory: $downloadPath"
}

function Main {
	param (
		[switch]$skipWSLImport,
		[switch]$skipWSLDefault,
		[switch]$ImportForce,
		[switch]$Debug
	)
	$ownerRepo = "naa0yama/devtool-wsl2"
	Write-Log "[DEBUG] Starting Main function with parameters: skipWSLImport=$skipWSLImport, skipWSLDefault=$skipWSLDefault, ImportForce=$ImportForce, Debug=$Debug"

	$owner = "naa0yama"
	$repo = "devtool-wsl2"

	try {
		Write-Log "[DEBUG] Attempting to get latest release info"
		$apiUrl = "https://api.github.com/repos/$owner/$repo/releases/latest"
		$headers = @{
			"User-Agent" = "PowerShell"
		}
		$apiUrlMessage = "GitHub API: " + $apiUrl
		Write-Log "[DEBUG] Calling $apiUrlMessage"
		$response = Invoke-RestMethod -Uri $apiUrl -Headers $headers
		Write-Log "[DEBUG] Response received from GitHub API"
		$assets   = $response.assets
		$tag_name = $response.tag_name
		$html_url = $response.html_url
		$wslPath = "$env:USERPROFILE\Documents\WSL2"
		$downloadPath = "$wslPath\dl\$tag_name"
		Write-Log "[DEBUG] WSL Path: $wslPath"
		Write-Log "[DEBUG] Download Path: $downloadPath"

		Clear-Host
		Write-Log "////////////////////////////////////////////////////////////////////////////////"
		Write-Log "//      _            _              _                     _  _____ "
		Write-Log '//     | |          | |            | |                   | |/ __  \'
		Write-Log "//   __| | _____   _| |_ ___   ___ | |________      _____| |' / /'"
		Write-Log "//  / _' |/ _ \ \ / / __/ _ \ / _ \| |______\ \ /\ / / __| |  / /  "
		Write-Log "// | (_| |  __/\ V /| || (_) | (_) | |       \ V  V /\__ \ |./ /___"
		Write-Log "//  \__,_|\___| \_/  \__\___/ \___/|_|        \_/\_/ |___/_|\_____/"
		Write-Log "//"
		Write-Log "//"
		Write-Log "// The latest tag is`t`t$tag_name"
		Write-Log "// The latest Release Pages is`t$html_url"
		Write-Log "// WSL2 Path`t`t`t$wslPath"
		Write-Log "// Downloaded Path`t`t$downloadPath"
		Write-Log "//"
		Write-Log "// Options:"
		Write-Log "//`tskipWSLImport`t`t$skipWSLImport"
		Write-Log "//`tskipWSLDefault`t`t$skipWSLDefault"
		Write-Log "//`tImportForce`t`t$ImportForce"
		Write-Log "//"

		Create-Dir $wslPath $downloadPath

		# Run the download
		Download-Assets -assets $assets -downloadPath $downloadPath

		# Perform hash verification (ダウンロードに失敗したファイルがあっても続行)
		if (Verify-Hashes -downloadPath $downloadPath -skipMissingFiles) {
			# Executes the combination of part files
			$tarGzFile = Combine-Parts -downloadPath $downloadPath

			if (-not $skipWSLImport -and $tarGzFile) {
				Import-WSL -wslPath $wslPath -tag_name $tag_name `
					-tarGzFile $tarGzFile -skipWSLDefault:$skipWSLDefault -ImportForce:$ImportForce
			}
		} else {
			Write-Log "`n`nHash verification failed. Aborting combination process." -ForegroundColor Red
			exit 1
		}
	} catch {
		Write-Log "`nAn error occurred: $_" -ForegroundColor Red
		exit 1
	} finally {
		if (-not $skipWSLImport) {
			Cleanup-DownloadPath -downloadPath $downloadPath
		}
	}
}

# デバッグモードの場合は、GitHub APIのテストのみを行う
if ($Debug) {
    try {
        Write-Log "Debug mode: Runs tests against the GitHub API" -Level "INFO"
        $owner = "naa0yama"
        $repo = "devtool-wsl2"
        $apiUrl = "https://api.github.com/repos/$owner/$repo/releases/latest"
        $headers = @{
            "User-Agent" = "PowerShell"
        }
        $apiUrlInfo = "GitHub API URL: " + $apiUrl
        Write-Log $apiUrlInfo -Level "INFO"
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers
        Write-Log "GitHub API レスポンス: $($response | ConvertTo-Json -Depth 1)" -Level "INFO"
        Write-Log "GitHub API テスト成功" -Level "INFO"
        exit 0
    } catch {
        Write-Log "GitHub API テスト失敗: $_" -Level "ERROR"
        exit 1
    }
}

# 通常モードの場合は、通常の処理を実行
Main -skipWSLImport:$skipWSLImport -skipWSLDefault:$skipWSLDefault -ImportForce:$ImportForce -Debug:$Debug
