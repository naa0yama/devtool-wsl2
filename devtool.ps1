#!/usr/bin/env powershell

param (
	[switch]$skipWSLImport,
	[switch]$skipWSLDefault,
	[switch]$ImportForce
)
$env:WSL_UTF8=1

function Get-LatestReleaseInfo {
	param (
		[string]$owner,
		[string]$repo
	)
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
		[string]$downloadPath
	)
	Add-Type -AssemblyName System.Net.Http
	$httpClient = [System.Net.Http.HttpClient]::new()
	$totalAssets = $assets.Count
	$currentAssetIndex = 0

	foreach ($asset in $assets) {
		if ($asset.name -like "*.tar.gz.part*" -or $asset.name -eq "sha256sum.txt") {
			$currentAssetIndex++
			$assetUrl = $asset.browser_download_url
			$outputFile = Join-Path $downloadPath $asset.name
			Write-Host "Downloading $($asset.name)"

			try {
				$response = $httpClient.GetAsync($assetUrl, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
				$response.EnsureSuccessStatusCode() | Out-Null

				$totalBytes = $response.Content.Headers.ContentLength
				$stream = $response.Content.ReadAsStreamAsync().Result
				$fileStream = [System.IO.File]::Create($outputFile)
				$buffer = New-Object byte[] 8388608 # 8MB
				$totalRead = 0
				$read = 0
				$lastProgress = 0

				while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
					$fileStream.Write($buffer, 0, $read)
					$totalRead += $read
					$percentComplete = [math]::Round(($totalRead / $totalBytes) * 100, 2)
					if ($percentComplete -ge $lastProgress + 1) {
						Write-Progress `
						-Activity "Downloading $($asset.name) ($currentAssetIndex of $totalAssets)" `
						-Status "$percentComplete% Complete" `
						-PercentComplete $percentComplete
						$lastProgress = $percentComplete
					}
				}

				$fileStream.Close()
				$stream.Close()

				# Check the file size after download
				$downloadedFileSize = (Get-Item $outputFile).Length
				if ($downloadedFileSize -eq $totalBytes) {
					Write-Host "Download Complete: $($asset.name)"
				} else {
					Write-Error "Download incomplete or corrupted: $($asset.name). Expected size: $totalBytes, Actual size: $downloadedFileSize"
				}
			} catch [System.Net.Http.HttpRequestException] {
				Write-Error "Network or DNS error occurred while downloading $($asset.name): $_"
			} catch {
				Write-Error "An error occurred while downloading $($asset.name): $_"
			} finally {
				if ($fileStream) {
					$fileStream.Close()
				}
				if ($stream) {
					$stream.Close()
				}
			}
		}
	}
	$httpClient.Dispose()
}

function Verify-Hashes {
	param (
		[string]$downloadPath
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

		for ($i = 0; $i -lt $totalFiles; $i++) {
			$hash = $hashes[$i]
			$filePath = Join-Path $downloadPath $hash.File
			if (Test-Path $filePath) {
				$fileHash = Get-FileHash -Path $filePath -Algorithm SHA256
				if ($fileHash.Hash -eq $hash.Hash) {
					Write-Host "[$($i + 1)/$totalFiles] $($hash.File) hash matches."
					$matchedFiles++
				} else {
					Write-Host "[$($i + 1)/$totalFiles] $($hash.File) hash does not match."
				}
			} else {
				Write-Host "[$($i + 1)/$totalFiles] $($hash.File) not found."
			}
		}

		if ($matchedFiles -eq $totalFiles) {
			Write-Host "`nAll file hashes match."
			return $true
		} else {
			Write-Host "`nSome file hashes do not match." -ForegroundColor Red
			return $false
		}
	} else {
		Write-Host "`nsha256sum.txt file not found." -ForegroundColor Red
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
		Write-Host "Combining parts into $outputFile"

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
		Write-Host "Combination Complete"
		return $outputFile
	} else {
		Write-Host "No part files found to combine."
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

	if ($ImportForce) {
		Write-Host "[ImportForce] is enabled. Listing WSL instances..."

		$wslOutput = wsl --list --quiet
		$wslLines = $wslOutput -split "`n"
		foreach ($line in $wslLines) {
			$_line = $line.Trim()
			if ($_line -match '^dwsl2-*') {
				try {
					wsl --unregister $_line | Out-Null
					Write-Host "[ImportForce] Successfully unregistered [$_line]"
				} catch {
					Write-Host "[ImportForce] Failed to unregister [$_line] : $_"
				}
			}
		}
	}

	$importPath = Join-Path $wslPath $tag_name
	if (-Not (Test-Path -Path $importPath)) {
		New-Item -ItemType Directory -Path $importPath | Out-Null
	}

	Write-Host "`nImporting WSL"
	wsl --import dwsl2-$tag_name $importPath $tarGzFile --version 2
	Write-Host "`nWSL imported successfully."

	if ($skipWSLDefault) {
		Write-Host "`nSetting WSL default Distribution"
		wsl --set-default dwsl2-$tag_name
	}
}
function Create-Dir {
	param (
		[string]$wslPath,
		[string]$downloadPath
	)
	if (-Not (Test-Path -Path $wslPath)) {
		Write-Host "Create WSL2 path $wslPath"
		New-Item -ItemType Directory -Path $wslPath | Out-Null
	}

	if (-Not (Test-Path -Path $downloadPath)) {
		Write-Host "Create downloaded path $downloadPath"
		New-Item -ItemType Directory -Path $downloadPath | Out-Null
	}
}

function Cleanup-DownloadPath {
	param (
		[string]$downloadPath
	)

	Write-Host "Cleanup ..."
	Remove-Item -Path $downloadPath -Recurse
	Write-Host "`nCleaned up parent directory: $downloadPath"
}

function Main {
	param (
		[switch]$skipWSLImport,
		[switch]$skipWSLDefault,
		[switch]$ImportForce
	)

	$owner = "naa0yama"
	$repo = "devtool-wsl2"

	try {
		$response = Get-LatestReleaseInfo -owner $owner -repo $repo
		$assets   = $response.assets
		$tag_name = $response.tag_name
		$html_url = $response.html_url
		$wslPath = "$env:USERPROFILE\Documents\WSL2"
		$downloadPath = "$wslPath\dl\$tag_name"
		Create-Dir $wslPath $downloadPath

		Write-Host "////////////////////////////////////////////////////////////////////////////////"
		Write-Host "//`t     _            _              _                     _  _____ "
		Write-Host "//`t    | |          | |            | |                   | |/ __  \"
		Write-Host "//`t  __| | _____   _| |_ ___   ___ | |________      _____| |`' / /'"
		Write-Host "//`t / _` |/ _ \ \ / / __/ _ \ / _ \| |______\ \ /\ / / __| |  / /  "
		Write-Host "//`t| (_| |  __/\ V /| || (_) | (_) | |       \ V  V /\__ \ |./ /___"
		Write-Host "//`t \__,_|\___| \_/  \__\___/ \___/|_|        \_/\_/ |___/_|\_____/"
		Write-Host "//"
		Write-Host "//"
		Write-Host "// The latest tag is`t`t$tag_name"
		Write-Host "// The latest Release Pages is`t$html_url"
		Write-Host "// WSL2 Path`t`t`t$wslPath"
		Write-Host "// Downloaded Path`t`t$downloadPath"
		Write-Host "//"
		Write-Host "// Options:"
		Write-Host "//`tskipWSLImport`t`t$skipWSLImport"
		Write-Host "//`tskipWSLDefault`t`t$skipWSLDefault"
		Write-Host "//`tImportForce`t`t$ImportForce"
		Write-Host "//"

		# Run the download
		# Download-Assets -assets $assets -downloadPath $downloadPath

		# Perform hash verification
		if (Verify-Hashes -downloadPath $downloadPath) {
			# Executes the combination of part files
			$tarGzFile = Combine-Parts -downloadPath $downloadPath

			if (-not $skipWSLImport -and $tarGzFile) {
				# Move the tar.gz file and run WSL import
				Import-WSL -wslPath $wslPath -tag_name $tag_name `
					-tarGzFile $tarGzFile -skipWSLDefault:$skipWSLDefault -ImportForce:$ImportForce
			}
		} else {
			Write-Host "`n`nHash verification failed. Aborting combination process." -ForegroundColor Red
			exit 1
		}
	} catch {
		Write-Host "`nAn error occurred: $_" -ForegroundColor Red
		exit 1
	} finally {
		# Cleanup-DownloadPath -downloadPath $downloadPath
	}
}

# Call the main function with parameters passed to the script
Main -skipWSLImport:$skipWSLImport -skipWSLDefault:$skipWSLDefault -ImportForce:$ImportForce
