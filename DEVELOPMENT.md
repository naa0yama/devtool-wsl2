# Development

## PowerShell get icon list

```powershell
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;

public class IconExtractor {
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern uint ExtractIconEx(
        string szFileName,
        int nIconIndex,
        IntPtr[] phiconLarge,
        IntPtr[] phiconSmall,
        uint nIcons);
    
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool DestroyIcon(IntPtr handle);
}
"@

$dllPath = "$env:SystemRoot\System32\imageres.dll"

# 全アイコンを抽出
function Export-AllIconsFromDll {
    param(
        [string]$DllPath = "$env:SystemRoot\System32\imageres.dll",
        [string]$OutputPath = "$env:TEMP\imageres_icons"
    )
    
    # アイコンの総数を取得
    $totalIcons = [IconExtractor]::ExtractIconEx($DllPath, -1, $null, $null, 0)
    Write-Host "総アイコン数: $totalIcons"
    Write-Host "抽出を開始します..."
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath | Out-Null
    }
    
    $successCount = 0
    
    for ($i = 0; $i -lt $totalIcons; $i++) {
        $hIconLarge = [IntPtr[]]::new(1)
        $hIconSmall = [IntPtr[]]::new(1)
        
        $result = [IconExtractor]::ExtractIconEx($DllPath, $i, $hIconLarge, $hIconSmall, 1)
        
        if ($result -gt 0 -and $hIconLarge[0] -ne [IntPtr]::Zero) {
            try {
                $icon = [System.Drawing.Icon]::FromHandle($hIconLarge[0])
                $bitmap = $icon.ToBitmap()
                $outputFile = Join-Path $OutputPath ("icon_{0:D4}.png" -f $i)
                $bitmap.Save($outputFile, [System.Drawing.Imaging.ImageFormat]::Png)
                $successCount++
                
                # 進捗表示
                if ($i % 50 -eq 0) {
                    Write-Host "進捗: $i / $totalIcons"
                }
                
                $bitmap.Dispose()
            }
            catch {
                Write-Warning "Index $i : 抽出失敗 - $_"
            }
            finally {
                [IconExtractor]::DestroyIcon($hIconLarge[0]) | Out-Null
            }
        }
        
        if ($hIconSmall[0] -ne [IntPtr]::Zero) {
            [IconExtractor]::DestroyIcon($hIconSmall[0]) | Out-Null
        }
    }
    
    Write-Host "`n完了: $successCount 個のアイコンを抽出しました"
    Write-Host "保存先: $OutputPath"
    
    # 保存先フォルダを開く
    explorer $OutputPath
}

# 実行
Export-AllIconsFromDll

```
