import XCTest
@testable import SafetyCore

final class P14VerificationTests: XCTestCase {
    func testNegativeEvidenceRequiresCompleteObservation() {
        let partial = ObservationRecord.negativeOrUnknown(
            found: false,
            completeness: .partial,
            source: .processSnapshot,
            incompleteReason: UnknownReasonCode.unknownEvidenceIncomplete.rawValue
        )
        XCTAssertEqual(partial.value, .unknown)
        XCTAssertNotEqual(partial.value, .false)
        let complete = ObservationRecord.negativeOrUnknown(
            found: false,
            completeness: .complete,
            source: .processSnapshot,
            incompleteReason: "x"
        )
        XCTAssertEqual(complete.value, .false)
        XCTAssertEqual(complete.confidence, .verified)
    }

    func testInferredCannotSatisfyStrictPredicate() {
        var ev = EvidenceBundle(canonicalPath: "/tmp/x", regenerable: .true, predicateConfidence: ["regenerable": .inferred])
        XCTAssertFalse(ev.satisfiesStrictPredicate("regenerable"))
        ev.predicateConfidence["regenerable"] = .verified
        XCTAssertTrue(ev.satisfiesStrictPredicate("regenerable"))
        XCTAssertFalse(EvidenceConfidence.inferred.canSatisfySafetyPredicate)
    }

