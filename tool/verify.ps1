[CmdletBinding()]
param(
    [ValidateSet('targeted', 'full', 'ui')]
    [string]$Mode = 'targeted',

    [string]$TestPath = 'test/quickjs_consistency_test.dart',

    [string]$PlainName,

    [switch]$Web,

    [switch]$Benchmark,

    [switch]$SkipNativeBuild,

    [int]$FailureTailLines = 80
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$LogDirectory = Join-Path $Root 'build/verification-logs'
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
    $escapedArguments = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            '"' + ($argument -replace '"', '\"') + '"'
        } else {
            $argument
        }
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.Arguments = ($escapedArguments -join ' ')
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    Set-Content -Path $stdoutPath -Value $stdout -NoNewline
    Set-Content -Path $stderrPath -Value $stderr -NoNewline

    $stopwatch.Stop()
    if ($process.ExitCode -eq 0) {
        Write-Host ("PASS {0} ({1:n1}s)" -f $Name, $stopwatch.Elapsed.TotalSeconds)
        return
    }

    Write-Host ("FAIL {0} ({1:n1}s, exit {2})" -f $Name, $stopwatch.Elapsed.TotalSeconds, $process.ExitCode)
    foreach ($path in @($stdoutPath, $stderrPath)) {
        if ((Test-Path $path) -and (Get-Item $path).Length -gt 0) {
            Write-Host "--- $(Split-Path -Leaf $path) (last $FailureTailLines lines) ---"
            Get-Content $path -Tail $FailureTailLines
        }
    }
    Write-Host "Full logs: $LogDirectory"
    exit $process.ExitCode
}

function Invoke-FlutterTest {
    param(
        [string]$Name,
        [string]$WorkingDirectory,
        [string[]]$ExtraArguments = @()
    )

    $flutterCommand = Get-Command flutter -ErrorAction Stop
    Invoke-LoggedCommand `
        -Name $Name `
        -WorkingDirectory $WorkingDirectory `
        -Executable $flutterCommand.Source `
        -Arguments (@('test', '--reporter', 'compact') + $ExtraArguments)
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

    $exampleBuild = Join-Path $Root 'example/build/windows'
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
        $flutterCommand = Get-Command flutter -ErrorAction Stop
        Invoke-LoggedCommand `
            -Name 'build-windows-native' `
            -WorkingDirectory (Join-Path $Root 'example') `
            -Executable $flutterCommand.Source `
            -Arguments @('build', 'windows', '--debug')
        $dllPath = Find-QuickjsWindowsDll
    }

    if (-not $dllPath) {
        throw 'Windows build completed but quickjs.dll could not be located.'
    }
    $env:QUICKJS_DLL_PATH = $dllPath
    Write-Host "Using QUICKJS_DLL_PATH=$dllPath"
}

if ($Mode -eq 'targeted') {
    $testArguments = @($TestPath)
    if ($PlainName) {
        $testArguments += @('--plain-name', $PlainName)
    }
    if ($Web) {
        $testArguments += @('-d', 'chrome')
    }
    Invoke-FlutterTest -Name 'targeted-test' -WorkingDirectory $Root -ExtraArguments $testArguments
    exit 0
}

if ($Mode -eq 'ui') {
    $quickjsUiRoot = Join-Path $Root 'packages/quickjs_ui'
    $flutterCommand = Get-Command flutter -ErrorAction Stop
    Initialize-QuickjsWindowsDll
    Invoke-LoggedCommand `
        -Name 'quickjs-ui-analyze' `
        -WorkingDirectory $quickjsUiRoot `
        -Executable $flutterCommand.Source `
        -Arguments @('analyze')
    Invoke-FlutterTest -Name 'quickjs-ui-tests' -WorkingDirectory $quickjsUiRoot
    if ($Benchmark) {
        Invoke-FlutterTest `
            -Name 'quickjs-ui-benchmarks' `
            -WorkingDirectory $quickjsUiRoot `
            -ExtraArguments @(
                'benchmark/canvas_120hz_benchmark_test.dart',
                'benchmark/control_state_120hz_benchmark_test.dart',
                'benchmark/adaptive_quality_benchmark_test.dart'
            )
    }
    Write-Host "quickjs_ui verification passed. Logs: $LogDirectory"
    exit 0
}

$dartCommand = Get-Command dart -ErrorAction Stop
$flutterCommand = Get-Command flutter -ErrorAction Stop

Invoke-LoggedCommand -Name 'format' -WorkingDirectory $Root -Executable $dartCommand.Source -Arguments @(
    'format', 'lib', 'test', 'example/lib', 'example/test'
)
Invoke-LoggedCommand -Name 'analyze' -WorkingDirectory $Root -Executable $flutterCommand.Source -Arguments @('analyze')
Invoke-FlutterTest -Name 'native-tests' -WorkingDirectory $Root
Invoke-FlutterTest `
    -Name 'web-consistency-tests' `
    -WorkingDirectory $Root `
    -ExtraArguments @('test/quickjs_consistency_test.dart', '-d', 'chrome')
Invoke-FlutterTest -Name 'example-tests' -WorkingDirectory (Join-Path $Root 'example')

Write-Host "All verification stages passed. Logs: $LogDirectory"
