[CmdletBinding()]
param(
    [ValidateSet('targeted', 'full', 'ui')]
    [string]$Mode = 'targeted',

    [string]$TestPath = 'test/consistency_test.dart',

    [string]$PlainName,

    [switch]$Web,

    [switch]$Benchmark,

    [switch]$SkipNativeBuild,

    [switch]$SkipFormat,


    [int]$FailureTailLines = 80
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$QuickjsRoot = Join-Path $Root 'packages/lemon_js'
$JsUiRoot = Join-Path $Root 'packages/lemon_js_ui'
$JsUiVideoPlayerRoot = Join-Path $Root 'packages/lemon_js_ui_video_player'
$ExtensionsRoot = Join-Path $Root 'packages/lemon_js_extensions'
$ExampleRoot = Join-Path $Root 'examples/lemon_js_example'
$LogDirectory = Join-Path $Root 'build/verification-logs'
$FlutterBin = Split-Path -Parent (Get-Command flutter -ErrorAction Stop).Source
$DartExecutable = Join-Path $FlutterBin 'cache/dart-sdk/bin/dart.exe'
$FlutterTool = Join-Path $FlutterBin 'cache/flutter_tools.snapshot'
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory)]
        [string]$Executable,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $safeName = $Name -replace '[^a-zA-Z0-9._-]', '-'
    $stdoutPath = Join-Path $LogDirectory "$safeName.stdout.log"
    $stderrPath = Join-Path $LogDirectory "$safeName.stderr.log"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Push-Location $WorkingDirectory
    try {
        & $Executable @Arguments 1> $stdoutPath 2> $stderrPath
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    $stopwatch.Stop()
    if ($exitCode -eq 0) {
        Write-Host ("PASS {0} ({1:n1}s)" -f $Name, $stopwatch.Elapsed.TotalSeconds)
        return
    }

    Write-Host ("FAIL {0} ({1:n1}s, exit {2})" -f $Name, $stopwatch.Elapsed.TotalSeconds, $exitCode)
    foreach ($path in @($stdoutPath, $stderrPath)) {
        if ((Test-Path $path) -and (Get-Item $path).Length -gt 0) {
            Write-Host "--- $(Split-Path -Leaf $path) (last $FailureTailLines lines) ---"
            Get-Content $path -Tail $FailureTailLines
        }
    }
    Write-Host "Full logs: $LogDirectory"
    exit $exitCode
}

function Invoke-FlutterTest {
    param(
        [string]$Name,
        [string]$WorkingDirectory,
        [string[]]$ExtraArguments = @()
    )

    Invoke-LoggedCommand `
        -Name $Name `
        -WorkingDirectory $WorkingDirectory `
        -Executable $DartExecutable `
        -Arguments (@($FlutterTool, 'test', '--reporter', 'compact') + $ExtraArguments)
}

function Find-QuickjsWindowsDll {
    $configuredPath = $env:QUICKJS_DLL_PATH
    if ($configuredPath) {
        $resolvedConfiguredPath = Resolve-Path -LiteralPath $configuredPath -ErrorAction SilentlyContinue
        if ($resolvedConfiguredPath) {
            return $resolvedConfiguredPath.Path
        }
        throw "QUICKJS_DLL_PATH does not exist: $configuredPath"
    }

    $exampleBuild = Join-Path $ExampleRoot 'build/windows'
    if (-not (Test-Path $exampleBuild)) {
        return $null
    }

    $configurationPriority = @('Debug', 'Profile', 'Release', 'RelWithDebInfo')
    $candidates = Get-ChildItem -LiteralPath $exampleBuild -Recurse -Filter 'quickjs.dll' -File |
        Where-Object { $_.FullName -match '[\\/]runner[\\/]' }
    foreach ($configuration in $configurationPriority) {
        $candidate = $candidates |
            Where-Object { $_.Directory.Name -eq $configuration } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }
    return ($candidates | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).FullName
}

