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

function New-ArtifactRecord {
    param(
        [string]$SourcePath,
        [string]$ArtifactPath,
        [string]$ArtifactRelativePath,
        [string]$Category,
        [string]$Status,
        [Int64]$SizeBytes = 0,
        $LastWriteTime = $null,
        [string]$Sha256 = $null,
        [string]$Warning = $null
    )

    return [pscustomobject][ordered]@{
        SourcePath = $SourcePath; ArtifactPath = $ArtifactPath; ArtifactRelativePath = $ArtifactRelativePath
        Category = $Category; SizeBytes = $SizeBytes; LastWriteTime = if ($LastWriteTime) { $LastWriteTime.ToString("o") } else { $null }
        Sha256 = $Sha256; Status = $Status; Warning = $Warning
    }
}

function Copy-ArtifactFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory,
        [Parameter(Mandatory = $true)][string]$DestinationPrefix,
        [Parameter(Mandatory = $true)][string]$Category
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return New-ArtifactRecord -SourcePath $Source -Category $Category -Status "missing" -Warning "Expected file missing."
    }

    $sourceItem = Get-Item -LiteralPath $Source
    $fileName = "{0}{1}" -f $DestinationPrefix, $sourceItem.Name
    $destination = Join-Path $DestinationDirectory $fileName
    $collision = 2
    if (Test-Path -LiteralPath $destination) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $extension = [System.IO.Path]::GetExtension($fileName)
        do {
            $destination = Join-Path $DestinationDirectory ("{0}-{1}{2}" -f $base, $collision, $extension)
            $collision++
        } while (Test-Path -LiteralPath $destination)
    }

    try {
        Copy-Item -LiteralPath $Source -Destination $destination -Force
        $warnings = @()
        if ($sourceItem.Length -eq 0) { $warnings += "Copied file is zero bytes." }
        if ($sourceItem.LastWriteTime -lt $artifactStart.AddHours(-2)) { $warnings += "Copied file is older than the artifact timestamp by more than 2 hours." }
        if (((Get-Date) - $sourceItem.LastWriteTime).TotalSeconds -lt 5) { $warnings += "Copied file was modified within the last 5 seconds; logs may still be writing or unflushed." }
        $sha256 = $null
        try { $sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() } catch { $warnings += "SHA256 unavailable: $($_.Exception.Message)" }
        $relative = (Join-Path ([System.IO.Path]::GetFileName($DestinationDirectory)) ([System.IO.Path]::GetFileName($destination))) -replace '\\', '/'
        return New-ArtifactRecord -SourcePath $sourceItem.FullName -ArtifactPath $destination -ArtifactRelativePath $relative -Category $Category -SizeBytes $sourceItem.Length -LastWriteTime $sourceItem.LastWriteTime -Sha256 $sha256 -Status "copied" -Warning ($warnings -join " ")
    } catch {
        return New-ArtifactRecord -SourcePath $Source -Category $Category -Status "failed" -Warning "Copy failed: $($_.Exception.Message)"
    }
}

