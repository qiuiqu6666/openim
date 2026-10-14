param(
    [string]$SourcePath = 'https://github.com/openimsdk/openim-sdk-core.git',
    [string]$Go = 'go',
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$AndroidNdk = $env:ANDROID_NDK_HOME
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $AndroidSdk) -or !(Test-Path -LiteralPath $AndroidNdk)) {
    throw 'Provide existing -AndroidSdk and -AndroidNdk directories.'
}
$version = '3.8.3-patch15-recovery.12-readseq2'
$mobile = 'v0.0.0-20250711185624-d5bb5ecc55c0'
$artifacts = Join-Path $PSScriptRoot 'artifacts'
$work = Join-Path $artifacts ('build-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $work 'source'
$bin = Join-Path $work 'tools'
New-Item -ItemType Directory -Force $bin | Out-Null
function Invoke-Checked([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed ($LASTEXITCODE)" }
}
$savedEnvironment = @{}
foreach ($key in @('PATH','GOBIN','ANDROID_HOME','ANDROID_NDK_HOME','CGO_ENABLED')) {
    $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
try {
    $goCommand = (Get-Command $Go -ErrorAction Stop).Source
    $env:PATH = $bin + [IO.Path]::PathSeparator + (Split-Path $goCommand) + [IO.Path]::PathSeparator + $env:PATH
    $env:GOBIN = $bin
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_NDK_HOME = $AndroidNdk
    $env:CGO_ENABLED = '1'
    Invoke-Checked git @('clone','--quiet','--no-hardlinks','--branch','v3.8.3-patch.15',$SourcePath,$source)
    & (Join-Path $PSScriptRoot 'apply.ps1') -SourcePath $source
    Push-Location $source
    try {
        Invoke-Checked $goCommand @('install',"golang.org/x/mobile/cmd/gomobile@$mobile")
        Invoke-Checked $goCommand @('install',"golang.org/x/mobile/cmd/gobind@$mobile")
        Invoke-Checked $goCommand @('get',"golang.org/x/mobile@$mobile")
        $env:CGO_ENABLED = '0'
        Invoke-Checked $goCommand @('test','-mod=mod','./pkg/common','./internal/interaction','./internal/conversation_msg','-count=1','-timeout=60s')
        $env:CGO_ENABLED = '1'
        Invoke-Checked gomobile @('init')
        $aar = Join-Path $work "core-sdk-$version.aar"
        $flags = '-s -w -X github.com/openimsdk/openim-sdk-core/v3/version.Version=v3.8.3-patch.15+recovery.12-readseq2 -extldflags "-Wl,--gc-sections,--as-needed,-z,max-page-size=16384"'
        Invoke-Checked gomobile @('bind','-androidapi','21','-target=android','-trimpath','-ldflags',$flags,'-o',$aar,'./open_im_sdk/','./open_im_sdk_callback/')
        $destination = Join-Path $artifacts "maven/io/openim/core-sdk/$version"
        New-Item -ItemType Directory -Force $destination | Out-Null
        Copy-Item -LiteralPath $aar -Destination $destination
        $pom = "<project><modelVersion>4.0.0</modelVersion><groupId>io.openim</groupId><artifactId>core-sdk</artifactId><version>$version</version><packaging>aar</packaging></project>"
        [IO.File]::WriteAllText((Join-Path $destination "core-sdk-$version.pom"), $pom)
        Get-FileHash -LiteralPath $aar -Algorithm SHA256
        Write-Output "Core artifact ready: $destination"
    } finally { Pop-Location }
} finally {
    foreach ($key in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
    }
}