function Initialize-QuickjsWindowsDll {
    if (-not $IsWindows -and $env:OS -ne 'Windows_NT') {
        return
    }

    $dllPath = Find-QuickjsWindowsDll
    if (-not $dllPath) {
        if ($SkipNativeBuild) {
            throw 'quickjs.dll was not found and -SkipNativeBuild was specified.'
        }
        Invoke-LoggedCommand `
            -Name 'build-windows-native' `
            -WorkingDirectory $ExampleRoot `
            -Executable $DartExecutable `
            -Arguments @($FlutterTool, 'build', 'windows', '--debug')
        $dllPath = Find-QuickjsWindowsDll
    }

    if (-not $dllPath) {
        throw 'Windows build completed but quickjs.dll could not be located.'
    }
    $env:QUICKJS_DLL_PATH = $dllPath
    $nativeDirectory = Split-Path -Parent $dllPath
    if ($env:PATH -notlike "$nativeDirectory;*") {
        $env:PATH = "$nativeDirectory;$env:PATH"
    }
    Write-Host "Using QUICKJS_DLL_PATH=$dllPath"
}

if ($Mode -eq 'targeted') {
    $testArguments = @($TestPath)
    if ($PlainName) {
        $testArguments += @('--plain-name', $PlainName)
    }
    if ($Web) {
        $testArguments += @('--platform', 'chrome')
    }
    Invoke-FlutterTest -Name 'targeted-test' -WorkingDirectory $QuickjsRoot -ExtraArguments $testArguments
    exit 0
}

if ($Mode -eq 'ui') {
    Initialize-QuickjsWindowsDll
    Invoke-LoggedCommand `
        -Name 'quickjs-ui-analyze' `
        -WorkingDirectory $JsUiRoot `
        -Executable $DartExecutable `
        -Arguments @($FlutterTool, 'analyze')
    Invoke-FlutterTest -Name 'quickjs-ui-tests' -WorkingDirectory $JsUiRoot
    if ($Benchmark) {
        Invoke-FlutterTest `
            -Name 'quickjs-ui-benchmarks' `
            -WorkingDirectory $JsUiRoot `
            -ExtraArguments @(
                'benchmark/canvas_120hz_benchmark_test.dart',
                'benchmark/control_state_120hz_benchmark_test.dart',
                'benchmark/adaptive_quality_benchmark_test.dart'
            )
    }
    Write-Host "quickjs_ui verification passed. Logs: $LogDirectory"
    exit 0
}

if (-not $SkipFormat) {
    Invoke-LoggedCommand -Name 'format' -WorkingDirectory $Root -Executable $DartExecutable -Arguments @(
        'format',
        'packages/lemon_js/lib',
        'packages/lemon_js/test',
        'packages/lemon_js_ui/lib',
        'packages/lemon_js_ui/test',
        'packages/lemon_js_ui_video_player/lib',
        'packages/lemon_js_ui_video_player/test',
        'packages/lemon_js_extensions/lib',
        'packages/lemon_js_extensions/test',
        'examples/lemon_js_example/lib',
        'examples/lemon_js_example/test'
    )
}
Invoke-LoggedCommand -Name 'quickjs-analyze' -WorkingDirectory $QuickjsRoot -Executable $DartExecutable -Arguments @($FlutterTool, 'analyze')
Invoke-LoggedCommand -Name 'quickjs-ui-analyze' -WorkingDirectory $JsUiRoot -Executable $DartExecutable -Arguments @($FlutterTool, 'analyze')
Invoke-LoggedCommand -Name 'quickjs-ui-video-player-analyze' -WorkingDirectory $JsUiVideoPlayerRoot -Executable $DartExecutable -Arguments @($FlutterTool, 'analyze')
Invoke-LoggedCommand -Name 'extensions-analyze' -WorkingDirectory $ExtensionsRoot -Executable $DartExecutable -Arguments @($FlutterTool, 'analyze')
Invoke-LoggedCommand -Name 'example-analyze' -WorkingDirectory $ExampleRoot -Executable $DartExecutable -Arguments @($FlutterTool, 'analyze')
Initialize-QuickjsWindowsDll
Invoke-FlutterTest -Name 'native-tests' -WorkingDirectory $QuickjsRoot
Invoke-FlutterTest `
    -Name 'web-consistency-tests' `
    -WorkingDirectory $QuickjsRoot `
    -ExtraArguments @('test/consistency_test.dart', '--platform', 'chrome')
Invoke-FlutterTest -Name 'quickjs-ui-tests' -WorkingDirectory $JsUiRoot
Invoke-FlutterTest -Name 'quickjs-ui-video-player-tests' -WorkingDirectory $JsUiVideoPlayerRoot
Invoke-FlutterTest -Name 'extensions-tests' -WorkingDirectory $ExtensionsRoot
Invoke-FlutterTest -Name 'example-tests' -WorkingDirectory $ExampleRoot

Write-Host "All verification stages passed. Logs: $LogDirectory"
