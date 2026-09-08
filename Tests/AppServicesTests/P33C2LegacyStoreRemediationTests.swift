import XCTest
@testable import SafetyCore

final class P33C2LegacyStoreRemediationTests: XCTestCase {

    func testStartStateIsUnresolvedUntilEvidence() {
        let state = CursorAgentCLIStoreLifecycle.classifyStore(
            hasCurrentSelector: false,
            hasRuntimeExecutable: false,
            hasFallbackReference: nil,
            migrationSourceProven: false,
            migrationDestProven: false,
            previousImplUsedThisStore: false,
            currentImplUsesOtherStoreOnly: false,
            currentImplStillReadsThisStore: false,
            vendorManagerAbsent: false,
            completionMarkersAbsent: false
        )
        // Without positive evidence, unknown secondary — not legacy.
        XCTAssertEqual(state, .unknownSecondaryStore)
        XCTAssertNotEqual(state, .legacyStoreVerified)
    }

    func testOldPathAloneIsNotLegacy() {
        XCTAssertTrue(CursorAgentCLIStoreLifecycle.oldPathOrMtimeAloneIsNotLegacy())
        let state = CursorAgentCLIStoreLifecycle.classifyStore(
            hasCurrentSelector: false,
            hasRuntimeExecutable: false,
            hasFallbackReference: nil,
            migrationSourceProven: false,
            migrationDestProven: false,
            previousImplUsedThisStore: true, // old impl used
            currentImplUsesOtherStoreOnly: false, // still ambiguous
            currentImplStillReadsThisStore: true,
            vendorManagerAbsent: false,
            completionMarkersAbsent: false
        )
        XCTAssertNotEqual(state, .legacyStoreVerified)
    }

    func testGSCurrentSelectorIsPrimaryProtected() {
        let state = CursorAgentCLIStoreLifecycle.classifyStore(
            hasCurrentSelector: true,
            hasRuntimeExecutable: false,
            hasFallbackReference: false,
            migrationSourceProven: false,
            migrationDestProven: false,
            previousImplUsedThisStore: false,
            currentImplUsesOtherStoreOnly: false,
            currentImplStillReadsThisStore: true,
            vendorManagerAbsent: false,
            completionMarkersAbsent: false
        )
        XCTAssertEqual(state, .currentPrimaryStore)
        XCTAssertEqual(
            CursorAgentCLIStoreLifecycle.planTierForGSWithoutRemediation(gsLifecycle: state),
            "KEEP"
        )
    }

    func testGSRuntimeActiveIsProtected() {
        let state = CursorAgentCLIStoreLifecycle.classifyStore(
            hasCurrentSelector: false,
            hasRuntimeExecutable: true,
            hasFallbackReference: false,
            migrationSourceProven: false,
            migrationDestProven: false,
            previousImplUsedThisStore: false,
            currentImplUsesOtherStoreOnly: false,
            currentImplStillReadsThisStore: true,
            vendorManagerAbsent: false,
            completionMarkersAbsent: false
        )
        XCTAssertEqual(state, .currentSecondaryStore)
    }

    func testGSFallbackIsProtected() {
        let state = CursorAgentCLIStoreLifecycle.classifyStore(
            hasCurrentSelector: false,
            hasRuntimeExecutable: false,
            hasFallbackReference: true,
            migrationSourceProven: false,
            migrationDestProven: false,
            previousImplUsedThisStore: false,
            currentImplUsesOtherStoreOnly: true,
            currentImplStillReadsThisStore: false,
            vendorManagerAbsent: false,
            completionMarkersAbsent: false
        )
        XCTAssertEqual(state, .fallbackStore)
    }

    func testUnreferencedVerifiedRequiresCompleteNegativeProof() {
        let ok = CursorAgentCLIStoreLifecycle.classifyVersionReference(
            selected: false,
            runtimeActive: false,
            fallbackReferenced: false,
            migrationReferenced: false,
            implementationMayCacheRead: false,
            snapshotComplete: true
        )
        XCTAssertEqual(ok, .unreferencedVerified)

        let cachePath = CursorAgentCLIStoreLifecycle.classifyVersionReference(
            selected: false,
            runtimeActive: false,
            fallbackReferenced: false,
            migrationReferenced: false,
            implementationMayCacheRead: true,
            snapshotComplete: true
        )
        XCTAssertEqual(cachePath, .unknown)
    }

