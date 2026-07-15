# Validation artifact collection

Use `tools\collect-validation-artifacts.ps1` after local build, runtime, or test changes when you need one shareable record of the validation evidence. It packages test console output, selected KenshiMP logs/configuration, binary hashes, and Git/build metadata without changing the build or runtime behavior.

Run it from the repository root or any directory:

```powershell
# From build\bin\Release
..\..\..\tools\collect-validation-artifacts.ps1

# Include selected files from a Kenshi installation
.\tools\collect-validation-artifacts.ps1 -BuildDir .\build\bin\Release -KenshiPath "C:\Games\Kenshi"

# Collect existing evidence without starting tests
.\tools\collect-validation-artifacts.ps1 -BuildDir .\build\bin\Release -SkipTests

# Return a failing PowerShell exit status when a test fails (the ZIP is still created)
.\tools\collect-validation-artifacts.ps1 -BuildDir .\build\bin\Release -FailOnTestFailure

# Use a longer server readiness timeout (default: 60 seconds)
.\tools\collect-validation-artifacts.ps1 -BuildDir .\build\bin\Release -IntegrationReadyTimeoutSeconds 120

# Keep the ZIP but opt in to a successful collector exit code after an integration failure
.\tools\collect-validation-artifacts.ps1 -BuildDir .\build\bin\Release -AllowIntegrationFailure
```

By default the script detects `build\bin\Release` when it exists, otherwise it uses the current directory. If unit or integration test executables are present, it runs them unless `-SkipTests` is used. Output defaults to `validation-artifacts\<timestamp>` under the repository, with a ZIP alongside it. `-OutDir` chooses a different parent directory; the timestamped artifact folder is created inside it.

Each artifact directory contains `summary.md`, `metadata.json`, captured unit/integration console logs, and an allowlisted set of runtime evidence. From `BuildDir` and an optional Kenshi path, the collector considers `KenshiOnline_Server.log`, `KenshiOnline_<pid>.log`, `KenshiOnline_CRASH.log`, `KenshiOnline_BREADCRUMB.txt`, `server.json`, `Plugins_x64.cfg`, and `data\Plugins_x64.cfg`. From `%APPDATA%\KenshiMP`, it considers `client.json` and PID-specific `client_<pid>.json`. It does not recursively collect the Kenshi directory.

Artifact filenames are source-qualified, for example `logs\build-KenshiOnline_Server.log`, `logs\kenshi-KenshiOnline_12345.log`, and `configs\appdata-client_12345.json`. `metadata.json` includes a manifest with the original source path, artifact-relative path, category, size, timestamp, status, SHA-256 when available, and warnings. `summary.md` shows warnings first, then test results, included files with source identity, and missing expected runtime files.

The collector warns about missing expected files, zero-byte files, files older than two hours, and files modified within five seconds of collection. A provided `-KenshiPath` must be an existing directory and must not be a placeholder path. These warnings make evidence gaps visible, but artifact collection is not proof of green validation. Integration runs explicitly use `KenshiMP.Server.exe` from `BuildDir`, capture its stdout and stderr as separate artifact logs, poll handshake readiness for up to 60 seconds by default, and report early process exits or timeouts with the host, port, status, and log paths. Metadata includes timestamps, Git state, PowerShell/Windows details, build paths, and hashes and sizes of the main binaries when present.

The collector deliberately does not collect saves, Steam credentials, tokens, environment dumps, unrelated user files, or the whole Kenshi directory. Review the ZIP before sharing it and attach the resulting `<timestamp>.zip` to the issue, chat, or handoff where validation evidence is needed.

A partial integration failure is still useful evidence. For example, `64 passed, 2 failed` means the ZIP contains the exact console output and `[FAIL]` lines for the two failed checks, alongside the binary hashes and Git state needed to reproduce the run. The script continues collecting after failures, but an integration failure returns a non-zero exit code by default. Use `-AllowIntegrationFailure` only when a caller explicitly needs the collector itself to succeed; `-FailOnTestFailure` additionally makes unit-test failures fail the collector.
