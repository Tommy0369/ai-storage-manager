import Foundation
import SafetyCore

/// Pure-data diff. No filesystem IO.
public enum StorageSnapshotDiffEngine {
    public static func compare(
        previous: StorageHistorySnapshot?,
        current: StorageHistorySnapshot,
        window: String = "since_last_scan",
        falseGREEN: Int = 0,
        duplicateEvaluations: Int = 0
    ) -> StorageChangeReport {
        let started = Date()
        guard let previous else {
            let explanation = StorageChangeExplanationBuilder.firstRun()
            return StorageChangeReport(
                currentSnapshotID: current.snapshotID,
                comparisonSnapshotID: nil,
                comparisonWindow: window,
                comparisonQuality: .noComparisonYet,
                diskUsedCurrent: diskBytes(current.diskCapacity.volumeUsedBytes),
                diskFreeCurrent: diskBytes(current.diskCapacity.volumeAvailableBytes),
                mappedCurrent: current.physicalMapAccounting.mappedBytes,
                coverageNotes: ["First history snapshot. No prior comparable scan."],
                explanation: explanation,
                falseGREEN: falseGREEN,
                duplicateEvaluations: duplicateEvaluations,
                diffMs: elapsedMs(since: started),
                changeReportBuildMs: elapsedMs(since: started)
            )
        }

        let quality = comparability(previous: previous, current: current)
        if quality == .notComparable {
            let explanation = StorageChangeExplanation(
                headline: "Storage history is not comparable for this pair of scans.",
                bodyLines: [
                    "Volume, schema, or root scope does not match.",
                    "Individual node trends are withheld to avoid inventing change."
                ],
                usesLowerBoundLanguage: false,
                firstRun: false
            )
            return StorageChangeReport(
                currentSnapshotID: current.snapshotID,
                comparisonSnapshotID: previous.snapshotID,
                comparisonWindow: window,
                comparisonQuality: .notComparable,
                diskUsedPrevious: previous.diskCapacity.volumeUsedBytes,
                diskUsedCurrent: diskBytes(current.diskCapacity.volumeUsedBytes),
                diskUsedDelta: signedDelta(
                    previous: previous.diskCapacity.volumeUsedBytes,
                    current: current.diskCapacity.volumeUsedBytes
                ),
                diskFreePrevious: previous.diskCapacity.volumeAvailableBytes,
                diskFreeCurrent: diskBytes(current.diskCapacity.volumeAvailableBytes),
                diskFreeDelta: signedDelta(
                    previous: previous.diskCapacity.volumeAvailableBytes,
                    current: current.diskCapacity.volumeAvailableBytes
                ),
                mappedPrevious: previous.physicalMapAccounting.mappedBytes,
                mappedCurrent: current.physicalMapAccounting.mappedBytes,
                coverageNotes: ["NOT_COMPARABLE: volume/schema/scope mismatch."],
                explanation: explanation,
                falseGREEN: falseGREEN,
                duplicateEvaluations: duplicateEvaluations,
                diffMs: elapsedMs(since: started),
                changeReportBuildMs: elapsedMs(since: started)
            )
        }

        let changes = matchNodes(previous: previous, current: current)
        let growing = changes
            .filter { $0.changeKind == .grew && $0.comparisonConfidence == .matched }
            .sorted { ($0.deltaBytes ?? 0) > ($1.deltaBytes ?? 0) }
        let shrinking = changes
            .filter { $0.changeKind == .shrank && $0.comparisonConfidence == .matched }
            .sorted { ($0.deltaBytes ?? 0) < ($1.deltaBytes ?? 0) }
        let newItems = changes
            .filter { $0.changeKind == .new }
            .sorted { ($0.currentBytes ?? 0) > ($1.currentBytes ?? 0) }
        let removed = changes
            .filter { $0.changeKind == .removed }
            .sorted { ($0.previousBytes ?? 0) > ($1.previousBytes ?? 0) }

        let identifiedGrowth = growing.reduce(Int64(0)) { $0 + max(0, $1.deltaBytes ?? 0) }
        let identifiedShrink = shrinking.reduce(Int64(0)) { $0 + abs(min(0, $1.deltaBytes ?? 0)) }

        let diskUsedDelta = signedDelta(
            previous: previous.diskCapacity.volumeUsedBytes,
            current: current.diskCapacity.volumeUsedBytes
        )
        let diskFreeDelta = signedDelta(
            previous: previous.diskCapacity.volumeAvailableBytes,
            current: current.diskCapacity.volumeAvailableBytes
        )

        let mappedDelta: Int64?
        var notes: [String] = []
        if quality == .fullyComparable,
           let prevMap = previous.physicalMapAccounting.mappedBytes,
           let curMap = current.physicalMapAccounting.mappedBytes {
            mappedDelta = signedDelta(previous: prevMap, current: curMap)
        } else {
            mappedDelta = nil
            notes.append("Map totals not fully comparable; reporting identified matched-node growth as lower bound.")
        }

        let unexplainedDelta: Int64?
        if let usedDelta = diskUsedDelta, usedDelta > 0 {
            let gap = usedDelta - identifiedGrowth
            if quality == .fullyComparable {
                unexplainedDelta = max(0, gap)
            } else if quality == .partiallyComparable {
                notes.append("PARTIAL comparison: unexplained remainder may include unmapped scope.")
                unexplainedDelta = gap > 0 ? gap : nil
            } else {
                unexplainedDelta = nil
            }
        } else {
            unexplainedDelta = quality == .fullyComparable ? 0 : nil
        }

        let categoryDeltas = categoryDeltas(previous: previous, current: current)
        let actionCorr = correlateActions(previous: previous, current: current, changes: changes)
        let regen = correlateRegeneration(previous: previous, current: current)

        let explanation = StorageChangeExplanationBuilder.build(
            quality: quality,
            diskUsedDelta: diskUsedDelta,
            identifiedGrowth: identifiedGrowth,
            unexplained: unexplainedDelta,
            topGrowing: Array(growing.prefix(5)),
            usesLowerBound: quality == .partiallyComparable
        )

        return StorageChangeReport(
            currentSnapshotID: current.snapshotID,
            comparisonSnapshotID: previous.snapshotID,
            comparisonWindow: window,
            comparisonQuality: quality,
            diskUsedPrevious: previous.diskCapacity.volumeUsedBytes,
            diskUsedCurrent: diskBytes(current.diskCapacity.volumeUsedBytes),
            diskUsedDelta: diskUsedDelta,
            diskFreePrevious: previous.diskCapacity.volumeAvailableBytes,
            diskFreeCurrent: diskBytes(current.diskCapacity.volumeAvailableBytes),
            diskFreeDelta: diskFreeDelta,
            mappedPrevious: previous.physicalMapAccounting.mappedBytes,
            mappedCurrent: current.physicalMapAccounting.mappedBytes,
            mappedDelta: mappedDelta,
            identifiedGrowthBytes: identifiedGrowth,
            identifiedShrinkBytes: identifiedShrink,
            unexplainedDeltaBytes: unexplainedDelta,
            topGrowing: Array(growing.prefix(10)),
            topShrinking: Array(shrinking.prefix(10)),
            newLargeItems: Array(newItems.prefix(10)),
            removedLargeItems: Array(removed.prefix(10)),
            categoryDeltas: categoryDeltas,
            relatedVerifiedActions: actionCorr,
            regeneratedItems: regen,
            coverageNotes: notes,
            explanation: explanation,
            allChanges: changes,
            falseGREEN: falseGREEN,
            duplicateEvaluations: duplicateEvaluations,
            diffMs: elapsedMs(since: started),
            changeReportBuildMs: elapsedMs(since: started)
        )
    }

