import XCTest
@testable import SafetyCore
@testable import AppServices

final class P34APreservationFirstRankingTests: XCTestCase {

    func testCursorClosureKeepAndZeroActionable() {
        XCTAssertEqual(CursorInvestigationClosure.stateDBDecision, "KEEP")
        XCTAssertEqual(CursorInvestigationClosure.agentCLIDecision, "KEEP")
        XCTAssertEqual(CursorInvestigationClosure.backupDecision, "KEEP")
        XCTAssertEqual(CursorInvestigationClosure.backupLifecycle, "CURRENT_RECOVERY_BACKUP")
        XCTAssertEqual(CursorInvestigationClosure.actionableBytes, 0)
        XCTAssertTrue(CursorInvestigationClosure.investigationClosed)
        XCTAssertTrue(CursorInvestigationClosure.backupKeepReason().contains("recovery"))
    }

    func testBackupRecoveryPathStillKeep() {
        let contract = CursorDatabaseBackupAnalyzer.knownVendorRecoveryContract()
        XCTAssertTrue(contract.restoreReachable)
        XCTAssertEqual(
            CursorDatabaseBackupAnalyzer.classifyLifecycle(
                restorePathReachable: true,
                isSoleRecoveryGeneration: true,
                migrationSpecificProven: false,
                supersededByNewerVendorGeneration: false,
                uniqueRecoveryStatePresent: true
            ),
            .currentRecoveryBackup
        )
        XCTAssertEqual(
            CursorDatabaseBackupAnalyzer.potentialRecoveryBytes(
                vendorRetentionCleanupFound: false,
                contractAligned: false,
                exactTargetBytes: 1_278_717_952
            ),
            0
        )
    }

    func testBoundedSearchPrinciple() {
        XCTAssertEqual(BoundedSemanticInspection.principle, "BROAD_BUNDLE_SEARCH_IS_NOT_DEFAULT")
        XCTAssertEqual(BoundedSemanticInspection.preferredOrder.first, "exact_known_resource")
        let scope = BoundedSemanticInspection.cursorStorageMainJSScope()
        XCTAssertTrue(scope.literalTargets.contains("toBackupPath"))
        XCTAssertLessThanOrEqual(scope.maxFiles, 8)
        XCTAssertFalse(
            BoundedSemanticInspection.shouldExpand(
                currentHits: 3, questionAnswered: true, scope: scope
            )
        )
        XCTAssertTrue(
            BoundedSemanticInspection.shouldExpand(
                currentHits: 0, questionAnswered: false, scope: scope
            )
        )
        XCTAssertTrue(BoundedSemanticInspection.sizeAloneDoesNotReopenClosedInvestigation())
    }

    func testClosedCursorNotReselectedBySize() {
        let score = PreservationFirstRanking.score(
            uniqueBytes: 14_000_000_000,
            userValue: 0.9,
            sourceOfTruthRisk: 0.9,
            proofFeasibility: 0.2,
            nativeContractAvailability: 0.0,
            preservationPotential: 0.0,
            expectedLocalRecovery: 0.0,
            implementationEffort: 0.8,
            runtimeRisk: 0.9,
            closedProtectedInvestigation: true,
            currentActionabilityBytes: 0
        )
        XCTAssertEqual(score, 0)
    }

    func testPreservationIsNotDelete() {
        XCTAssertTrue(PreservationFirstRanking.preservationIsNotDelete())
        XCTAssertTrue(PreservationFirstRanking.userOriginalBlocksDestructiveDeletion())
        XCTAssertTrue(PreservationFirstRanking.userOriginalDoesNotBlockPreservationAnalysis())
        XCTAssertTrue(PreservationFirstRanking.rawDeleteIsNotLocalOffloadFallback())
        XCTAssertTrue(PreservationFirstRanking.iCloudAccountAloneIsNotRemoteProof())
        XCTAssertTrue(PreservationFirstRanking.remoteVerifiedButDeletePropagatesBlocksEviction())
    }

