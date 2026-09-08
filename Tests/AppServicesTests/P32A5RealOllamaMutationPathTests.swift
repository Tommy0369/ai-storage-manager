import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P32A5RealOllamaMutationPathTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    override func setUp() {
        super.setUp()
        ExecutionPermitLedger.reset()
        RemoteReacquisitionProofIndex.reset()
        VendorStorageProofIndex.reset()
    }

    func testAuthorizationTextFingerprintStable() {
        let a = OllamaNativePostMutationProbe.authorizationTextFingerprint()
        let b = OllamaNativePostMutationProbe.authorizationTextFingerprint(
            OllamaNativePostMutationProbe.authorizationText
        )
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.isEmpty)
    }

    func testWrongAuthorizationTextAbortsWithoutLaunch() throws {
        let fake = FakeProcessRunner()
        let (item, decision, gate) = makeOllamaFixture()
        let report = try ActExecutionOrchestrator.executeOllamaNativeCleanup(
            .init(
                entityID: OllamaNativePostMutationProbe.authorizedEntityID,
                canonicalModel: OllamaNativePostMutationProbe.authorizedCanonicalModel,
                authorizationText: "wrong text",
                item: item,
                snapshot: nil,
                scanDecision: decision,
                scanGate: gate,
                scanRuntimeResolution: nil,
                postVerifyContract: nil,
                ruleVersion: "test",
                humanConfirmed: true,
                expectedRecoveryBytes: 100,
                engine: SafetyRuleEngine(knowledge: try loadKB()),
                executor: StorageActionExecutorRouter(
                    ollamaExecutor: OllamaNativeCleanupExecutor(processRunner: fake, resolveExecutable: {
                        URL(fileURLWithPath: "/usr/local/bin/ollama")
                    })
                ),
                processRunner: fake
            )
        )
        XCTAssertEqual(report.outcome, "ABORTED")
        XCTAssertEqual(report.abortReason, "AUTHORIZATION_TEXT_MISMATCH")
        XCTAssertFalse(report.realMutationExecuted)
        XCTAssertEqual(fake.invocations.count, 0)
    }

    func testWrongEntityAbortsWithoutLaunch() throws {
        let fake = FakeProcessRunner()
        let (item, decision, gate) = makeOllamaFixture(entityID: "ai.ollama.model.other:1b", model: "library/other:1b")
        let report = try ActExecutionOrchestrator.executeOllamaNativeCleanup(
            .init(
                entityID: "ai.ollama.model.other:1b",
                canonicalModel: "library/other:1b",
                item: item,
                snapshot: nil,
                scanDecision: decision,
                scanGate: gate,
                scanRuntimeResolution: nil,
                postVerifyContract: nil,
                ruleVersion: "test",
                humanConfirmed: true,
                expectedRecoveryBytes: 100,
                engine: SafetyRuleEngine(knowledge: try loadKB()),
                executor: StorageActionExecutorRouter(
                    ollamaExecutor: OllamaNativeCleanupExecutor(processRunner: fake)
                ),
                processRunner: fake
            )
        )
        XCTAssertEqual(report.outcome, "ABORTED")
        XCTAssertTrue(report.abortReason?.contains("ENTITY_NOT_AUTHORIZED") == true)
        XCTAssertEqual(fake.invocations.count, 0)
    }

    func testPostVerifyExit0ButModelRemains() {
        let before = OllamaNativePostMutationProbe.BeforeSnapshot(
            entityID: OllamaNativePostMutationProbe.authorizedEntityID,
            canonicalModel: OllamaNativePostMutationProbe.authorizedCanonicalModel,
            modelPresent: true,
            uniqueBytes: 2_497_293_931,
            sharedBytes: 0,
            exclusiveDigestBytes: ["sha256:abc": 100],
            manifestPath: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b",
            freeBytes: 1_000,
            observedAt: Date()
        )
        let after = OllamaNativePostMutationProbe.AfterEvidence(
            modelPresent: true,
            inventoryFailure: nil,
            oldManifestPresent: true,
            remainingReferencedBlobCount: 1,
            remainingUniqueBytes: 2_497_293_931,
            remainingSharedBytes: 0,
            exclusiveDigestsStillPresent: 1,
            exclusiveDigestBytesGone: 0,
            freeBytes: 1_000,
            mappedDeltaBytes: 0,
            diskFreeDeltaBytes: 0,
            regenerationDetected: false,
            observedAt: Date()
        )
        let result = OllamaNativePostMutationProbe.verify(
            before: before,
            after: after,
            processFailed: false,
            contract: nil
        )
        XCTAssertEqual(result.logical, .modelRemains)
        XCTAssertEqual(result.verifiedRecoveredBytes, 0)
    }

    func testPostVerifyModelRemovedPartialStorage() {
        let before = OllamaNativePostMutationProbe.BeforeSnapshot(
            entityID: OllamaNativePostMutationProbe.authorizedEntityID,
            canonicalModel: OllamaNativePostMutationProbe.authorizedCanonicalModel,
            modelPresent: true,
            uniqueBytes: 1000,
            sharedBytes: 0,
            exclusiveDigestBytes: ["sha256:a": 600, "sha256:b": 400],
            manifestPath: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b",
            freeBytes: 1_000,
            observedAt: Date()
        )
        let after = OllamaNativePostMutationProbe.AfterEvidence(
            modelPresent: false,
            inventoryFailure: nil,
            oldManifestPresent: false,
            remainingReferencedBlobCount: 0,
            remainingUniqueBytes: 400,
            remainingSharedBytes: 0,
            exclusiveDigestsStillPresent: 1,
            exclusiveDigestBytesGone: 600,
            freeBytes: 1_600,
            mappedDeltaBytes: 600,
            diskFreeDeltaBytes: 600,
            regenerationDetected: false,
            observedAt: Date()
        )
        let result = OllamaNativePostMutationProbe.verify(
            before: before,
            after: after,
            processFailed: false,
            contract: nil
        )
        XCTAssertEqual(result.logical, .modelRemoved)
        XCTAssertEqual(result.verifiedRecoveredBytes, 600)
        XCTAssertEqual(result.storage, .partial)
    }

    func testHFAndRawBlobStillNotExecutable() {
        // P3.2B: HF SNAPSHOT executable; blob / repo still blocked.
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .snapshot
            ),
            .implemented
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .blob
            ),
            .notSupported
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .ollama, entityKind: .blob
            ),
            .notSupported
        )
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToTrash), .implemented)
    }

    func testRouterDefaultOnCoordinator() {
        let c = LiveStorageActionCoordinator()
        XCTAssertNotNil(c)
    }

    // MARK: - fixtures

    private func loadKB() throws -> KnowledgeBaseDocument {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = cwd.appendingPathComponent("knowledge/compiled/compiled_rules_v0.1.json")
        return try KnowledgeBaseLoader().load(from: url)
    }

    private func makeOllamaFixture(
        entityID: String = OllamaNativePostMutationProbe.authorizedEntityID,
        model: String = OllamaNativePostMutationProbe.authorizedCanonicalModel
    ) -> (ClassifiedItem, ActionDecision, MutationGateResult) {
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/\(model.replacingOccurrences(of: ":", with: "/"))"
        let entity = StorageEntity(
            id: entityID, kind: .cache, category: "AI_DEV", subcategory: "ollama",
            displayName: model, path: path, logicalBytes: 2_497_293_931
        )
        let detected = DetectedEntity(
            entity: entity, bucket: .developer, domain: "AI Tools",
            associatedProcesses: ["ollama"], identified: true, annotation: nil
        )
        let safety = SafetyDecision(
            entity: entity, action: .noAction, safetyClass: .red, safetyScore: nil,
            reasonCodes: [], sideEffects: [], matchedRuleID: nil, evaluationLayer: .unknownFallback,
            evidenceConfidence: 0, userExplanationJA: "t", growthCauses: [], requiresUserApproval: true, blockedBy: nil
        )
        var item = ClassifiedItem(
            detected: detected, decision: safety, semantic: SemanticResult(from: safety),
            allocatedBytes: 2_497_293_931, actionVariants: [:], inclusiveBytes: 2_497_293_931,
            exclusiveBytes: 2_497_293_931, resolution: .l3Product, unknownReason: nil, verification: nil
        )
        item.verification = VerificationAnnotation(
            vendorProofNotes: [
                "LOCAL_MANIFEST=\(model)",
                "OLLAMA_CLI_RESOLVED=/usr/local/bin/ollama",
                "OLLAMA_BINARY_FP=testfp",
                "OLLAMA_EXECUTION_TRANSPORT_AVAILABLE",
            ],
            uniqueBytesProven: 2_497_293_931,
            sharedBytesProven: 0,
            referenceGraphConfidence: .verified
        )
        let decision = ActionDecision(
            entityID: entityID,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: false,
            explanationCodes: ["fixture"]
        )
        let gate = MutationGateResult(
            entityID: entityID,
            path: path,
            action: StorageAction.vendorNativeCleanup.rawValue,
            safetyClass: SafetyClass.unknown.rawValue,
            recommendation: nil,
            readiness: MutationReadiness.verifyMore.rawValue,
            satisfiedRequirements: [],
            missingRequirements: ["test"],
            staleRequirements: [],
            conflictedRequirements: [],
            blockingReasons: ["test"],
            requiredFreshChecks: [],
            actionBindingFingerprint: nil,
            transactionContractAvailable: true,
            postVerifyContractAvailable: true,
            auditContractAvailable: true,
            freshRuntimeCheckRequired: true,
            freshCloudCheckRequired: false,
            approvalRequired: true,
            executorImplemented: true
        )
        return (item, decision, gate)
    }
}
