import XCTest
@testable import SafetyCore
@testable import AppServices

final class P34BVoiceMemosPreservationTests: XCTestCase {

    func testPreservationIsNotDeletion() {
        XCTAssertTrue(VoiceMemosPreservationRules.preservationIsNotDeletion)
        XCTAssertFalse(VoiceMemosPreservationRules.deleteRecordingAliasesRemoveLocalDownload())
        XCTAssertTrue(VoiceMemosPreservationRules.distinctActions.contains("DELETE_RECORDING"))
        XCTAssertTrue(VoiceMemosPreservationRules.distinctActions.contains("REMOVE_LOCAL_DOWNLOAD"))
        XCTAssertNotEqual(
            VoiceMemosPreservationRules.distinctActions.firstIndex(of: "DELETE_RECORDING"),
            VoiceMemosPreservationRules.distinctActions.firstIndex(of: "REMOVE_LOCAL_DOWNLOAD")
        )
    }

    func testUserOriginalAllowsPreservationAnalysisBlocksDelete() {
        XCTAssertTrue(VoiceMemosPreservationRules.userOriginalDefault)
        XCTAssertTrue(VoiceMemosPreservationRules.userOriginalBlocksDelete)
        XCTAssertTrue(VoiceMemosPreservationRules.userOriginalAllowsPreservationAnalysis)
    }

    func testVendorDocsAndSafetyDefaults() {
        XCTAssertTrue(VoiceMemosPreservationRules.vendorDocsCrossDeviceSync)
        XCTAssertTrue(VoiceMemosPreservationRules.vendorDocsPermanentDeletePropagates)
        XCTAssertTrue(VoiceMemosPreservationRules.genericMacOptimizeStorageInsufficient)
        XCTAssertTrue(VoiceMemosPreservationRules.rawDeleteIsNotNativeEviction)
        XCTAssertTrue(VoiceMemosPreservationRules.genericMoveToICloudBlocked)
        XCTAssertTrue(VoiceMemosPreservationRules.fileProviderNotAssumed)
        XCTAssertFalse(VoiceMemosPreservationRules.missingLocalFileImpliesCloudOnly())
        XCTAssertFalse(VoiceMemosPreservationRules.iCloudEnabledAloneProvesRemoteObject())
        XCTAssertFalse(VoiceMemosPreservationRules.remoteCopyAloneCreatesActionability())
    }

    func testICloudEnabledOnlyKeepsRemoteUnknownForAction() {
        // Setting enabled without recording-level remote object proof.
        let bytes = VoiceMemosPreservationRules.eligibleLocalEvictionBytes(
            remoteIdentityVerified: false,
            remoteCurrentVerified: false,
            reacquisitionVerified: false,
            nativeLocalOnlyEvictionVerified: false,
            deletePropagation: .unknown,
            blastRadiusBound: false,
            exactLocalMediaTargetVerified: true,
            stateCompatible: true,
            bytes: 14_000_000_000
        )
        XCTAssertEqual(bytes, 0)
    }

    func testRemotePresentWithoutEvictionAPIYieldsZero() {
        let bytes = VoiceMemosPreservationRules.eligibleLocalEvictionBytes(
            remoteIdentityVerified: true,
            remoteCurrentVerified: true,
            reacquisitionVerified: true,
            nativeLocalOnlyEvictionVerified: false,
            deletePropagation: .localOnlyVerified,
            blastRadiusBound: true,
            exactLocalMediaTargetVerified: true,
            stateCompatible: true,
            bytes: 3_000_000_000
        )
        XCTAssertEqual(bytes, 0)
    }

    func testRemotePresentButOnlyRawDeleteBlocked() {
        XCTAssertTrue(VoiceMemosPreservationRules.rawDeleteIsNotNativeEviction)
        let contract = VoiceMemosPreservationRules.knownNoNativeLocalEvictionContract()
        XCTAssertFalse(contract.contractFound)
        XCTAssertEqual(contract.candidateBytes, 0)
        XCTAssertFalse(contract.currentExecutable)
    }

    func testDeletePropagatesCannotImplementRemoveLocalDownload() {
        XCTAssertEqual(
            DeletionPropagationSemantics.syncPropagatesDelete.rawValue,
            "SYNC_PROPAGATES_DELETE"
        )
        let bytes = VoiceMemosPreservationRules.eligibleLocalEvictionBytes(
            remoteIdentityVerified: true,
            remoteCurrentVerified: true,
            reacquisitionVerified: true,
            nativeLocalOnlyEvictionVerified: true,
            deletePropagation: .syncPropagatesDelete,
            blastRadiusBound: true,
            exactLocalMediaTargetVerified: true,
            stateCompatible: true,
            bytes: 1_000
        )
        XCTAssertEqual(bytes, 0)
    }

    func testNativeLocalEvictionAllGatesPassStillNotExecutableThisPhase() {
        let bytes = VoiceMemosPreservationRules.eligibleLocalEvictionBytes(
            remoteIdentityVerified: true,
            remoteCurrentVerified: true,
            reacquisitionVerified: true,
            nativeLocalOnlyEvictionVerified: true,
            deletePropagation: .localOnlyVerified,
            blastRadiusBound: true,
            exactLocalMediaTargetVerified: true,
            stateCompatible: true,
            bytes: 2_500_000_000
        )
        XCTAssertEqual(bytes, 2_500_000_000)
        // Phase rule: even if gates pass in fixture, product does not add executor here.
        let live = VoiceMemosPreservationRules.knownNoNativeLocalEvictionContract()
        XCTAssertFalse(live.currentExecutable)
    }

    func testSyncArchitectureCloudKitNotFileProvider() {
        XCTAssertEqual(
            VoiceMemosPreservationRules.classifySyncArchitecture(
                cloudKitLinked: true,
                fileProviderLinked: false,
                coreDataMirroringPresent: true
            ),
            .cloudKitCoreDataMirroring
        )
        XCTAssertEqual(
            VoiceMemosPreservationRules.classifySyncArchitecture(
                cloudKitLinked: true,
                fileProviderLinked: true,
                coreDataMirroringPresent: true
            ),
            .fileProvider
        )
    }

    func testGenericICloudMoveBlockedForVoiceMemos() {
        XCTAssertFalse(
            PreservationFirstRanking.genericICloudRelocationAllowed(forPathClass: "VoiceMemos")
        )
        XCTAssertTrue(VoiceMemosPreservationRules.genericMoveToICloudBlocked)
    }

    func testCursorStillClosed() {
        XCTAssertEqual(CursorInvestigationClosure.actionableBytes, 0)
        XCTAssertTrue(CursorInvestigationClosure.investigationClosed)
        XCTAssertEqual(CursorInvestigationClosure.backupDecision, "KEEP")
    }

    func testRemovedModelsAndExecutorSet() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: "\(home)/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-mlx"
        ))
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToTrash), .implemented)
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(for: .removeLocalDownload),
            .notImplemented
        )
    }

    func testBoundedSearchPrincipleStillHolds() {
        XCTAssertEqual(BoundedSemanticInspection.principle, "BROAD_BUNDLE_SEARCH_IS_NOT_DEFAULT")
    }
}