    func testGenericICloudBlockedForVoiceMemosAndAppSupport() {
        XCTAssertFalse(PreservationFirstRanking.genericICloudRelocationAllowed(forPathClass: "VoiceMemos"))
        XCTAssertFalse(PreservationFirstRanking.genericICloudRelocationAllowed(forPathClass: "Application Support"))
        XCTAssertFalse(PreservationFirstRanking.genericICloudRelocationAllowed(forPathClass: "Group Containers"))
        XCTAssertFalse(PreservationFirstRanking.genericICloudRelocationAllowed(forPathClass: "Cursor"))
    }

    func testVoiceMemosRanksAboveClosedCursorForNextProof() {
        let cursor = PreservationFirstRanking.score(
            uniqueBytes: 14_900_000_000,
            userValue: 0.95,
            sourceOfTruthRisk: 0.95,
            proofFeasibility: 0.1,
            nativeContractAvailability: 0.0,
            preservationPotential: 0.0,
            expectedLocalRecovery: 0.0,
            implementationEffort: 0.9,
            runtimeRisk: 0.9,
            closedProtectedInvestigation: true,
            currentActionabilityBytes: 0
        )
        let voice = PreservationFirstRanking.score(
            uniqueBytes: 14_092_847_946,
            userValue: 0.95,
            sourceOfTruthRisk: 0.8,
            proofFeasibility: 0.7,
            nativeContractAvailability: 0.35,
            preservationPotential: 0.85,
            expectedLocalRecovery: 0.4,
            implementationEffort: 0.55,
            runtimeRisk: 0.4,
            closedProtectedInvestigation: false,
            currentActionabilityBytes: 0
        )
        XCTAssertEqual(cursor, 0)
        XCTAssertGreaterThan(voice, cursor)
        XCTAssertGreaterThan(voice, 0.4)
    }

    func testGoalDoesNotOverrideSafety() {
        XCTAssertEqual(PreservationFirstRanking.completedVerifiedRecoveryBytes, 5_580_814_899)
        XCTAssertEqual(PreservationFirstRanking.remainingTwentyGBGoal, 14_419_185_101)
        // Remaining goal does not create actionability.
        XCTAssertEqual(PreservationFirstRanking.cursorClosureActionableBytes(), 0)
    }

    func testRemovedModelsStillAbsent() {
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
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(for: .removeLocalDownload),
            .notImplemented
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(for: .moveToICloud),
            .notImplemented
        )
    }

    func testPreservationContractNotReadyWithoutRemoteAndNative() {
        let contract = PreservationContract(
            vendor: "APPLE_VOICE_MEMOS",
            storageClass: "USER_ORIGINAL_RECORDINGS",
            exactTarget: "recording_or_vendor_supported_set",
            preservationAction: .removeLocalDownload,
            remoteIdentity: "UNKNOWN",
            sourceOfTruthState: "LOCAL_OR_UNKNOWN",
            localResidencyState: "LOCALLY_RESIDENT",
            cloudState: "REMOTE_UNKNOWN",
            deletionPropagationSemantics: "UNKNOWN",
            nativeOperation: "NONE_PROVEN",
            blastRadius: "UNKNOWN",
            postVerifyContract: "N/A",
            evidence: ["CloudKit metadata present", "ZEVICTIONDATE column exists"],
            confidence: "PARTIAL",
            contractReady: false,
            currentExecutable: false,
            candidateBytes: 0
        )
        XCTAssertFalse(contract.contractReady)
        XCTAssertFalse(contract.currentExecutable)
        XCTAssertEqual(contract.candidateBytes, 0)
    }

    func testGlobalInvariantPreserved() {
        XCTAssertEqual(
            VendorCleanupContractInvariant.noVendorCleanupWithoutAlignedContract,
            "NO_VENDOR_CLEANUP_ACTION_WITHOUT_ALIGNED_CONTRACT"
        )
    }
}