    public static func comparability(
        previous: StorageHistorySnapshot,
        current: StorageHistorySnapshot
    ) -> StorageComparisonQuality {
        guard previous.schemaVersion == current.schemaVersion,
              previous.schemaVersion == storageHistorySchemaVersion else {
            return .notComparable
        }
        guard previous.volumeIdentity == current.volumeIdentity else {
            return .notComparable
        }
        guard previous.rootScopeIdentity == current.rootScopeIdentity else {
            return .notComparable
        }

        let prevComplete = previous.physicalMapAccounting.basis == .rootMeasured
            && previous.physicalMapAccounting.coverage == .complete
        let curComplete = current.physicalMapAccounting.basis == .rootMeasured
            && current.physicalMapAccounting.coverage == .complete
        if prevComplete && curComplete {
            return .fullyComparable
        }
        return .partiallyComparable
    }

    public static func signedDelta(previous: Int64, current: Int64) -> Int64 {
        current &- previous
    }

    public static func signedDelta(previous: Int64?, current: Int64?) -> Int64? {
        guard let previous, let current else { return nil }
        return current &- previous
    }

    private static func diskBytes(_ value: Int64?) -> Int64 { value ?? 0 }

    public static func selectSnapshot(
        in store: StorageHistoryStore,
        window: ComparisonWindow,
        now: Date = Date()
    ) -> StorageHistorySnapshot? {
        let all = store.loadAll()
        guard !all.isEmpty else { return nil }
        switch window {
        case .sinceLastScan:
            return all.count >= 2 ? all[1] : nil
        case .hours24:
            return store.snapshot(atOrBefore: now.addingTimeInterval(-24 * 3600))
                ?? all.first { $0.generatedAt <= now.addingTimeInterval(-24 * 3600) }
        case .days7:
            let target = now.addingTimeInterval(-7 * 24 * 3600)
            return store.snapshot(atOrBefore: target)
        case .days30:
            let target = now.addingTimeInterval(-30 * 24 * 3600)
            return store.snapshot(atOrBefore: target)
        }
    }