    func testUnreferencedWithoutRemediationPotentialZero() {
        let unreferenced = CursorAgentCLIStoreLifecycle.unreferencedVerifiedBytes(
            versionRefs: [(1_000_000, .unreferencedVerified), (500, .selected)]
        )
        XCTAssertEqual(unreferenced, 1_000_000)
        let potential = CursorAgentCLIStoreLifecycle.potentialRecoveryBytes(
            remediationContractFound: false,
            contractAligned: false,
            exactTargetBytes: unreferenced
        )
        XCTAssertEqual(potential, 0)
        XCTAssertNotEqual(unreferenced, potential)
    }

    func testMigrationSourceRemainsWhenProven() {
        let state = CursorAgentCLIStoreLifecycle.classifyStore(
            hasCurrentSelector: false,
            hasRuntimeExecutable: false,
            hasFallbackReference: false,
            migrationSourceProven: true,
            migrationDestProven: false,
            previousImplUsedThisStore: true,
            currentImplUsesOtherStoreOnly: true,
            currentImplStillReadsThisStore: false,
            vendorManagerAbsent: false,
            completionMarkersAbsent: false
        )
        XCTAssertEqual(state, .migrationSourceRemains)
        XCTAssertEqual(
            CursorAgentCLIStoreLifecycle.planTierForGSWithoutRemediation(gsLifecycle: state),
            "VERIFY_MORE"
        )
    }

    func testMigrationIncompleteStaysProtectedVerifyMore() {
        // Migration evidence but still readable / incomplete → not unreferenced.
        let state = CursorAgentCLIStoreLifecycle.classifyStore(
            hasCurrentSelector: false,
            hasRuntimeExecutable: false,
            hasFallbackReference: nil,
            migrationSourceProven: true,
            migrationDestProven: false,
            previousImplUsedThisStore: true,
            currentImplUsesOtherStoreOnly: false,
            currentImplStillReadsThisStore: true,
            vendorManagerAbsent: false,
            completionMarkersAbsent: false
        )
        XCTAssertEqual(state, .migrationSource)
        XCTAssertEqual(
            CursorAgentCLIStoreLifecycle.planTierForGSWithoutRemediation(gsLifecycle: .migrationSource),
            "VERIFY_MORE"
        )
    }

    func testDuplicateVsSameLabelDifferentArtifact() {
        XCTAssertEqual(
            CursorAgentCLIStoreLifecycle.classifyVersionOverlap(
                presentInHOME: true, presentInGS: true, artifactExactMatch: true
            ),
            .duplicatedVersion
        )
        XCTAssertEqual(
            CursorAgentCLIStoreLifecycle.classifyVersionOverlap(
                presentInHOME: true, presentInGS: true, artifactExactMatch: false
            ),
            .sameLabelDifferentArtifact
        )
        XCTAssertEqual(
            CursorAgentCLIStoreLifecycle.classifyVersionOverlap(
                presentInHOME: false, presentInGS: true, artifactExactMatch: nil
            ),
            .gsOnlyVersion
        )
        XCTAssertTrue(CursorAgentCLIStoreLifecycle.localDuplicateDoesNotAuthorizeRemoval())
    }

    func testSiblingHomeCleanupAgainstGSRemainsStoreMismatch() {
        let home = "/Users/u/.local/share/cursor-agent/versions"
        let gs = "/Users/u/Library/Application Support/Cursor/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions"
        XCTAssertEqual(
            CursorAgentCLIStoreLifecycle.siblingHomeCleanupAgainstGSStillMismatched(
                homeVersions: home, gsVersions: gs
            ),
            .storeMismatch
        )
        // Regression: HOME contract still ALIGNED for HOME store
        let contract = VendorCleanupContractGate.cursorHomeInstallCleanupContract(
            resolvedHomeVersions: home
        )
        let homeEntity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: "v-home",
            exactTargetID: "2026.08.11-e8db854",
            storeCanonicalPath: home,
            isCurrent: false,
            isActive: false,
            isFallbackProtected: false
        )
        let homeEval = VendorCleanupContractGate.evaluate(
            entity: homeEntity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(homeEval.alignmentStatus, .aligned)

        let gsEntity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: "v-gs",
            exactTargetID: "2026.08.31-4057e58",
            storeCanonicalPath: gs,
            isCurrent: true,
            isActive: false,
            isFallbackProtected: false
        )
        let gsEval = VendorCleanupContractGate.evaluate(
            entity: gsEntity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(gsEval.alignmentStatus, .storeMismatch)
        XCTAssertFalse(VendorCleanupContractInvariant.actionabilityAllowed(alignment: gsEval))
    }

