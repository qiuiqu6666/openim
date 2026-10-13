param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath
)

$ErrorActionPreference = 'Stop'
$taskSource = (Resolve-Path -LiteralPath $SourcePath).Path
$taskPatch = Join-Path $PSScriptRoot 'patches/0001-sdk-recovery.patch'
$taskExpected = '101cf038eb114bc58bd9298dedeff33e3b1a73f2'

$taskHead = & git -C $taskSource rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $taskHead -ne $taskExpected) {
    throw "SDK source must be checked out at $taskExpected. No changes were made."
}

$taskManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'patches/manifest.json') -Raw | ConvertFrom-Json
$taskHash = (Get-FileHash -LiteralPath $taskPatch -Algorithm SHA256).Hash.ToLowerInvariant()
if ($taskHash -ne $taskManifest.patch_sha256) {
    throw 'Patch hash does not match its manifest. No changes were made.'
}

& git -C $taskSource apply --reverse --check $taskPatch 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Output 'Recovery patch is already applied. No changes were made.'
    exit 0
}

$taskStatus = & git -C $taskSource status --porcelain
if ($LASTEXITCODE -ne 0 -or $taskStatus) {
    throw 'Use a clean SDK checkout. Existing changes were preserved.'
}

& git -C $taskSource apply --check $taskPatch
if ($LASTEXITCODE -ne 0) { throw 'Patch applicability check failed. No changes were made.' }
& git -C $taskSource apply $taskPatch
if ($LASTEXITCODE -ne 0) { throw 'Patch application failed. Inspect the SDK checkout.' }
Write-Output 'Recovery patch applied to SDK source. No build was performed.'