    public enum ComparisonWindow: String, Sendable {
        case sinceLastScan = "since_last_scan"
        case hours24 = "24h"
        case days7 = "7d"
        case days30 = "30d"
    }

    // MARK: - Matching

    private static func matchNodes(
        previous: StorageHistorySnapshot,
        current: StorageHistorySnapshot
    ) -> [StorageChangeItem] {
        let prevByID = Dictionary(previous.physicalNodeSummaries.map { ($0.stableIdentity, $0) }, uniquingKeysWith: { first, _ in first })
        let curByID = Dictionary(current.physicalNodeSummaries.map { ($0.stableIdentity, $0) }, uniquingKeysWith: { first, _ in first })
        var usedPrev = Set<String>()
        var items: [StorageChangeItem] = []

        for (id, cur) in curByID {
            if let prev = prevByID[id] {
                usedPrev.insert(id)
                if cur.identityStability == "snapshot_local"
                    || prev.identityStability == "snapshot_local"
                    || id.contains("#") {
                    items.append(StorageChangeItem(
                        identity: id,
                        displayName: cur.displayName,
                        previousBytes: prev.bytes,
                        currentBytes: cur.bytes,
                        deltaBytes: nil,
                        changeKind: .unknownMatch,
                        semanticCategory: cur.semanticCategory,
                        nodeKind: cur.nodeKind,
                        comparisonConfidence: .unknownMatch
                    ))
                } else {
                    items.append(matchedItem(previous: prev, current: cur))
                }
            } else {
                // Do not match by displayName / size alone.
                items.append(StorageChangeItem(
                    identity: id,
                    displayName: cur.displayName,
                    previousBytes: nil,
                    currentBytes: cur.bytes,
                    deltaBytes: cur.bytes,
                    changeKind: .new,
                    semanticCategory: cur.semanticCategory,
                    nodeKind: cur.nodeKind,
                    comparisonConfidence: .new
                ))
            }
        }

        for (id, prev) in prevByID where !usedPrev.contains(id) {
            items.append(StorageChangeItem(
                identity: id,
                displayName: prev.displayName,
                previousBytes: prev.bytes,
                currentBytes: nil,
                deltaBytes: prev.bytes.map { -$0 },
                changeKind: .removed,
                semanticCategory: prev.semanticCategory,
                nodeKind: prev.nodeKind,
                comparisonConfidence: .removed
            ))
        }
        return items
    }

    private static func matchedItem(
        previous: HistoryNodeSummary,
        current: HistoryNodeSummary
    ) -> StorageChangeItem {
        guard previous.bytesKnown, current.bytesKnown,
              let pb = previous.bytes, let cb = current.bytes else {
            return StorageChangeItem(
                identity: current.stableIdentity,
                displayName: current.displayName,
                previousBytes: previous.bytes,
                currentBytes: current.bytes,
                deltaBytes: nil,
                changeKind: .unknownMatch,
                semanticCategory: current.semanticCategory,
                nodeKind: current.nodeKind,
                comparisonConfidence: .unknownMatch
            )
        }
        let delta = signedDelta(previous: pb, current: cb)
        let kind: StorageChangeKind
        if delta > 0 { kind = .grew }
        else if delta < 0 { kind = .shrank }
        else { kind = .unchanged }
        return StorageChangeItem(
            identity: current.stableIdentity,
            displayName: current.displayName,
            previousBytes: pb,
            currentBytes: cb,
            deltaBytes: delta,
            changeKind: kind,
            semanticCategory: current.semanticCategory,
            nodeKind: current.nodeKind,
            comparisonConfidence: .matched
        )
    }

