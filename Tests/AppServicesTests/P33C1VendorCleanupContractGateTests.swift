import XCTest
@testable import SafetyCore
@testable import AppServices

final class P33C1VendorCleanupContractGateTests: XCTestCase {
    func testInvariantCapabilityIsNotPermission() {
        XCTAssertFalse(VendorCleanupContractInvariant.capabilityIsPermission)
        XCTAssertFalse(VendorCleanupContractInvariant.cleanupCommandIsContract)
        XCTAssertTrue(VendorCleanupContractInvariant.approvalCannotOverrideUnknown)
        XCTAssertTrue(VendorCleanupContractInvariant.approvalCannotOverrideMismatch)
        XCTAssertEqual(
            VendorCleanupContractInvariant.requiredDimensions,
            ["vendor", "store", "exactTarget", "blastRadius", "state"]
        )
        XCTAssertEqual(
            VendorCleanupContractInvariant.noVendorCleanupWithoutAlignedContract,
            "NO_VENDOR_CLEANUP_ACTION_WITHOUT_ALIGNED_CONTRACT"
        )
    }

    func testCleanupExistsButWrongStore() {
        let contract = VendorCleanupContractSpec(
            vendor: "CURSOR",
            storageClass: "DOWNLOAD_CACHE",
            actionClass: "VENDOR_NATIVE_CLEANUP",
            declaredTargetRoot: "/x/cache",
            resolvedTargetRoot: "/x/cache",
            targetSelectorKind: .vendorStaleSet,
            targetSelector: "stale",
            currentTargetExclusions: ["current"],
            fallbackExclusions: [],
            blastRadius: "cache only",
            blastRadiusBound: true,
            previewCapability: false,
            dryRunCapability: false,
            runtimeRequirements: "",
            reacquisitionRequirements: "",
            postVerifyContract: "",
            auditContract: "",
            sourceEvidence: "literal",
            confidence: "VERIFIED",
            contractReachable: true
        )
        let entity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: "v1",
            exactTargetID: "v1",
            storeCanonicalPath: "/x/cache"
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .semanticClassMismatch)
        XCTAssertFalse(r.mayReachApprovalBoundary)
        XCTAssertFalse(VendorCleanupContractInvariant.actionabilityAllowed(alignment: r))
    }

    func testSameRootWrongStorageClass() {
        // Paths equal, classes differ → SEMANTIC_CLASS_MISMATCH (checked before path utility)
        let contract = VendorCleanupContractGate.cursorHomeInstallCleanupContract(
            resolvedHomeVersions: "/same/versions"
        )
        var mismatched = contract
        mismatched.storageClass = "STAGING"
        let entity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: "v",
            exactTargetID: "v",
            storeCanonicalPath: "/same/versions"
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity, contract: mismatched, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .semanticClassMismatch)
    }

    func testRightStoreWrongVersion() {
        let contract = VendorCleanupContractSpec(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            actionClass: "VENDOR_NATIVE_CLEANUP",
            declaredTargetRoot: "/v",
            resolvedTargetRoot: "/v",
            targetSelectorKind: .exactVersion,
            targetSelector: "version-A",
            currentTargetExclusions: [],
            fallbackExclusions: [],
            blastRadius: "one version",
            blastRadiusBound: true,
            previewCapability: false,
            dryRunCapability: false,
            runtimeRequirements: "",
            reacquisitionRequirements: "",
            postVerifyContract: "",
            auditContract: "",
            sourceEvidence: "",
            confidence: "VERIFIED",
            contractReachable: true
        )
        let entity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: "version-B",
            exactTargetID: "version-B",
            storeCanonicalPath: "/v"
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .targetMismatch)
    }

    func testRightTargetUnknownBlastRadius() {
        var contract = VendorCleanupContractGate.ollamaModelFixtureContract
        contract.blastRadiusBound = false
        let entity = VendorCleanupEntityContext(
            vendor: "OLLAMA",
            storageClass: "MANAGED_MODEL_STORE",
            entityID: "library/qwen3:4b",
            exactTargetID: "library/qwen3:4b",
            storeCanonicalPath: "~/.ollama/models"
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .blastRadiusUnbounded)
        XCTAssertFalse(r.mayReachApprovalBoundary)
    }

    func testCurrentVersionIncludedConflicts() {
        let contract = VendorCleanupContractGate.cursorHomeInstallCleanupContract(
            resolvedHomeVersions: "/home/versions"
        )
        let entity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: "cur",
            exactTargetID: "cur",
            storeCanonicalPath: "/home/versions",
            isCurrent: true
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .blocked)
        XCTAssertTrue(r.strictConflicts.contains("current_version_included"))
    }

    func testActiveVersionIncludedBlocked() {
        let contract = VendorCleanupContractGate.cursorHomeInstallCleanupContract(
            resolvedHomeVersions: "/home/versions"
        )
        let entity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: "act",
            exactTargetID: "act",
            storeCanonicalPath: "/home/versions",
            isActive: true
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .blocked)
    }

    func testFallbackVersionProtected() {
        let contract = VendorCleanupContractGate.cursorHomeInstallCleanupContract(
            resolvedHomeVersions: "/home/versions"
        )
        let entity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: "fb",
            exactTargetID: "fb",
            storeCanonicalPath: "/home/versions",
            isFallbackProtected: true
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .blocked)
        XCTAssertTrue(r.strictConflicts.contains("fallback_version_included"))
    }

    func testContractStringOnlyUnreachable() {
        var contract = VendorCleanupContractGate.cursorHomeInstallCleanupContract(
            resolvedHomeVersions: "/home/versions"
        )
        contract.contractReachable = false
        contract.confidence = "VERIFIED_LITERAL_REFERENCE"
        let entity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: "v",
            exactTargetID: "v",
            storeCanonicalPath: "/home/versions"
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .contractUnreachable)
    }

    func testExactAlignedStillNotExecutableAndNoSafetyClass() {
        let contract = VendorCleanupContractGate.cursorHomeInstallCleanupContract(
            resolvedHomeVersions: "/home/versions"
        )
        let entity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: "old",
            exactTargetID: "old",
            storeCanonicalPath: "/home/versions"
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .aligned)
        XCTAssertTrue(r.mayReachApprovalBoundary)
        XCTAssertFalse(r.assignsSafetyClass)
        // No Cursor executor — alignment ≠ executable
        XCTAssertFalse(CursorAgentCLISafetyRules.versionExecutable(
            isCurrent: false, isActive: false, nativeCleanupContractApplies: true
        ))
    }

    func testUnknownRequiredProofsBlockEvenIfOtherwiseAligned() {
        let contract = VendorCleanupContractGate.cursorHomeInstallCleanupContract(
            resolvedHomeVersions: "/home/versions"
        )
        let entity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: "old",
            exactTargetID: "old",
            storeCanonicalPath: "/home/versions",
            requiredProofsUnknown: ["runtime_inactive_complete"]
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .verifyMore)
        XCTAssertFalse(r.mayReachApprovalBoundary)
    }

    func testOllamaContractRegression() {
        let entity = VendorCleanupEntityContext(
            vendor: "OLLAMA",
            storageClass: "MANAGED_MODEL_STORE",
            entityID: "library/qwen3:4b",
            exactTargetID: "library/qwen3:4b",
            storeCanonicalPath: "~/.ollama/models"
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity,
            contract: VendorCleanupContractGate.ollamaModelFixtureContract,
            actionIsVendorNativeCleanup: true
        )
        XCTAssertTrue(r.vendorMatches)
        XCTAssertTrue(r.storageClassMatches)
        XCTAssertTrue(r.exactTargetMatches)
        XCTAssertTrue(r.blastRadiusBound)
        XCTAssertEqual(r.alignmentStatus, .aligned)
        // Do not require live qwen3 present
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        ))
    }

    func testHFContractRegressionLastRevisionSemantic() {
        let entity = VendorCleanupEntityContext(
            vendor: "HUGGING_FACE",
            storageClass: "HF_HUB_CACHE",
            entityID: "ai.hf.snapshot...49e6aa286ad6",
            exactTargetID: "49e6aa286ad6",
            storeCanonicalPath: "~/.cache/huggingface/hub"
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity,
            contract: VendorCleanupContractGate.huggingFaceRevisionFixtureContract,
            actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .aligned)
        XCTAssertTrue(r.blastRadiusBound)
        // Path may disappear at repo level; semantic consequence still exact — preserved in contract text
        XCTAssertTrue(
            VendorCleanupContractGate.huggingFaceRevisionFixtureContract.blastRadius
                .contains("last-revision")
        )
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: "\(home)/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-mlx"
        ))
    }

    func testCursorActualStoreMismatchAgainstHomeContract() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let gs = CursorAgentCLIPathResolver.versionsRoot(home: home)
        let homeVers = CursorAgentCLIPathResolver.homeVersionsRoot(home: home)
        guard FileManager.default.fileExists(atPath: gs) else {
            throw XCTSkip("GS store absent")
        }
        let contract = VendorCleanupContractGate.cursorHomeInstallCleanupContract(
            resolvedHomeVersions: homeVers
        )
        let selected = CursorAgentCLIPathResolver.resolveSelectedVersion(home: home) ?? "unknown"
        let entity = VendorCleanupEntityContext(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            entityID: selected,
            exactTargetID: selected,
            storeCanonicalPath: gs
        )
        let r = VendorCleanupContractGate.evaluate(
            entity: entity, contract: contract, actionIsVendorNativeCleanup: true
        )
        XCTAssertEqual(r.alignmentStatus, .storeMismatch)
        XCTAssertEqual(r.storePathRelationship, .siblingStore)
        XCTAssertFalse(r.mayReachApprovalBoundary)
    }

    func testGateDoesNotCreateGreen() {
        let r = VendorCleanupContractGate.evaluate(
            entity: VendorCleanupEntityContext(
                vendor: "OLLAMA",
                storageClass: "MANAGED_MODEL_STORE",
                entityID: "x",
                exactTargetID: "library/qwen3:4b",
                storeCanonicalPath: "~/.ollama/models"
            ),
            contract: VendorCleanupContractGate.ollamaModelFixtureContract,
            actionIsVendorNativeCleanup: true
        )
        XCTAssertFalse(r.assignsSafetyClass)
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

    func testDBStillProtected() {
        XCTAssertFalse(CursorDatabaseRootCauseAnalyzer.rawDatabaseExecutable(dbOpen: true))
    }
}
