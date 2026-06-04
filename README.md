# Kenshi-Online (Authority Architecture Rewrite)

**⚠️ WORK IN PROGRESS - NOT PRODUCTION READY**

Kenshi-Online is a 16-player co-op multiplayer mod for Kenshi implementing proper client-server authority architecture.

## Current Status: Testing Phase (Phase 1+2)

**What's Implemented:**
- ✅ **Phase 1**: Authority data model (NetEntityId with generation, LocalAuthorityState enum)
- ✅ **Phase 2**: Client-side inbound authority validation (AuthorityValidator, PendingSnapshotQueue)

**What's Working:**
- Echo suppression framework (prevents local player rubber-banding)
- Authority validation gate (blocks unauthorized entity control)
- Spawn race handling (queues position updates until entity spawns)

**Known Issues:**
- ⚠️ Compilation error in packet_handler.cpp (duplicate function definition)
- ⚠️ Prediction reconciliation not implemented yet (Phase 7)
- ⚠️ Generation not propagated in protocol messages yet (Phase 6)

## Architecture

**The Core Law:** Server owns truth, clients own input.

- **Server**: Validates all client commands, broadcasts authoritative snapshots
- **Client**: Sends input/commands only, validates inbound authority before applying
- **Entities**: Tracked with NetEntityId (id + generation) to prevent ghost control bugs
- **Authority States**: LocalOwned (predict), RemoteOwned (interpolate), ServerOwned (apply server updates)

## Phases (8 total, 2 complete)

1. ✅ **Authority Data Model** - NetEntityId, LocalAuthorityState, validation helpers
2. ✅ **Client Inbound Validation** - AuthorityValidator, PendingSnapshotQueue  
3. ⏳ **Pending Spawn Queue** - Spawn-before-sync handshake
4. ⏳ **Network Thread Safety** - Verify command queue safety
5. ⏳ **Server Authority Enforcement** - Server-side validation
6. ⏳ **Protocol Generation Tracking** - Add generation to all entity packets
7. ⏳ **Client Prediction** - Local prediction + reconciliation
8. ⏳ **Authority Stats** - Observability metrics

## Building

**Requirements:**
- Visual Studio 2022 (MSVC)
- CMake 3.20+
- Kenshi (Steam or GOG)

**Build:**
```bash
cd build
msbuild KenshiMP.sln /p:Configuration=Release /p:Platform=x64
```

## Contributing

This is an experimental rewrite implementing proper authority architecture. Contributions welcome but coordinate with maintainers first as architecture is still being finalized.

**Key files:**
- `KenshiMP.Core/sync/authority_validator.*` - Client validation
- `KenshiMP.Core/sync/pending_snapshot_queue.*` - Spawn race handling
- `KenshiMP.Core/net/packet_handler.cpp` - Packet handling with validation
- `KenshiMP.Common/include/kmp/types.h` - Core types (NetEntityId, authority enums)

## License

MIT License - See LICENSE file

---

**This is a testing/development branch.** For stable releases, see main releases page (when available).
