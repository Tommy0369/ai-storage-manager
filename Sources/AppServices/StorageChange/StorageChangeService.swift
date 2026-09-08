import Foundation
import SafetyCore

/// Orchestrates history persist + diff from existing explorer output. No filesystem crawl.
public enum StorageChangeService {
    public static func recordAndDiff(
        explorer: StorageExplorerSnapshot,
        store: StorageHistoryStore,
        actionHistory: [UIActionHistoryItem] = [],
        entitySummaries: [HistoryEntitySummary] = [],
        window: StorageSnapshotDiffEngine.ComparisonWindow = .sinceLastScan,
        falseGREEN: Int = 0,
        duplicateEvaluations: Int = 0
    ) -> (history: StorageHistorySnapshot, report: StorageChangeReport, writeSuccess: Bool, status: P302HistoryStatusReport) {
        let serializeStarted = Date()
        let history = StorageHistoryBuilder.build(
            from: explorer,
            actionHistory: actionHistory,
            entitySummaries: entitySummaries
        )
        let serializeMs = Int(Date().timeIntervalSince(serializeStarted) * 1000)

        let loadStarted = Date()
        let previous: StorageHistorySnapshot?
        switch window {
        case .sinceLastScan:
            previous = store.newest()
        default:
            previous = StorageSnapshotDiffEngine.selectSnapshot(in: store, window: window)
        }
        // When recording current, "since last scan" previous is newest BEFORE save.
        let loadMs = Int(Date().timeIntervalSince(loadStarted) * 1000)

        let writeSuccess = store.saveSoft(history)
        var report = StorageSnapshotDiffEngine.compare(
            previous: previous,
            current: history,
            window: window.rawValue,
            falseGREEN: falseGREEN,
            duplicateEvaluations: duplicateEvaluations
        )
        report.snapshotSerializationMs = serializeMs
        report.historyLoadMs = loadMs
        let status = store.status(writeSuccess: writeSuccess)
        return (history, report, writeSuccess, status)
    }

