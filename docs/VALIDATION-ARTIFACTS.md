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

Each artifact directory contains `summary.md`, `metadata.json`, captured unit/integration console logs, and any available selected files: build-directory `KenshiOnline_Server.log`, `server.json`, and generated unit/integration console logs; Kenshi-path `KenshiOnline.log`, `KenshiOnline_Server.log`, `server.json`, `Plugins_x64.cfg`, and `data\Plugins_x64.cfg`; and `%APPDATA%\KenshiMP\client.json`. Integration runs explicitly use `KenshiMP.Server.exe` from `BuildDir`, capture its stdout and stderr as separate artifact logs, poll handshake readiness for up to 60 seconds by default, and report early process exits or timeouts with the host, port, status, and log paths. Metadata includes timestamps, Git state, PowerShell/Windows details, build paths, and hashes and sizes of the main binaries when present.

The collector deliberately does not collect saves, Steam credentials, tokens, environment dumps, unrelated user files, or the whole Kenshi directory. Review the ZIP before sharing it and attach the resulting `<timestamp>.zip` to the issue, chat, or handoff where validation evidence is needed.

A partial integration failure is still useful evidence. For example, `64 passed, 2 failed` means the ZIP contains the exact console output and `[FAIL]` lines for the two failed checks, alongside the binary hashes and Git state needed to reproduce the run. The script continues collecting after failures, but an integration failure returns a non-zero exit code by default. Use `-AllowIntegrationFailure` only when a caller explicitly needs the collector itself to succeed; `-FailOnTestFailure` additionally makes unit-test failures fail the collector.
