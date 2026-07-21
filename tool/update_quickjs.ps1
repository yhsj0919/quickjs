# Updates the vendored QuickJS sources to a release tag.
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tool\update_quickjs.ps1
#   powershell -ExecutionPolicy Bypass -File .\tool\update_quickjs.ps1 v0.15.0

param(
    [string]$Tag = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$VendorPath = Join-Path $Root "third_party\quickjs"
$VersionFile = Join-Path $Root "third_party\VERSION"
$RepositoryUrl = "https://github.com/quickjs-ng/quickjs.git"

if (-not $Tag) {
    if (-not (Test-Path $VersionFile)) {
        throw "Missing $VersionFile and no tag argument provided."
    }
    $Tag = (Get-Content $VersionFile -Raw).Trim()
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("quickjs-update-" + [guid]::NewGuid())
$CheckoutPath = Join-Path $TempRoot "quickjs"

try {
    New-Item -ItemType Directory -Path $TempRoot | Out-Null
    Write-Host "Downloading QuickJS $Tag ..."
    & git clone --depth 1 --branch $Tag --single-branch $RepositoryUrl $CheckoutPath
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE"
    }

    # A published Flutter package must contain the actual sources, not a gitlink.
    Remove-Item -LiteralPath (Join-Path $CheckoutPath ".git") -Recurse -Force
    $NestedModules = Join-Path $CheckoutPath ".gitmodules"
    if (Test-Path $NestedModules) {
        Remove-Item -LiteralPath $NestedModules -Force
    }

    if (Test-Path $VendorPath) {
        Remove-Item -LiteralPath $VendorPath -Recurse -Force
    }
    Move-Item -LiteralPath $CheckoutPath -Destination $VendorPath
    Set-Content -Path $VersionFile -Value $Tag
    Write-Host "Done. Vendored $Tag in third_party/quickjs"
} finally {
    if (Test-Path $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}
