[CmdletBinding()]
param(
    [string]$BuildDir,
    [string]$KenshiPath,
    [string]$OutDir,
    [switch]$RunTests,
    [switch]$SkipTests,
    [switch]$FailOnTestFailure,
    [ValidateRange(1, 600)]
    [int]$IntegrationReadyTimeoutSeconds = 60,
    [switch]$AllowIntegrationFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Get-GitOutput {
    param([string[]]$Arguments)

    try {
        $output = & git @Arguments 2>$null
        if ($LASTEXITCODE -eq 0) { return @($output) }
    } catch { }
    return @()
}

function Copy-ArtifactFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return $null }

    $destination = Join-Path $DestinationDirectory ([System.IO.Path]::GetFileName($Source))
    if (Test-Path -LiteralPath $destination) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($Source)
        $extension = [System.IO.Path]::GetExtension($Source)
        $destination = Join-Path $DestinationDirectory ("{0}-{1}{2}" -f $base, ([guid]::NewGuid().ToString("N").Substring(0, 8)), $extension)
    }
    Copy-Item -LiteralPath $Source -Destination $destination -Force
    return $destination
}

$repoRoot = Resolve-FullPath (Join-Path $PSScriptRoot "..")
$releaseDir = Join-Path $repoRoot "build\bin\Release"
if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    if (Test-Path -LiteralPath $releaseDir -PathType Container) {
        $BuildDir = $releaseDir
    } else {
        $BuildDir = (Get-Location).Path
    }
}
$BuildDir = Resolve-FullPath $BuildDir
if (-not (Test-Path -LiteralPath $BuildDir -PathType Container)) {
    throw "BuildDir does not exist: $BuildDir"
}
if (-not [string]::IsNullOrWhiteSpace($KenshiPath)) { $KenshiPath = Resolve-FullPath $KenshiPath }

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $repoRoot "validation-artifacts"
}
$OutDir = Join-Path (Resolve-FullPath $OutDir) $timestamp
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$logsDir = Join-Path $OutDir "logs"
$configsDir = Join-Path $OutDir "configs"
New-Item -ItemType Directory -Path $logsDir, $configsDir -Force | Out-Null

$testNames = @("KenshiMP.UnitTest.exe", "KenshiMP.IntegrationTest.exe")
$availableTests = @($testNames | Where-Object { Test-Path -LiteralPath (Join-Path $BuildDir $_) -PathType Leaf })
$shouldRunTests = $availableTests.Count -gt 0
if ($PSBoundParameters.ContainsKey("RunTests")) { $shouldRunTests = [bool]$RunTests }
if ($SkipTests) { $shouldRunTests = $false }

$testResults = @()
if ($shouldRunTests) {
    foreach ($testName in $availableTests) {
        $testPath = Join-Path $BuildDir $testName
        $logPath = Join-Path $logsDir ("{0}.console.log" -f [System.IO.Path]::GetFileNameWithoutExtension($testName))
        Write-Host "Running $testName..."
        $serverStdoutPath = $null
        $serverStderrPath = $null
        if ($testName -eq "KenshiMP.IntegrationTest.exe") {
            $serverStdoutPath = Join-Path $logsDir "KenshiMP.Server.stdout.log"
            $serverStderrPath = Join-Path $logsDir "KenshiMP.Server.stderr.log"
            $previousServerStdout = $env:KMP_SERVER_STDOUT_LOG
            $previousServerStderr = $env:KMP_SERVER_STDERR_LOG
            $previousReadyTimeout = $env:KMP_READY_TIMEOUT_SECONDS
            $previousNonInteractive = $env:KMP_NONINTERACTIVE
            $env:KMP_SERVER_STDOUT_LOG = $serverStdoutPath
            $env:KMP_SERVER_STDERR_LOG = $serverStderrPath
            $env:KMP_READY_TIMEOUT_SECONDS = $IntegrationReadyTimeoutSeconds.ToString()
            $env:KMP_NONINTERACTIVE = "1"
        }
        try {
            Push-Location $BuildDir
            if ($testName -eq "KenshiMP.IntegrationTest.exe") {
                $serverPath = Join-Path $BuildDir "KenshiMP.Server.exe"
                & $testPath $serverPath 2>&1 | Tee-Object -FilePath $logPath
            } else {
                & $testPath 2>&1 | Tee-Object -FilePath $logPath
            }
            $exitCode = $LASTEXITCODE
        } finally {
            Pop-Location
            if ($testName -eq "KenshiMP.IntegrationTest.exe") {
                $env:KMP_SERVER_STDOUT_LOG = $previousServerStdout
                $env:KMP_SERVER_STDERR_LOG = $previousServerStderr
                $env:KMP_READY_TIMEOUT_SECONDS = $previousReadyTimeout
                $env:KMP_NONINTERACTIVE = $previousNonInteractive
            }
        }
        $lines = @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue)
        $summary = $lines | Where-Object { $_ -match "Results:\s*\d+\s+passed,\s*\d+\s+failed" } | Select-Object -Last 1
        $passed = $null
        $failed = $null
        if ($summary -and $summary -match "Results:\s*(\d+)\s+passed,\s*(\d+)\s+failed") {
            $passed = [int]$matches[1]
            $failed = [int]$matches[2]
        } elseif ($lines | Where-Object { $_ -match "All tests PASSED!" }) {
            $passed = "all"
            $failed = 0
            $summary = "All tests PASSED!"
        }
        $failLines = @($lines | Where-Object { $_ -match "\[FAIL\]" })
        $testResults += [pscustomobject]@{
            Name = $testName; ExitCode = $exitCode; Passed = $passed; Failed = $failed
            Summary = $summary; Failures = $failLines; Log = ("logs/{0}" -f [System.IO.Path]::GetFileName($logPath))
            ServerStdoutLog = if ($serverStdoutPath) { "logs/$([System.IO.Path]::GetFileName($serverStdoutPath))" } else { $null }
            ServerStderrLog = if ($serverStderrPath) { "logs/$([System.IO.Path]::GetFileName($serverStderrPath))" } else { $null }
        }
    }
} elseif ($SkipTests) {
    Write-Host "Tests skipped by -SkipTests."
}

