import XCTest
@testable import SafetyCore

final class P18DetectorCatalogProfilingTests: XCTestCase {
    func makeHome() throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("p18-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        return home
    }

    func write(_ path: String, _ body: String = "x") throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: URL(fileURLWithPath: path))
    }

    // MARK: Cache reuse

    func testRepeatedDirectoryMeasurementUsesCache() {
        DirectorySizeCache.reset()
        ScannedNodeCache.reset()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p18-du-\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? Data("a".utf8).write(to: URL(fileURLWithPath: "\(dir)/a.txt"))
        _ = DirectorySizeCache.bytes(at: dir)
        _ = DirectorySizeCache.bytes(at: dir)
        let stats = DirectorySizeCache.stats()
        XCTAssertGreaterThanOrEqual(stats.hits, 1)
    }

    func testScannedNodeCacheReusesSamePath() {
        DirectorySizeCache.reset()
        ScannedNodeCache.reset()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p18-scan-\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let scanner = ReadOnlyStorageScanner()
        _ = ScannedNodeCache.getOrScan(path: dir, scanner: scanner)
        _ = ScannedNodeCache.getOrScan(path: dir, scanner: scanner)
        let stats = ScannedNodeCache.stats()
        XCTAssertGreaterThanOrEqual(stats.hits, 1)
    }

    func testMetadataCacheReusesExistence() {
        SharedMetadataCache.reset()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p18-meta-\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        _ = SharedMetadataCache.pathExists(dir)
        _ = SharedMetadataCache.pathExists(dir)
        let stats = SharedMetadataCache.stats()
        XCTAssertGreaterThanOrEqual(stats.hits, 1)
    }

    // MARK: Detector catalog telemetry

    func testDetectorCatalogProducesRuntimeReport() throws {
        let home = try makeHome()
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Caches", withIntermediateDirectories: true)
        let tel = DetectorCatalogTelemetry()
        let catalog = DetectorCatalog(detectors: [MacOSDetector()], proofTargets: [])
        _ = catalog.detectAll(home: home, scanner: ReadOnlyStorageScanner(), telemetry: tel)
        let report = DetectorCatalog.lastCatalogTelemetry
        XCTAssertNotNil(report)
        XCTAssertFalse(report?.perDetector.isEmpty ?? true)
        XCTAssertFalse(report?.stages.isEmpty ?? true)
    }

    func testNodeModulesProofNotInDefaultCatalog() {
        let catalog = DetectorCatalog(proofTargets: ["derived-data"])
        let ids = catalog.detectors.map(\.detectorID)
        XCTAssertFalse(ids.contains("NodeModulesProofDetector"))
    }

    func testNodeModulesProofOptInOnly() {
        let catalog = DetectorCatalog(proofTargets: ["derived-data", "node-modules"])
        let ids = catalog.detectors.map(\.detectorID)
        XCTAssertTrue(ids.contains("NodeModulesProofDetector"))
    }

    // MARK: Cursor honest relationships

    func testSnapshotStoreHasAssociatedStoreVerifiedNotFakeWorkspace() throws {
        let home = try makeHome()
        let storeID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        let store = "\(home)/Library/Application Support/Cursor/snapshots/stores/\(storeID)"
        try FileManager.default.createDirectory(atPath: "\(store)/objects", withIntermediateDirectories: true)
        try write("\(store)/baseline.marker", "root_key=\(storeID)\n")
        try write("\(store)/objects/o")
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/User/workspaceStorage", withIntermediateDirectories: true)
        DetectorCatalog.sharedCursorIndex = nil
        let found = CursorStoresVerificationDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let linked = found.first { $0.entity.id == "cursor.snapshots.store.\(storeID)" }
        let rels = linked?.annotation?.relationships ?? []
        let storeRel = rels.first { $0.type == .associatedWithCursorStore }
        let wsRel = rels.first { $0.type == .belongsToWorkspace }
        XCTAssertEqual(storeRel?.confidence, .verified)
        XCTAssertNotEqual(wsRel?.confidence, .verified)
    }

    func testBasenameRootRefUsesPossibleWorkspaceNotVerifiedBelongs() throws {
        let home = try makeHome()
        try FileManager.default.createDirectory(atPath: "\(home)/Workspace/demo-proj", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/roots/demo-proj-abcdef", withIntermediateDirectories: true)
        try write("\(home)/Library/Application Support/Cursor/snapshots/roots/demo-proj-abcdef/r")
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)
        DetectorCatalog.sharedCursorIndex = nil
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let ref = found.first { $0.entity.id.contains("rootref") }
        let ws = ref?.annotation?.relationships.first { $0.type == .belongsToWorkspace }
        let possible = ref?.annotation?.relationships.first { $0.type == .possibleWorkspaceContext }
        XCTAssertNotEqual(ws?.confidence, .verified)
        XCTAssertEqual(possible?.confidence, .inferred)
    }

    func testSharedCursorIndexBuiltOncePerCatalogRun() throws {
        let home = try makeHome()
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)
        DetectorCatalog.sharedCursorIndex = nil
        let catalog = DetectorCatalog(proofTargets: [])
        _ = catalog.detectAll(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertNotNil(DetectorCatalog.sharedCursorIndex)
    }

    func testDetectorTiersPresent() {
        let catalog = DetectorCatalog(proofTargets: ["derived-data"])
        XCTAssertTrue(catalog.detectors.contains { $0.detectorID == "GitDetector" && $0.tier == .should })
        XCTAssertTrue(catalog.detectors.contains { $0.detectorID == "ChromeAppSupportDetector" && $0.tier == .should })
        XCTAssertTrue(catalog.detectors.contains { $0.detectorID == "XcodeDerivedDataProofDetector" && $0.tier == .optInProof })
    }

    func testTimeoutObservationStaysUnknownNotInactiveVerified() {
        let handles = OpenFileSnapshot(openPaths: [], snapshotFailed: true, failureReason: "LSOF_TIMEOUT", completeness: .partial)
        let procs = ProcessTableSnapshot(names: [], commandLines: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let (state, conf, comp, _) = ActiveStateResolver.resolve(
            entityPath: "/tmp/x.bundle/rootfs.img",
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: handles,
            processCompleteness: .complete,
            handleCompleteness: .partial
        )
        XCTAssertEqual(state, .unknown)
        XCTAssertNotEqual(conf, .verified)
        XCTAssertNotEqual(comp, .complete)
    }
}
