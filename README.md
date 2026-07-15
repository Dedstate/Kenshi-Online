# Kenshi Online

**Experimental multiplayer mod infrastructure for Kenshi**

[![Status](https://img.shields.io/badge/status-experimental-orange)]()
[![Version](https://img.shields.io/badge/version-0.1.0--alpha-blue)]()
[![Platform](https://img.shields.io/badge/platform-Windows%20x64-lightgrey)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()

> **Alpha status:** This project is in active development. Local builds and tests are available, but runtime behavior inside Kenshi still requires manual validation. See [Known Issues](#known-issues).

---

## Quick Start

```powershell
# 1. Clone with submodules
git clone --recursive https://github.com/Dedstate/Kenshi-Online.git
cd Kenshi-Online

# 2. Configure
cmake -S . -B .\build -A x64

# 3. Build Release
cmake --build .\build --config Release --parallel

# 4. Run basic validation
.\build\bin\Release\KenshiMP.UnitTest.exe
.\build\bin\Release\KenshiMP.IntegrationTest.exe
```

Expected current baseline:

```text
UnitTest: 95 passed, 0 failed
IntegrationTest: currently has 2 known failing assertions
```

Do not treat the project as fully runtime-validated until it has been tested inside a real Kenshi installation.

---

## Current State

Confirmed or actively implemented areas:

* Dedicated server and ENet-based client/server protocol.
* Client-side core DLL and injector tooling.
* Shared protocol/message/common libraries.
* Unit test coverage for core protocol and utility behavior.
* Integration test coverage for handshake, entity spawn, position sync, chat, disconnect, time sync, inventory, trade, squad, faction, building, server query, and full-session paths.
* Validation artifact collection workflow for local test/runtime evidence.

Areas that still need runtime validation or follow-up work:

* Real Kenshi runtime validation on the target game version.
* Connect/disconnect/reconnect behavior under the actual game process.
* Building placement confirmation semantics.
* Disconnect cleanup/reconnect-preservation semantics.
* Multi-client runtime behavior beyond basic local test coverage.
* Hook behavior inside Kenshi, including crash containment and pointer safety.
* Installer/uninstaller behavior against disposable or backed-up Kenshi installs.

---

## Documentation

* [Validation artifact collection](docs/VALIDATION-ARTIFACTS.md)
* [Authority implementation notes](docs/AUTHORITY-IMPLEMENTATION-COMPLETE.md)
* [Recent multiplayer fixes](docs/MULTIPLAYER-FIXES-2026-06-04.md)
* Build instructions are included below.

Some older documentation may describe intended architecture or historical plans rather than fully validated runtime behavior. Prefer recent validation logs, test results, and PR notes when deciding what is currently confirmed.

---

## Architecture

```text
Kenshi process
  KenshiMP.Core.dll
    Hooks / scanners / runtime integration
    Network client
    Packet handling
    Local game-state bridge

        ENet protocol

Dedicated server
  KenshiMP.Server.exe
    Connection/session handling
    Server-side world state
    Authority validation
    Persistence and broadcast logic
```

Main projects:

```text
KenshiMP.Common           Shared protocol, messages, math, and utilities
KenshiMP.Scanner          Memory scanning helpers
KenshiMP.Core             Client-side Kenshi plugin/core DLL
KenshiMP.Server           Dedicated server
KenshiMP.MasterServer     Master/server-browser related code
KenshiMP.Injector         Injector/launcher tooling
KenshiMP.TestClient       Test client target
KenshiMP.UnitTest         Unit test target
KenshiMP.IntegrationTest  Integration test target
KenshiMP.LiveTest         Runtime-oriented test target
```

Third-party dependencies are managed as git submodules under `lib/`.

---

## Building from Source

### Prerequisites

* Windows 10/11 x64
* Visual Studio 2022 with C++ workload
* Windows SDK
* CMake 3.20+
* Git with submodule support

### Clone

```powershell
git clone --recursive https://github.com/Dedstate/Kenshi-Online.git
cd Kenshi-Online
```

If the repository was cloned without submodules:

```powershell
git submodule update --init --recursive
```

### Build

```powershell
cmake -S . -B .\build -A x64
cmake --build .\build --config Release --parallel
```

### Output

Typical Release outputs are written to:

```text
build\bin\Release
```

Important binaries include:

```text
KenshiMP.Core.dll
KenshiMP.Server.exe
KenshiMP.Injector.exe
KenshiMP.UnitTest.exe
KenshiMP.IntegrationTest.exe
```

For final runtime checks, prefer a full Release build instead of a single-target build:

```powershell
cmake --build .\build --config Release --parallel
```

---

## Validation

### Unit tests

```powershell
.\build\bin\Release\KenshiMP.UnitTest.exe
```

Current expected result:

```text
95 passed, 0 failed
```

### Integration tests

```powershell
.\build\bin\Release\KenshiMP.IntegrationTest.exe
```

Current known state:

```text
64 passed, 2 failed
```

Known failing assertions:

```text
Client 1 received EntityDespawn for Bob's entity
Client 1 received building placement confirmation
```

These are known behavior/test mismatches in the current baseline and should be handled in a follow-up fix. They should not be hidden or presented as a green integration result.

### Validation artifacts

If available in your branch, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\collect-validation-artifacts.ps1 `
  -BuildDir .\build\bin\Release
```

The collector packages test output, selected logs/configuration, binary hashes, Git state, and metadata into `validation-artifacts/`.

A created artifact ZIP is evidence of the run. It is not automatically proof that every test passed.

---

## Runtime Use

This project is not currently presented as a ready-to-use end-user multiplayer release.

For local runtime testing:

1. Build Release.
2. Use a disposable or backed-up Kenshi installation.
3. Start `KenshiMP.Server.exe`.
4. Launch Kenshi through the intended injector/plugin path.
5. Confirm the game reaches the main menu.
6. Attempt local connection to the server.
7. Check server/client logs.
8. Collect validation artifacts if sharing results.

Avoid testing installer or plugin changes directly against your primary Kenshi installation unless you have backups and understand the modified files.

---

## Server

The server uses `server.json` when present, otherwise defaults are created by the server.

Example:

```json
{
  "serverName": "My Server",
  "port": 7777,
  "maxPlayers": 16
}
```

Run from the Release output directory:

```powershell
.\build\bin\Release\KenshiMP.Server.exe
```

For LAN or remote testing, make sure the UDP port is reachable and record the exact test environment in your validation notes.

---

## Known Issues

### Current

* IntegrationTest currently has two known failing assertions.
* Runtime behavior inside Kenshi still needs explicit manual validation.
* Disconnect cleanup and reconnect preservation semantics need to be reconciled with tests.
* Building placement should confirm the server-assigned building ID to the builder client.
* Combat, hooks, SEH behavior, and multi-client runtime behavior require live validation.
* Installer/uninstaller workflows should be tested only on disposable or backed-up Kenshi copies.

### Recently improved

* Windows Release build and unit-test validation have been exercised locally.
* Validation artifact collection was added to make local test/runtime evidence easier to share.
* Several installer, networking, crash-safety, and spawn hardening changes have been integrated, but runtime validation remains required.

See the docs and recent PR notes for exact validation status before relying on a feature.

---

## Contributing

1. Fork the repository.
2. Create a focused branch.
3. Keep changes scoped.
4. Build Release.
5. Run unit tests.
6. Run integration tests and report the exact result.
7. For runtime changes, test against a real Kenshi installation and record evidence.
8. Open a PR with validation notes.

Suggested PR validation block:

```text
Build:
- cmake --build .\build --config Release --parallel

Tests:
- UnitTest: <result>
- IntegrationTest: <result>

Runtime:
- Kenshi version/build:
- Runtime smoke: passed/failed/not tested
- Artifact ZIP:
- Remaining risks:
```

Areas needing help:

* Fixing the two known IntegrationTest mismatches.
* Runtime validation inside Kenshi.
* Connect/disconnect/reconnect stress testing.
* Building placement and world-state synchronization.
* Installer safety and reproducible validation.
* Documentation cleanup.

---

## Project Stats

Approximate project shape:

* Projects: Core, Server, Common, Scanner, Injector, MasterServer, TestClient, UnitTest, IntegrationTest, LiveTest.
* Language: C++17.
* Build system: CMake / Visual Studio.
* Platform: Windows x64.
* Networking: ENet.
* Hooking/runtime support: MinHook and project-specific scanner/core code.

These numbers may change frequently while the project is under active development.

---

## License

MIT License. See [LICENSE](LICENSE).

---

## Contact

* GitHub: [Dedstate/Kenshi-Online](https://github.com/Dedstate/Kenshi-Online)
* Issues: [Report bugs](https://github.com/Dedstate/Kenshi-Online/issues)

---

**Last Updated:** 2026-07-15
**Version:** 0.1.0-alpha
**Status:** Experimental; buildable locally, unit-test green, integration baseline temporarily has two known failures.
