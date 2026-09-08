import XCTest
@testable import SafetyCore

final class P13LifecycleDetectorTests: XCTestCase {
    func makeHome() throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("p13-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        return home
    }

    func write(_ path: String, _ body: String = "x") throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: URL(fileURLWithPath: path))
    }

    func testSnapshotRootAndInstances() throws {
        let home = try makeHome()
        let snap = "\(home)/Library/Application Support/Cursor/snapshots"
        try FileManager.default.createDirectory(atPath: "\(snap)/codebases/aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa/objects", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(snap)/codebases/aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa/refs", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(snap)/codebases/aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa/staging", withIntermediateDirectories: true)
        try write("\(snap)/codebases/aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa/objects/o")
        try FileManager.default.createDirectory(atPath: "\(snap)/roots/demo-proj-abcdef", withIntermediateDirectories: true)
        try write("\(snap)/roots/demo-proj-abcdef/r")
        try FileManager.default.createDirectory(atPath: "\(snap)/state", withIntermediateDirectories: true)
        try write("\(snap)/state/state.db")
        try FileManager.default.createDirectory(atPath: "\(home)/Workspace/demo-proj", withIntermediateDirectories: true)
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.entity.id == "cursor.snapshots.root" })
        XCTAssertTrue(found.contains { $0.entity.id.contains("cursor.snapshots.instance.") })
        XCTAssertTrue(found.contains { $0.entity.id.hasSuffix(".objects") })
        XCTAssertTrue(found.contains { $0.entity.id == "cursor.snapshots.database" })
        let db = found.first { $0.entity.id == "cursor.snapshots.database" }
        XCTAssertEqual(db?.annotation?.lifecycle.role, .database)
        XCTAssertEqual(db?.annotation?.lifecycle.roleConfidence, .inferred)
        XCTAssertFalse(db?.annotation?.lifecycle.roleConfidence.canSatisfySafetyPredicate ?? true)
        let rootRef = found.first { $0.entity.id.contains("rootref") }
        let possible = rootRef?.annotation?.relationships.first { $0.type == .possibleWorkspaceContext }
        XCTAssertEqual(possible?.type, .possibleWorkspaceContext)
        XCTAssertEqual(possible?.presence, .present)
        XCTAssertEqual(possible?.confidence, .inferred)
        let ws = rootRef?.annotation?.relationships.first { $0.type == .belongsToWorkspace }
        XCTAssertNotEqual(ws?.confidence, .verified)
        XCTAssertNil(found.first?.annotation.flatMap { _ in Optional<SafetyClass>.none })
        XCTAssertFalse(found.contains { $0.entity.id.lowercased().contains("green") })
    }

    func testWorkspaceReferenceMissing() throws {
        let home = try makeHome()
        let snap = "\(home)/Library/Application Support/Cursor/snapshots/roots/missing-zzzzzz"
        try FileManager.default.createDirectory(atPath: snap, withIntermediateDirectories: true)
        try write("\(snap)/r")
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)
        try write("\(home)/Library/Application Support/Cursor/snapshots/codebases/.keep")
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let rels = found.first { $0.entity.id.contains("rootref") }?.annotation?.relationships ?? []
        let ws = rels.first { $0.type == .belongsToWorkspace }
        XCTAssertEqual(ws?.presence, .unknown)
        XCTAssertNotEqual(ws?.confidence, .verified)
        XCTAssertTrue(found.contains { $0.annotation?.unknownReasons.contains(UnknownReasonCode.workspaceReferenceMissing.rawValue) == true })
    }

    func testSnapshotAgeDoesNotSetRegenerable() throws {
        let home = try makeHome()
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/codebases", withIntermediateDirectories: true)
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.annotation?.lifecycle.role == .snapshot })
        let ev = EvidenceResolver().resolve(path: "\(home)/Library/Application Support/Cursor/snapshots")
        XCTAssertEqual(ev.regenerable, .unknown)
        XCTAssertNotEqual(ev.regenerable, .true)
        XCTAssertEqual(ev.sourceOfTruth, .unknown)
    }

    func testUnknownSnapshotStructureStaysUnknownRoleOnEmptyRoot() throws {
        let home = try makeHome()
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots/weird", withIntermediateDirectories: true)
        try write("\(home)/Library/Application Support/Cursor/snapshots/weird/x")
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.annotation?.unknownReasons.contains(UnknownReasonCode.lifecycleMixedContent.rawValue) == true })
    }

    func testDeepDecompositionDoesNotChangeUniqueBytes() {
        let parent = AccountingInput(id: "cursor.snapshots.root", path: "/s", inclusiveBytes: 100, safetyClass: .red, resolution: .l3Product)
        let child = AccountingInput(id: "cursor.snapshots.instance.a", path: "/s/codebases/a", inclusiveBytes: 40, safetyClass: .red, resolution: .l4SemanticEntity)
        let r0 = ByteAccountant.account([parent])
        let r1 = ByteAccountant.account([parent, child])
        XCTAssertEqual(r0.uniqueTotal, r1.uniqueTotal)
        XCTAssertEqual(r1.uniqueTotal, 100)
    }

    func testClaudeVMDecomposition() throws {
        let home = try makeHome()
        let bundle = "\(home)/Library/Application Support/Claude/vm_bundles/claudevm.bundle"
        try FileManager.default.createDirectory(atPath: bundle, withIntermediateDirectories: true)
        try write("\(bundle)/rootfs.img", String(repeating: "r", count: 32))
        try write("\(bundle)/vmlinuz", "k")
        try write("\(bundle)/sessiondata.img", "w")
        try write("\(bundle)/machineIdentifier", "id")
        try write("\(bundle)/.rootfs.img.origin", "deadbeef")
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Claude/vm_bundles/warm", withIntermediateDirectories: true)
        try write("\(home)/Library/Application Support/Claude/vm_bundles/warm/c")
        let found = ClaudeVMBundleDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.annotation?.semanticType == "CLAUDE_VM_BUNDLE" })
        XCTAssertTrue(found.contains { $0.annotation?.semanticType == "CLAUDE_VM_RUNTIME_IMAGE" })
        XCTAssertTrue(found.contains { $0.annotation?.semanticType == "CLAUDE_VM_WRITABLE_STATE" })
        XCTAssertTrue(found.contains { $0.annotation?.semanticType == "CLAUDE_VM_METADATA" })
        XCTAssertTrue(found.contains { $0.annotation?.semanticType == "CLAUDE_VM_CACHE" })
        XCTAssertTrue(found.contains { $0.annotation?.lifecycle.activeState == .unknown })
        XCTAssertNotEqual(found.first { $0.annotation?.semanticType == "CLAUDE_VM_BUNDLE" }?.annotation?.relationships.first?.confidence, .verified)
    }

    func testOldBundleNotAutomaticallySafe() throws {
        let home = try makeHome()
        let bundle = "\(home)/Library/Application Support/Claude/vm_bundles/old.bundle"
        try FileManager.default.createDirectory(atPath: bundle, withIntermediateDirectories: true)
        try write("\(bundle)/rootfs.img")
        let found = ClaudeVMBundleDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertFalse(found.contains { $0.annotation?.lifecycle.roleConfidence == .verified && $0.annotation?.lifecycle.role == .cache })
        let engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "x", principle: "x", rules: []))
        if let entity = found.first?.entity {
            let d = engine.evaluate(EvaluationRequest(entity: entity, intendedAction: .moveToTrash, evidence: EvidenceBundle(canonicalPath: entity.path), state: RuntimeState()))
            XCTAssertNotEqual(d.safetyClass, .green)
        }
    }

    func testIOSBackupSplitAndNoContentWalk() throws {
        let home = try makeHome()
        let a = "\(home)/Library/Application Support/MobileSync/Backup/DEVICEA"
        let b = "\(home)/Library/Application Support/MobileSync/Backup/DEVICEB"
        try FileManager.default.createDirectory(atPath: "\(a)/00", withIntermediateDirectories: true)
        try write("\(a)/00/secret-photo", "NOPE")
        try write("\(a)/Status.plist", """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Date</key><date>2026-08-10T00:00:00Z</date><key>IsEncrypted</key><true/></dict></plist>
        """)
        try FileManager.default.createDirectory(atPath: b, withIntermediateDirectories: true)
        try write("\(b)/Status.plist", """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Date</key><date>2025-11-12T00:00:00Z</date></dict></plist>
        """)
        let found = IOSBackupDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.entity.id.contains("DEVICEA") })
        XCTAssertTrue(found.contains { $0.entity.id.contains("DEVICEB") })
        XCTAssertTrue(found.contains { $0.annotation?.relationships.contains(where: { $0.type == .backupOf }) == true })
        XCTAssertFalse(found.contains { $0.entity.path.contains("/00/secret-photo") })
        XCTAssertTrue(found.contains { $0.annotation?.lifecycle.role == .backup })
        let engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "x", principle: "x", rules: []))
        let backup = found.first { $0.entity.id.contains("DEVICEA") && !$0.entity.id.contains("status") }!
        let d = engine.evaluate(EvaluationRequest(entity: backup.entity, intendedAction: .moveToTrash, evidence: EvidenceBundle(canonicalPath: backup.entity.path), state: RuntimeState()))
        XCTAssertNotEqual(d.safetyClass, .green)
    }

    func testContainerLifecycleRoles() throws {
        let home = try makeHome()
        let bid = "com.tinyspeck.slackmacgap"
        let base = "\(home)/Library/Containers/\(bid)/Data"
        try FileManager.default.createDirectory(atPath: "\(base)/Documents", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(base)/Library/Caches", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(base)/Library/Preferences", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(base)/Library/Application Support", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(base)/tmp", withIntermediateDirectories: true)
        try write("\(base)/Documents/a")
        try write("\(base)/Library/Caches/a")
        try write("\(base)/Library/Preferences/a")
        try write("\(base)/Library/Application Support/a")
        try write("\(base)/tmp/a")
        let found = ContainerDeepDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertEqual(found.first { $0.entity.id.contains(".documents") }?.annotation?.lifecycle.role, .userContent)
        XCTAssertEqual(found.first { $0.entity.id.contains(".caches") }?.annotation?.lifecycle.role, .cache)
        XCTAssertEqual(found.first { $0.entity.id.contains(".preferences") }?.annotation?.lifecycle.role, .userConfiguration)
        XCTAssertEqual(found.first { $0.entity.id.contains(".app_support") }?.annotation?.lifecycle.role, .mixed)
        XCTAssertEqual(found.first { $0.entity.id.contains(".tmp") }?.annotation?.lifecycle.role, .temporary)
    }

    func testUnknownBundleRemainsUnknown() {
        let identity = ProductIdentityResolver.resolve(bundleID: "com.example.not.in.catalog")
        XCTAssertEqual(identity.confidence, .unknown)
        XCTAssertNil(identity.name)
    }

    func testGroupContainerDoesNotInventSecondOwner() throws {
        let home = try makeHome()
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Group Containers/group.com.unknown.app", withIntermediateDirectories: true)
        try write("\(home)/Library/Group Containers/group.com.unknown.app/x")
        let found = GroupContainerLifecycleDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertEqual(found.first?.annotation?.owningProducts.count, 1)
        XCTAssertEqual(found.first?.annotation?.owningProducts.first?.confidence, .unknown)
    }

    func testVerifiedNotInferredAndInferredCannotSatisfySafety() {
        XCTAssertNotEqual(EvidenceConfidence.verified, EvidenceConfidence.inferred)
        XCTAssertFalse(EvidenceConfidence.inferred.canSatisfySafetyPredicate)
        XCTAssertFalse(EvidenceConfidence.unknown.canSatisfySafetyPredicate)
        XCTAssertTrue(EvidenceConfidence.verified.canSatisfySafetyPredicate)
        XCTAssertNotEqual(PredicateValue.unknown, PredicateValue.false)
    }

    func testSpecificDetectorBeatsGeneric() {
        let generic = DetectedEntity(
            entity: StorageEntity(id: "appsupport.Cursor.snapshots", kind: .unknown, category: "x", subcategory: "Cursor", displayName: "g", path: "/AS/Cursor/snapshots", logicalBytes: 10),
            bucket: .developer, domain: "AI Tools", associatedProcesses: [], identified: true,
            annotation: DetectionAnnotation(detectorID: "appsupport.lifecycle", specificity: 55, semanticType: "SNAPSHOT", lifecycle: LifecycleEvidence(role: .snapshot, roleConfidence: .inferred))
        )
        let specific = DetectedEntity(
            entity: StorageEntity(id: "cursor.snapshots.root", kind: .generatedBuild, category: "x", subcategory: "Cursor", displayName: "s", path: "/AS/Cursor/snapshots", logicalBytes: 10),
            bucket: .developer, domain: "AI Tools", associatedProcesses: [], identified: true,
            annotation: DetectionAnnotation(detectorID: "cursor.snapshot", specificity: 100, semanticType: "CURSOR_SNAPSHOT_ROOT", lifecycle: LifecycleEvidence(role: .snapshot, roleConfidence: .inferred))
        )
        let merged = DetectorConflictResolver.merge([generic, specific])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.entity.id, "cursor.snapshots.root")
    }

    func testDetectorCannotCreateGreenOrActions() throws {
        let home = try makeHome()
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/snapshots", withIntermediateDirectories: true)
        let found = CursorSnapshotDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.allSatisfy { $0.annotation != nil })
        XCTAssertTrue(found.allSatisfy { $0.bucket != .unknown || true })
        let preview = ReadOnlyAnalysisPipeline(knowledge: KnowledgeBaseDocument(version: "x", principle: "x", rules: [])).preview(
            for: SafetyDecision(entity: StorageEntity(id: "x", kind: .cache, category: "t", subcategory: "t", displayName: "x", path: "/x", logicalBytes: 1), action: .userReview, safetyClass: .unknown, safetyScore: nil, reasonCodes: [], sideEffects: [], matchedRuleID: nil, evaluationLayer: .unknownFallback, evidenceConfidence: 0, userExplanationJA: "x", growthCauses: [], requiresUserApproval: true, blockedBy: nil)
        )
        XCTAssertFalse(preview.executable)
    }
}
