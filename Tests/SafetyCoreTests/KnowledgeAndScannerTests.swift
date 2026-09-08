import XCTest
@testable import SafetyCore

final class KnowledgeCompilerTests: XCTestCase {
    func compiledURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("knowledge/compiled/compiled_rules_v0.1.json")
    }

    func bootstrapURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("knowledge/source/bootstrap_rules_v0.1.json")
    }

    func testCompiledRuleCountIs178() throws {
        let doc = try KnowledgeBaseLoader().load(from: compiledURL())
        XCTAssertEqual(doc.rules.count, 178)
        let report = KnowledgeCompiler().validate(doc, bootstrap: try KnowledgeBaseLoader().load(from: bootstrapURL()))
        XCTAssertTrue(report.isValid, "\(report.issues)")
        XCTAssertTrue(report.greenMissingPredicates.isEmpty)
        XCTAssertTrue(report.duplicateIDs.isEmpty)
        XCTAssertTrue(report.bootstrapConflicts.isEmpty)
    }

    func testCorruptedKnowledgeBaseFails() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("bad.json")
        try! "{".data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try KnowledgeBaseLoader().load(from: url))
    }

    func testGreenRequiresPredicates() {
        let bad = KnowledgeBaseDocument(version: "x", principle: "x", rules: [
            SafetyRule(
                id: "bad.green",
                entity: "X",
                category: "X",
                subcategory: "X",
                match: RuleMatch(path: "/tmp/x"),
                defaultClass: .green,
                baseScore: 1,
                evaluationLayer: .genericCacheTemp,
                sourceOfTruth: false,
                regenerable: true,
                networkRequired: false,
                requiredPredicates: [],
                demoteToYellowIf: [],
                demoteToRedIf: [],
                hardBlockIf: [],
                actionMode: .moveToTrash,
                effects: [],
                verification: [],
                growthCauses: [],
                explanationJA: "x",
                reasonCodes: []
            )
        ])
        let report = KnowledgeCompiler().validate(bad)
        XCTAssertFalse(report.isValid)
    }
}

final class ScannerEvidenceTests: XCTestCase {
    func testSymlinkIsNotFollowedIntoSystem() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("asm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let link = tmp.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/System")
        let node = ReadOnlyStorageScanner().scanNode(path: link.path)
        XCTAssertEqual(node?.isSymlink, true)
        XCTAssertTrue(node?.skippedBecauseSymlink == true)
        XCTAssertFalse(node?.canonicalPath.hasPrefix("/System") ?? true)
    }

    func testLogicalAndAllocatedAreSeparatedOnModel() {
        let n = ScannedNode(
            path: "/tmp", canonicalPath: "/tmp", logicalBytes: 10, allocatedBytes: 4,
            fileCount: 1, isDirectory: true, isSymlink: false, isPackage: false, isHidden: false,
            owner: nil, posixPermissions: nil, created: nil, modified: nil, accessed: nil,
            skippedBecauseSymlink: false
        )
        XCTAssertNotEqual(n.logicalBytes, n.allocatedBytes)
    }

    func testTOCTOUReconfirmDetectsHandleChange() {
        struct FixedHandle: OpenHandleChecker {
            let value: PredicateValue
            func hasOpenHandles(path: String) -> PredicateValue { value }
        }
        struct NeverProc: ProcessRunningChecker {
            func isRunning(executableNames: [String]) -> PredicateValue { .false }
        }
        let first = EvidenceResolver(processes: NeverProc(), handles: FixedHandle(value: .false)).resolve(path: "/tmp")
        let prev = EvidenceSnapshot(capturedAt: Date(), bundle: first, state: RuntimeState())
        let gate = ReconfirmGate(resolver: EvidenceResolver(processes: NeverProc(), handles: FixedHandle(value: .true)))
        let result = gate.reconfirm(path: "/tmp", previous: prev, associatedProcesses: [])
        XCTAssertTrue(result.stale)
    }

    func testMissingPredicateStaysUnknownNotGreen() throws {
        let doc = try KnowledgeBaseLoader().load(from: KnowledgeCompilerTests().compiledURL())
        let engine = SafetyRuleEngine(knowledge: doc)
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Caches/testers"
        let entity = StorageEntity(id: "c", kind: .cache, category: "MACOS", subcategory: "CACHE", displayName: "c", path: path, logicalBytes: 1)
        let ev = EvidenceBundle(canonicalPath: path, openFileHandle: .unknown, owningProcessRunning: .unknown, sourceOfTruth: .false, regenerable: .true)
        let d = engine.evaluate(EvaluationRequest(entity: entity, intendedAction: .moveToTrash, evidence: ev, state: RuntimeState()))
        XCTAssertNotEqual(d.safetyClass, .green)
    }

    func testCoverageMath() {
        let c = IdentifiedStorageCoverage(scannedBytes: 203, identifiedBytes: 185, unknownBytes: 18)
        XCTAssertEqual(c.percent, 185.0 / 203.0 * 100, accuracy: 0.01)
    }

    func testUserProtectionAfterScanBlocks() {
        let store = UserProtectionStore(rules: [])
        store.add(UserProtectionRule(id: "later", label: "Later", pathPrefixes: ["/tmp/later-protect"]))
        let engine = SafetyRuleEngine(
            knowledge: KnowledgeBaseDocument(version: "x", principle: "x", rules: []),
            protection: store
        )
        let entity = StorageEntity(id: "x", kind: .cache, category: "t", subcategory: "t", displayName: "x", path: "/tmp/later-protect/a", logicalBytes: 1)
        let d = engine.evaluate(EvaluationRequest(entity: entity, intendedAction: .moveToTrash, evidence: EvidenceBundle(canonicalPath: "/tmp/later-protect/a"), state: RuntimeState()))
        XCTAssertEqual(d.evaluationLayer, .userProtection)
        XCTAssertNotEqual(d.safetyClass, .green)
    }
}
