# Downloads quickjs-wasi browser assets (QuickJS WASM).
# @see https://www.npmjs.com/package/quickjs-wasi

param(
    [string]$Version = "3.0.0"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Assets = Join-Path $Root "assets\web"
New-Item -ItemType Directory -Force -Path $Assets | Out-Null

$base = "https://unpkg.com/quickjs-wasi@$Version"
$dist = "$base/dist"

Invoke-WebRequest -Uri "$base/quickjs.wasm" -OutFile (Join-Path $Assets "quickjs.wasm")
Invoke-WebRequest -Uri "$dist/index.js" -OutFile (Join-Path $Assets "quickjs_wasi.js")
Invoke-WebRequest -Uri "$dist/wasi-shim.js" -OutFile (Join-Path $Assets "wasi-shim.js")
Invoke-WebRequest -Uri "$dist/extensions.js" -OutFile (Join-Path $Assets "extensions.js")
Invoke-WebRequest -Uri "$dist/version.js" -OutFile (Join-Path $Assets "version.js")

Write-Host "Fetched quickjs-wasi@$Version into $Assets"
Write-Host "quickjs_web.js / quickjs_bridge.mjs are maintained in-repo."