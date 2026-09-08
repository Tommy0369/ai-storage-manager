import XCTest
@testable import SafetyCore

final class P17ProofStabilizationTests: XCTestCase {
    func makeHome() throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("p17-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        return home
    }

    func write(_ path: String, _ body: String = "x") throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: URL(fileURLWithPath: path))
    }

    // MARK: Cursor

    func testWorkspaceStorageExplicitJSONVerified() throws {
        let home = try makeHome()
        let project = "\(home)/Workspace/demo"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let wid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let ws = "\(home)/Library/Application Support/Cursor/User/workspaceStorage/\(wid)"
        try FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
        try write("\(ws)/workspace.json", "{\"folder\":\"file://\(project)\"}")
        let found = CursorWorkspaceStorageDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let hit = found.first { $0.entity.id.contains(wid) }
        XCTAssertEqual(hit?.annotation?.relationships.first?.confidence, .verified)
        XCTAssertEqual(hit?.annotation?.relationships.first?.target, project)
    }

    func testRemoteURINotLocalVerified() throws {
        let home = try makeHome()
        let wid = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let ws = "\(home)/Library/Application Support/Cursor/User/workspaceStorage/\(wid)"
        try FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
        try write("\(ws)/workspace.json", "{\"folder\":\"vscode-remote://ssh-remote+host/project\"}")
        let found = CursorWorkspaceStorageDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let hit = found.first { $0.entity.id.contains(wid) }
        XCTAssertNotEqual(hit?.annotation?.relationships.first?.confidence, .verified)
    }

    func testBasenameStillInferred() throws {
        let home = try makeHome()
        try FileManager.default.createDirectory(atPath: "\(home)/Workspace/demo-proj", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/roots/demo-proj-abcdef", withIntermediateDirectories: true)
        try write("\(home)/Library/Application Support/Cursor/snapshots/roots/demo-proj-abcdef/r")
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let ref = found.first { $0.entity.id.contains("rootref") }
        XCTAssertEqual(ref?.annotation?.relationships.first?.confidence, .inferred)
    }

    func testMetadataDiscoveryDoesNotDumpValues() throws {
        let home = try makeHome()
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        try FileManager.default.createDirectory(atPath: gs, withIntermediateDirectories: true)
        try write("\(gs)/storage.json", "{\"profileAssociations\":{\"workspaces\":{\"file://\(home)/Workspace/x\":\"__default__profile__\"}}}")
        let discovery = CursorExplicitMetadataResolver.discover(home: home)
        for m in discovery.report.sanitizedMappings {
            XCTAssertFalse(m.workspacePath.contains("secret"))
            XCTAssertLessThan(m.workspacePath.count, 2000)
        }
    }

    // MARK: Claude window

    func testSnapshotMergeUnionsExactHandles() {
        let a = OpenFileSnapshot(openPaths: ["/tmp/a.img"], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let b = OpenFileSnapshot(openPaths: ["/tmp/b.img"], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let m = OpenFileSnapshot.merge(a, b)
        XCTAssertEqual(m.completeness, .complete)
        XCTAssertTrue(m.openPaths.contains("/tmp/a.img"))
        XCTAssertTrue(m.openPaths.contains("/tmp/b.img"))
    }

    func testPartialMergeBlocksInactiveVerified() {
        let a = OpenFileSnapshot(openPaths: [], snapshotFailed: true, failureReason: "LSOF_TIMEOUT", completeness: .partial)
        let b = OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let m = OpenFileSnapshot.merge(a, b)
        XCTAssertEqual(m.completeness, .partial)
        let procs = ProcessTableSnapshot(names: ["Claude"], commandLines: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let (state, conf, _, _) = ActiveStateResolver.resolve(
            entityPath: "/tmp/vm/rootfs.img",
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: m,
            processCompleteness: .complete,
            handleCompleteness: m.completeness
        )
        XCTAssertNotEqual(state, .inactive)
        XCTAssertNotEqual(conf, .verified)
    }

    func testSiblingBundleHandleDoesNotActivateTarget() {
        let target = "/tmp/vm_bundles/a.bundle/rootfs.img"
        let sibling = "/tmp/vm_bundles/b.bundle/rootfs.img"
        let handles = OpenFileSnapshot(openPaths: [sibling], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let procs = ProcessTableSnapshot(names: ["Claude"], commandLines: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let (state, conf, _, _) = ActiveStateResolver.resolve(
            entityPath: target,
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: handles,
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        XCTAssertNotEqual(state, .active)
        XCTAssertNotEqual(conf, .verified)
    }

    // MARK: Runtime / budgets

    func testSizeCacheHitsAvoidRespawn() {
        DirectorySizeCache.reset()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p17-size-\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: URL(fileURLWithPath: "\(dir)/f"))
        _ = DirectorySizeCache.bytes(at: dir, timeoutSeconds: 2)
        let before = DirectorySizeCache.stats()
        _ = DirectorySizeCache.bytes(at: dir, timeoutSeconds: 2)
        let after = DirectorySizeCache.stats()
        XCTAssertEqual(after.hits, before.hits + 1)
        XCTAssertEqual(after.spawns, before.spawns)
    }

    func testNodeModulesRemainsOptIn() {
        let def = DetectorCatalog(proofTargets: ["derived-data"])
        XCTAssertFalse(def.detectors.contains { String(describing: type(of: $0)).contains("NodeModules") })
    }

    func testBudgetExhaustionPreservesUnknown() {
        let chain = VerificationChain.finalize(
            entityID: "e",
            claim: "CURSOR",
            result: "unknown",
            requiredSteps: ["db"],
            satisfied: [],
            failed: [],
            unknown: [UnknownReasonCode.proofBudgetExceeded.rawValue]
        )
        XCTAssertEqual(chain.confidence, .unknown)
        XCTAssertFalse(chain.satisfiesStrictChain)
    }

    // MARK: GREEN regression

    func testDerivedDataMissingWorkspaceNoGreen() throws {
        let home = try makeHome()
        let dd = "\(home)/Library/Developer/Xcode/DerivedData/NoWS-abc"
        try FileManager.default.createDirectory(atPath: dd, withIntermediateDirectories: true)
        try write("\(dd)/x")
        let found = XcodeDerivedDataProofDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let hit = found.first { $0.entity.path == dd }!
        let evidence = EvidenceBundle(
            canonicalPath: dd,
            isSymlink: .false,
            openFileHandle: .false,
            owningProcessRunning: .false,
            sourceOfTruth: .unknown,
            regenerable: .unknown,
            predicateConfidence: [
                "no_open_file_handle": .verified,
                "owning_process_not_running": .verified,
                "canonical_path": .verified
            ]
        )
        let sot = SourceOfTruthResolver.resolve(entity: hit.entity, annotation: hit.annotation, evidence: evidence)
        let regen = RegenerabilityResolver.resolve(entity: hit.entity, annotation: hit.annotation, evidence: evidence, sourceOfTruth: sot)
        XCTAssertNotEqual(sot.confidence, EvidenceConfidence.verified)
        XCTAssertNotEqual(regen.value, PredicateValue.true)
        let knowledge = try KnowledgeBaseLoader().load(from: locateKB())
        var evidence2 = evidence
        evidence2.sourceOfTruth = sot.value
        evidence2.regenerable = regen.value
        let decision = SafetyRuleEngine(knowledge: knowledge).evaluate(EvaluationRequest(
            entity: hit.entity,
            intendedAction: .userReview,
            evidence: evidence2,
            state: RuntimeState()
        ))
        let item = ClassifiedItem(
            detected: hit,
            decision: decision,
            semantic: LLMBoundary.freeze(decision),
            allocatedBytes: 1,
            actionVariants: [:],
            inclusiveBytes: 1,
            exclusiveBytes: 1,
            resolution: .l4SemanticEntity,
            verification: VerificationAnnotation(sourceOfTruth: sot, regenerable: regen)
        )
        let audited = GreenCandidateAuditor(knowledge: knowledge).audit(item: item, evidence: evidence2, state: RuntimeState())
        XCTAssertNotEqual(audited.0.safetyClass, SafetyClass.green)
    }

    func testOpenFileUnknownBlocksGreen() throws {
        let knowledge = try KnowledgeBaseLoader().load(from: locateKB())
        let entity = StorageEntity(
            id: "xcode.deriveddata.App",
            kind: .generatedBuild,
            category: "DEVELOPER",
            subcategory: "DerivedData",
            displayName: "App",
            path: "/dd/App",
            logicalBytes: 10
        )
        let evidence = EvidenceBundle(
            canonicalPath: entity.path,
            openFileHandle: .unknown,
            owningProcessRunning: .false,
            sourceOfTruth: .false,
            regenerable: .true,
            predicateConfidence: [
                "regenerable": .verified,
                "not_source_of_truth": .verified,
                "owning_process_not_running": .verified
                // no_open_file_handle missing → cannot satisfy
            ]
        )
        let decision = SafetyRuleEngine(knowledge: knowledge).evaluate(EvaluationRequest(
            entity: entity,
            intendedAction: .userReview,
            evidence: evidence,
            state: RuntimeState(hasOpenHandles: false, owningProcessRunning: false)
        ))
        XCTAssertNotEqual(decision.safetyClass, SafetyClass.green)
    }

    // MARK: Chrome / TomyLocal

    func testChromeHistoryNotGreen() throws {
        let home = try makeHome()
        let profile = "\(home)/Library/Application Support/Google/Chrome/Default"
        try FileManager.default.createDirectory(atPath: "\(profile)/History", withIntermediateDirectories: true)
        try write("\(profile)/History/h")
        let found = ChromeAppSupportDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let hist = found.first { $0.annotation?.lifecycle.role == .history }
        XCTAssertNotNil(hist)
        let knowledge = try KnowledgeBaseLoader().load(from: locateKB())
        let decision = SafetyRuleEngine(knowledge: knowledge).evaluate(EvaluationRequest(
            entity: hist!.entity,
            intendedAction: .userReview,
            evidence: EvidenceBundle(canonicalPath: hist!.entity.path),
            state: RuntimeState()
        ))
        XCTAssertNotEqual(decision.safetyClass, .green)
    }

    func testTomyLocalUnknownOwner() throws {
        let home = try makeHome()
        let root = "\(home)/Library/Application Support/TomyLocal"
        try FileManager.default.createDirectory(atPath: "\(root)/models", withIntermediateDirectories: true)
        try write("\(root)/models/x")
        let found = TomyLocalInspectorDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.annotation?.provenance.confidence == .unknown })
        XCTAssertFalse(found.contains { $0.annotation?.lifecycle.roleConfidence == .verified && $0.annotation?.lifecycle.role == .cache })
    }

    func locateKB() -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("knowledge/compiled/compiled_rules_v0.1.json"),
            cwd.appendingPathComponent("Sources/SafetyCore/Resources/knowledge/compiled_rules_v0.1.json"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }
}
