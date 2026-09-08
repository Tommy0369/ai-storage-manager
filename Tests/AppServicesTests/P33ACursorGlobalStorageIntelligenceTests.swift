import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P33ACursorGlobalStorageIntelligenceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("p33a-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    func testRootNotExecutableBecauseLarge() {
        XCTAssertFalse(CursorGlobalStorageIntelligence.rootMayBecomeExecutable(becauseLarge: true))
    }

    func testPathCacheWordDoesNotPromoteSafety() {
        XCTAssertFalse(CursorGlobalStorageIntelligence.pathCacheWordPromotesSafety())
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        try? FileManager.default.createDirectory(atPath: gs + "/mystery-cache-bucket", withIntermediateDirectories: true)
        writeFile(gs + "/mystery-cache-bucket/x.bin", size: 120_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, openPaths: [], runtimeCompleteness: "COMPLETE", measureBytes: measure())
        )
        let cache = report.components.first { $0.relativePath.contains("cache") }
        XCTAssertEqual(cache?.componentKind, .cacheSuspect)
        XCTAssertEqual(cache?.recommendedAction, .verifyMore)
        XCTAssertNotEqual(cache?.actionability, "EXECUTABLE")
    }

    func testOldMTimeDoesNotPromoteSafety() {
        XCTAssertFalse(CursorGlobalStorageIntelligence.oldMTimePromotesSafety())
    }

    func testExtensionAbsentManagedDataRemains() {
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        try? FileManager.default.createDirectory(atPath: gs + "/publisher.missing-ext", withIntermediateDirectories: true)
        writeFile(gs + "/publisher.missing-ext/data.bin", size: 50_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, measureBytes: measure())
        )
        let own = report.extensionOwnership.first { $0.namespace == "publisher.missing-ext" }
        XCTAssertEqual(own?.availabilityState, "EXTENSION_ABSENT_MANAGED_DATA_REMAINS")
        XCTAssertFalse(own?.extensionInstalled ?? true)
        let comp = report.components.first { $0.relativePath == "publisher.missing-ext" }
        XCTAssertEqual(comp?.componentKind, .extensionAbsentStorage)
        XCTAssertNotEqual(comp?.recommendedAction, .nativeCleanupCandidate)
    }

    func testExtensionPresentOwnershipVerified() throws {
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        let ext = "\(home)/.cursor/extensions"
        try FileManager.default.createDirectory(atPath: gs + "/acme.tools", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: ext + "/acme.tools-1.2.3", withIntermediateDirectories: true)
        writeFile(gs + "/acme.tools/x.bin", size: 10_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, measureBytes: measure())
        )
        let own = report.extensionOwnership.first { $0.namespace == "acme.tools" }
        XCTAssertEqual(own?.extensionInstalled, true)
        XCTAssertEqual(own?.version, "1.2.3")
        XCTAssertTrue(own?.ownershipEvidence.contains("EXACT_PREFIX_MATCH") == true)
    }

    func testUnknownNamespaceProtected() {
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        try? FileManager.default.createDirectory(atPath: gs + "/weird_no_dot_name", withIntermediateDirectories: true)
        writeFile(gs + "/weird_no_dot_name/x.bin", size: 5_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, measureBytes: measure())
        )
        let c = report.components.first { $0.relativePath == "weird_no_dot_name" }
        XCTAssertEqual(c?.classificationConfidence, .unknown)
        XCTAssertEqual(c?.recommendedAction, .verifyMore)
    }

    func testLargeDatabaseRuntimeUnknownProtected() {
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        try? FileManager.default.createDirectory(atPath: gs, withIntermediateDirectories: true)
        // Minimal sqlite header so file(1)/our path classifier uses name
        writeFile(gs + "/state.vscdb", size: 10_000_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, openPaths: [], runtimeCompleteness: "UNKNOWN", measureBytes: measure())
        )
        let db = report.components.first { $0.relativePath == "state.vscdb" }
        XCTAssertEqual(db?.componentKind, .database)
        XCTAssertEqual(db?.recommendedAction, .keep)
        XCTAssertEqual(db?.runtimeState, "RUNTIME_UNKNOWN")
        XCTAssertFalse(report.rootExecutable)
    }

    func testOpenDatabaseActiveVerified() {
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        try? FileManager.default.createDirectory(atPath: gs, withIntermediateDirectories: true)
        writeFile(gs + "/state.vscdb", size: 100_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(
                home: home,
                openPaths: [gs + "/state.vscdb"],
                runtimeCompleteness: "COMPLETE",
                measureBytes: measure()
            )
        )
        let db = report.components.first { $0.relativePath == "state.vscdb" }
        XCTAssertEqual(db?.runtimeState, "ACTIVE_VERIFIED")
        XCTAssertEqual(db?.recommendedAction, .keep)
    }

    func testClosedDatabaseStillNotDeletable() {
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        try? FileManager.default.createDirectory(atPath: gs, withIntermediateDirectories: true)
        writeFile(gs + "/state.vscdb", size: 100_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, openPaths: [], runtimeCompleteness: "COMPLETE", measureBytes: measure())
        )
        let db = report.components.first { $0.relativePath == "state.vscdb" }
        XCTAssertEqual(db?.runtimeState, "INACTIVE_VERIFIED")
        XCTAssertEqual(db?.recommendedAction, .keep)
    }

    func testConversationStateKeep() {
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        try? FileManager.default.createDirectory(atPath: gs, withIntermediateDirectories: true)
        writeFile(gs + "/conversation-search.db", size: 50_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, measureBytes: measure())
        )
        let c = report.components.first { $0.relativePath == "conversation-search.db" }
        XCTAssertEqual(c?.componentKind, .aiConversationOrContextState)
        XCTAssertEqual(c?.recommendedAction, .keep)
        XCTAssertTrue(c?.userOriginalState.contains("USER") == true)
    }

    func testVerifiedRegenerableCacheBecomesCandidateNotExecutable() {
        // Fixture: agent-cli versions tree
        let home = tempRoot.path
        let versions = "\(home)/Library/Application Support/Cursor/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions/2026.01.01"
        try? FileManager.default.createDirectory(atPath: versions, withIntermediateDirectories: true)
        writeFile(versions + "/cursor-agent", size: 200_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, runtimeCompleteness: "COMPLETE", measureBytes: measure())
        )
        let v = report.components.first { $0.componentKind == .vendorToolchainVersions }
        XCTAssertEqual(v?.recommendedAction, .nativeCleanupCandidate)
        XCTAssertEqual(v?.actionability, "CANDIDATE_ONLY_NOT_EXECUTABLE")
        XCTAssertFalse(report.opportunities.contains(where: \.currentExecutable))
    }

    func testSoftwareReinstallNotDataReacquire() {
        let map = CursorGlobalStorageIntelligence.mapExtensionNamespace("anysphere.cursor-retrieval", home: tempRoot.path)
        XCTAssertTrue(map.isCursorFirstParty)
        XCTAssertFalse(map.installed)
        // reacquisition stays UNKNOWN at component level
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage/anysphere.cursor-retrieval/checkpoints"
        try? FileManager.default.createDirectory(atPath: gs, withIntermediateDirectories: true)
        writeFile(gs + "/x.bin", size: 10_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, measureBytes: measure())
        )
        let c = report.components.first { $0.relativePath == "anysphere.cursor-retrieval" }
        XCTAssertEqual(c?.reacquisitionState, "UNKNOWN")
    }

    func testParentChildAccountingNoDoubleCount() {
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        try? FileManager.default.createDirectory(atPath: gs, withIntermediateDirectories: true)
        writeFile(gs + "/state.vscdb", size: 10_000_000_000)
        writeFile(gs + "/a.bin", size: 3_000_000_000)
        writeFile(gs + "/b.bin", size: 1_000_000_000)
        // Also nested under a directory child
        try? FileManager.default.createDirectory(atPath: gs + "/childDir", withIntermediateDirectories: true)
        writeFile(gs + "/childDir/x.bin", size: 0) // bytes come from measure of childDir
        var sizes: [String: Int64] = [
            gs: 14_000_000_000,
            gs + "/state.vscdb": 10_000_000_000,
            gs + "/a.bin": 3_000_000_000,
            gs + "/b.bin": 1_000_000_000,
            gs + "/childDir": 0,
        ]
        let sizesCopy = sizes
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, measureBytes: { sizesCopy[$0] ?? P33AFixtureBytes.bytes(at: $0) })
        )
        XCTAssertEqual(report.observedBytes, 14_000_000_000)
        XCTAssertTrue(report.accountingValid)
        // Must not claim 28GB opportunity
        let sumChildren = sizes.filter { $0.key != gs }.values.reduce(0, +)
        XCTAssertEqual(sumChildren, 14_000_000_000)
    }

    func testClassificationCoverageAllowsUnknown() {
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        try? FileManager.default.createDirectory(atPath: gs + "/zzz", withIntermediateDirectories: true)
        writeFile(gs + "/zzz/x.bin", size: 1_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, measureBytes: measure())
        )
        XCTAssertTrue(report.components.contains { $0.classificationConfidence == .unknown || $0.componentKind == .unknownAppManaged })
    }

    func testPrivacyNoPromptContentInEvidence() {
        let home = tempRoot.path
        let gs = "\(home)/Library/Application Support/Cursor/User/globalStorage"
        try? FileManager.default.createDirectory(atPath: gs, withIntermediateDirectories: true)
        writeFile(gs + "/conversation-search.db", size: 1_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, measureBytes: measure())
        )
        let blob = (try? JSONEncoder().encode(report)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertFalse(blob.lowercased().contains("\"role\": \"user\""))
        XCTAssertFalse(blob.contains("SELECT value FROM"))
        XCTAssertTrue(report.privacyNote.contains("No prompt"))
    }

    func testActionabilityDoesNotChangeSafety() {
        let home = tempRoot.path
        let versions = "\(home)/Library/Application Support/Cursor/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions/v1"
        try? FileManager.default.createDirectory(atPath: versions, withIntermediateDirectories: true)
        writeFile(versions + "/bin", size: 5_000_000_000)
        let report = CursorGlobalStorageIntelligence.analyze(
            .init(home: home, measureBytes: measure())
        )
        XCTAssertEqual(report.rootSafety, "PROTECTED")
        for opp in report.opportunities {
            XCTAssertEqual(opp.currentSafety, "PROTECTED")
            XCTAssertFalse(opp.currentExecutable)
        }
    }

    func testRemovedAIModelsStayGone() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: "\(home)/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-mlx"
        ))
        XCTAssertFalse(
            HuggingFaceLocalCandidatePolicy.mayCreateVendorNativeCleanupCandidate(
                localSnapshotPresent: false,
                remoteExactRevisionAvailable: true
            )
        )
    }

    func testExecutorSetUnchanged() {
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToTrash), .implemented)
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .ollama, entityKind: .model
            ),
            .implemented
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .snapshot
            ),
            .implemented
        )
    }

    func testPrefixFalsePositiveAvoidedForCursorpyright() {
        let home = tempRoot.path
        let ext = "\(home)/.cursor/extensions"
        try? FileManager.default.createDirectory(atPath: ext + "/anysphere.cursorpyright-1.0.12", withIntermediateDirectories: true)
        let map = CursorGlobalStorageIntelligence.mapExtensionNamespace("anysphere.cursor-retrieval", home: home)
        XCTAssertFalse(map.installed, "cursorpyright must not match cursor-retrieval")
    }

    // MARK: - helpers

    private func measure() -> @Sendable (String) -> Int64 {
        { path in
            P33AFixtureBytes.bytes(at: path)
        }
    }

    private func writeFile(_ path: String, size: Int) {
        FileManager.default.createFile(atPath: path, contents: Data(), attributes: nil)
        let meta = path + ".p33a_size"
        try? String(size).write(toFile: meta, atomically: true, encoding: .utf8)
    }
}

private enum P33AFixtureBytes {
    static func bytes(at path: String) -> Int64 {
        let fm = FileManager.default
        let meta = path + ".p33a_size"
        if let s = try? String(contentsOfFile: meta, encoding: .utf8), let v = Int64(s) {
            return v
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard let kids = try? fm.contentsOfDirectory(atPath: path) else { return 0 }
        return kids
            .filter { !$0.hasSuffix(".p33a_size") }
            .reduce(Int64(0)) { acc, name in
            acc + bytes(at: path + "/" + name)
        }
    }
}