    func testVerifiedPredicateOnlyAcceptsVerified() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SafetyCore/Resources/knowledge/compiled_rules_v0.1.json")
        let doc = try KnowledgeBaseLoader().load(from: url)
        let engine = SafetyRuleEngine(knowledge: doc)
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Developer/Xcode/DerivedData/App-abc"
        let entity = StorageEntity(id: "xcode.derived_data", kind: .generatedBuild, category: "X", subcategory: "X", displayName: "d", path: path, logicalBytes: 1)
        let inferred = EvidenceBundle(
            canonicalPath: path,
            isSymlink: .false,
            openFileHandle: .false,
            owningProcessRunning: .false,
            sourceOfTruth: .false,
            regenerable: .true,
            predicateConfidence: [
                "canonical_path": .verified,
                "not_symlink": .verified,
                "no_open_file_handle": .verified,
                "owning_process_not_running": .verified,
                "not_source_of_truth": .verified,
                "regenerable": .inferred,
            ]
        )
        let d = engine.evaluate(EvaluationRequest(entity: entity, intendedAction: .moveToTrash, evidence: inferred, state: RuntimeState()))
        XCTAssertNotEqual(d.safetyClass, .green)
        XCTAssertTrue(d.reasonCodes.contains(where: { $0.contains("NOT_VERIFIED") || $0.contains("UNKNOWN") }))
    }

    func testSourceOfTruthUserDocumentVerified() {
        let entity = StorageEntity(id: "doc", kind: .userOriginal, category: "U", subcategory: "D", displayName: "d", path: "/Users/x/Documents/a.pdf", logicalBytes: 1)
        let rec = SourceOfTruthResolver.resolve(entity: entity, annotation: nil, evidence: EvidenceBundle(canonicalPath: entity.path))
        XCTAssertEqual(rec.value, .true)
        XCTAssertEqual(rec.confidence, .verified)
    }

    func testSourceOfTruthCacheNameAloneUnknown() {
        let entity = StorageEntity(id: "c", kind: .cache, category: "C", subcategory: "C", displayName: "c", path: "/tmp/something-cache", logicalBytes: 1)
        let note = DetectionAnnotation(
            detectorID: "t",
            specificity: 50,
            semanticType: "CACHE",
            lifecycle: LifecycleEvidence(role: .cache, roleConfidence: .inferred)
        )
        let rec = SourceOfTruthResolver.resolve(entity: entity, annotation: note, evidence: EvidenceBundle(canonicalPath: entity.path))
        XCTAssertEqual(rec.value, .unknown)
        XCTAssertEqual(rec.confidence, .unknown)
    }

    func testDatabaseAloneSourceOfTruthUnknown() {
        let entity = StorageEntity(id: "db", kind: .applicationSupport, category: "A", subcategory: "D", displayName: "d", path: "/tmp/state.db", logicalBytes: 1)
        let note = DetectionAnnotation(
            detectorID: "t",
            specificity: 50,
            semanticType: "DB",
            lifecycle: LifecycleEvidence(role: .database, roleConfidence: .inferred)
        )
        let rec = SourceOfTruthResolver.resolve(entity: entity, annotation: note, evidence: EvidenceBundle(canonicalPath: entity.path))
        XCTAssertEqual(rec.value, .unknown)
    }

    func testBackupIsProtectedSourceCopy() {
        let entity = StorageEntity(id: "ios", kind: .userOriginal, category: "B", subcategory: "IOS", displayName: "b", path: "/tmp/Backup/device", logicalBytes: 10)
        let note = DetectionAnnotation(
            detectorID: "ios.backup",
            specificity: 100,
            semanticType: "IOS_DEVICE_BACKUP",
            lifecycle: LifecycleEvidence(role: .backup, roleConfidence: .inferred)
        )
        let rec = SourceOfTruthResolver.resolve(entity: entity, annotation: note, evidence: EvidenceBundle(canonicalPath: entity.path))
        XCTAssertEqual(rec.value, .true)
        XCTAssertEqual(rec.confidence, .verified)
        let regen = RegenerabilityResolver.resolve(entity: entity, annotation: note, evidence: EvidenceBundle(canonicalPath: entity.path), sourceOfTruth: rec)
        XCTAssertEqual(regen.value, .false)
        XCTAssertEqual(regen.confidence, .verified)
    }

    func testPathOnlyDerivedDataNotRegenerableTrue() {
        let entity = StorageEntity(id: "dd", kind: .generatedBuild, category: "X", subcategory: "X", displayName: "d", path: "/Users/x/Library/Developer/Xcode/DerivedData/App", logicalBytes: 1)
        let ev = EvidenceBundle(canonicalPath: entity.path, sourceProjectExists: .unknown)
        let sot = ObservationRecord(value: .unknown, confidence: .unknown, completeness: .unknown, source: .unknown)
        let rec = RegenerabilityResolver.resolve(entity: entity, annotation: nil, evidence: ev, sourceOfTruth: sot)
        XCTAssertNotEqual(rec.value, .true)
        XCTAssertNotEqual(rec.confidence, .verified)
    }

    func testNodeModulesWithoutLockfileNotVerifiedRegenerable() {
        let entity = StorageEntity(id: "nm", kind: .cache, category: "N", subcategory: "N", displayName: "n", path: "/tmp/proj/node_modules", logicalBytes: 1)
        let ev = EvidenceBundle(canonicalPath: entity.path, sourceProjectExists: .true, manifestExists: .true, lockfileExists: .false)
        let sot = ObservationRecord(value: .false, confidence: .inferred, completeness: .partial, source: .unknown)
        let rec = RegenerabilityResolver.resolve(entity: entity, annotation: nil, evidence: ev, sourceOfTruth: sot)
        XCTAssertNotEqual(rec.confidence, .verified)
        XCTAssertNotEqual(rec.value, .true)
    }

    func testNodeModulesWithLockfileVerifiedRegenerable() {
        let entity = StorageEntity(id: "nm", kind: .cache, category: "N", subcategory: "N", displayName: "n", path: "/tmp/proj/node_modules", logicalBytes: 1)
        let note = DetectionAnnotation(
            detectorID: "node.modules.proof",
            specificity: 115,
            semanticType: "NODE_MODULES",
            lifecycle: LifecycleEvidence(role: .generatedArtifact, roleConfidence: .inferred),
            relationships: [
                EntityRelationship(type: .derivedFrom, target: "/tmp/proj", presence: .present, confidence: .verified)
            ]
        )
        let ev = EvidenceBundle(canonicalPath: entity.path, sourceProjectExists: .true, manifestExists: .true, lockfileExists: .true)
        let sot = ObservationRecord(value: .false, confidence: .inferred, completeness: .partial, source: .unknown)
        let rec = RegenerabilityResolver.resolve(entity: entity, annotation: note, evidence: ev, sourceOfTruth: sot)
        XCTAssertEqual(rec.value, .true)
        XCTAssertEqual(rec.confidence, .verified)
    }

    func testSnapshotAgeDoesNotImplyRegenerable() {
        let entity = StorageEntity(id: "snap", kind: .generatedBuild, category: "A", subcategory: "C", displayName: "s", path: "/tmp/Cursor/snapshots/stores/abc", logicalBytes: 1)
        let note = DetectionAnnotation(detectorID: "c", specificity: 100, semanticType: "STORE", lifecycle: LifecycleEvidence(role: .snapshot, roleConfidence: .inferred))
        let sot = SourceOfTruthResolver.resolve(entity: entity, annotation: note, evidence: EvidenceBundle(canonicalPath: entity.path))
        let regen = RegenerabilityResolver.resolve(entity: entity, annotation: note, evidence: EvidenceBundle(canonicalPath: entity.path), sourceOfTruth: sot)
        XCTAssertEqual(regen.value, .unknown)
    }

    func testActiveExactHandleVerified() {
        let handles = OpenFileSnapshot(openPaths: ["/vm/rootfs.img"], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let procs = ProcessTableSnapshot(names: ["Claude"], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let (state, conf, _, _) = ActiveStateResolver.resolve(
            entityPath: "/vm/rootfs.img",
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: handles,
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        XCTAssertEqual(state, .active)
        XCTAssertEqual(conf, .verified)
    }

    func testClaudeRunningWithoutBundleRelationUnknown() {
        let handles = OpenFileSnapshot(openPaths: ["/other"], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let procs = ProcessTableSnapshot(names: ["Claude"], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let (state, conf, _, _) = ActiveStateResolver.resolve(
            entityPath: "/vm/rootfs.img",
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: handles,
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        XCTAssertEqual(state, .unknown)
        XCTAssertNotEqual(conf, .verified)
    }

    func testPartialProcessSnapshotCannotSupportInactive() {
        let handles = OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let procs = ProcessTableSnapshot(names: [], snapshotFailed: true, failureReason: "fail", completeness: .partial)
        let (state, conf, _, _) = ActiveStateResolver.resolve(
            entityPath: "/vm/rootfs.img",
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: handles,
            processCompleteness: .partial,
            handleCompleteness: .complete
        )
        XCTAssertEqual(state, .unknown)
        XCTAssertNotEqual(state, .inactive)
        XCTAssertEqual(conf, .unknown)
    }

    func testCompleteSnapshotInactiveVerified() {
        let handles = OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let procs = ProcessTableSnapshot(names: ["Finder"], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let (state, conf, _, _) = ActiveStateResolver.resolve(
            entityPath: "/vm/rootfs.img",
            associatedProcesses: ["Claude"],
            processes: procs,
            handles: handles,
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        XCTAssertEqual(state, .inactive)
        XCTAssertEqual(conf, .verified)
    }

    func testCursorStoreDetectorFindsStores() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("p14-\(UUID().uuidString)").path
        let storeID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        let store = "\(home)/Library/Application Support/Cursor/snapshots/stores/\(storeID)"
        try FileManager.default.createDirectory(atPath: "\(store)/objects", withIntermediateDirectories: true)
        try Data("root_key=\(storeID)\n".utf8).write(to: URL(fileURLWithPath: "\(store)/baseline.marker"))
        try Data("x".utf8).write(to: URL(fileURLWithPath: "\(store)/objects/o"))
        let ws = "\(home)/Library/Application Support/Cursor/User/workspaceStorage/ws1"
        try FileManager.default.createDirectory(atPath: ws, withIntermediateDirectories: true)
        let project = "\(home)/Workspace/demo"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let json = "{\"folder\":\"file://\(project)\"}"
        try Data(json.utf8).write(to: URL(fileURLWithPath: "\(ws)/workspace.json"))
        // embed store id in json to create VERIFIED link
        try Data("{\"folder\":\"file://\(project)\",\"note\":\"\(storeID)\"}".utf8).write(to: URL(fileURLWithPath: "\(ws)/workspace.json"))
        let found = CursorStoresVerificationDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.entity.id.contains("cursor.snapshots.store.") })
        let linked = found.first { $0.entity.id == "cursor.snapshots.store.\(storeID)" }
        let wsRel = linked?.annotation?.relationships.first { $0.type == .belongsToWorkspace }
        XCTAssertEqual(linked?.annotation?.provenance.confidence, .verified)
        XCTAssertEqual(wsRel?.type, .belongsToWorkspace)
    }

    func testFolderNameOnlyWorkspaceStaysInferred() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("p14b-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/roots/demo-proj-abcdef", withIntermediateDirectories: true)
        try Data("x".utf8).write(to: URL(fileURLWithPath: "\(home)/Library/Application Support/Cursor/snapshots/roots/demo-proj-abcdef/r"))
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)
        // no Workspace/demo-proj
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let ref = found.first { $0.entity.id.contains("rootref") }
        let ws = ref?.annotation?.relationships.first { $0.type == .belongsToWorkspace }
        XCTAssertEqual(ws?.presence, .unknown)
        XCTAssertNotEqual(ws?.confidence, .verified)
    }

    func testCloudPathAloneNotSafeEvict() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("cld-\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: "\(home)/Library/CloudStorage/Dropbox", withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: URL(fileURLWithPath: "\(home)/Library/CloudStorage/Dropbox/f"))
        let found = CloudResolutionDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.annotation?.unknownReasons.contains(UnknownReasonCode.unknownRemoteCopy.rawValue) == true })
        let engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "x", principle: "x", rules: []))
        if let e = found.first {
            let d = engine.evaluate(EvaluationRequest(entity: e.entity, intendedAction: .cloudEvictOnly, evidence: EvidenceBundle(canonicalPath: e.entity.path), state: RuntimeState()))
            XCTAssertNotEqual(d.safetyClass, .green)
        }
    }

    func testVoiceMemosRecordingsAreUserContent() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vm-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings", withIntermediateDirectories: true)
        try Data("x".utf8).write(to: URL(fileURLWithPath: "\(home)/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/a.m4a"))
        let found = VoiceMemosDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let rec = found.first { $0.entity.id == "voicememos.recordings" }
        XCTAssertEqual(rec?.annotation?.lifecycle.role, .userContent)
        let sot = SourceOfTruthResolver.resolve(entity: rec!.entity, annotation: rec!.annotation, evidence: EvidenceBundle(canonicalPath: rec!.entity.path))
        XCTAssertEqual(sot.value, .true)
        XCTAssertEqual(sot.confidence, .verified)
    }

    func testDeepVerificationDoesNotChangeByteTotal() {
        let parent = AccountingInput(id: "cursor.snapshots.stores", path: "/s", inclusiveBytes: 100, safetyClass: .red, resolution: .l4SemanticEntity)
        let child = AccountingInput(id: "cursor.snapshots.store.a", path: "/s/a", inclusiveBytes: 40, safetyClass: .red, resolution: .l4SemanticEntity)
        let r0 = ByteAccountant.account([parent])
        let r1 = ByteAccountant.account([parent, child])
        XCTAssertEqual(r0.uniqueTotal, r1.uniqueTotal)
    }

    func testRootfsNotAutomaticallyRegenerable() {
        let entity = StorageEntity(id: "claude.vm.runtime", kind: .generatedBuild, category: "A", subcategory: "C", displayName: "r", path: "/tmp/vm_bundles/x/rootfs.img", logicalBytes: 10)
        let note = DetectionAnnotation(detectorID: "claude.vm", specificity: 100, semanticType: "CLAUDE_VM_RUNTIME_IMAGE", lifecycle: LifecycleEvidence(role: .runtime, roleConfidence: .inferred))
        let sot = SourceOfTruthResolver.resolve(entity: entity, annotation: note, evidence: EvidenceBundle(canonicalPath: entity.path))
        let regen = RegenerabilityResolver.resolve(entity: entity, annotation: note, evidence: EvidenceBundle(canonicalPath: entity.path), sourceOfTruth: sot)
        XCTAssertEqual(regen.value, .unknown)
    }
}
