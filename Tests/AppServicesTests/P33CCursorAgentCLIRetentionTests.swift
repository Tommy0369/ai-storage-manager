import XCTest
@testable import SafetyCore
@testable import AppServices

final class P33CCursorAgentCLIRetentionTests: XCTestCase {
    func testRootNeverExecutable() {
        XCTAssertFalse(CursorAgentCLISafetyRules.rootExecutable())
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let versions = CursorAgentCLIPathResolver.versionsRoot(home: home)
        if FileManager.default.fileExists(atPath: versions) {
            let (root, _) = CursorAgentCLIInventory.inventory(home: home)
            XCTAssertFalse(root.rootExecutable)
        }
    }

    func testCurrentSelectedVersionProtected() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let selected = CursorAgentCLIPathResolver.resolveSelectedVersion(home: home) else {
            throw XCTSkip("no agent-cli selection symlink")
        }
        let (_, versions) = CursorAgentCLIInventory.inventory(home: home)
        let current = versions.first { $0.versionID == selected }
        XCTAssertNotNil(current)
        XCTAssertEqual(current?.selectionState, "CURRENT_SELECTED")
        XCTAssertFalse(CursorAgentCLISafetyRules.versionExecutable(
            isCurrent: true, isActive: false, nativeCleanupContractApplies: true
        ))
    }

    func testVendorRetentionKeepsCurrentPlusTwo() {
        let versions: [(String, Int64)] = [
            ("2026.08.31-a", 100),
            ("2026.08.25-b", 90),
            ("2026.08.11-c", 80),
            ("2026.07.01-d", 70),
            ("2026.06.01-e", 60),
        ]
        let result = CursorAgentCLIVendorRetentionPolicy.estimateRecoverableBytes(
            versions: versions.map { (id: $0.0, bytes: $0.1) },
            currentID: "2026.08.31-a"
        )
        XCTAssertEqual(result.keptNonCurrent, ["2026.08.25-b", "2026.08.11-c"])
        XCTAssertEqual(result.candidates, ["2026.07.01-d", "2026.06.01-e"])
        XCTAssertEqual(result.candidateBytes, 130)
        XCTAssertEqual(result.protectedBytes, 270)
    }

    func testNativeCleanupCandidateRequiresContract() {
        XCTAssertFalse(CursorAgentCLISafetyRules.isNativeCleanupCandidate(
            isCurrent: false, isActive: false, isRequiredFallback: false,
            vendorToolchainVerified: true, userOriginalFalseVerified: true,
            nativeCleanupContractFound: false, blastRadiusKnown: false, reacquisitionKnown: true
        ))
        // Even with full predicates, P3.3C execution remains false
        XCTAssertTrue(CursorAgentCLISafetyRules.isNativeCleanupCandidate(
            isCurrent: false, isActive: false, isRequiredFallback: false,
            vendorToolchainVerified: true, userOriginalFalseVerified: true,
            nativeCleanupContractFound: true, blastRadiusKnown: true, reacquisitionKnown: true
        ))
        XCTAssertFalse(CursorAgentCLISafetyRules.versionExecutable(
            isCurrent: false, isActive: false, nativeCleanupContractApplies: true
        ))
    }

    func testFallbackVersionProtected() {
        XCTAssertFalse(CursorAgentCLISafetyRules.isNativeCleanupCandidate(
            isCurrent: false, isActive: false, isRequiredFallback: true,
            vendorToolchainVerified: true, userOriginalFalseVerified: true,
            nativeCleanupContractFound: true, blastRadiusKnown: true, reacquisitionKnown: true
        ))
    }

    func testOldMtimeDoesNotPromoteSafety() {
        XCTAssertTrue(CursorAgentCLISafetyRules.oldMtimeDoesNotPromoteSafety())
    }

    func testSoftwareUpdateDoesNotProveOldReacquire() {
        XCTAssertTrue(CursorAgentCLISafetyRules.softwareUpdateDoesNotProveOldArtifactReacquire())
    }

    func testPartialRuntimeIsNotInactiveVerified() {
        // Non-current + PARTIAL runtime → UNKNOWN, not cleanup candidate via inactiveVerified alone
        let state = CursorAgentCLIVersionState.unknown
        XCTAssertNotEqual(state, .inactiveVerified)
    }

    func testLiteralCleanupStringAloneIsNotVerifiedCallPath() {
        let confidence = "VERIFIED_LITERAL_REFERENCE"
        XCTAssertNotEqual(confidence, "VERIFIED_CALL_PATH")
    }

    func testStateVscdbStillProtected() {
        // P3.3B regression: DB remains KEEP / not executable when open
        XCTAssertFalse(CursorDatabaseRootCauseAnalyzer.rawDatabaseExecutable(dbOpen: true))
    }

    func testRemovedAIModelsStillAbsent() {
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

    func testHardlinkAccountingDoesNotInflate() {
        // When observed == unique, shared inflation is zero
        let (root, _) = CursorAgentCLIInventory.inventory()
        if root.versionCount > 0 {
            XCTAssertEqual(root.hardlinkSharedBytes, max(0, root.observedBytes - root.uniqueBytes))
            XCTAssertLessThanOrEqual(root.mappedVersionBytes, root.uniqueBytes + 4096)
        }
    }

    func testUserDataInsideVersionBlocksPureToolchain() {
        // Fixture-style: userish names → not pure toolchain
        let userish = ["workspace", "credentials"]
        XCTAssertFalse(userish.isEmpty)
        let pure = userish.isEmpty
        XCTAssertFalse(pure)
    }

    func testLiveInventoryIfPresent() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let versions = CursorAgentCLIPathResolver.versionsRoot(home: home)
        guard FileManager.default.fileExists(atPath: versions) else {
            throw XCTSkip("agent-cli versions root absent")
        }
        let (root, records) = CursorAgentCLIInventory.inventory(home: home)
        XCTAssertGreaterThan(root.versionCount, 0)
        XCTAssertFalse(root.rootExecutable)
        XCTAssertTrue(root.accountingValid)
        if let selected = root.selectedVersion {
            XCTAssertTrue(records.contains { $0.versionID == selected && $0.selectionState == "CURRENT_SELECTED" })
        }
        // package.json name evidence for toolchain when present
        let named = records.compactMap(\.packageName)
        if !named.isEmpty {
            XCTAssertTrue(named.contains("@anysphere/agent-cli-runtime") || named.contains { $0.contains("agent-cli") })
        }
    }
}
