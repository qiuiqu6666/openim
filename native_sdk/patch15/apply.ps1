param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath
)

$ErrorActionPreference = 'Stop'
$taskSource = (Resolve-Path -LiteralPath $SourcePath).Path
$taskManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
$taskPatch = Join-Path $PSScriptRoot $taskManifest.patch
$taskBaseCommit = $taskManifest.patch_base_commit
if (!$taskBaseCommit) { $taskBaseCommit = $taskManifest.commit }
$taskHead = & git -C $taskSource rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $taskHead -ne $taskBaseCommit) {
    throw "Expected patch base commit $taskBaseCommit. Existing files were preserved."
}
$taskHash = (Get-FileHash -LiteralPath $taskPatch -Algorithm SHA256).Hash.ToLowerInvariant()
if ($taskHash -ne $taskManifest.patch_sha256) {
    throw 'Patch hash mismatch. No changes were made.'
}
& git -c core.autocrlf=false -C $taskSource apply --reverse --check $taskPatch 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Output 'Recovery patch is already applied.'
    return
}
$taskStatus = & git -C $taskSource status --porcelain
if ($LASTEXITCODE -ne 0 -or $taskStatus) {
    throw 'Use a clean official SDK checkout. Existing changes were preserved.'
}
& git -c core.autocrlf=false -C $taskSource apply --check $taskPatch
if ($LASTEXITCODE -ne 0) { throw 'Patch applicability check failed. No changes were made.' }
& git -c core.autocrlf=false -C $taskSource apply $taskPatch
if ($LASTEXITCODE -ne 0) { throw 'Patch application failed. Inspect the checkout before proceeding.' }
Write-Output 'Recovery patch applied to source. App SDK dependencies were not changed.'
