param([string]$ArchivePath)
$ErrorActionPreference = 'Stop'
$expected = '1a8f011820b5e282396328b2fbac294e8011ecc891d68e45e680186cf3822f69'
$url = 'https://github.com/openimsdk/openim-sdk-core/releases/download/v3.8.3-patch.15/openim-sdk-core_v3.8.3-patch.15_iOS_xcframework.zip'
if (!$ArchivePath) {
    $directory = Join-Path $PSScriptRoot 'artifacts'
    New-Item -ItemType Directory -Force $directory | Out-Null
    $ArchivePath = Join-Path $directory 'official-ios-patch15.zip'
    if (!(Test-Path -LiteralPath $ArchivePath)) {
        Invoke-WebRequest $url -OutFile $ArchivePath
    }
}
if ((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'Official iOS archive SHA256 mismatch.'
}
$target = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../local_plugin/flutter_openim_sdk/ios/Frameworks'))
if (Test-Path -LiteralPath (Join-Path $target 'OpenIMCore.xcframework')) {
    throw 'Framework already exists. Preserve it; use a fresh checkout to prepare another copy.'
}
Expand-Archive -LiteralPath $ArchivePath -DestinationPath $target
Write-Output 'Official unpatched iOS patch.15 prepared for comparison. For parity with Android recovery.10, run build-ios.sh on macOS instead.'
