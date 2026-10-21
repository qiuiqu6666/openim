[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    & flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter APK build failed (exit code $LASTEXITCODE)."
    }

    $apkDirectory = Join-Path $PSScriptRoot 'build/app/outputs/flutter-apk'
    $packages = foreach ($architecture in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
        $apkPath = Join-Path $apkDirectory "app-$architecture-release.apk"
        if (!(Test-Path -LiteralPath $apkPath -PathType Leaf)) {
            throw "Expected APK was not generated: $apkPath"
        }
        Get-Item -LiteralPath $apkPath
    }
    $packages | Select-Object Name, @{Name='SizeMiB'; Expression={
        [math]::Round($_.Length / 1MB, 2)
    }}, FullName | Format-Table -AutoSize
} finally {
    Pop-Location
}
