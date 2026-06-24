[CmdletBinding()]
param(
    [ValidateSet('targeted', 'full')]
    [string]$Mode = 'targeted',

    [string]$TestPath = 'test/quickjs_consistency_test.dart',

    [string]$PlainName,

    [switch]$Web,

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

    $process = Start-Process `
        -FilePath $Executable `
        -ArgumentList $escapedArguments `
        -WorkingDirectory $WorkingDirectory `
        -NoNewWindow `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

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

    Invoke-LoggedCommand `
        -Name $Name `
        -WorkingDirectory $WorkingDirectory `
        -Executable 'flutter' `
        -Arguments (@('test', '--reporter', 'compact') + $ExtraArguments)
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

Invoke-LoggedCommand -Name 'format' -WorkingDirectory $Root -Executable 'dart' -Arguments @(
    'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'example/lib', 'example/test'
)
Invoke-LoggedCommand -Name 'analyze' -WorkingDirectory $Root -Executable 'flutter' -Arguments @('analyze')
Invoke-FlutterTest -Name 'native-tests' -WorkingDirectory $Root
Invoke-FlutterTest `
    -Name 'web-consistency-tests' `
    -WorkingDirectory $Root `
    -ExtraArguments @('test/quickjs_consistency_test.dart', '-d', 'chrome')
Invoke-FlutterTest -Name 'example-tests' -WorkingDirectory (Join-Path $Root 'example')

Write-Host "All verification stages passed. Logs: $LogDirectory"