    public static func demoChangeReport() -> StorageChangeReport {
        let prevDisk = DiskCapacitySnapshot(
            volumeName: "Macintosh HD",
            volumeTotalBytes: 494_000_000_000,
            volumeAvailableBytes: 146_900_000_000,
            volumeUsedBytes: 347_100_000_000
        )
        let curDisk = DiskCapacitySnapshot(
            volumeName: "Macintosh HD",
            volumeTotalBytes: 494_000_000_000,
            volumeAvailableBytes: 128_500_000_000,
            volumeUsedBytes: 365_500_000_000
        )
        let accountingPrev = PhysicalMapAccounting(
            mappedBytes: 120_000_000_000,
            basis: .rootMeasured,
            coverage: .complete,
            rootMeasurementStatus: .exact,
            rootMeasuredBytes: 120_000_000_000,
            rootTotalKnown: true,
            knownChildMappedBytes: 118_000_000_000,
            fallbackUsed: false,
            accountingValid: true,
            unknownRemainderKnown: true
        )
        let accountingCur = PhysicalMapAccounting(
            mappedBytes: 135_000_000_000,
            basis: .rootMeasured,
            coverage: .complete,
            rootMeasurementStatus: .exact,
            rootMeasuredBytes: 135_000_000_000,
            rootTotalKnown: true,
            knownChildMappedBytes: 133_000_000_000,
            fallbackUsed: false,
            accountingValid: true,
            unknownRemainderKnown: true
        )
        let previous = StorageHistorySnapshot(
            snapshotID: "hist-prev",
            generatedAt: Date().addingTimeInterval(-7 * 24 * 3600),
            volumeIdentity: StorageHistoryBuilder.volumeIdentity(from: prevDisk),
            rootScopeIdentity: "phys:/Users/demo",
            diskCapacity: prevDisk,
            physicalMapAccounting: accountingPrev,
            physicalNodeSummaries: [
                HistoryNodeSummary(stableIdentity: "phys:/ollama", displayName: L10n.t("entity.ollamaModels.title"), bytes: 40_500_000_000, bytesKnown: true, nodeKind: "directory", semanticCategory: ProductStorageCategory.aiTools.rawValue, depth: 1),
                HistoryNodeSummary(stableIdentity: "phys:/downloads", displayName: "Downloads", bytes: 10_000_000_000, bytesKnown: true, nodeKind: "directory", semanticCategory: ProductStorageCategory.personalFiles.rawValue, depth: 1),
                HistoryNodeSummary(stableIdentity: "phys:/xcode", displayName: "Xcode", bytes: 20_000_000_000, bytesKnown: true, nodeKind: "directory", semanticCategory: ProductStorageCategory.developer.rawValue, depth: 1),
                HistoryNodeSummary(stableIdentity: "phys:/derived", displayName: "DerivedData", bytes: 8_000_000_000, bytesKnown: true, nodeKind: "directory", semanticCategory: ProductStorageCategory.developer.rawValue, depth: 2)
            ],
            semanticCategoryTotals: [
                HistoryCategoryTotal(category: ProductStorageCategory.aiTools.rawValue, bytes: 40_500_000_000),
                HistoryCategoryTotal(category: ProductStorageCategory.personalFiles.rawValue, bytes: 10_000_000_000),
                HistoryCategoryTotal(category: ProductStorageCategory.developer.rawValue, bytes: 28_000_000_000)
            ],
            scanCoverage: HistoryScanCoverage(physicalNodeCount: 4, maxDepth: 2, accountingValid: true, mapCoverage: "COMPLETE", mapBasis: "ROOT_MEASURED")
        )
        let current = StorageHistorySnapshot(
            snapshotID: "hist-cur",
            generatedAt: Date(),
            volumeIdentity: previous.volumeIdentity,
            rootScopeIdentity: previous.rootScopeIdentity,
            diskCapacity: curDisk,
            physicalMapAccounting: accountingCur,
            physicalNodeSummaries: [
                HistoryNodeSummary(stableIdentity: "phys:/ollama", displayName: L10n.t("entity.ollamaModels.title"), bytes: 48_600_000_000, bytesKnown: true, nodeKind: "directory", semanticCategory: ProductStorageCategory.aiTools.rawValue, depth: 1),
                HistoryNodeSummary(stableIdentity: "phys:/downloads", displayName: "Downloads", bytes: 14_200_000_000, bytesKnown: true, nodeKind: "directory", semanticCategory: ProductStorageCategory.personalFiles.rawValue, depth: 1),
                HistoryNodeSummary(stableIdentity: "phys:/xcode", displayName: "Xcode", bytes: 22_700_000_000, bytesKnown: true, nodeKind: "directory", semanticCategory: ProductStorageCategory.developer.rawValue, depth: 1),
                HistoryNodeSummary(stableIdentity: "phys:/derived", displayName: "DerivedData", bytes: 4_600_000_000, bytesKnown: true, nodeKind: "directory", semanticCategory: ProductStorageCategory.developer.rawValue, depth: 2),
                HistoryNodeSummary(stableIdentity: "phys:/movie", displayName: "movie.mov", bytes: 8_400_000_000, bytesKnown: true, nodeKind: "file", semanticCategory: ProductStorageCategory.personalFiles.rawValue, depth: 1)
            ],
            semanticCategoryTotals: [
                HistoryCategoryTotal(category: ProductStorageCategory.aiTools.rawValue, bytes: 48_600_000_000),
                HistoryCategoryTotal(category: ProductStorageCategory.personalFiles.rawValue, bytes: 22_600_000_000),
                HistoryCategoryTotal(category: ProductStorageCategory.developer.rawValue, bytes: 27_300_000_000)
            ],
            actionStateSummaries: [
                HistoryActionSummary(
                    actionID: "act-1",
                    entityID: "xcode.deriveddata.old",
                    action: StorageAction.moveToTrash.rawValue,
                    auditStatus: "POST_VERIFIED",
                    verificationState: UIReadinessState.completed.rawValue,
                    executedAt: Date().addingTimeInterval(-3 * 24 * 3600),
                    logicalActionCompleted: true
                )
            ],
            scanCoverage: HistoryScanCoverage(physicalNodeCount: 5, maxDepth: 2, accountingValid: true, mapCoverage: "COMPLETE", mapBasis: "ROOT_MEASURED")
        )
        return StorageSnapshotDiffEngine.compare(previous: previous, current: current, window: "7d")
    }
}
