param(
    [string]$Go = 'go',
    [string]$Python = 'python',
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$AndroidNdk = $env:ANDROID_NDK_HOME
)
$ErrorActionPreference = 'Stop'
function Invoke-Checked([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed ($LASTEXITCODE)" }
}
if (!(Test-Path -LiteralPath $AndroidSdk) -or !(Test-Path -LiteralPath $AndroidNdk)) {
    throw 'Provide existing -AndroidSdk and -AndroidNdk directories.'
}
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
Invoke-Checked $Python @((Join-Path $PSScriptRoot 'prepare_source.py'))
$version = $manifest.android.coordinate.Split(':')[2]
$mobile = $manifest.gomobile
$artifacts = Join-Path $PSScriptRoot 'artifacts'
$work = Join-Path $artifacts ('build-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $work 'source'
$bin = Join-Path $work 'tools'
New-Item -ItemType Directory -Force $bin | Out-Null
Invoke-Checked $Python @((Join-Path $PSScriptRoot 'prepare_source.py'), '--output', $source)
$savedEnvironment = @{}
foreach ($key in @('PATH','GOBIN','ANDROID_HOME','ANDROID_NDK_HOME','CGO_ENABLED','GOTOOLCHAIN','GOWORK','GOFLAGS')) {
    $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
try {
    $goCommand = (Get-Command $Go -ErrorAction Stop).Source
    $env:PATH = $bin + [IO.Path]::PathSeparator + (Split-Path $goCommand) + [IO.Path]::PathSeparator + $env:PATH
    $env:GOTOOLCHAIN = 'local'
    $env:GOWORK = 'off'
    $env:GOFLAGS = '-mod=readonly'
    if ((& $goCommand version) -notlike "* go$($manifest.go_version) *") { throw "Use Go $($manifest.go_version)." }
    $env:GOBIN = $bin
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_NDK_HOME = $AndroidNdk
    Push-Location $source
    try {
        Invoke-Checked $goCommand @('install',"golang.org/x/mobile/cmd/gomobile@$mobile")
        Invoke-Checked $goCommand @('install',"golang.org/x/mobile/cmd/gobind@$mobile")
        $env:CGO_ENABLED = '0'
        Invoke-Checked $goCommand @('test','./pkg/logpolicy','./pkg/cache','./internal/user','./open_im_sdk','./pkg/common','./pkg/network','./pkg/syncer','./internal/group','./internal/interaction','./internal/conversation_msg','./internal/relation','-count=1','-timeout=120s')
        Invoke-Checked $goCommand @('test','./internal/third/file','-run','^(TestUploadDeadline|TestUploadHash)','-count=1','-timeout=30s')
        Invoke-Checked $goCommand @('test','github.com/openimsdk/tools/log','-run','TestDiagnosticBranding','-count=1')
        Invoke-Checked $goCommand @('test','./internal/third','-run','TestBrandedLogPaths','-count=1')
        $env:CGO_ENABLED = '1'
        # gomobile init installs gobind@latest. Only its cache directory is needed.
        $goPath = & $goCommand env GOPATH
        New-Item -ItemType Directory -Force (Join-Path ($goPath.Split([IO.Path]::PathSeparator)[0]) 'pkg/gomobile') | Out-Null
        $aar = Join-Path $work "core-sdk-$version.aar"
        $flags = '-s -w -X github.com/openimsdk/openim-sdk-core/v3/version.Version=' + $manifest.sdk_version + ' -extldflags "-Wl,--gc-sections,--as-needed,-z,max-page-size=16384"'
        Invoke-Checked gomobile @('bind','-androidapi','21','-target=android','-trimpath','-ldflags',$flags,'-o',$aar,'./open_im_sdk/','./open_im_sdk_callback/')
        Invoke-Checked $Python @((Join-Path $PSScriptRoot 'prepare_source.py'), '--check-dependencies', $source)
        $receipt = Join-Path $work 'verification.json'
        Invoke-Checked $Python @((Join-Path $PSScriptRoot 'record_artifact.py'), 'android', $aar, $receipt)
        $destination = Join-Path $artifacts "maven/io/openim/core-sdk/$version"
        New-Item -ItemType Directory -Force $destination | Out-Null
        Copy-Item -LiteralPath $aar -Destination $destination
        Copy-Item -LiteralPath $receipt -Destination $destination
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
