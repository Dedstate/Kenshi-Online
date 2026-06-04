#include "authority_validator.h"
#include <spdlog/spdlog.h>

namespace kmp {

SnapshotDecision AuthorityValidator::ValidateInboundSnapshot(
    const CharacterPosition& pos,
    uint32_t sourcePlayerId,
    uint32_t myPlayerId,
    EntityRegistry& registry
) {
    // 1. Check if entity exists in registry
    auto* info = registry.Find(pos.entityId);
    if (!info) {
        // Entity not spawned yet → queue for interpolator to handle later
        return SnapshotDecision::QueuePendingSpawn;
    }

    // 2. Check generation match
    // Note: For Phase 2, generation checking uses 0 (Phase 6 will add full tracking)
    if (pos.generation != 0 && info->generation != pos.generation) {
        // Stale data from old spawn → reject
        return SnapshotDecision::RejectStaleGeneration;
    }

    // 3. Check if destroyed
    if (info->destroyed) {
        // Entity was destroyed locally → reject update
        return SnapshotDecision::RejectDestroyed;
    }

    // 4. Check ownership
    uint32_t ownerPlayerId = registry.GetOwnerPlayerId(pos.entityId);

    // 4a. My own entity coming back from server → reconcile prediction
    if (ownerPlayerId == myPlayerId) {
        return SnapshotDecision::ReconcileLocal;
    }

    // 4b. Source doesn't own this entity → authority violation
    if (ownerPlayerId != sourcePlayerId) {
        spdlog::warn(
            "[AuthorityValidator] Authority violation: entity {} owned by player {} "
            "but update came from player {}",
            pos.entityId, ownerPlayerId, sourcePlayerId
        );
        return SnapshotDecision::RejectAuthorityViolation;
    }

    // 4c. Remote or server-owned entity with valid owner → apply
    if (registry.IsRemote(pos.entityId)) {
        return SnapshotDecision::ApplyRemote;
    }

    // 5. Default: unknown reason → reject
    spdlog::warn(
        "[AuthorityValidator] Unknown validation failure for entity {} from player {}",
        pos.entityId, sourcePlayerId
    );
    return SnapshotDecision::RejectUnknown;
}

} // namespace kmp
