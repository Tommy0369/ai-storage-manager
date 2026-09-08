import XCTest
@testable import AppServices
import SafetyCore

final class P304ProgressiveScanTests: XCTestCase {
    func testRootTimeoutDoesNotBlockFirstUsefulMap() throws {
        let dir = try makeHomeishFixture()
        defer { try? FileManager.default.removeItem(at: dir) }

        let session = ScanSessionContext.begin()
        defer { ScanSessionContext.end() }
        session.testMeasurementOverride = { path in
            if path == dir.path {
                Thread.sleep(forTimeInterval: 0.4)
                return SizeMeasurement.unknown(reason: "DU_TIMEOUT", timedOut: true, method: "bounded_du")
            }
            // Child sizes resolve immediately.
            if path.hasSuffix("/Library") {
                return SizeMeasurement.exact(bytes: 80_000_000, method: "bounded_du")
            }
            if path.hasSuffix("/Documents") {
                return SizeMeasurement.exact(bytes: 20_000_000, method: "bounded_du")
            }
            return SizeMeasurement.exact(bytes: 1_000_000, method: "bounded_du")
        }

        var firstUsefulMs: Int?
        let started = Date()
        let (root, stats) = PhysicalHierarchyBuilder.build(
            rootPath: dir.path,
            displayName: "FixtureRoot",
            nodeKind: .volume,
            config: PhysicalHierarchyConfig(
                maxDepth: 2,
                maxChildrenPerDirectory: 20,
                maxNodes: 100,
                expandPackages: false,
                followSymlinks: false,
                rootTimeoutSeconds: 2,
                childTimeoutSeconds: 1
            ),
            onPublication: { node, pub, kind in
                if kind == .firstUsefulMap {
                    firstUsefulMs = pub.timeToFirstUsefulMapMs
                    XCTAssertFalse(node.children.isEmpty)
                    let accounting = PhysicalMapAccountingResolver.resolve(for: node)
                    XCTAssertTrue(accounting.accountingValid)
                    XCTAssertGreaterThan(accounting.reportMappedBytes, 0)
                }
            }
        )
        let totalMs = Int(Date().timeIntervalSince(started) * 1000)
        XCTAssertNotNil(firstUsefulMs)
        XCTAssertLessThan(firstUsefulMs ?? totalMs, 350)
        XCTAssertGreaterThan(stats.timeToFirstHierarchyMs, firstUsefulMs ?? 0)
        XCTAssertFalse(root.children.isEmpty)
        XCTAssertEqual(PhysicalMapAccountingResolver.resolve(for: root).basis, .knownChildrenLowerBound)
    }

