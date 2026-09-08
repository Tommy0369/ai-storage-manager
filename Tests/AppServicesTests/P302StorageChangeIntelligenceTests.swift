import XCTest
@testable import AppServices
import SafetyCore

final class P302StorageChangeIntelligenceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.setOverride(.english)
    }

    override func tearDown() {
        L10n.setOverride(.english)
        super.tearDown()
    }

    func testHistoryStoreFirstAndSecondSnapshotWithRetention() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p302-hist-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StorageHistoryStore(directory: dir, retentionLimit: 3, locationType: "temp")
        let a = sampleHistory(id: "a", used: 100, mapped: 80, at: Date().addingTimeInterval(-100))
        let b = sampleHistory(id: "b", used: 110, mapped: 90, at: Date().addingTimeInterval(-50))
        try store.save(a)
        try store.save(b)
        XCTAssertEqual(store.loadAll().count, 2)
        try store.save(sampleHistory(id: "c", used: 120, mapped: 95, at: Date().addingTimeInterval(-20)))
        try store.save(sampleHistory(id: "d", used: 125, mapped: 96, at: Date()))
        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(Set(loaded.map(\.snapshotID)), Set(["b", "c", "d"]))
        // Soft retention: oldest logical snapshot falls out of the exposed window.
        XCTAssertFalse(loaded.contains { $0.snapshotID == "a" })
    }

    func testCorruptAndUnsupportedSchemaIgnoredSafely() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p302-bad-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: dir.appendingPathComponent("bad.json"))
        var unsupported = sampleHistory(id: "old", used: 1, mapped: 1, at: Date())
        unsupported.schemaVersion = 99
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(unsupported).write(to: dir.appendingPathComponent("old.json"))
        let store = StorageHistoryStore(directory: dir, locationType: "temp")
        XCTAssertEqual(store.loadAll().count, 0)
        XCTAssertThrowsError(try store.load(id: "old")) { error in
            XCTAssertEqual(error as? StorageHistoryStoreError, .unsupportedSchema(99))
        }
    }

    func testWriteFailureDoesNotAlterSafetyFlags() {
        let explorer = PreviewSnapshotFactory.explorerDemo()
        // Read-only path should soft-fail.
        let store = StorageHistoryStore(
            directory: URL(fileURLWithPath: "/priv/root/no-write-\(UUID().uuidString)"),
            locationType: "temp"
        )
        let result = StorageChangeService.recordAndDiff(
            explorer: explorer,
            store: store,
            falseGREEN: 0,
            duplicateEvaluations: 0
        )
        XCTAssertFalse(result.writeSuccess)
        XCTAssertEqual(result.report.falseGREEN, 0)
        XCTAssertEqual(result.report.duplicateEvaluations, 0)
        XCTAssertEqual(result.report.comparisonQuality, .noComparisonYet)
    }

    func testDiffGrowthShrinkNewRemovedSignedArithmetic() {
        let report = StorageChangeService.demoChangeReport()
        XCTAssertEqual(report.comparisonQuality, .fullyComparable)
        XCTAssertEqual(report.diskUsedDelta, 18_400_000_000)
        XCTAssertEqual(report.diskFreeDelta, -18_400_000_000)
        XCTAssertGreaterThan(report.identifiedGrowthBytes, 0)
        XCTAssertEqual(report.topGrowing.first?.displayName, "Ollama Models")
        XCTAssertEqual(report.topGrowing.first?.deltaBytes, 8_100_000_000)
        XCTAssertEqual(report.topShrinking.first?.displayName, "DerivedData")
        XCTAssertEqual(report.topShrinking.first?.deltaBytes, -3_400_000_000)
        XCTAssertTrue(report.newLargeItems.contains { $0.displayName == "movie.mov" })
        // Signed: 10→15 = +5, never UInt underflow
        XCTAssertEqual(StorageSnapshotDiffEngine.signedDelta(previous: 10, current: 15), 5)
        XCTAssertEqual(StorageSnapshotDiffEngine.signedDelta(previous: 15, current: 10), -5)
    }

    func testSameDisplayNameDifferentIdentityDoesNotMatch() {
        let prev = sampleHistory(
            id: "p",
            used: 100,
            mapped: 50,
            at: Date().addingTimeInterval(-10),
            nodes: [
                HistoryNodeSummary(stableIdentity: "id:a", displayName: "Cache", bytes: 10, bytesKnown: true, nodeKind: "directory", depth: 1)
            ]
        )
        let cur = sampleHistory(
            id: "c",
            used: 110,
            mapped: 60,
            at: Date(),
            nodes: [
                HistoryNodeSummary(stableIdentity: "id:b", displayName: "Cache", bytes: 12, bytesKnown: true, nodeKind: "directory", depth: 1)
            ]
        )
        let report = StorageSnapshotDiffEngine.compare(previous: prev, current: cur)
        XCTAssertTrue(report.newLargeItems.contains { $0.identity == "id:b" })
        XCTAssertTrue(report.removedLargeItems.contains { $0.identity == "id:a" })
        XCTAssertFalse(report.allChanges.contains { $0.changeKind == .grew && $0.displayName == "Cache" && $0.comparisonConfidence == .matched })
    }

    func testUnknownMatchRemainsUnknown() {
        let prev = sampleHistory(
            id: "p", used: 100, mapped: 50, at: Date().addingTimeInterval(-10),
            nodes: [HistoryNodeSummary(stableIdentity: "n1", displayName: "X", bytes: nil, bytesKnown: false, nodeKind: "directory", depth: 1)]
        )
        let cur = sampleHistory(
            id: "c", used: 100, mapped: 50, at: Date(),
            nodes: [HistoryNodeSummary(stableIdentity: "n1", displayName: "X", bytes: 20, bytesKnown: true, nodeKind: "directory", depth: 1)]
        )
        let report = StorageSnapshotDiffEngine.compare(previous: prev, current: cur)
        XCTAssertTrue(report.allChanges.contains { $0.changeKind == .unknownMatch })
        XCTAssertFalse(report.topGrowing.contains { $0.identity == "n1" })
    }

    func testComparabilityCompletePartialAndVolumeMismatch() {
        var completeA = sampleHistory(id: "a", used: 100, mapped: 80, at: Date().addingTimeInterval(-10))
        completeA.physicalMapAccounting = measuredAccounting(80)
        var completeB = sampleHistory(id: "b", used: 110, mapped: 90, at: Date())
        completeB.physicalMapAccounting = measuredAccounting(90)
        XCTAssertEqual(StorageSnapshotDiffEngine.comparability(previous: completeA, current: completeB), .fullyComparable)

        var partial = completeB
        partial.physicalMapAccounting = PhysicalMapAccounting(
            mappedBytes: 50,
            basis: .knownChildrenLowerBound,
            coverage: .partial,
            rootMeasurementStatus: .timeout,
            rootMeasuredBytes: nil,
            rootTotalKnown: false,
            knownChildMappedBytes: 50,
            fallbackUsed: true,
            accountingValid: true,
            unknownRemainderKnown: false
        )
        let partialReport = StorageSnapshotDiffEngine.compare(previous: completeA, current: partial)
        XCTAssertEqual(partialReport.comparisonQuality, .partiallyComparable)
        XCTAssertNil(partialReport.mappedDelta)
        XCTAssertTrue(partialReport.explanation.usesLowerBoundLanguage)

        var otherVolume = completeB
        otherVolume.volumeIdentity = "Other#1"
        XCTAssertEqual(
            StorageSnapshotDiffEngine.comparability(previous: completeA, current: otherVolume),
            .notComparable
        )
    }

    func testFirstRunProducesNoTrend() {
        let cur = sampleHistory(id: "only", used: 100, mapped: 80, at: Date())
        let report = StorageSnapshotDiffEngine.compare(previous: nil, current: cur)
        XCTAssertEqual(report.comparisonQuality, .noComparisonYet)
        XCTAssertTrue(report.explanation.firstRun)
        XCTAssertNil(report.diskUsedDelta)
        XCTAssertTrue(report.topGrowing.isEmpty)
    }

    func testExplanationIdentifiedAndUnexplained() {
        let report = StorageChangeService.demoChangeReport()
        XCTAssertFalse(report.explanation.firstRun)
        XCTAssertGreaterThan(report.identifiedGrowthBytes, 0)
        XCTAssertNotNil(report.unexplainedDeltaBytes)
        XCTAssertTrue(report.explanation.bodyLines.contains { $0.lowercased().contains("growth alone") })
    }

    func testActionCorrelationRequiresIdentityNotTimestamp() {
        var prev = sampleHistory(id: "p", used: 100, mapped: 80, at: Date().addingTimeInterval(-100))
        var cur = sampleHistory(id: "c", used: 90, mapped: 70, at: Date())
        cur.physicalNodeSummaries = [
            HistoryNodeSummary(
                stableIdentity: "entity:xcode.deriveddata.old",
                displayName: "DerivedData",
                bytes: 1_000_000_000,
                bytesKnown: true,
                nodeKind: "directory",
                depth: 1
            )
        ]
        prev.physicalNodeSummaries = [
            HistoryNodeSummary(
                stableIdentity: "entity:xcode.deriveddata.old",
                displayName: "DerivedData",
                bytes: 5_000_000_000,
                bytesKnown: true,
                nodeKind: "directory",
                depth: 1
            )
        ]
        cur.actionStateSummaries = [
            HistoryActionSummary(
                actionID: "act",
                entityID: "xcode.deriveddata.old",
                action: StorageAction.moveToTrash.rawValue,
                auditStatus: "POST_VERIFIED",
                verificationState: UIReadinessState.completed.rawValue,
                executedAt: Date(),
                logicalActionCompleted: true
            ),
            HistoryActionSummary(
                actionID: "near",
                entityID: "unrelated.entity",
                action: StorageAction.moveToTrash.rawValue,
                auditStatus: "POST_VERIFIED",
                verificationState: UIReadinessState.completed.rawValue,
                executedAt: Date(),
                logicalActionCompleted: true
            )
        ]
        let report = StorageSnapshotDiffEngine.compare(previous: prev, current: cur)
        XCTAssertTrue(report.relatedVerifiedActions.contains { $0.entityID == "xcode.deriveddata.old" })
        XCTAssertFalse(report.relatedVerifiedActions.contains { $0.entityID == "unrelated.entity" })
    }

    func testWindowSelectionUsesClosestAtOrBeforeWithoutInterpolation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p302-win-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StorageHistoryStore(directory: dir, locationType: "temp")
        let now = Date()
        try store.save(sampleHistory(id: "d10", used: 1, mapped: 1, at: now.addingTimeInterval(-10 * 24 * 3600)))
        try store.save(sampleHistory(id: "d5", used: 1, mapped: 1, at: now.addingTimeInterval(-5 * 24 * 3600)))
        try store.save(sampleHistory(id: "d1", used: 1, mapped: 1, at: now.addingTimeInterval(-1 * 24 * 3600)))
        let picked = StorageSnapshotDiffEngine.selectSnapshot(in: store, window: .days7, now: now)
        XCTAssertEqual(picked?.snapshotID, "d10")
    }

    func testHistoryBuiltFromExplorerWithoutSecondCrawl() {
        let explorer = PreviewSnapshotFactory.explorerDemo()
        let hist = StorageHistoryBuilder.build(from: explorer)
        XCTAssertEqual(hist.schemaVersion, storageHistorySchemaVersion)
        XCTAssertFalse(hist.physicalNodeSummaries.isEmpty)
        XCTAssertEqual(hist.physicalMapAccounting.basis, explorer.mapAccounting?.basis
                        ?? PhysicalMapAccountingResolver.resolve(for: explorer.physicalRoot).basis)
    }

    // MARK: - Helpers

    private func measuredAccounting(_ mapped: Int64) -> PhysicalMapAccounting {
        PhysicalMapAccounting(
            mappedBytes: mapped,
            basis: .rootMeasured,
            coverage: .complete,
            rootMeasurementStatus: .exact,
            rootMeasuredBytes: mapped,
            rootTotalKnown: true,
            knownChildMappedBytes: mapped,
            fallbackUsed: false,
            accountingValid: true,
            unknownRemainderKnown: true
        )
    }

    func testDuplicateStableIdentityDoesNotCrashDiff() {
        var prev = sampleHistory(id: "p", used: 10, mapped: 8, at: Date().addingTimeInterval(-10))
        var cur = sampleHistory(id: "c", used: 12, mapped: 9, at: Date())
        let dup = HistoryNodeSummary(
            stableIdentity: "entity:ai.huggingface_cache",
            displayName: "HF",
            bytes: 1,
            bytesKnown: true,
            nodeKind: "directory",
            depth: 1
        )
        cur.physicalNodeSummaries = [dup, dup]
        prev.physicalNodeSummaries = [dup]
        XCTAssertNoThrow(StorageSnapshotDiffEngine.compare(previous: prev, current: cur))
    }

    private func sampleHistory(
        id: String,
        used: Int64,
        mapped: Int64,
        at: Date,
        nodes: [HistoryNodeSummary] = []
    ) -> StorageHistorySnapshot {
        let disk = DiskCapacitySnapshot(
            volumeName: "Macintosh HD",
            volumeTotalBytes: 494_000_000_000,
            volumeAvailableBytes: 494_000_000_000 - used,
            volumeUsedBytes: used,
            observedAt: at
        )
        return StorageHistorySnapshot(
            snapshotID: id,
            generatedAt: at,
            volumeIdentity: StorageHistoryBuilder.volumeIdentity(from: disk),
            rootScopeIdentity: "phys:/Users/demo",
            diskCapacity: disk,
            physicalMapAccounting: measuredAccounting(mapped),
            physicalNodeSummaries: nodes,
            semanticCategoryTotals: [],
            scanCoverage: HistoryScanCoverage(
                physicalNodeCount: nodes.count,
                maxDepth: 1,
                accountingValid: true,
                mapCoverage: "COMPLETE",
                mapBasis: "ROOT_MEASURED"
            )
        )
    }
}
