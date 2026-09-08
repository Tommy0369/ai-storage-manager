import XCTest
@testable import SafetyCore

final class P16ProofEnrichmentTests: XCTestCase {
    func makeHome() throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("p16-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        return home
    }

    func write(_ path: String, _ body: String = "x") throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Cursor

    func testCursorExplicitUUIDInWorkspaceJSONVerified() throws {
        let home = try makeHome()
        let project = "\(home)/Workspace/demo"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let storeID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        try FileManager.default.createDirectory(
            atPath: "\(home)/Library/Application Support/Cursor/snapshots/stores/\(storeID)/objects",
            withIntermediateDirectories: true
        )
        try write("\(home)/Library/Application Support/Cursor/snapshots/stores/\(storeID)/baseline.marker", "root_key=\(storeID)\n")
        let ws = "\(home)/Library/Application Support/Cursor/User/workspaceStorage/ws1"
        try FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
        try write("\(ws)/workspace.json", "{\"folder\":\"file://\(project)\",\"store\":\"\(storeID)\"}")
        let found = CursorStoresVerificationDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let hit = found.first { $0.entity.id.contains(storeID) }
        XCTAssertEqual(hit?.annotation?.relationships.first { $0.type == .belongsToWorkspace }?.confidence, .verified)
        XCTAssertEqual(hit?.annotation?.relationships.first { $0.type == .belongsToWorkspace }?.target, project)
    }

