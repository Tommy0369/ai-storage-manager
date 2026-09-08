import XCTest
@testable import SafetyCore

final class P202DerivedDataSurfaceTests: XCTestCase {
    private func makeHome() throws -> String {
        let dir = NSTemporaryDirectory() + "asm-p202-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func installRunnerFixture(home: String, name: String, workspacePath: String?, includeInfo: Bool) throws -> String {
        let dd = "\(home)/Library/Developer/Xcode/DerivedData/\(name)"
        try FileManager.default.createDirectory(atPath: "\(dd)/Build", withIntermediateDirectories: true)
        if includeInfo, let workspacePath {
            let plist: [String: Any] = ["WorkspacePath": workspacePath]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: "\(dd)/info.plist"))
        }
        return dd
    }

    func testConcreteChildSurfacesWithRootDistinct() throws {
        let home = try makeHome()
        let project = "\(home)/Fixtures/App.xcodeproj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        _ = try installRunnerFixture(home: home, name: "Runner-abc123", workspacePath: project, includeInfo: true)

        let catalog = DetectorCatalog(proofTargets: ["derived-data"])
        let detected = catalog.detectAll(home: home, scanner: ReadOnlyStorageScanner())
        let root = detected.first { $0.entity.id == "xcode.derived_data" }
        let child = detected.first { $0.entity.id == "xcode.deriveddata.Runner-abc123" }
        XCTAssertNotNil(root)
        XCTAssertNotNil(child)
        XCTAssertNotEqual(root?.entity.path, child?.entity.path)
    }

    func testMetadataAbsentStillSurfacesEntityWithUnknownProof() throws {
        let home = try makeHome()
        let dd = try installRunnerFixture(home: home, name: "NoInfo-xyz", workspacePath: nil, includeInfo: false)
        let found = XcodeDerivedDataProofDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.entity.path == dd })
        let hit = found.first { $0.entity.path == dd }!
        XCTAssertTrue(hit.annotation?.unknownReasons.contains(UnknownReasonCode.sourceRelationUnknown.rawValue) == true)
    }

    func testWorkspacePathExplicitProducesVerifiedRelationship() throws {
        let home = try makeHome()
        let project = "\(home)/Projects/Runner.xcodeproj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let dd = try installRunnerFixture(home: home, name: "Runner-p112like", workspacePath: project, includeInfo: true)
        let hit = XcodeDerivedDataProofDetector().detect(home: home, scanner: ReadOnlyStorageScanner()).first { $0.entity.path == dd }
        let rel = hit?.annotation?.relationships.first { $0.type == .derivedFrom }
        XCTAssertEqual(rel?.confidence, .verified)
        XCTAssertEqual(rel?.presence, .present)
    }

    func testMissingSourceBlocksVerifiedRelationship() throws {
        let home = try makeHome()
        let missing = "\(home)/Missing/Project.xcodeproj"
        let dd = try installRunnerFixture(home: home, name: "Runner-stale", workspacePath: missing, includeInfo: true)
        let hit = XcodeDerivedDataProofDetector().detect(home: home, scanner: ReadOnlyStorageScanner()).first { $0.entity.path == dd }
        let rel = hit?.annotation?.relationships.first { $0.type == .derivedFrom }
        XCTAssertEqual(rel?.confidence, .verified)
        XCTAssertEqual(rel?.presence, .missing)
    }

    func testSurfaceFunnelFilesystemToDetector() throws {
        let home = try makeHome()
        let project = "\(home)/ws/App.xcodeproj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        _ = try installRunnerFixture(home: home, name: "Runner-funnel", workspacePath: project, includeInfo: true)

        let catalog = DetectorCatalog(proofTargets: ["derived-data"])
        let detected = catalog.detectAll(home: home, scanner: ReadOnlyStorageScanner())
        let items = detected.map { entity -> ClassifiedItem in
            let decision = SafetyDecision(
                entity: entity.entity,
                action: .noAction,
                safetyClass: .unknown,
                safetyScore: SafetyScore(value: 50),
                reasonCodes: [],
                sideEffects: [],
                matchedRuleID: nil,
                evaluationLayer: .exactVendor,
                evidenceConfidence: 0.5,
                userExplanationJA: "test",
                growthCauses: [],
                requiresUserApproval: false,
                blockedBy: nil
            )
            return ClassifiedItem(
                detected: entity,
                decision: decision,
                semantic: SemanticResult(from: decision),
                allocatedBytes: entity.entity.logicalBytes,
                actionVariants: [:],
                inclusiveBytes: entity.entity.logicalBytes,
                exclusiveBytes: entity.entity.logicalBytes,
                resolution: .l4SemanticEntity
            )
        }
        let backlog = EntityVerificationBacklogReport(entries: [], totalCandidates: 0, attemptedCount: 0, blockedCount: 0)
        let result = DerivedDataSurfaceAnalyzer.analyze(
            home: home,
            items: items,
            proofTargets: ["derived-data"],
            catalogRuntime: DetectorCatalog.lastCatalogTelemetry,
            verificationBacklog: backlog
        )
        XCTAssertEqual(result.funnel.filesystemChildCount, 1)
        XCTAssertEqual(result.funnel.detectorMatchedCount, 1)
        XCTAssertEqual(result.funnel.entityEmittedCount, 1)
        XCTAssertEqual(result.registration.defaultScanIncludesDerivedDataProof, true)
        XCTAssertEqual(result.registration.entries.first { $0.detectorID == "XcodeDerivedDataProofDetector" }?.tier, "OPT_IN_PROOF")
    }

    func testRootCauseEmptyDerivedDataIsRealStateChanged() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let backlog = EntityVerificationBacklogReport(entries: [], totalCandidates: 0, attemptedCount: 0, blockedCount: 0)
        let result = DerivedDataSurfaceAnalyzer.analyze(
            home: home,
            items: [],
            proofTargets: ["derived-data"],
            catalogRuntime: nil,
            verificationBacklog: backlog
        )
        if result.funnel.filesystemChildCount == 0 {
            XCTAssertEqual(result.rootCause.classification, DerivedDataSurfaceRootCause.realStateChanged.rawValue)
            XCTAssertFalse(result.rootCause.architecturalFixRequired)
        }
    }

    func testHistoricalPathClassificationNoLongerExists() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let check = DerivedDataSurfaceAnalyzer.checkHistorical(
            home: home,
            suffix: "Runner-nonexistent-test-id",
            entityID: "xcode.deriveddata.test"
        )
        if !check.exists {
            XCTAssertEqual(check.classification, HistoricalDerivedDataState.noLongerExists.rawValue)
        }
    }

    func testDefaultCatalogIncludesDerivedDataProofDetector() {
        let catalog = DetectorCatalog(proofTargets: ["derived-data"])
        XCTAssertTrue(catalog.detectors.contains { $0.detectorID == "XcodeDerivedDataProofDetector" })
        XCTAssertTrue(catalog.proofTargets.contains("derived-data"))
    }

    func testMultipleChildrenRemainDistinct() throws {
        let home = try makeHome()
        let p1 = "\(home)/A.xcodeproj"
        let p2 = "\(home)/B.xcodeproj"
        try FileManager.default.createDirectory(atPath: p1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: p2, withIntermediateDirectories: true)
        _ = try installRunnerFixture(home: home, name: "Runner-one", workspacePath: p1, includeInfo: true)
        _ = try installRunnerFixture(home: home, name: "Runner-two", workspacePath: p2, includeInfo: true)
        let found = XcodeDerivedDataProofDetector(maxChildren: 8).detect(home: home, scanner: ReadOnlyStorageScanner())
        let ids = Set(found.map(\.entity.id))
        XCTAssertTrue(ids.contains("xcode.deriveddata.Runner-one"))
        XCTAssertTrue(ids.contains("xcode.deriveddata.Runner-two"))
        XCTAssertEqual(ids.count, 2)
    }
}