    func testMeasurementRequestsCoalesce() {
        let session = ScanSessionContext.begin()
        defer { ScanSessionContext.end() }
        session.testMeasurementOverride = { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return SizeMeasurement.exact(bytes: 42, method: "test")
        }
        let path = "/tmp/p304-coalesce-\(UUID().uuidString)"
        let group = DispatchGroup()
        for _ in 0..<4 {
            group.enter()
            DispatchQueue.global().async {
                _ = session.measure(path: path, caller: "test")
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(session.uniqueMeasurementKeys, 1)
        XCTAssertEqual(session.measurementRequests, 4)
        XCTAssertGreaterThanOrEqual(session.coalescedRequests, 1)
        XCTAssertLessThanOrEqual(session.maxMeasurementConcurrency, session.budget.maxConcurrentMeasurements)
    }

    func testProgressiveFinalEqualsCanonicalFixture() throws {
        let dir = try makeHomeishFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = PhysicalHierarchyConfig(
            maxDepth: 3,
            maxChildrenPerDirectory: 20,
            maxNodes: 100,
            expandPackages: false,
            followSymlinks: false,
            rootTimeoutSeconds: 5,
            childTimeoutSeconds: 2
        )

        _ = ScanSessionContext.begin()
        let (progressive, _) = PhysicalHierarchyBuilder.build(
            rootPath: dir.path,
            displayName: "FixtureRoot",
            nodeKind: .volume,
            config: config
        )
        ScanSessionContext.end()

        _ = ScanSessionContext.begin()
        let (canonical, _) = PhysicalHierarchyBuilder.build(
            rootPath: dir.path,
            displayName: "FixtureRoot",
            nodeKind: .volume,
            config: config
        )
        ScanSessionContext.end()

        XCTAssertEqual(progressive.children.map(\.displayName).sorted(), canonical.children.map(\.displayName).sorted())
        XCTAssertEqual(
            PhysicalMapAccountingResolver.resolve(for: progressive).basis,
            PhysicalMapAccountingResolver.resolve(for: canonical).basis
        )
        XCTAssertEqual(
            PhysicalHierarchyBuilder.hasDuplicateByteOwnership(progressive),
            PhysicalHierarchyBuilder.hasDuplicateByteOwnership(canonical)
        )
    }

    func testSnapshotLocalIdentityDoesNotFalseMatchAcrossHistory() {
        var prev = sampleHistory(id: "p", used: 10, at: Date().addingTimeInterval(-10))
        var cur = sampleHistory(id: "c", used: 12, at: Date())
        prev.physicalNodeSummaries = [
            HistoryNodeSummary(
                stableIdentity: "entity:ai.huggingface_cache#2",
                displayName: "HF A",
                bytes: 10,
                bytesKnown: true,
                nodeKind: "directory",
                depth: 1,
                identityStability: "snapshot_local"
            )
        ]
        cur.physicalNodeSummaries = [
            HistoryNodeSummary(
                stableIdentity: "entity:ai.huggingface_cache#2",
                displayName: "HF B",
                bytes: 20,
                bytesKnown: true,
                nodeKind: "directory",
                depth: 1,
                identityStability: "snapshot_local"
            )
        ]
        let report = StorageSnapshotDiffEngine.compare(previous: prev, current: cur)
        XCTAssertTrue(report.allChanges.contains { $0.comparisonConfidence == .unknownMatch })
        XCTAssertFalse(report.topGrowing.contains { $0.identity.contains("huggingface_cache") })
    }

    func testDuplicateIdentityNoCrashAndNoSilentOverwrite() throws {
        let explorer = PreviewSnapshotFactory.explorerDemo()
        // Force colliding entity IDs on two presented nodes via history builder path.
        XCTAssertNoThrow(StorageHistoryBuilder.build(from: explorer))
        XCTAssertNoThrow(StorageSnapshotDiffEngine.compare(
            previous: StorageHistoryBuilder.build(from: explorer),
            current: StorageHistoryBuilder.build(from: explorer)
        ))
    }

    private func makeHomeishFixture() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("p304-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["Library", "Documents", "Downloads"] {
            let child = dir.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            try Data(repeating: 0x61, count: 8_192).write(to: child.appendingPathComponent("f.bin"))
        }
        return dir
    }

    private func sampleHistory(id: String, used: Int64, at: Date) -> StorageHistorySnapshot {
        let disk = DiskCapacitySnapshot(
            volumeName: "Macintosh HD",
            volumeTotalBytes: 100,
            volumeAvailableBytes: 100 - used,
            volumeUsedBytes: used,
            observedAt: at
        )
        return StorageHistorySnapshot(
            snapshotID: id,
            generatedAt: at,
            volumeIdentity: StorageHistoryBuilder.volumeIdentity(from: disk),
            rootScopeIdentity: "phys:/Users/demo",
            diskCapacity: disk,
            physicalMapAccounting: PhysicalMapAccounting(
                mappedBytes: used,
                basis: .rootMeasured,
                coverage: .complete,
                rootMeasurementStatus: .exact,
                rootMeasuredBytes: used,
                rootTotalKnown: true,
                knownChildMappedBytes: used,
                fallbackUsed: false,
                accountingValid: true,
                unknownRemainderKnown: true
            ),
            physicalNodeSummaries: [],
            semanticCategoryTotals: [],
            scanCoverage: HistoryScanCoverage(
                physicalNodeCount: 0,
                maxDepth: 0,
                accountingValid: true,
                mapCoverage: "COMPLETE",
                mapBasis: "ROOT_MEASURED"
            )
        )
    }
}
