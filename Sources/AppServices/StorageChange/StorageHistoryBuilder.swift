import Foundation
import SafetyCore

/// Builds compact history from an already-produced explorer snapshot.
/// No filesystem IO — observation reuse only.
public enum StorageHistoryBuilder {
    public static let privacyFieldsStored: [String] = [
        "stableIdentity",
        "parentIdentity",
        "displayName",
        "size",
        "semanticCategory",
        "nodeKind",
        "actionReadinessSummary",
        "timestamp",
        "comparisonFields"
    ]

    public static func build(
        from explorer: StorageExplorerSnapshot,
        actionHistory: [UIActionHistoryItem] = [],
        entitySummaries: [HistoryEntitySummary] = []
    ) -> StorageHistorySnapshot {
        let accounting = explorer.mapAccounting
            ?? PhysicalMapAccountingResolver.resolve(for: explorer.physicalRoot)
        let colliding = collidingEntityIDs(in: explorer.presentedRoot)
        var seenIdentities = Set<String>()
        let nodes = flattenPresented(
            explorer.presentedRoot,
            parent: nil,
            collidingEntities: colliding,
            seenIdentities: &seenIdentities
        )
        var categoryTotals: [String: Int64] = [:]
        for node in nodes where node.bytesKnown {
            let key = node.semanticCategory ?? ProductStorageCategory.otherUnknown.rawValue
            categoryTotals[key, default: 0] += max(0, node.bytes ?? 0)
        }
        // Prefer exclusive-ish top-level category presentation totals when available via map nodes.
        let categories = categoryTotals
            .map { HistoryCategoryTotal(category: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }

        let actions = actionHistory.prefix(40).map { item in
            HistoryActionSummary(
                actionID: item.id,
                entityID: item.entityID,
                action: item.action.rawValue,
                auditStatus: item.logicalVerified ? "POST_VERIFIED" : "EXECUTED",
                verificationState: item.readiness.rawValue,
                executedAt: item.timestamp,
                logicalActionCompleted: item.logicalVerified,
                permitID: item.permitID,
                verifiedRecoveredBytes: item.verifiedRecoveredBytes
            )
        }

        return StorageHistorySnapshot(
            snapshotID: explorer.snapshotID,
            generatedAt: explorer.generatedAt,
            volumeIdentity: volumeIdentity(from: explorer.diskCapacity),
            rootScopeIdentity: explorer.physicalRoot.id,
            diskCapacity: explorer.diskCapacity,
            physicalMapAccounting: accounting,
            physicalNodeSummaries: nodes,
            semanticCategoryTotals: categories,
            selectedEntitySummaries: Array(entitySummaries.prefix(80)),
            actionStateSummaries: Array(actions),
            scanCoverage: HistoryScanCoverage(
                physicalNodeCount: explorer.telemetry.physicalNodeCount,
                maxDepth: explorer.telemetry.maxDepth,
                accountingValid: explorer.accountingValid,
                mapCoverage: accounting.coverage.rawValue,
                mapBasis: accounting.basis.rawValue
            )
        )
    }

    public static func volumeIdentity(from disk: DiskCapacitySnapshot) -> String {
        let name = disk.volumeName.isEmpty ? "volume" : disk.volumeName
        return "\(name)#\(disk.volumeTotalBytes ?? 0)"
    }

    private static func flattenPresented(
        _ node: StorageNodePresentation,
        parent: String?,
        collidingEntities: Set<String>,
        seenIdentities: inout Set<String>
    ) -> [HistoryNodeSummary] {
        let base = preferredIdentity(node, collidingEntities: collidingEntities)
        let usedCollisionSuffix = seenIdentities.contains(base)
        let identity = uniquifyIdentity(base, seen: &seenIdentities)
        let summary = HistoryNodeSummary(
            stableIdentity: identity,
            parentIdentity: parent,
            displayName: node.title,
            bytes: node.physical.bytesKnown ? node.bytes : nil,
            bytesKnown: node.physical.bytesKnown,
            nodeKind: node.physical.nodeKind.rawValue,
            semanticCategory: node.semanticCategory.rawValue,
            depth: node.physical.depth,
            identityStability: usedCollisionSuffix ? "snapshot_local" : "canonical"
        )
        var out = [summary]
        let selfID = summary.stableIdentity
        for child in node.children {
            out.append(contentsOf: flattenPresented(
                child,
                parent: selfID,
                collidingEntities: collidingEntities,
                seenIdentities: &seenIdentities
            ))
        }
        return out
    }

    private static func uniquifyIdentity(_ base: String, seen: inout Set<String>) -> String {
        if seen.insert(base).inserted { return base }
        var index = 2
        while true {
            let candidate = "\(base)#\(index)"
            if seen.insert(candidate).inserted { return candidate }
            index += 1
        }
    }

    public static func preferredIdentity(
        _ node: StorageNodePresentation,
        collidingEntities: Set<String> = []
    ) -> String {
        if let entity = node.technicalEntityID, !entity.isEmpty, !collidingEntities.contains(entity) {
            return "entity:" + entity
        }
        return node.physical.id
    }

    public static func collidingEntityIDs(in root: StorageNodePresentation) -> Set<String> {
        var counts: [String: Int] = [:]
        func walk(_ node: StorageNodePresentation) {
            if let entity = node.technicalEntityID, !entity.isEmpty {
                counts[entity, default: 0] += 1
            }
            for child in node.children { walk(child) }
        }
        walk(root)
        return Set(counts.filter { $0.value > 1 }.map(\.key))
    }
}