    func testCursorFolderNameOnlyStaysInferred() throws {
        let home = try makeHome()
        let project = "\(home)/Workspace/ai-storage-manager"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: "\(home)/Library/Application Support/Cursor/snapshots/roots/ai-storage-manager-deadbeef",
            withIntermediateDirectories: true
        )
        try write("\(home)/Library/Application Support/Cursor/snapshots/roots/ai-storage-manager-deadbeef/r")
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)
        let ws = "\(home)/Library/Application Support/Cursor/User/workspaceStorage/ws1"
        try FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
        try write("\(ws)/workspace.json", "{\"folder\":\"file://\(project)\"}")
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let ref = found.first { $0.entity.id.contains("rootref") }
        let possible = ref?.annotation?.relationships.first { $0.type == .possibleWorkspaceContext }
        XCTAssertEqual(possible?.confidence, .inferred)
    }

    func testCursorMissingTargetNotVerified() throws {
        let home = try makeHome()
        let missing = "\(home)/Workspace/gone-project"
        let storeID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        try FileManager.default.createDirectory(
            atPath: "\(home)/Library/Application Support/Cursor/snapshots/stores/\(storeID)",
            withIntermediateDirectories: true
        )
        try write("\(home)/Library/Application Support/Cursor/snapshots/stores/\(storeID)/baseline.marker", "x")
        let ws = "\(home)/Library/Application Support/Cursor/User/workspaceStorage/ws1"
        try FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
        try write("\(ws)/workspace.json", "{\"folder\":\"file://\(missing)\",\"store\":\"\(storeID)\"}")
        let found = CursorStoresVerificationDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let hit = found.first { $0.entity.id.contains(storeID) }
        let rel = hit?.annotation?.relationships.first { $0.type == .belongsToWorkspace }
        XCTAssertNotEqual(rel?.confidence, .verified)
        XCTAssertTrue(hit?.annotation?.unknownReasons.contains(UnknownReasonCode.cursorWorkspaceTargetNotFound.rawValue) == true
            || rel?.confidence == .unknown)
    }

    func testCursorSecondaryIndexUniquePathVerified() throws {
        let home = try makeHome()
        let project = "\(home)/Workspace/indexed-proj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let rootName = "indexed-proj-aabbcc"
        let indexPath = "\(home)/Library/Application Support/Cursor/snapshots/roots/\(rootName)/secondary-index-baseline"
        try FileManager.default.createDirectory(atPath: (indexPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        // Encode workspace path in index blob
        try write(indexPath, "noise \(project) more noise")
        try write("\(home)/Library/Application Support/Cursor/snapshots/roots/\(rootName)/baseline.marker", "root_key=\(rootName)\n")
        let ws = "\(home)/Library/Application Support/Cursor/User/workspaceStorage/ws1"
        try FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
        try write("\(ws)/workspace.json", "{\"folder\":\"file://\(project)\"}")
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let ref = found.first { $0.entity.id.contains("rootref.\(rootName)") }
        let wsRel = ref?.annotation?.relationships.first { $0.type == .belongsToWorkspace }
        XCTAssertEqual(wsRel?.confidence, .verified)
        XCTAssertEqual(wsRel?.target, project)
    }

    func testCursorAmbiguousIndexNotVerified() throws {
        let home = try makeHome()
        let p1 = "\(home)/Workspace/a"
        let p2 = "\(home)/Workspace/b"
        try FileManager.default.createDirectory(atPath: p1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: p2, withIntermediateDirectories: true)
        let rootName = "ambiguous-root-ffff"
        let indexPath = "\(home)/Library/Application Support/Cursor/snapshots/roots/\(rootName)/secondary-index-baseline"
        try FileManager.default.createDirectory(atPath: (indexPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try write(indexPath, "\(p1) and also \(p2)")
        try write("\(home)/Library/Application Support/Cursor/snapshots/roots/\(rootName)/baseline.marker", "root_key=\(rootName)\n")
        for (id, path) in [("ws1", p1), ("ws2", p2)] {
            let ws = "\(home)/Library/Application Support/Cursor/User/workspaceStorage/\(id)"
            try FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
            try write("\(ws)/workspace.json", "{\"folder\":\"file://\(path)\"}")
        }
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let ref = found.first { $0.entity.id.contains(rootName) }
        let ws = ref?.annotation?.relationships.first { $0.type == .belongsToWorkspace }
        XCTAssertNotEqual(ws?.confidence, .verified)
        XCTAssertTrue(ref?.annotation?.unknownReasons.contains(UnknownReasonCode.cursorRelationshipAmbiguous.rawValue) == true
            || ws?.confidence == .unknown
            || ref?.annotation?.provenance.confidence == .unknown)
    }

    // MARK: - Claude

    func testClaudeParentOpenDoesNotActivateChild() {
        let child = "/tmp/vm_bundles/x.bundle/rootfs.img"
        let parent = "/tmp/vm_bundles"
        let handles = OpenFileSnapshot(openPaths: [parent], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let procs = ProcessTableSnapshot(names: ["Claude"], commandLines: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let (state, conf, _, _) = ActiveStateResolver.resolve(
            entityPath: child,
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: handles,
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        XCTAssertNotEqual(state, .active)
        XCTAssertNotEqual(conf, .verified)
    }

    func testClaudeProcessRunningAloneDoesNotActivateBundle() {
        let path = "/tmp/vm_bundles/x.bundle/rootfs.img"
        let handles = OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let procs = ProcessTableSnapshot(names: ["Claude"], commandLines: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let (state, conf, _, _) = ActiveStateResolver.resolve(
            entityPath: path,
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: handles,
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        XCTAssertEqual(state, .unknown)
        XCTAssertEqual(conf, .inferred)
    }

    func testClaudeMissingExactEvidenceStaysUnknownNotInactiveVerified() {
        let path = "/tmp/vm_bundles/x.bundle/rootfs.img"
        let handles = OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil, completeness: .partial)
        let procs = ProcessTableSnapshot(names: [], commandLines: [], snapshotFailed: true, failureReason: "TIMEOUT", completeness: .partial)
        let (state, conf, _, _) = ActiveStateResolver.resolve(
            entityPath: path,
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: handles,
            processCompleteness: .partial,
            handleCompleteness: .partial
        )
        XCTAssertEqual(state, .unknown)
        XCTAssertNotEqual(state, .inactive)
        XCTAssertNotEqual(conf, .verified)
    }

    // MARK: - DerivedData

    func testDerivedDataPathOnlyNeverStrictVerified() throws {
        let home = try makeHome()
        let dd = "\(home)/Library/Developer/Xcode/DerivedData/NoInfo-abc"
        try FileManager.default.createDirectory(atPath: dd, withIntermediateDirectories: true)
        try write("\(dd)/Build/o")
        let found = XcodeDerivedDataProofDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let hit = found.first { $0.entity.path == dd }
        XCTAssertNotNil(hit)
        let evidence = EvidenceBundle(canonicalPath: dd, isSymlink: .false)
        let sot = SourceOfTruthResolver.resolve(entity: hit!.entity, annotation: hit!.annotation, evidence: evidence)
        let regen = RegenerabilityResolver.resolve(entity: hit!.entity, annotation: hit!.annotation, evidence: evidence, sourceOfTruth: sot)
        XCTAssertNotEqual(sot.confidence, .verified)
        XCTAssertNotEqual(regen.value, .true)
    }

    func testDerivedDataLightweightNoRecursiveRequirement() throws {
        let home = try makeHome()
        let project = "\(home)/Apps/App.xcodeproj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let dd = "\(home)/Library/Developer/Xcode/DerivedData/App-xyz"
        try FileManager.default.createDirectory(atPath: "\(dd)/Build", withIntermediateDirectories: true)
        let plist: [String: Any] = ["WorkspacePath": project]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: URL(fileURLWithPath: "\(dd)/info.plist"))
        // Huge nested tree must not be required — only info.plist proof
        try FileManager.default.createDirectory(atPath: "\(dd)/Build/deep/a/b/c", withIntermediateDirectories: true)
        let found = XcodeDerivedDataProofDetector(maxChildren: 6).detect(home: home, scanner: ReadOnlyStorageScanner())
        let hit = found.first { $0.entity.path == dd }
        XCTAssertEqual(hit?.annotation?.relationships.first { $0.type == .derivedFrom }?.confidence, .verified)
        XCTAssertTrue(hit?.annotation?.unknownReasons.contains(where: { $0.hasPrefix("PROOF_BUDGET_FILES=") }) == true)
    }

    // MARK: - node_modules opt-in

    func testNodeModulesNotInDefaultCatalogWithoutOptIn() {
        let catalog = DetectorCatalog(proofTargets: ["derived-data"])
        XCTAssertFalse(catalog.detectors.contains { String(describing: type(of: $0)).contains("NodeModules") })
        let withNM = DetectorCatalog(proofTargets: ["derived-data", "node-modules"])
        XCTAssertTrue(withNM.detectors.contains { String(describing: type(of: $0)).contains("NodeModules") })
    }

    func testNodeModulesPackageJSONAloneInsufficient() throws {
        let home = try makeHome()
        let project = "\(home)/Workspace/app"
        try FileManager.default.createDirectory(atPath: "\(project)/node_modules", withIntermediateDirectories: true)
        try write("\(project)/package.json", "{\"name\":\"app\"}")
        try write("\(project)/node_modules/x")
        let found = NodeModulesProofDetector(maxProjects: 4).detect(home: home, scanner: ReadOnlyStorageScanner())
        let hit = found.first { $0.entity.path.hasSuffix("/node_modules") }
        let evidence = EvidenceBundle(
            canonicalPath: hit!.entity.path,
            sourceProjectExists: .true,
            manifestExists: .true,
            lockfileExists: .false
        )
        let sot = ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .relationshipMetadata)
        let regen = RegenerabilityResolver.resolve(entity: hit!.entity, annotation: hit!.annotation, evidence: evidence, sourceOfTruth: sot)
        XCTAssertNotEqual(regen.confidence, .verified)
    }

    // MARK: - VerificationChain

    func testChainOneInferredStepBlocksVerified() {
        let chain = VerificationChain.finalize(
            entityID: "e",
            claim: "REGENERABILITY",
            result: "true",
            requiredSteps: ["a", "b"],
            satisfied: ["a"],
            failed: [],
            unknown: []
        )
        XCTAssertNotEqual(chain.confidence, .verified)
        XCTAssertFalse(chain.satisfiesStrictChain)
    }

    func testChainOneUnknownStepBlocksVerified() {
        let chain = VerificationChain.finalize(
            entityID: "e",
            claim: "ACTIVE_STATE",
            result: "active",
            requiredSteps: ["runtime_observation_verified"],
            satisfied: [],
            failed: [],
            unknown: ["ACTIVE_STATE_UNKNOWN"]
        )
        XCTAssertEqual(chain.confidence, .unknown)
        XCTAssertEqual(chain.failureReason, "ACTIVE_STATE_UNKNOWN")
        XCTAssertFalse(chain.satisfiesStrictChain)
    }

    func testChainAllRequiredVerified() {
        let chain = VerificationChain.finalize(
            entityID: "e",
            claim: "RELATIONSHIP_BELONGS_TO_WORKSPACE",
            result: "present:/ws",
            requiredSteps: ["explicit_metadata", "target_resolved"],
            satisfied: ["explicit_metadata", "target_resolved"],
            failed: [],
            unknown: []
        )
        XCTAssertEqual(chain.confidence, .verified)
        XCTAssertTrue(chain.satisfiesStrictChain)
    }

    func testProofEnrichmentDoesNotAlterUniqueTotal() {
        let parent = AccountingInput(id: "xcode.derived_data", path: "/dd", inclusiveBytes: 200, safetyClass: .yellow, resolution: .l3Product)
        let child = AccountingInput(id: "xcode.deriveddata.App", path: "/dd/App", inclusiveBytes: 50, safetyClass: .yellow, resolution: .l4SemanticEntity)
        XCTAssertEqual(ByteAccountant.account([parent]).uniqueTotal, ByteAccountant.account([parent, child]).uniqueTotal)
    }

    func testVerificationChainDoesNotSetGreen() {
        let knowledge = KnowledgeBaseDocument(version: "t", principle: "t", rules: [])
        let entity = StorageEntity(
            id: "xcode.deriveddata.App",
            kind: .generatedBuild,
            category: "DEVELOPER",
            subcategory: "DerivedData",
            displayName: "App DerivedData",
            path: "/dd/App",
            logicalBytes: 10
        )
        let decision = SafetyRuleEngine(knowledge: knowledge).evaluate(EvaluationRequest(
            entity: entity,
            intendedAction: .userReview,
            evidence: EvidenceBundle(canonicalPath: entity.path, sourceOfTruth: .false, regenerable: .true),
            state: RuntimeState()
        ))
        // Detector/chain layer never assigns GREEN; engine may still classify non-green without full predicates.
        XCTAssertNotEqual(decision.safetyClass, SafetyClass.green)
    }
}