    private static func categoryDeltas(
        previous: StorageHistorySnapshot,
        current: StorageHistorySnapshot
    ) -> [StorageCategoryDelta] {
        let prev = Dictionary(previous.semanticCategoryTotals.map { ($0.category, $0.bytes) }, uniquingKeysWith: { first, _ in first })
        let cur = Dictionary(current.semanticCategoryTotals.map { ($0.category, $0.bytes) }, uniquingKeysWith: { first, _ in first })
        let keys = Set(prev.keys).union(cur.keys)
        return keys.map { key in
            let p = prev[key] ?? 0
            let c = cur[key] ?? 0
            return StorageCategoryDelta(
                category: key,
                previousBytes: p,
                currentBytes: c,
                deltaBytes: signedDelta(previous: p, current: c)
            )
        }
        .sorted { abs($0.deltaBytes) > abs($1.deltaBytes) }
    }

    private static func correlateActions(
        previous: StorageHistorySnapshot,
        current: StorageHistorySnapshot,
        changes: [StorageChangeItem]
    ) -> [StorageVerifiedActionCorrelation] {
        _ = previous
        var out: [StorageVerifiedActionCorrelation] = []
        for action in current.actionStateSummaries {
            guard action.logicalActionCompleted == true else { continue }
            let entityKey = "entity:" + action.entityID
            guard let change = changes.first(where: {
                $0.identity == entityKey || $0.identity.contains(action.entityID)
            }) else { continue }
            // Exact identity correlation — entity match + shrink evidence.
            // Timestamp proximity alone is insufficient (P3.2A.6).
            guard change.changeKind == .shrank || change.changeKind == .removed else { continue }
            let recovered = action.verifiedRecoveredBytes.map { VerifiedActionResultBuilder.byteLabel($0) }
            let note: String
            if let recovered, let permit = action.permitID {
                note = "\(recovered) was removed by your verified cleanup (permit \(permit.suffix(8)))."
            } else if let recovered {
                note = "\(recovered) was removed by your verified action for this entity."
            } else {
                note = "Verified action correlates with observed decrease for the same entity identity."
            }
            out.append(StorageVerifiedActionCorrelation(
                actionID: action.actionID,
                entityID: action.entityID,
                relatedChangeIdentity: change.identity,
                note: note
            ))
        }
        return out
    }

    private static func correlateRegeneration(
        previous: StorageHistorySnapshot,
        current: StorageHistorySnapshot
    ) -> [StorageRegenerationCorrelation] {
        let prevEntities = Set(previous.selectedEntitySummaries.map(\.entityID))
        var out: [StorageRegenerationCorrelation] = []
        for action in current.actionStateSummaries where action.verificationState?.uppercased().contains("REGENERATED") == true {
            // Successor entities present now that were not previous.
            for entity in current.selectedEntitySummaries where !prevEntities.contains(entity.entityID) {
                if entity.entityID.contains("deriveddata") || entity.displayName.lowercased().contains("derived") {
                    out.append(StorageRegenerationCorrelation(
                        previousEntityID: action.entityID,
                        successorEntityID: entity.entityID,
                        successorBytes: entity.bytes,
                        note: "Semantic successor observed after verified cleanup; not treated as failed cleanup."
                    ))
                }
            }
        }
        // Also: readiness regenerated marker on action summaries
        for action in current.actionStateSummaries where action.verificationState == UIReadinessState.regenerated.rawValue {
            out.append(StorageRegenerationCorrelation(
                previousEntityID: action.entityID,
                successorEntityID: action.entityID + "#successor",
                note: "Action history reports regenerated state."
            ))
        }
        return out
    }

    private static func elapsedMs(since: Date) -> Int {
        Int(Date().timeIntervalSince(since) * 1000)
    }
}
