import XCTest
@testable import SafetyCore
@testable import AppServices

final class P33C1AgentCLIPathAlignmentTests: XCTestCase {
    func testSiblingStoreIsNotExactMatch() {
        let home = "/Users/u/.local/share/cursor-agent/versions"
        let gs = "/Users/u/Library/Application Support/Cursor/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions"
        let rel = CursorAgentCLIPathAlignment.relationship(actualCanonical: gs, cleanupCanonical: home)
        XCTAssertEqual(rel, .siblingStore)
        XCTAssertFalse(CursorAgentCLIPathAlignment.cleanupCoversActualStore(
            relationship: rel, semanticClassMatch: true
        ))
    }

    func testExactRootMatchRequiresEqualCanonical() {
        let p = "/Users/u/.local/share/cursor-agent/versions"
        let rel = CursorAgentCLIPathAlignment.relationship(actualCanonical: p, cleanupCanonical: p)
        XCTAssertEqual(rel, .exactRootMatch)
        XCTAssertTrue(CursorAgentCLIPathAlignment.cleanupCoversActualStore(
            relationship: rel, semanticClassMatch: true
        ))
    }

    func testSamePathDifferentRoleDownloadCacheNotCoveredInstalled() {
        // Semantic mismatch: even if paths equal, storage class must match for coverage.
        let rel = CleanupTargetRelationship.exactRootMatch
        XCTAssertFalse(CursorAgentCLIPathAlignment.cleanupCoversActualStore(
            relationship: rel, semanticClassMatch: false
        ))
    }

    func testCleanupPathMismatchFixture() {
        let actual = ".../agent-cli/versions"
        let cleanup = ".../agent-cli/cache"
        // Different leaf → unrelated (after normalize they won't match)
        let rel = CursorAgentCLIPathAlignment.relationship(
            actualCanonical: "/tmp/agent-cli/versions",
            cleanupCanonical: "/tmp/agent-cli/cache"
        )
        XCTAssertEqual(rel, .unrelated)
        let cov = CursorAgentCLIPathAlignment.coverageForActualStoreVersion(
            relationship: rel, isCurrent: false, isFallbackWindow: false
        )
        XCTAssertEqual(cov, .notCovered)
        _ = actual; _ = cleanup
    }

    func testVersionCoverageSiblingStoreAllNotCovered() {
        let rel = CleanupTargetRelationship.siblingStore
        XCTAssertEqual(
            CursorAgentCLIPathAlignment.coverageForActualStoreVersion(
                relationship: rel, isCurrent: false, isFallbackWindow: false
            ),
            .notCovered
        )
        XCTAssertEqual(
            CursorAgentCLIPathAlignment.coverageForActualStoreVersion(
                relationship: rel, isCurrent: true, isFallbackWindow: false
            ),
            .notCovered
        )
    }

    func testExactMatchCurrentAndFallbackNotRemovable() {
        let rel = CleanupTargetRelationship.exactRootMatch
        XCTAssertEqual(
            CursorAgentCLIPathAlignment.coverageForActualStoreVersion(
                relationship: rel, isCurrent: true, isFallbackWindow: false
            ),
            .notCovered
        )
        XCTAssertEqual(
            CursorAgentCLIPathAlignment.coverageForActualStoreVersion(
                relationship: rel, isCurrent: false, isFallbackWindow: true
            ),
            .notCovered
        )
        XCTAssertEqual(
            CursorAgentCLIPathAlignment.coverageForActualStoreVersion(
                relationship: rel, isCurrent: false, isFallbackWindow: false
            ),
            .covered
        )
    }

    func testPotentialBytesOnlyCoveredInactive() {
        let bytes = CursorAgentCLIPathAlignment.potentialRecoveryBytes(versions: [
            ("cur", 100, .notCovered),
            ("fb", 90, .notCovered),
            ("old", 80, .covered),
            ("unk", 70, .unknown),
        ])
        XCTAssertEqual(bytes, 80)
    }

    func testEmptyCandidateWhenAllProtected() {
        let bytes = CursorAgentCLIPathAlignment.potentialRecoveryBytes(versions: [
            ("cur", 100, .notCovered),
            ("fb1", 90, .notCovered),
            ("fb2", 80, .notCovered),
        ])
        XCTAssertEqual(bytes, 0)
    }

    func testUnknownSelectionYieldsZeroPotentialNotFullRoot() {
        let bytes = CursorAgentCLIPathAlignment.potentialRecoveryBytes(versions: [
            ("a", 1_000_000_000, .unknown),
            ("b", 1_000_000_000, .unknown),
        ])
        XCTAssertEqual(bytes, 0)
    }

    func testParentBlastRadiusIsNotExactMatch() {
        let rel = CursorAgentCLIPathAlignment.relationship(
            actualCanonical: "/root/versions",
            cleanupCanonical: "/root"
        )
        XCTAssertEqual(rel, .targetIsParent)
        XCTAssertFalse(CursorAgentCLIPathAlignment.cleanupCoversActualStore(
            relationship: rel, semanticClassMatch: true
        ))
    }

    func testLegacyPathDoesNotCoverCurrent() {
        let cov = CursorAgentCLIPathAlignment.coverageForActualStoreVersion(
            relationship: .legacyRoot, isCurrent: false, isFallbackWindow: false
        )
        XCTAssertEqual(cov, .notCovered)
    }

    func testStateVscdbStillProtected() {
        XCTAssertFalse(CursorDatabaseRootCauseAnalyzer.rawDatabaseExecutable(dbOpen: true))
    }

    func testRemovedModelsAbsent() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: "\(home)/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-mlx"
        ))
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

    func testLiveSiblingMismatchIfPresent() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let actual = CursorAgentCLIPathResolver.versionsRoot(home: home)
        let cleanup = CursorAgentCLIPathResolver.homeVersionsRoot(home: home)
        guard FileManager.default.fileExists(atPath: actual) else {
            throw XCTSkip("GS agent-cli versions absent")
        }
        let rel = CursorAgentCLIPathAlignment.relationship(
            actualCanonical: actual,
            cleanupCanonical: cleanup
        )
        XCTAssertEqual(rel, .siblingStore)
        XCTAssertFalse(CursorAgentCLIPathAlignment.cleanupCoversActualStore(
            relationship: rel, semanticClassMatch: true
        ))
        // Full root must not be treated as potential when NOT_COVERED
        let (_, versions) = CursorAgentCLIInventory.inventory(home: home)
        let covered = versions.map {
            (
                id: $0.versionID,
                bytes: $0.uniqueBytes,
                coverage: CursorAgentCLIPathAlignment.coverageForActualStoreVersion(
                    relationship: rel,
                    isCurrent: $0.selectionState == "CURRENT_SELECTED",
                    isFallbackWindow: false
                )
            )
        }
        XCTAssertEqual(CursorAgentCLIPathAlignment.potentialRecoveryBytes(versions: covered), 0)
    }
}
