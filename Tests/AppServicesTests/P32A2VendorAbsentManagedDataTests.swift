import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P32A2VendorAbsentManagedDataTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    override func setUp() {
        super.setUp()
        ExecutionPermitLedger.reset()
    }

    func testAppAbsentDataPresentClassifiesRemediation() {
        var item = makeOllamaItem(ownershipVerified: true, remoteFresh: true)
        let iface = absentInterface(modelData: true)
        let rem = VendorAbsentManagedDataAnalyzer.evaluateOllamaModel(item: item, interface: iface)
        XCTAssertEqual(rem.managedDataAvailability, .vendorAbsentManagedDataRemains)
        XCTAssertEqual(rem.recommendedRemediation, .reinstallVendorToRestoreNativeManagement)
        XCTAssertTrue(rem.requiresSoftwareInstall)
        XCTAssertTrue(rem.readyForInstallAuthorization)
        XCTAssertFalse(rem.rawDeleteAllowed)
        XCTAssertFalse(rem.nativeCleanupAvailable)
        XCTAssertTrue(rem.cleanupRequiresSeparateApproval)
        _ = item
    }

    func testAppPresentDoesNotShowAbsentRemediation() {
        var item = makeOllamaItem(ownershipVerified: true, remoteFresh: true)
        let iface = OllamaNativeInterfaceResolution(
            interfaceKind: .cli,
            status: .resolvedCLI,
            installReality: .ollamaAppWithEmbeddedCLI,
            ollamaAppFound: true,
            bundleIdentifier: "com.ollama.app",
            bundleVersion: "1.0",
            bundleLocationClass: "APPLICATIONS",
            cliResolved: true,
            cliExecutableURL: "/usr/local/bin/ollama",
            cliExecutableLocationClass: "USR_LOCAL",
            cliVersion: "0.5",
            supportsPS: true,
            supportsRM: true,
            guiExecutableRejectedAsCLI: false,
            localAPIReachable: false,
            localAPIIdentityVerified: false,
            localAPIVersion: nil,
            resolutionMethod: "FIXED",
            resolutionEvidence: [],
            resolutionDurationMs: 1,
            binaryFingerprint: "fp",
            observedAt: Date()
        )
        let rem = VendorAbsentManagedDataAnalyzer.evaluateOllamaModel(item: item, interface: iface)
        XCTAssertEqual(rem.managedDataAvailability, .vendorPresentNativeInterfaceAvailable)
        XCTAssertNotEqual(rem.recommendedRemediation, .reinstallVendorToRestoreNativeManagement)
        XCTAssertFalse(rem.readyForInstallAuthorization)
        _ = item
    }

    func testUnknownOwnershipDoesNotRecommendReinstall() {
        let item = makeOllamaItem(ownershipVerified: false, remoteFresh: false)
        let rem = VendorAbsentManagedDataAnalyzer.evaluateOllamaModel(
            item: item,
            interface: absentInterface(modelData: true)
        )
        XCTAssertEqual(rem.recommendedRemediation, .verifyMore)
        XCTAssertFalse(rem.readyForInstallAuthorization)
    }

    func testCustomProtectedKeepsCleanupBlocked() {
        var item = makeOllamaItem(ownershipVerified: true, remoteFresh: true)
        item.verification?.vendorProofNotes.append("USER_ORIGINAL")
        let rem = VendorAbsentManagedDataAnalyzer.evaluateOllamaModel(
            item: item,
            interface: absentInterface(modelData: true)
        )
        XCTAssertEqual(rem.recommendedRemediation, .keep)
        XCTAssertFalse(rem.rawDeleteAllowed)
    }

    func testInstallProposalDoesNotCreateCleanupPermit() {
        let proposal = SoftwareInstallationProposal.proposeRestoreOllamaManagement(
            entityID: "ai.ollama.model.library.qwen3:4b"
        )
        XCTAssertTrue(proposal.doesNotAuthorizeCleanup)
        XCTAssertTrue(proposal.invalidatesPriorCleanupProofs)
        XCTAssertNil(proposal.asCleanupPermitStub())
        XCTAssertFalse(VendorReinstallInvalidation.priorCleanupPermitValidAfterReinstall())
    }

    func testInstallInvalidatesOldCleanupPreflight() {
        XCTAssertFalse(VendorReinstallInvalidation.priorCleanupPermitValidAfterReinstall())
        XCTAssertEqual(
            VendorReinstallInvalidation.reason,
            "VENDOR_REINSTALL_INVALIDATES_PRIOR_CLEANUP_PROOF"
        )
    }

    func testModelNotRecognizedAfterReinstallBlocksRm() {
        // Fixture: CLI restored but inventory does not contain target.
        let names: Set<String> = ["llama3:8b"]
        let recognized = names.contains(where: {
            OllamaModelIdentityNormalization.matches($0, canonical: "library/qwen3:4b")
        })
        XCTAssertFalse(recognized)
        // No executor call — recognition gate fails.
    }

    func testModelRecognizedAfterReinstallMayReachApprovalBoundaryFixture() {
        let req = VendorPostInstallVerificationRequirements(
            ollamaAppOrCLIPresent: true,
            cliContractProven: true,
            supportsPS: true,
            supportsRM: true,
            exactModelRecognizedByInstalledInventory: true,
            localManifestIdentityMatches: true,
            referenceGraphVerified: true,
            runtimeSnapshotComplete: true,
            targetInactiveVerified: true,
            remoteProofFresh: true,
            scopedExecutorCapable: true
        )
        XCTAssertTrue(req.allSatisfied)
    }

    func testRawDeleteNeverOffered() {
        let rem = VendorAbsentManagedDataAnalyzer.evaluateOllamaModel(
            item: makeOllamaItem(ownershipVerified: true, remoteFresh: true),
            interface: absentInterface(modelData: true)
        )
        XCTAssertFalse(rem.rawDeleteAllowed)
        let support = ActionExecutionCapabilityRegistry.support(
            for: .moveToTrash,
            entityID: "ai.ollama.model.library.qwen3:4b",
            path: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        )
        // MOVE_TO_TRASH capability exists globally, but Ollama model path is not authorized trash target.
        XCTAssertFalse(ActionExecutionPolicy.allowsFirstMutationTrash(
            entityID: "ai.ollama.model.library.qwen3:4b",
            path: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        ))
        _ = support
    }

    func testHFUnaffected() {
        // P3.2B implements SNAPSHOT only — repository/hub remain unavailable.
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .snapshot
            ),
            .implemented
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .repository
            ),
            .notImplemented
        )
    }

    func testMoveToTrashUnchanged() {
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToTrash), .implemented)
    }

    func testPlanTierRequiresVendorRestoration() {
        let fact = OptimizationActionFact(
            entityID: "ai.ollama.model.library.qwen3:4b",
            displayName: "library/qwen3:4b",
            canonicalPath: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b",
            action: .vendorNativeCleanup,
            eligible: true,
            safetyClass: .unknown,
            expectedLogicalBytes: 2_497_293_931,
            blockedReasons: [VendorManagedDataAvailability.vendorAbsentManagedDataRemains.rawValue],
            explanation: "Restore Ollama management"
        )
        let candidate = OptimizationCandidateBuilder.fromFact(fact)
        XCTAssertEqual(candidate.tier, .requiresVendorRestoration)
        XCTAssertNotEqual(candidate.tier, .executableNow)
    }

    func testRemediationPlanSeparatesInstallFromCleanup() {
        let steps = VendorAbsentManagedDataAnalyzer.remediationPlanSteps()
        let install = steps.first { $0.stepID == "restore_vendor" }
        let cleanupAuth = steps.first { $0.stepID == "cleanup_human_approval" }
        let cleanupExec = steps.first { $0.stepID == "cleanup_execution" }
        XCTAssertEqual(install?.requiresHumanAuthorization, true)
        XCTAssertEqual(install?.canMutateUserData, false)
        XCTAssertEqual(cleanupAuth?.requiresHumanAuthorization, true)
        XCTAssertEqual(cleanupExec?.canMutateUserData, true)
        XCTAssertNotEqual(install?.order, cleanupAuth?.order)
    }

    // MARK: - Helpers

    private func absentInterface(modelData: Bool) -> OllamaNativeInterfaceResolution {
        OllamaNativeInterfaceResolution(
            interfaceKind: .none,
            status: .unresolved,
            installReality: .staleModelDataWithNoInstall,
            ollamaAppFound: false,
            bundleIdentifier: nil,
            bundleVersion: nil,
            bundleLocationClass: nil,
            cliResolved: false,
            cliExecutableURL: nil,
            cliExecutableLocationClass: nil,
            cliVersion: nil,
            supportsPS: false,
            supportsRM: false,
            guiExecutableRejectedAsCLI: false,
            localAPIReachable: false,
            localAPIIdentityVerified: false,
            localAPIVersion: nil,
            resolutionMethod: "NONE",
            resolutionEvidence: modelData ? ["MODEL_DATA_PRESENT", "BUNDLE_NOT_FOUND"] : ["BUNDLE_NOT_FOUND"],
            resolutionDurationMs: 1,
            binaryFingerprint: nil,
            observedAt: Date()
        )
    }

    private func makeOllamaItem(ownershipVerified: Bool, remoteFresh: Bool) -> ClassifiedItem {
        let model = "library/qwen3:4b"
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        let entityID = "ai.ollama.model.library.qwen3:4b"
        let entity = StorageEntity(
            id: entityID, kind: .cache, category: "AI_DEV", subcategory: "ollama",
            displayName: model, path: path, logicalBytes: 2_497_293_931
        )
        let detected = DetectedEntity(
            entity: entity, bucket: .developer, domain: "AI Tools",
            associatedProcesses: ["ollama"], identified: true, annotation: nil
        )
        let decision = SafetyDecision(
            entity: entity, action: .noAction, safetyClass: .unknown, safetyScore: nil,
            reasonCodes: [], sideEffects: [], matchedRuleID: nil, evaluationLayer: .unknownFallback,
            evidenceConfidence: 0, userExplanationJA: "t", growthCauses: [], requiresUserApproval: true, blockedBy: nil
        )
        var item = ClassifiedItem(
            detected: detected, decision: decision, semantic: SemanticResult(from: decision),
            allocatedBytes: 2_497_293_931, actionVariants: [:], inclusiveBytes: 2_497_293_931,
            exclusiveBytes: 2_497_293_931, resolution: .l3Product, unknownReason: nil, verification: nil
        )
        let now = Date()
        item.verification = VerificationAnnotation(
            vendorProofNotes: ["LOCAL_MANIFEST=\(model)"],
            referenceGraphConfidence: ownershipVerified ? .verified : .unknown,
            reacquisition: ObservationRecord(
                value: remoteFresh ? .true : .unknown,
                confidence: remoteFresh ? .verified : .unknown,
                completeness: remoteFresh ? .complete : .unknown,
                source: .vendorRule
            ),
            remoteReacquisitionProof: remoteFresh ? RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entityID,
                localIdentity: model,
                remoteIdentity: model,
                remoteRevisionOrDigest: "sha256-test",
                status: .verified,
                verifiedAt: now,
                freshUntil: now.addingTimeInterval(900),
                authenticationClass: .anonymous,
                proofMethod: .ollamaManifestGET,
                requiredObjectsChecked: 1,
                requiredObjectsVerified: 1,
                confidence: .verified,
                estimatedRedownloadBytes: 2_497_293_931,
                endpointClass: "ollama.registry"
            ) : nil
        )
        return item
    }
}
