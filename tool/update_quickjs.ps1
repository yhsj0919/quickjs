# Updates the QuickJS git submodule to a release tag.
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tool\update_quickjs.ps1
#   powershell -ExecutionPolicy Bypass -File .\tool\update_quickjs.ps1 v0.15.0

param(
    [string]$Tag = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$SubmodulePath = Join-Path $Root "third_party\quickjs"
$VersionFile = Join-Path $Root "third_party\VERSION"
$SubmoduleUrl = "https://github.com/quickjs-ng/quickjs.git"

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Test-GitWorkTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    $GitDir = Join-Path $Path ".git"
    if (-not (Test-Path $GitDir)) {
        return $false
    }

    $WorkTreeRoot = (& git -C $Path rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    $ResolvedPath = (Resolve-Path $Path).Path.TrimEnd("\", "/")
    $ResolvedWorkTreeRoot = (Resolve-Path $WorkTreeRoot).Path.TrimEnd("\", "/")
    return $ResolvedPath -eq $ResolvedWorkTreeRoot
}

if (-not $Tag) {
    if (-not (Test-Path $VersionFile)) {
        throw "Missing $VersionFile and no tag argument provided."
    }
    $Tag = (Get-Content $VersionFile -Raw).Trim()
}

Write-Host "Updating QuickJS to $Tag ..."

Invoke-Git @("-C", $Root, "submodule", "sync", "--recursive", "third_party/quickjs")

if (-not (Test-GitWorkTree $SubmodulePath)) {
    if ((Test-Path $SubmodulePath) -and (Get-ChildItem -Force $SubmodulePath | Select-Object -First 1)) {
        throw "Submodule path exists but is not a git checkout: $SubmodulePath"
    }

    Invoke-Git @("-C", $Root, "submodule", "update", "--init", "--recursive", "third_party/quickjs")
}

$RemoteUrl = (& git -C $SubmodulePath remote get-url origin 2>$null)
if ($LASTEXITCODE -ne 0 -or $RemoteUrl -ne $SubmoduleUrl) {
    & git -C $SubmodulePath remote remove origin 2>$null
    & git -C $SubmodulePath remote add origin $SubmoduleUrl
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to configure origin remote for $SubmodulePath"
    }
}

Invoke-Git @("-C", $SubmodulePath, "fetch", "origin", "--tags", "--force")

& git -C $SubmodulePath rev-parse --verify --quiet "refs/tags/$Tag" *> $null
if ($LASTEXITCODE -ne 0) {
    throw "QuickJS tag '$Tag' was not found in $SubmoduleUrl"
}

Invoke-Git @("-C", $SubmodulePath, "checkout", "--detach", $Tag)
Invoke-Git @("-C", $SubmodulePath, "submodule", "update", "--init", "--recursive")

Set-Content -Path $VersionFile -Value $Tag -NoNewline
Add-Content -Path $VersionFile -Value ""
Write-Host "Done. Pinned $Tag in third_party/VERSION"
