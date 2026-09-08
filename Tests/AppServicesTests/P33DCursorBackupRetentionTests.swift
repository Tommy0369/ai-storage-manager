import XCTest
@testable import SafetyCore
@testable import AppServices

final class P33DCursorBackupRetentionTests: XCTestCase {

    func testFilenameAloneIsNotSafe() {
        XCTAssertTrue(CursorDatabaseBackupAnalyzer.filenameAloneIsNotSafe())
        XCTAssertEqual(CursorDatabaseBackupAnalyzer.relativeBackup, "state.vscdb.backup")
    }

    func testOldMtimeDoesNotPromoteSafety() {
        XCTAssertTrue(CursorDatabaseBackupAnalyzer.oldMtimeDoesNotPromoteSafety())
    }

    func testStructuralDuplicateWithoutLifecycleStaysProtected() {
        XCTAssertTrue(CursorDatabaseBackupAnalyzer.structuralDuplicateWithoutLifecycleStaysProtected())
        let potential = CursorDatabaseBackupAnalyzer.potentialRecoveryBytes(
            vendorRetentionCleanupFound: false,
            contractAligned: false,
            exactTargetBytes: 1_278_717_952
        )
        XCTAssertEqual(potential, 0)
    }

    func testUniqueStateImpliesProtectedRecovery() {
        let life = CursorDatabaseBackupAnalyzer.classifyLifecycle(
            restorePathReachable: false,
            isSoleRecoveryGeneration: false,
            migrationSpecificProven: false,
            supersededByNewerVendorGeneration: false,
            uniqueRecoveryStatePresent: true
        )
        XCTAssertEqual(life, .currentRecoveryBackup)
        XCTAssertEqual(
            CursorDatabaseBackupAnalyzer.planTier(lifecycle: life, cleanupContractFound: false),
            "KEEP"
        )
    }

    func testActiveRestorePathIsRecoveryKeep() {
        let life = CursorDatabaseBackupAnalyzer.classifyLifecycle(
            restorePathReachable: true,
            isSoleRecoveryGeneration: true,
            migrationSpecificProven: false,
            supersededByNewerVendorGeneration: false,
            uniqueRecoveryStatePresent: false
        )
        XCTAssertEqual(life, .currentRecoveryBackup)
        let contract = CursorDatabaseBackupAnalyzer.knownVendorRecoveryContract()
        XCTAssertTrue(contract.contractFound)
        XCTAssertTrue(contract.restorePathFound)
        XCTAssertTrue(contract.restoreReachable)
        XCTAssertEqual(contract.backupRetentionCount, 1)
        XCTAssertEqual(contract.creationTrigger, .storageCloseSnapshot)
        XCTAssertTrue(contract.cleanupSemantics.contains("NONE_FOUND"))
    }

    func testMigrationIncompleteVerifyMore() {
        let life = CursorDatabaseBackupAnalyzer.classifyLifecycle(
            restorePathReachable: false,
            isSoleRecoveryGeneration: true,
            migrationSpecificProven: true,
            supersededByNewerVendorGeneration: false,
            uniqueRecoveryStatePresent: false
        )
        XCTAssertEqual(life, .migrationBackupRemains)
        XCTAssertEqual(
            CursorDatabaseBackupAnalyzer.planTier(lifecycle: life, cleanupContractFound: false),
            "VERIFY_MORE"
        )
    }

    func testSupersededWithoutCleanupStillZeroPotential() {
        let life = CursorDatabaseBackupAnalyzer.classifyLifecycle(
            restorePathReachable: false,
            isSoleRecoveryGeneration: false,
            migrationSpecificProven: false,
            supersededByNewerVendorGeneration: true,
            uniqueRecoveryStatePresent: false
        )
        XCTAssertEqual(life, .supersededRecoveryBackup)
        XCTAssertEqual(
            CursorDatabaseBackupAnalyzer.potentialRecoveryBytes(
                vendorRetentionCleanupFound: false,
                contractAligned: false,
                exactTargetBytes: 100
            ),
            0
        )
    }