function Copy-ArtifactPattern {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory,
        [Parameter(Mandatory = $true)][string]$DestinationPrefix,
        [Parameter(Mandatory = $true)][string]$Category,
        [string]$NameRegex = $null
    )

    $matches = @(Get-ChildItem -LiteralPath $SourceDirectory -Filter $Pattern -File -ErrorAction SilentlyContinue)
    if ($NameRegex) { $matches = @($matches | Where-Object { $_.Name -match $NameRegex }) }
    if ($matches.Count -eq 0) {
        return @(New-ArtifactRecord -SourcePath (Join-Path $SourceDirectory $Pattern) -Category $Category -Status "missing" -Warning "Expected file missing.")
    }
    return @($matches | ForEach-Object { Copy-ArtifactFile -Source $_.FullName -DestinationDirectory $DestinationDirectory -DestinationPrefix $DestinationPrefix -Category $Category })
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
if (-not [string]::IsNullOrWhiteSpace($KenshiPath)) {
    $KenshiPath = Resolve-FullPath $KenshiPath
    $placeholderPatterns = @("\Path\To\", "\Your\Downgraded\Kenshi", "\Actual\Kenshi")
    if ($placeholderPatterns | Where-Object { $KenshiPath.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) {
        throw "KenshiPath appears to be a placeholder path: $KenshiPath"
    }
    if (-not (Test-Path -LiteralPath $KenshiPath -PathType Container)) {
        throw "KenshiPath does not exist or is not a directory: $KenshiPath"
    }
}

$artifactStart = Get-Date
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
        $summaryMatch = Select-String -LiteralPath $logPath -Pattern "Results:\s*\d+\s+passed,\s*\d+\s+failed" | Select-Object -Last 1
        $summary = if ($summaryMatch) { $summaryMatch.Line.Trim() } else { $null }
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
        $failLines = @(Select-String -LiteralPath $logPath -Pattern "\[FAIL\]" | ForEach-Object { $_.Line.Trim() })
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

$artifactRecords = @()
foreach ($name in @("KenshiOnline_Server.log", "KenshiOnline_CRASH.log", "KenshiOnline_BREADCRUMB.txt")) {
    $artifactRecords += Copy-ArtifactFile -Source (Join-Path $BuildDir $name) -DestinationDirectory $logsDir -DestinationPrefix "build-" -Category "log"
}
$artifactRecords += Copy-ArtifactPattern -SourceDirectory $BuildDir -Pattern "KenshiOnline_*.log" -NameRegex '^KenshiOnline_(?!Server\.log$|CRASH\.log$).+\.log$' -DestinationDirectory $logsDir -DestinationPrefix "build-" -Category "log"
foreach ($name in @("server.json", "Plugins_x64.cfg", "data\Plugins_x64.cfg")) {
    $artifactRecords += Copy-ArtifactFile -Source (Join-Path $BuildDir $name) -DestinationDirectory $configsDir -DestinationPrefix "build-" -Category "config"
}
foreach ($pattern in @("*unit*console*.log", "*integration*console*.log")) {
    Get-ChildItem -LiteralPath $BuildDir -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
        $artifactRecords += Copy-ArtifactFile -Source $_.FullName -DestinationDirectory $logsDir -DestinationPrefix "build-" -Category "test-log"
    }
}
if ($KenshiPath) {
    foreach ($name in @("KenshiOnline_Server.log", "KenshiOnline_CRASH.log", "KenshiOnline_BREADCRUMB.txt")) {
        $artifactRecords += Copy-ArtifactFile -Source (Join-Path $KenshiPath $name) -DestinationDirectory $logsDir -DestinationPrefix "kenshi-" -Category "log"
    }
    $artifactRecords += Copy-ArtifactPattern -SourceDirectory $KenshiPath -Pattern "KenshiOnline_*.log" -NameRegex '^KenshiOnline_(?!Server\.log$|CRASH\.log$).+\.log$' -DestinationDirectory $logsDir -DestinationPrefix "kenshi-" -Category "log"
    foreach ($relativePath in @("server.json", "Plugins_x64.cfg", "data\Plugins_x64.cfg")) {
        $artifactRecords += Copy-ArtifactFile -Source (Join-Path $KenshiPath $relativePath) -DestinationDirectory $configsDir -DestinationPrefix "kenshi-" -Category "config"
    }
}
$appData = [Environment]::GetFolderPath("ApplicationData")
if ($appData) {
    $appDataKenshiMp = Join-Path $appData "KenshiMP"
    $artifactRecords += Copy-ArtifactFile -Source (Join-Path $appDataKenshiMp "client.json") -DestinationDirectory $configsDir -DestinationPrefix "appdata-" -Category "config"
    $artifactRecords += Copy-ArtifactPattern -SourceDirectory $appDataKenshiMp -Pattern "client_*.json" -DestinationDirectory $configsDir -DestinationPrefix "appdata-" -Category "config"
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
    CollectedFiles = $artifactRecords
    Warnings = @()
}
$metadataWarnings = @($artifactRecords | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Warning) } | ForEach-Object { "$($_.Status): $($_.SourcePath) - $($_.Warning)" })
$coreRuntimeLogs = @($artifactRecords | Where-Object { $_.Status -eq "copied" -and $_.SourcePath -match "KenshiOnline_\d+\.log$" })
if ($coreRuntimeLogs.Count -eq 0) { $metadataWarnings += "No Core runtime log found (expected KenshiOnline_<pid>.log)." }
if ($KenshiPath) {
    $kenshiLogs = @($artifactRecords | Where-Object { $_.Status -eq "copied" -and $_.SourcePath.StartsWith($KenshiPath, [StringComparison]::OrdinalIgnoreCase) -and $_.Category -eq "log" })
    if ($kenshiLogs.Count -eq 0) { $metadataWarnings += "No Kenshi-side logs found under KenshiPath." }
}
$metadata.Warnings = $metadataWarnings
$metadataPath = Join-Path $OutDir "metadata.json"
Write-Utf8File -Path $metadataPath -Content ($metadata | ConvertTo-Json -Depth 6)

$summaryLines = @("# KenshiMP validation artifacts", "", "- Timestamp: $($metadata.Timestamp)", "- Repository: $repoRoot", "- Build directory: $BuildDir")
if ($KenshiPath) { $summaryLines += "- Kenshi path: $KenshiPath" }
$summaryLines += "- Git: $($metadata.GitBranch) $($metadata.GitCommit)", "", "## Warnings", ""
if ($metadataWarnings.Count -eq 0) { $summaryLines += "No artifact warnings." }
foreach ($warning in $metadataWarnings) { $summaryLines += "- $warning" }
$summaryLines += "", "## Test results", ""
if ($testResults.Count -eq 0) { $summaryLines += "Tests were not run." }
foreach ($result in $testResults) {
    $summaryLines += "- $($result.Name): exit $($result.ExitCode); $($result.Summary)"
    if ($result.ServerStdoutLog) { $summaryLines += "  - Server stdout: $($result.ServerStdoutLog)" }
    if ($result.ServerStderrLog) { $summaryLines += "  - Server stderr: $($result.ServerStderrLog)" }
    foreach ($failure in $result.Failures) { $summaryLines += "  - $failure" }
}
$summaryLines += "", "## Included files", ""
$copiedRecords = @($artifactRecords | Where-Object { $_.Status -eq "copied" })
if ($copiedRecords.Count -eq 0) { $summaryLines += "No allowlisted logs or configurations were present." }
foreach ($record in $copiedRecords) { $summaryLines += "- $($record.ArtifactRelativePath) <- $($record.SourcePath) ($($record.SizeBytes) bytes; $($record.LastWriteTime))" }
$summaryLines += "", "## Missing expected runtime files", ""
$missingRecords = @($artifactRecords | Where-Object { $_.Status -eq "missing" })
if ($missingRecords.Count -eq 0) { $summaryLines += "None." }
foreach ($record in $missingRecords) { $summaryLines += "- $($record.SourcePath)" }
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