$copiedFiles = @()
foreach ($name in @("KenshiOnline_Server.log", "server.json")) {
    $copied = Copy-ArtifactFile -Source (Join-Path $BuildDir $name) -DestinationDirectory $(if ($name -like "*.log") { $logsDir } else { $configsDir })
    if ($copied) { $copiedFiles += $copied }
}
foreach ($pattern in @("*unit*console*.log", "*integration*console*.log")) {
    Get-ChildItem -LiteralPath $BuildDir -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
        $copied = Copy-ArtifactFile -Source $_.FullName -DestinationDirectory $logsDir
        if ($copied) { $copiedFiles += $copied }
    }
}
if ($KenshiPath) {
    foreach ($relativePath in @("KenshiOnline.log", "KenshiOnline_Server.log", "server.json", "Plugins_x64.cfg", "data\Plugins_x64.cfg")) {
        $copied = Copy-ArtifactFile -Source (Join-Path $KenshiPath $relativePath) -DestinationDirectory $(if ($relativePath -like "*.log") { $logsDir } else { $configsDir })
        if ($copied) { $copiedFiles += $copied }
    }
}
$appData = [Environment]::GetFolderPath("ApplicationData")
if ($appData) {
    $copied = Copy-ArtifactFile -Source (Join-Path $appData "KenshiMP\client.json") -DestinationDirectory $configsDir
    if ($copied) { $copiedFiles += $copied }
}

$binaryMetadata = @()
foreach ($name in @("KenshiMP.UnitTest.exe", "KenshiMP.IntegrationTest.exe", "KenshiMP.Server.exe", "KenshiMP.Injector.exe", "KenshiMP.Core.dll")) {
    $path = Join-Path $BuildDir $name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $file = Get-Item -LiteralPath $path
        $binaryMetadata += [pscustomobject]@{ Name = $name; SizeBytes = $file.Length; Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
}

$osInfo = $null
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $osInfo = "{0} ({1})" -f $os.Caption, $os.Version
} catch { }

$metadata = [ordered]@{
    Timestamp = (Get-Date).ToString("o"); RepoPath = $repoRoot; GitBranch = ((Get-GitOutput @("branch", "--show-current")) -join "")
    GitCommit = ((Get-GitOutput @("rev-parse", "HEAD")) -join ""); GitStatusShort = @(Get-GitOutput @("status", "--short"))
    PowerShellVersion = $PSVersionTable.PSVersion.ToString(); WindowsOs = $osInfo; BuildDir = $BuildDir; KenshiPath = $KenshiPath
    Binaries = $binaryMetadata; TestsRun = $shouldRunTests; TestResults = $testResults
}
$metadataPath = Join-Path $OutDir "metadata.json"
Write-Utf8File -Path $metadataPath -Content ($metadata | ConvertTo-Json -Depth 6)

$summaryLines = @("# KenshiMP validation artifacts", "", "- Timestamp: $($metadata.Timestamp)", "- Repository: $repoRoot", "- Build directory: $BuildDir")
if ($KenshiPath) { $summaryLines += "- Kenshi path: $KenshiPath" }
$summaryLines += "- Git: $($metadata.GitBranch) $($metadata.GitCommit)", "", "## Test results", ""
if ($testResults.Count -eq 0) { $summaryLines += "Tests were not run." }
foreach ($result in $testResults) {
    $summaryLines += "- $($result.Name): exit $($result.ExitCode); $($result.Summary)"
    if ($result.ServerStdoutLog) { $summaryLines += "  - Server stdout: $($result.ServerStdoutLog)" }
    if ($result.ServerStderrLog) { $summaryLines += "  - Server stderr: $($result.ServerStderrLog)" }
    foreach ($failure in $result.Failures) { $summaryLines += "  - $failure" }
}
$summaryLines += "", "## Included files", ""
if ($copiedFiles.Count -eq 0) { $summaryLines += "No optional logs or configurations were present." }
foreach ($file in $copiedFiles) { $summaryLines += "- $([System.IO.Path]::GetFileName($file))" }
$summaryPath = Join-Path $OutDir "summary.md"
Write-Utf8File -Path $summaryPath -Content (($summaryLines -join "`n") + "`n")

$zipPath = "$OutDir.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zipPath -Force
Write-Host "Validation artifact ZIP: $zipPath"

$hasTestFailure = @($testResults | Where-Object { ($_.ExitCode -ne 0) -or ($_.Failed -is [int] -and $_.Failed -gt 0) }).Count -gt 0
$integrationFailure = @($testResults | Where-Object { $_.Name -eq "KenshiMP.IntegrationTest.exe" -and (($_.ExitCode -ne 0) -or ($_.Failed -is [int] -and $_.Failed -gt 0)) }).Count -gt 0
if ($integrationFailure -and -not $AllowIntegrationFailure) {
    throw "Integration test failed; artifacts were still created: $zipPath. Use -AllowIntegrationFailure only to preserve a successful collector exit code."
}
if ($FailOnTestFailure -and $hasTestFailure) { throw "One or more tests failed; artifacts were still created: $zipPath" }