    func testWrongCleanupContractsDoNotCoverBackup() {
        let backup = "/Users/u/Library/Application Support/Cursor/User/globalStorage/state.vscdb.backup"
        let homeCLI = "/Users/u/.local/share/cursor-agent/versions"
        XCTAssertEqual(
            CursorDatabaseBackupAnalyzer.wrongCleanupContractAgainstBackup(
                contractVendor: "CURSOR",
                contractStorageClass: "INSTALLED_VERSIONS",
                backupStoreCanonical: backup,
                contractResolvedRoot: homeCLI
            ),
            .semanticClassMismatch
        )
        // Even if paths somehow matched, wrong class still mismatches first.
        XCTAssertEqual(
            CursorDatabaseBackupAnalyzer.wrongCleanupContractAgainstBackup(
                contractVendor: "CURSOR",
                contractStorageClass: "INSTALLED_VERSIONS",
                backupStoreCanonical: backup,
                contractResolvedRoot: backup
            ),
            .semanticClassMismatch
        )
    }

    func testMainDBAndAgentCLIRemainProtected() {
        XCTAssertFalse(CursorDatabaseRootCauseAnalyzer.rawDatabaseExecutable(dbOpen: true))
        XCTAssertFalse(CursorAgentCLISafetyRules.rootExecutable())
        XCTAssertFalse(CursorDatabaseBackupAnalyzer.rootExecutable())
        // Agent-cli GS remains non-actionable under HOME cleanup
        let home = "/Users/u/.local/share/cursor-agent/versions"
        let gs = "/Users/u/Library/Application Support/Cursor/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions"
        XCTAssertEqual(
            CursorAgentCLIStoreLifecycle.siblingHomeCleanupAgainstGSStillMismatched(
                homeVersions: home, gsVersions: gs
            ),
            .storeMismatch
        )
    }

    func testFileTypeClassification() {
        XCTAssertEqual(
            CursorDatabaseBackupAnalyzer.classifyFileType(
                validSQLite: true,
                isPathPlusBackupSuffixCopy: true,
                usedAsOpenFailureRestore: true
            ),
            .recoveryBackup
        )
        XCTAssertEqual(
            CursorDatabaseBackupAnalyzer.classifyFileType(
                validSQLite: false,
                isPathPlusBackupSuffixCopy: true,
                usedAsOpenFailureRestore: false
            ),
            .opaqueCursorBackup
        )
    }

    func testOllamaHFRegressionAndExecutorSet() {
        let o = VendorCleanupContractGate.evaluate(
            entity: VendorCleanupEntityContext(
                vendor: "OLLAMA",
                storageClass: "MANAGED_MODEL_STORE",
                entityID: "library/qwen3:4b",
                exactTargetID: "library/qwen3:4b",
                storeCanonicalPath: "~/.ollama/models"
            ),
            contract: VendorCleanupContractGate.ollamaModelFixtureContract,
            actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(o.alignmentStatus, .aligned)
        let h = VendorCleanupContractGate.evaluate(
            entity: VendorCleanupEntityContext(
                vendor: "HUGGING_FACE",
                storageClass: "HF_HUB_CACHE",
                entityID: "x",
                exactTargetID: "49e6aa286ad6",
                storeCanonicalPath: "~/.cache/huggingface/hub"
            ),
            contract: VendorCleanupContractGate.huggingFaceRevisionFixtureContract,
            actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(h.alignmentStatus, .aligned)
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

    func testGlobalInvariantPreserved() {
        XCTAssertEqual(
            VendorCleanupContractInvariant.noVendorCleanupWithoutAlignedContract,
            "NO_VENDOR_CLEANUP_ACTION_WITHOUT_ALIGNED_CONTRACT"
        )
    }
}