    func testKnownArchitectureDualPrimaryNoLegacyNoRemediation() {
        let (home, gs, rel, rem) = CursorAgentCLIStoreLifecycle.knownArchitectureEvidence()
        XCTAssertEqual(home.lifecycleState, .currentPrimaryStore)
        XCTAssertEqual(gs.lifecycleState, .currentPrimaryStore)
        XCTAssertEqual(rel, .siblingStore)
        XCTAssertFalse(rem.contractFound)
        XCTAssertEqual(rem.remediationKind, .none)
        XCTAssertEqual(home.managerClass, "USER_HOME_AGENT_CLI")
        XCTAssertEqual(gs.managerClass, "GLOBALSTORAGE_WORKER_AGENT_CLI")
        XCTAssertNotEqual(gs.lifecycleState, .legacyStoreVerified)
        let potential = CursorAgentCLIStoreLifecycle.potentialRecoveryBytes(
            remediationContractFound: rem.contractFound,
            contractAligned: rem.contractAligned,
            exactTargetBytes: 2_678_732_085
        )
        XCTAssertEqual(potential, 0)
    }

    func testLegacyVerifiedRequiresFullEvidence() {
        let legacy = CursorAgentCLIStoreLifecycle.classifyStore(
            hasCurrentSelector: false,
            hasRuntimeExecutable: false,
            hasFallbackReference: false,
            migrationSourceProven: false,
            migrationDestProven: false,
            previousImplUsedThisStore: true,
            currentImplUsesOtherStoreOnly: true,
            currentImplStillReadsThisStore: false,
            vendorManagerAbsent: false,
            completionMarkersAbsent: false
        )
        XCTAssertEqual(legacy, .legacyStoreVerified)
    }

    func testOllamaAndHFContractsRemainAlignedFixtures() {
        let oEntity = VendorCleanupEntityContext(
            vendor: "OLLAMA",
            storageClass: "MANAGED_MODEL_STORE",
            entityID: "library/qwen3:4b",
            exactTargetID: "library/qwen3:4b",
            storeCanonicalPath: "~/.ollama/models"
        )
        XCTAssertEqual(
            VendorCleanupContractGate.evaluate(
                entity: oEntity,
                contract: VendorCleanupContractGate.ollamaModelFixtureContract,
                actionIsVendorNativeCleanup: true
            ).alignmentStatus,
            .aligned
        )

        let hEntity = VendorCleanupEntityContext(
            vendor: "HUGGING_FACE",
            storageClass: "HF_HUB_CACHE",
            entityID: "ai.hf.snapshot...49e6aa286ad6",
            exactTargetID: "49e6aa286ad6",
            storeCanonicalPath: "~/.cache/huggingface/hub"
        )
        XCTAssertEqual(
            VendorCleanupContractGate.evaluate(
                entity: hEntity,
                contract: VendorCleanupContractGate.huggingFaceRevisionFixtureContract,
                actionIsVendorNativeCleanup: true
            ).alignmentStatus,
            .aligned
        )
    }

    func testNoCursorExecutorAndGlobalInvariantPreserved() {
        XCTAssertEqual(
            VendorCleanupContractInvariant.noVendorCleanupWithoutAlignedContract,
            "NO_VENDOR_CLEANUP_ACTION_WITHOUT_ALIGNED_CONTRACT"
        )
        XCTAssertFalse(CursorAgentCLISafetyRules.rootExecutable())
        XCTAssertFalse(
            CursorAgentCLISafetyRules.versionExecutable(
                isCurrent: false, isActive: false, nativeCleanupContractApplies: true
            )
        )
    }

    func testRemediationContractReadyWouldRequireAlignment() {
        // When a hypothetical GS remediation exists and aligns, potential may move.
        let bytes: Int64 = 100
        XCTAssertEqual(
            CursorAgentCLIStoreLifecycle.potentialRecoveryBytes(
                remediationContractFound: true,
                contractAligned: true,
                exactTargetBytes: bytes
            ),
            bytes
        )
        XCTAssertEqual(
            CursorAgentCLIStoreLifecycle.potentialRecoveryBytes(
                remediationContractFound: true,
                contractAligned: false,
                exactTargetBytes: bytes
            ),
            0
        )
    }
}
