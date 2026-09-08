import XCTest
@testable import SafetyCore

final class P15VerificationProofTests: XCTestCase {
    func makeHome() throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("p15-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        return home
    }

    func write(_ path: String, _ body: String = "x") throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: URL(fileURLWithPath: path))
    }

    func testExplicitWorkspaceMetadataVerifiedRelationship() throws {
        let home = try makeHome()
        let project = "\(home)/Workspace/demo-proj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let rootName = "demo-proj-abcdef"
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/roots/\(rootName)", withIntermediateDirectories: true)
        try write("\(home)/Library/Application Support/Cursor/snapshots/roots/\(rootName)/baseline.marker", "root_key=\(rootName)\n")
        // Explicit: root key appears in workspace.json text
        let ws = "\(home)/Library/Application Support/Cursor/User/workspaceStorage/ws1"
        try FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
        try write("\(ws)/workspace.json", "{\"folder\":\"file://\(project)\",\"note\":\"\(rootName)\"}")
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)

        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let ref = found.first { $0.entity.id.contains("rootref") }
        XCTAssertEqual(ref?.annotation?.relationships.first?.confidence, .verified)
        XCTAssertEqual(ref?.annotation?.relationships.first?.presence, .present)
        XCTAssertEqual(ref?.annotation?.relationships.first?.target, project)
    }

    func testBasenameOnlyWorkspaceStaysInferredEvenIfWorkspaceJSONExists() throws {
        let home = try makeHome()
        let project = "\(home)/Workspace/demo-proj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/roots/demo-proj-abcdef", withIntermediateDirectories: true)
        try write("\(home)/Library/Application Support/Cursor/snapshots/roots/demo-proj-abcdef/baseline.marker", "root_key=demo-proj-abcdef\n")
        let ws = "\(home)/Library/Application Support/Cursor/User/workspaceStorage/ws1"
        try FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
        // folder basename matches, but root key NOT referenced → INFERRED
        try write("\(ws)/workspace.json", "{\"folder\":\"file://\(project)\"}")
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let ref = found.first { $0.entity.id.contains("rootref") }
        XCTAssertEqual(ref?.annotation?.relationships.first?.confidence, .inferred)
        XCTAssertNotEqual(ref?.annotation?.relationships.first?.confidence, .verified)
    }

    func testFolderNameMappingRemainsInferred() throws {
        let home = try makeHome()
        try FileManager.default.createDirectory(atPath: "\(home)/Workspace/demo-proj", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/roots/demo-proj-abcdef", withIntermediateDirectories: true)
        try write("\(home)/Library/Application Support/Cursor/snapshots/roots/demo-proj-abcdef/r")
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)
        // no workspace.json
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let ref = found.first { $0.entity.id.contains("rootref") }
        XCTAssertEqual(ref?.annotation?.relationships.first?.confidence, .inferred)
        XCTAssertNotEqual(ref?.annotation?.relationships.first?.confidence, .verified)
    }

    func testStoreWithoutMetadataStaysUnknownRelation() throws {
        let home = try makeHome()
        let storeID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        let store = "\(home)/Library/Application Support/Cursor/snapshots/stores/\(storeID)"
        try FileManager.default.createDirectory(atPath: "\(store)/objects", withIntermediateDirectories: true)
        try write("\(store)/baseline.marker", "root_key=\(storeID)\n")
        try write("\(store)/objects/o")
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/User/workspaceStorage", withIntermediateDirectories: true)
        let found = CursorStoresVerificationDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let linked = found.first { $0.entity.id == "cursor.snapshots.store.\(storeID)" }
        let ws = linked?.annotation?.relationships.first { $0.type == .belongsToWorkspace }
        XCTAssertNotEqual(ws?.confidence, .verified)
        XCTAssertNotEqual(linked?.annotation?.provenance.confidence, .verified)
    }

    func testExactRootfsHandleActiveVerified() {
        let path = "/tmp/vm_bundles/claudevm.bundle/rootfs.img"
        let handles = OpenFileSnapshot(openPaths: [path], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let procs = ProcessTableSnapshot(names: ["Claude"], commandLines: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let (state, conf, _, _) = ActiveStateResolver.resolve(
            entityPath: path,
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: handles,
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        XCTAssertEqual(state, .active)
        XCTAssertEqual(conf, .verified)
    }

    func testProcessCommandLineReferencesBundleActiveVerified() {
        let bundle = "/tmp/vm_bundles/claudevm.bundle"
        let procs = ProcessTableSnapshot(
            names: ["Claude"],
            commandLines: ["Claude --bundle \(bundle)/rootfs.img"],
            snapshotFailed: false,
            failureReason: nil,
            completeness: .complete
        )
        let handles = OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let (state, conf, _, _) = ActiveStateResolver.resolve(
            entityPath: "\(bundle)/rootfs.img",
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: handles,
            processCompleteness: .complete,
            handleCompleteness: .complete,
            relatedPaths: ["\(bundle)/sessiondata.img"]
        )
        XCTAssertEqual(state, .active)
        XCTAssertEqual(conf, .verified)
    }

    func testDerivedDataFullChainRegenerableTrue() throws {
        let home = try makeHome()
        let project = "\(home)/Apps/Runner.xcworkspace"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        try write("\(project)/contents.xcworkspacedata", "x")
        let dd = "\(home)/Library/Developer/Xcode/DerivedData/Runner-abc"
        try FileManager.default.createDirectory(atPath: "\(dd)/Build", withIntermediateDirectories: true)
        let plist: [String: Any] = ["WorkspacePath": project]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: "\(dd)/info.plist"))
        try write("\(dd)/Build/o")

        let found = XcodeDerivedDataProofDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let hit = found.first { $0.entity.path == dd }
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.annotation?.relationships.first { $0.type == .derivedFrom }?.confidence, .verified)
        XCTAssertEqual(hit?.annotation?.provenance.confidence, .verified)

        var evidence = EvidenceResolver().resolve(path: dd, associatedProcesses: [])
        evidence.isSymlink = .false
        let sot = SourceOfTruthResolver.resolve(entity: hit!.entity, annotation: hit!.annotation, evidence: evidence)
        XCTAssertEqual(sot.value, .false)
        XCTAssertEqual(sot.confidence, .verified)
        let regen = RegenerabilityResolver.resolve(entity: hit!.entity, annotation: hit!.annotation, evidence: evidence, sourceOfTruth: sot)
        XCTAssertEqual(regen.value, .true)
        XCTAssertEqual(regen.confidence, .verified)

        let knowledge = KnowledgeBaseDocument(version: "t", principle: "t", rules: [])
        let decision = SafetyRuleEngine(knowledge: knowledge).evaluate(EvaluationRequest(
            entity: hit!.entity,
            intendedAction: .userReview,
            evidence: evidence,
            state: RuntimeState()
        ))
        let item = ClassifiedItem(
            detected: hit!,
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: 1,
            actionVariants: [:],
            inclusiveBytes: 1,
            exclusiveBytes: 1,
            resolution: .l4SemanticEntity,
            verification: VerificationAnnotation(sourceOfTruth: sot, regenerable: regen, provenanceConfidence: .verified)
        )
        let chains = VerificationChainBuilder.build(for: item)
        XCTAssertTrue(chains.contains { $0.claim == "REGENERABILITY" && $0.confidence == EvidenceConfidence.verified })
        XCTAssertTrue(chains.contains { $0.claim.contains("DERIVED_FROM") && $0.confidence == EvidenceConfidence.verified })
    }

    func testDerivedDataMissingProjectUnknown() throws {
        let home = try makeHome()
        let dd = "\(home)/Library/Developer/Xcode/DerivedData/Runner-xyz"
        try FileManager.default.createDirectory(atPath: dd, withIntermediateDirectories: true)
        let missing = "\(home)/Apps/Missing.xcworkspace"
        let plist: [String: Any] = ["WorkspacePath": missing]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: "\(dd)/info.plist"))
        try write("\(dd)/x")
        let found = XcodeDerivedDataProofDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let hit = found.first { $0.entity.path == dd }
        let rel = hit?.annotation?.relationships.first { $0.type == .derivedFrom }
        XCTAssertEqual(rel?.presence, .missing)
        let evidence = EvidenceBundle(canonicalPath: dd, isSymlink: .false, sourceProjectExists: .false)
        let sot = SourceOfTruthResolver.resolve(entity: hit!.entity, annotation: hit!.annotation, evidence: evidence)
        let regen = RegenerabilityResolver.resolve(entity: hit!.entity, annotation: hit!.annotation, evidence: evidence, sourceOfTruth: sot)
        XCTAssertNotEqual(regen.value, .true)
    }

    func testNodeModulesLocalDependencyUnknown() throws {
        let home = try makeHome()
        let project = "\(home)/Workspace/app"
        try FileManager.default.createDirectory(atPath: "\(project)/node_modules", withIntermediateDirectories: true)
        try write("\(project)/package.json", "{\"dependencies\":{\"local\":\"file:../lib\"}}")
        try write("\(project)/package-lock.json", "{}")
        try write("\(project)/node_modules/x")
        let found = NodeModulesProofDetector(maxProjects: 4).detect(home: home, scanner: ReadOnlyStorageScanner())
        let hit = found.first { $0.entity.path.hasSuffix("/node_modules") }
        XCTAssertNotNil(hit)
        XCTAssertTrue(hit?.annotation?.unknownReasons.contains(UnknownReasonCode.unknownCustomAsset.rawValue) == true)
        let evidence = EvidenceBundle(canonicalPath: hit!.entity.path, sourceProjectExists: .true, manifestExists: .true, lockfileExists: .true)
        let sot = ObservationRecord(value: .false, confidence: .inferred, completeness: .partial, source: .unknown)
        let regen = RegenerabilityResolver.resolve(entity: hit!.entity, annotation: hit!.annotation, evidence: evidence, sourceOfTruth: sot)
        XCTAssertNotEqual(regen.confidence, .verified)
    }

    func testCloudPathOnlyRemoteUnknown() {
        let obs = CloudResolutionDetector.observeCloudState(path: "/tmp/not-a-cloud-path-\(UUID().uuidString)")
        XCTAssertEqual(obs.remoteCopy, .unknown)
        XCTAssertTrue(obs.unknownReasons.contains(UnknownReasonCode.unknownRemoteCopy.rawValue))
    }

    func testInferredEdgeDoesNotSatisfyStrictChain() {
        let chain = VerificationChain(
            entityID: "x",
            claim: "REGENERABILITY",
            result: "true",
            confidence: .inferred,
            failedRequirements: []
        )
        XCTAssertFalse(chain.satisfiesStrictChain)
    }

    func testChromeSemanticSplit() throws {
        let home = try makeHome()
        let profile = "\(home)/Library/Application Support/Google/Chrome/Default"
        try FileManager.default.createDirectory(atPath: "\(profile)/History", withIntermediateDirectories: true)
        try write("\(profile)/History/h")
        try FileManager.default.createDirectory(atPath: "\(profile)/Preferences", withIntermediateDirectories: true)
        try write("\(profile)/Preferences/p")
        let found = ChromeAppSupportDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.entity.id.contains("chrome.profile.default.history") })
        XCTAssertTrue(found.contains { $0.annotation?.lifecycle.role == .history })
        XCTAssertTrue(found.contains { $0.annotation?.lifecycle.role == .userConfiguration })
    }

    func testProofDoesNotChangeByteTotal() {
        let parent = AccountingInput(id: "xcode.derived_data", path: "/dd", inclusiveBytes: 100, safetyClass: .yellow, resolution: .l3Product)
        let child = AccountingInput(id: "xcode.deriveddata.Runner-abc", path: "/dd/Runner-abc", inclusiveBytes: 40, safetyClass: .yellow, resolution: .l4SemanticEntity)
        let r0 = ByteAccountant.account([parent])
        let r1 = ByteAccountant.account([parent, child])
        XCTAssertEqual(r0.uniqueTotal, r1.uniqueTotal)
    }
}
