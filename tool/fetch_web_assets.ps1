# Downloads and verifies quickjs-wasi browser assets (QuickJS WASM).
# @see https://unpkg.com/

[CmdletBinding()]
param(
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version = "3.0.1",

    [ValidatePattern('^https?://')]
    [string]$RegistryBaseUrl = "https://unpkg.com"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Assets = Join-Path $Root "assets\web"
$PackageBaseUrl = "$($RegistryBaseUrl.TrimEnd('/'))/quickjs-wasi@$Version"
$StagingRoot = Join-Path (Split-Path -Parent $Assets) ".quickjs-wasi-$([Guid]::NewGuid().ToString('N'))"
$Downloads = Join-Path $StagingRoot "downloads"
$Backups = Join-Path $StagingRoot "backups"

$AssetFiles = @(
    [pscustomobject]@{ Source = "/quickjs.wasm"; Target = "quickjs.wasm" },
    [pscustomobject]@{ Source = "/dist/index.js"; Target = "quickjs_wasi.js" },
    [pscustomobject]@{ Source = "/dist/wasi-shim.js"; Target = "wasi-shim.js" },
    [pscustomobject]@{ Source = "/dist/extensions.js"; Target = "extensions.js" },
    [pscustomobject]@{ Source = "/dist/version.js"; Target = "version.js" }
)

function Get-FileSha256Base64 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Stream = [System.IO.File]::OpenRead($Path)
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToBase64String($Sha256.ComputeHash($Stream))
    }
    finally {
        $Sha256.Dispose()
        $Stream.Dispose()
    }
}

function Assert-DownloadedFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Metadata
    )

    $File = Get-Item -LiteralPath $Path
    if ($File.Length -ne [long]$Metadata.size) {
        throw "Size mismatch for $($Metadata.path): expected $($Metadata.size), got $($File.Length)"
    }

    $IntegrityParts = "$($Metadata.integrity)" -split '-', 2
    if ($IntegrityParts.Count -ne 2 -or $IntegrityParts[0] -ne "sha256") {
        throw "Unsupported integrity value for $($Metadata.path): $($Metadata.integrity)"
    }

    $ActualHash = Get-FileSha256Base64 -Path $Path
    if ($ActualHash -cne $IntegrityParts[1]) {
        throw "SHA-256 mismatch for $($Metadata.path)"
    }
}

function Assert-WasmHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($Bytes.Length -lt 4 -or
        $Bytes[0] -ne 0 -or
        $Bytes[1] -ne 0x61 -or
        $Bytes[2] -ne 0x73 -or
        $Bytes[3] -ne 0x6d) {
        throw "Downloaded quickjs.wasm does not have a valid WebAssembly header"
    }
}

function Restore-Assets {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InstalledFiles
    )

    foreach ($Asset in $InstalledFiles) {
        $Destination = Join-Path $Assets $Asset.Target
        $Backup = Join-Path $Backups $Asset.Target
        if (Test-Path -LiteralPath $Backup) {
            Copy-Item -LiteralPath $Backup -Destination $Destination -Force
        }
        elseif (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Force
        }
    }
}

New-Item -ItemType Directory -Force -Path $Assets, $Downloads, $Backups | Out-Null

try {
    Write-Host "Reading quickjs-wasi@$Version metadata ..."
    $Metadata = Invoke-RestMethod -Uri "$PackageBaseUrl/?meta"
    if ($Metadata.version -ne $Version) {
        throw "Registry returned quickjs-wasi@$($Metadata.version), expected $Version"
    }

    foreach ($Asset in $AssetFiles) {
        $FileMetadata = @($Metadata.files | Where-Object { $_.path -ceq $Asset.Source })
        if ($FileMetadata.Count -ne 1) {
            throw "Metadata does not contain exactly one $($Asset.Source) entry"
        }

        $DownloadPath = Join-Path $Downloads $Asset.Target
        Write-Host "Downloading $($Asset.Source) ..."
        Invoke-WebRequest -Uri "$PackageBaseUrl$($Asset.Source)" -OutFile $DownloadPath
        Assert-DownloadedFile -Path $DownloadPath -Metadata $FileMetadata[0]
    }

    Assert-WasmHeader -Path (Join-Path $Downloads "quickjs.wasm")
    $VersionSource = Get-Content -LiteralPath (Join-Path $Downloads "version.js") -Raw
    if ($VersionSource -notmatch ('VERSION\s*=\s*["'']' + [Regex]::Escape($Version) + '["'']')) {
        throw "Downloaded version.js does not declare VERSION = $Version"
    }

    $InstalledFiles = @()
    try {
        foreach ($Asset in $AssetFiles) {
            $Destination = Join-Path $Assets $Asset.Target
            if (Test-Path -LiteralPath $Destination) {
                Copy-Item -LiteralPath $Destination -Destination (Join-Path $Backups $Asset.Target)
            }
            $InstalledFiles += $Asset
            Copy-Item -LiteralPath (Join-Path $Downloads $Asset.Target) -Destination $Destination -Force
        }
    }
    catch {
        Restore-Assets -InstalledFiles $InstalledFiles
        throw
    }

    Write-Host "Fetched and verified quickjs-wasi@$Version into $Assets"
    Write-Host "quickjs_web.js / quickjs_bridge.mjs / quickjs_web_worker.js are maintained in-repo."
}
finally {
    if (Test-Path -LiteralPath $StagingRoot) {
        Remove-Item -LiteralPath $StagingRoot -Recurse -Force
    }
}
