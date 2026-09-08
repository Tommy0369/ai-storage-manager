import XCTest
@testable import SafetyCore

final class GoldenSafetyTests: XCTestCase {
    var engine: SafetyRuleEngine!
    var home: String!

    override func setUp() {
        home = FileManager.default.homeDirectoryForCurrentUser.path
        let url = knowledgeURL()
        do {
            let doc = try KnowledgeBaseLoader().load(from: url)
            XCTAssertGreaterThanOrEqual(doc.rules.count, 40)
            engine = SafetyRuleEngine(knowledge: doc, protection: UserProtectionStore())
        } catch {
            XCTFail("KB load failed from \(url.path): \(error)")
            engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "x", principle: "x", rules: []), protection: UserProtectionStore())
        }
    }

    func knowledgeURL() -> URL {
        let this = URL(fileURLWithPath: #filePath)
        let root = this
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root
            .appendingPathComponent("Sources/SafetyCore/Resources/knowledge/compiled_rules_v0.1.json")
    }

    func entity(_ id: String, path: String, kind: EntityKind = .cache, bytes: Int64 = 1_000) -> StorageEntity {
        StorageEntity(
            id: id,
            kind: kind,
            category: "test",
            subcategory: "test",
            displayName: id,
            path: path,
            logicalBytes: bytes
        )
    }

    func evidence(
        path: String,
        regenerable: PredicateValue = .true,
        sourceOfTruth: PredicateValue = .false,
        open: PredicateValue = .false,
        proc: PredicateValue = .false,
        symlink: PredicateValue = .false,
        extra: [String: PredicateValue] = [:],
        icloud: PredicateValue = .unknown,
        syncDelete: PredicateValue = .false
    ) -> EvidenceBundle {
        EvidenceBundle(
            canonicalPath: path,
            ownerIsCurrentUser: .true,
            isSymlink: symlink,
            iCloudEvictable: icloud,
            openFileHandle: open,
            owningProcessRunning: proc,
            sourceOfTruth: sourceOfTruth,
            regenerable: regenerable,
            syncWouldDeleteRemote: syncDelete,
            extra: extra,
            confidence: 0.9,
            predicateConfidence: [
                "canonical_path": .verified,
                "not_symlink": symlink == .unknown ? .unknown : .verified,
                "no_open_file_handle": open == .unknown ? .unknown : .verified,
                "owning_process_not_running": proc == .unknown ? .unknown : .verified,
                "not_source_of_truth": sourceOfTruth == .unknown ? .unknown : .verified,
                "regenerable": regenerable == .unknown ? .unknown : .verified,
                "sync_would_not_delete_remote": syncDelete == .unknown ? .unknown : .verified,
                "icloud_evictable": icloud == .unknown ? .unknown : .verified,
            ]
        )
    }

    func eval(
        path: String,
        action: ActionMode = .moveToTrash,
        kind: EntityKind = .cache,
        state: RuntimeState = RuntimeState(),
        evidence: EvidenceBundle? = nil
    ) -> SafetyDecision {
        let e = entity(path, path: path, kind: kind)
        let ev = evidence ?? self.evidence(path: path)
        return engine.evaluate(EvaluationRequest(entity: e, intendedAction: action, evidence: ev, state: state))
    }

    func testFalseGreenKPI_systemPathsNeverGreen() {
        for path in ["/System/Library", "/usr/bin/swift", "/bin/ls", "/sbin/mount"] {
            let d = eval(path: path)
            XCTAssertNotEqual(d.safetyClass, .green, path)
            XCTAssertEqual(d.action, .hardBlock)
        }
    }

    func testKeychainHardBlock() {
        let d = eval(path: "\(home!)/Library/Keychains/login.keychain-db", kind: .credentials)
        XCTAssertNotEqual(d.safetyClass, .green)
        XCTAssertEqual(d.action, .hardBlock)
    }

    func testUserDocumentsProtected() {
        let d = eval(path: "\(home!)/Documents/invoice.pdf", kind: .userOriginal)
        XCTAssertEqual(d.evaluationLayer, .userProtection)
        XCTAssertNotEqual(d.safetyClass, .green)
    }

    func testPhotosProtected() {
        let d = eval(path: "\(home!)/Pictures/IMG_0001.heic", kind: .userOriginal)
        XCTAssertNotEqual(d.safetyClass, .green)
    }

    func testDerivedDataGreenOnlyWhenPredicatesHold() {
        let path = "\(home!)/Library/Developer/Xcode/DerivedData/App-abc"
        let good = eval(
            path: path,
            evidence: evidence(path: path)
        )
        XCTAssertEqual(good.safetyClass, .green)
        XCTAssertEqual(good.matchedRuleID, "xcode.derived_data")
        XCTAssertNotNil(good.safetyScore)
        XCTAssertTrue(good.requiresUserApproval)

        let unknown = eval(
            path: path,
            evidence: evidence(path: path, open: .unknown)
        )
        XCTAssertEqual(unknown.safetyClass, .unknown)
        XCTAssertNil(unknown.safetyScore)
    }

    func testUnknownNeverPromotesToGreen() {
        let d = eval(path: "/tmp/some-random-blob-xyz")
        XCTAssertEqual(d.safetyClass, .unknown)
        XCTAssertEqual(d.evaluationLayer, .unknownFallback)
        XCTAssertNil(d.safetyScore)
    }

    func testScoreDoesNotPromote() {
        let path = "/tmp/some-random-blob-xyz"
        var d = eval(path: path)
        XCTAssertEqual(d.safetyClass, .unknown)
        d.safetyScore = SafetyScore(value: 99)
        XCTAssertEqual(d.safetyClass, .unknown)
    }

    func testSymlinkNotFollowedIsUnknown() {
        let path = "\(home!)/Library/Caches/foo"
        let d = eval(path: path, evidence: evidence(path: path, symlink: .true))
        XCTAssertEqual(d.safetyClass, .unknown)
        XCTAssertTrue(d.reasonCodes.contains("SYMLINK_NOT_FOLLOWED"))
    }

    func testActiveProcessBlocks() {
        let path = "\(home!)/Library/Developer/Xcode/DerivedData/App-abc"
        let d = eval(path: path, state: RuntimeState(owningProcessRunning: true))
        XCTAssertEqual(d.safetyClass, .red)
        XCTAssertEqual(d.evaluationLayer, .activeUse)
    }

    func testCloudDeleteIsRedEvictCanBeGreen() {
        let path = "\(home!)/Library/Mobile Documents/com~apple~CloudDocs/file.pdf"
        let ev = evidence(path: path, icloud: .true, syncDelete: .false)
        let del = eval(path: path, action: .moveToTrash, evidence: ev)
        XCTAssertEqual(del.safetyClass, .red)

        let evict = eval(path: path, action: .cloudEvictOnly, evidence: ev)
        XCTAssertEqual(evict.safetyClass, .green)
        XCTAssertEqual(evict.action, .cloudEvictOnly)
    }

    func testDockerVolumeRed() {
        let d = eval(path: "entity://docker/volumes/pgdata", kind: .dockerVolume)
        XCTAssertEqual(d.safetyClass, .red)
        XCTAssertEqual(d.matchedRuleID, "docker.volumes")
    }

    func testGitSourceRed() {
        let d = eval(path: "/tmp/proj/.git/objects/pack/pack-1.pack", kind: .gitHistory)
        XCTAssertEqual(d.safetyClass, .red)
    }

    func testNodeModulesNotAutoGreen() {
        let path = "/tmp/proj/node_modules/left-pad"
        let d = eval(
            path: path,
            evidence: evidence(path: path, extra: ["manifest_exists": .true, "lockfile_exists": .true])
        )
        XCTAssertNotEqual(d.safetyClass, .green)
        XCTAssertEqual(d.matchedRuleID, "node.node_modules")
    }

    func testXcodeArchivesNotGreen() {
        let path = "\(home!)/Library/Developer/Xcode/Archives/2026-08-25/App.xcarchive"
        let d = eval(path: path)
        XCTAssertNotEqual(d.safetyClass, .green)
        XCTAssertEqual(d.matchedRuleID, "xcode.archives")
    }

    func testCursorLogsNotWholeAppSupport() {
        let logs = "\(home!)/Library/Application Support/Cursor/logs/main.log"
        let whole = "\(home!)/Library/Application Support/Cursor/User/settings.json"
        XCTAssertEqual(eval(path: logs, evidence: evidence(path: logs)).matchedRuleID, "ai.cursor_logs")
        XCTAssertEqual(eval(path: whole).matchedRuleID, "ai.cursor_app_support")
        XCTAssertEqual(eval(path: whole).safetyClass, .red)
    }

    func testClaudeMdRed() {
        let d = eval(path: "/tmp/proj/CLAUDE.md", kind: .userOriginal)
        XCTAssertEqual(d.safetyClass, .red)
    }

    func testPermanentDeleteForbidden() {
        let path = "\(home!)/Library/Caches/foo"
        let d = eval(path: path, action: .permanentDelete, evidence: evidence(path: path))
        XCTAssertEqual(d.action, .hardBlock)
        XCTAssertNotEqual(d.safetyClass, .green)
    }

    func testLLMCannotOverrideClass() {
        let path = "/tmp/unknown-thing"
        let decision = eval(path: path)
        let semantic = LLMBoundary.freeze(decision)
        XCTAssertEqual(semantic.safetyClass, .unknown)
        XCTAssertNil(semantic.safetyScore)
    }

    func testActionPlannerForbidsPermanentAndHardBlock() {
        let planner = ActionPlanner()
        let path = "/System/Library"
        let plan = planner.plan(eval(path: path))
        XCTAssertTrue(plan.forbidden)
        XCTAssertFalse(plan.executableInV01)
    }

    func testVerificationSeparatesLogicalPhysical() {
        let report = ResultVerifier().report(
            beforeLogical: 117_000_000_000,
            afterLogical: 0,
            targetStillPresent: false,
            physicalReclaimed: 12_000_000_000,
            availableDelta: 10_000_000_000,
            resourceStillValid: true
        )
        XCTAssertEqual(report.logicalBytesRemoved, 117_000_000_000)
        XCTAssertNotEqual(report.logicalBytesRemoved, report.physicalBytesReclaimed)
        XCTAssertTrue(report.notes.contains("APFS_LOGICAL_PHYSICAL_MISMATCH"))
    }

    func testAuditDoesNotStoreFullPath() {
        let event = AuditEvent(
            entityID: "x",
            path: "\(home!)/Documents/secret-tax-return.pdf",
            logicalBytes: 10,
            previousClass: nil,
            safetyClass: .red,
            reasonCodes: ["USER_PROTECTION"],
            action: .hardBlock,
            userApproved: nil,
            executionOK: nil,
            verificationNotes: []
        )
        XCTAssertEqual(event.pathBasename, "secret-tax-return.pdf")
        XCTAssertFalse(event.pathBasename.contains("Documents"))
    }

    func testApplicationSupportFolderNotGreen() {
        let path = "\(home!)/Library/Application Support/SomeApp/db.sqlite"
        let d = eval(path: path, kind: .applicationSupport)
        XCTAssertNotEqual(d.safetyClass, .green)
    }

    func testUserProtectionNaturalLanguagePropagates() {
        let store = UserProtectionStore()
        store.add(UserProtectionRule(
            id: "protect.custom",
            label: "Tax",
            pathPrefixes: ["/tmp/tax"],
            naturalLanguageOrigin: "税務は消すな"
        ))
        engine = SafetyRuleEngine(knowledge: engine.knowledge, protection: store)
        let d = eval(path: "/tmp/tax/2025.pdf", kind: .userOriginal)
        XCTAssertEqual(d.evaluationLayer, .userProtection)
    }
}
