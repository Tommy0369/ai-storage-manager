import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P32AOllamaNativeCleanupTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    override func setUp() {
        super.setUp()
        ExecutionPermitLedger.reset()
        RemoteReacquisitionProofIndex.reset()
        VendorStorageProofIndex.reset()
    }

    // MARK: - Capability scope

    func testCapabilityOllamaModelImplemented() {
        let s = ActionExecutionCapabilityRegistry.support(
            for: .vendorNativeCleanup, vendor: .ollama, entityKind: .model
        )
        XCTAssertEqual(s, .implemented)
    }

    func testCapabilityHFSnapshotImplemented() {
        let s = ActionExecutionCapabilityRegistry.support(
            for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .snapshot
        )
        XCTAssertEqual(s, .implemented)
    }

    func testCapabilityHFRepositoryStillNotImplemented() {
        let s = ActionExecutionCapabilityRegistry.support(
            for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .repository
        )
        XCTAssertEqual(s, .notImplemented)
    }

    func testCapabilityOllamaBlobNotSupported() {
        let s = ActionExecutionCapabilityRegistry.support(
            for: .vendorNativeCleanup, vendor: .ollama, entityKind: .blob
        )
        XCTAssertEqual(s, .notSupported)
    }

    func testMoveToTrashUnchanged() {
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToTrash), .implemented)
    }

    // MARK: - Exact command / injection

    func testExactCommandArgvNoShell() throws {
        let fake = FakeProcessRunner(nextResult: BoundedProcessResult(outcome: .commandAccepted, exitCode: 0))
        let exe = URL(fileURLWithPath: "/usr/local/bin/ollama")
        let executor = OllamaNativeCleanupExecutor(processRunner: fake, resolveExecutable: { exe })
        let (plan, permit) = try makePermitBundle(model: "library/qwen3:4b")
        _ = try executor.execute(plan: plan, permit: permit, canonicalModel: "library/qwen3:4b")
        XCTAssertEqual(fake.invocations.count, 1)
        XCTAssertEqual(fake.invocations[0].executablePath, "/usr/local/bin/ollama")
        XCTAssertEqual(fake.invocations[0].arguments, ["rm", "library/qwen3:4b"])
    }

    func testCommandInjectionRejected() {
        XCTAssertFalse(OllamaModelIdentity.isValidCanonical("; rm -rf ~"))
        XCTAssertFalse(OllamaModelIdentity.isValidCanonical("model && something"))
        XCTAssertFalse(OllamaModelIdentity.isValidCanonical("qwen3\n4b"))
        XCTAssertFalse(OllamaModelIdentity.isValidCanonical("/etc/passwd"))
        XCTAssertFalse(OllamaModelIdentity.isValidCanonical("library/qwen3:4b;id"))
        XCTAssertTrue(OllamaModelIdentity.isValidCanonical("library/qwen3:4b"))
    }

    func testInjectionNeverReachesRunner() throws {
        let fake = FakeProcessRunner()
        let executor = OllamaNativeCleanupExecutor(
            processRunner: fake,
            resolveExecutable: { URL(fileURLWithPath: "/usr/local/bin/ollama") }
        )
        let (plan, permit) = try makePermitBundle(model: "library/qwen3:4b")
        XCTAssertThrowsError(try executor.execute(plan: plan, permit: permit, canonicalModel: "; rm -rf ~"))
        XCTAssertEqual(fake.invocations.count, 0)
    }

    // MARK: - Permit / approval / single-use

    func testNoPermitNeverLaunches() throws {
        let fake = FakeProcessRunner()
        let executor = OllamaNativeCleanupExecutor(
            processRunner: fake,
            resolveExecutable: { URL(fileURLWithPath: "/usr/local/bin/ollama") }
        )
        let plan = DryRunActionPlan(
            entityID: "ai.ollama.model.library.qwen3:4b",
            path: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b",
            action: StorageAction.vendorNativeCleanup.rawValue,
            readiness: MutationReadiness.approvalRequired.rawValue,
            steps: [],
            executorImplemented: true
        )
        // Invalid permit path via wrong action
        let bad = try makeTrashPermit(path: plan.path)
        XCTAssertThrowsError(try executor.execute(plan: plan, permit: bad, canonicalModel: "library/qwen3:4b"))
        XCTAssertEqual(fake.invocations.count, 0)
    }

    func testDoubleExecutionRejected() throws {
        let fake = FakeProcessRunner(nextResult: BoundedProcessResult(outcome: .commandAccepted, exitCode: 0))
        let executor = OllamaNativeCleanupExecutor(
            processRunner: fake,
            resolveExecutable: { URL(fileURLWithPath: "/usr/local/bin/ollama") }
        )
        let (plan, permit) = try makePermitBundle(model: "library/qwen3:4b")
        _ = try executor.execute(plan: plan, permit: permit, canonicalModel: "library/qwen3:4b")
        XCTAssertThrowsError(try executor.execute(plan: plan, permit: permit, canonicalModel: "library/qwen3:4b"))
        XCTAssertEqual(fake.invocations.count, 1)
    }

    // MARK: - Outcomes

    func testNonzeroExitNoRecovery() throws {
        let fake = FakeProcessRunner(nextResult: BoundedProcessResult(outcome: .nonzeroExit, exitCode: 1, stderr: "not found"))
        let executor = OllamaNativeCleanupExecutor(
            processRunner: fake,
            resolveExecutable: { URL(fileURLWithPath: "/usr/local/bin/ollama") }
        )
        let (plan, permit) = try makePermitBundle(model: "library/qwen3:4b")
        let audit = try executor.execute(plan: plan, permit: permit, canonicalModel: "library/qwen3:4b")
        XCTAssertNotNil(audit.failureReason)
        XCTAssertNil(audit.measuredRecoveryBytes)
    }

    func testTimeoutUnknownNoRetry() throws {
        let fake = FakeProcessRunner(nextResult: BoundedProcessResult(outcome: .timedOut))
        let executor = OllamaNativeCleanupExecutor(
            processRunner: fake,
            resolveExecutable: { URL(fileURLWithPath: "/usr/local/bin/ollama") }
        )
        let (plan, permit) = try makePermitBundle(model: "library/qwen3:4b")
        let audit = try executor.execute(plan: plan, permit: permit, canonicalModel: "library/qwen3:4b")
        XCTAssertEqual(audit.failureReason, "TIMED_OUT")
        XCTAssertEqual(fake.invocations.count, 1)
    }

    func testExit0ButModelRemainsNotVerified() {
        let result = OllamaPostMutationVerifier.verify(
            canonicalModel: "library/qwen3:4b",
            modelStillInstalled: true,
            removedExclusiveBlobBytes: nil,
            remainingUnreferencedBlobBytes: nil,
            sharedRetainedBytes: nil,
            contract: nil
        )
        XCTAssertEqual(result.logical, .modelRemains)
        XCTAssertEqual(result.verifiedRecoveredBytes, 0)
        XCTAssertFalse(result.steps.first { $0.step == "verify_exact_model_absent" }?.satisfied ?? true)
    }

    func testModelRemovedBytesRemainPartial() {
        let result = OllamaPostMutationVerifier.verify(
            canonicalModel: "library/qwen3:4b",
            modelStillInstalled: false,
            removedExclusiveBlobBytes: 0,
            remainingUnreferencedBlobBytes: 100,
            sharedRetainedBytes: 0,
            contract: nil
        )
        XCTAssertEqual(result.logical, .modelRemoved)
        XCTAssertEqual(result.storage, .remains)
        XCTAssertEqual(result.verifiedRecoveredBytes, 0)
    }

    func testActualRecoveryNotFromEstimate() {
        let result = OllamaPostMutationVerifier.verify(
            canonicalModel: "library/qwen3:4b",
            modelStillInstalled: false,
            removedExclusiveBlobBytes: 50,
            remainingUnreferencedBlobBytes: 0,
            sharedRetainedBytes: 0,
            contract: nil
        )
        XCTAssertEqual(result.verifiedRecoveredBytes, 50)
        XCTAssertEqual(result.storage, .recovered)
    }

    // MARK: - Gate / remote / runtime

    func testExpiredRemoteProofBlocksGate() {
        var item = makeOllamaItem(model: "library/qwen3:4b")
        var proof = makeRemoteProof(model: "library/qwen3:4b", fresh: false)
        proof.freshUntil = Date().addingTimeInterval(-10)
        item.verification?.remoteReacquisitionProof = proof
        item.verification?.reacquisition = ObservationRecord(
            value: .true, confidence: .verified, completeness: .complete, source: .vendorRule
        )
        item.verification?.activeState = .inactive
        item.verification?.activeStateConfidence = .verified
        item.verification?.referenceGraphConfidence = .verified
        let decision = ActionDecision(
            entityID: item.detected.entity.id,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true,
            explanationCodes: ["MODEL=library/qwen3:4b"]
        )
        let gate = MutationGate.evaluate(MutationGateInput(
            item: item,
            action: .vendorNativeCleanup,
            actionDecision: decision,
            snapshot: nil,
            recommendation: nil,
            preflight: nil,
            runtimeResolution: nil,
            transactionContract: TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: .vendorNativeCleanup, item: item),
            approvalState: .scanDefault,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t"
        ))
        XCTAssertTrue(gate.blockingReasons.contains("REMOTE_PROOF_STALE") || gate.missingRequirements.contains("remote_reacquisition_fresh_verified"))
    }

    func testActiveModelBlocks() {
        var item = makeOllamaItem(model: "library/qwen3:4b")
        item.verification?.remoteReacquisitionProof = makeRemoteProof(model: "library/qwen3:4b", fresh: true)
        item.verification?.reacquisition = ObservationRecord(
            value: .true, confidence: .verified, completeness: .complete, source: .vendorRule
        )
        item.verification?.activeState = .active
        item.verification?.activeStateConfidence = .verified
        item.verification?.referenceGraphConfidence = .verified
        let decision = ActionDecision(
            entityID: item.detected.entity.id,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true,
            explanationCodes: []
        )
        let gate = MutationGate.evaluate(MutationGateInput(
            item: item,
            action: .vendorNativeCleanup,
            actionDecision: decision,
            snapshot: nil,
            recommendation: nil,
            preflight: nil,
            runtimeResolution: nil,
            transactionContract: TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: .vendorNativeCleanup, item: item),
            approvalState: .scanDefault,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t"
        ))
        XCTAssertTrue(gate.blockingReasons.contains(ActionBlockReason.sourceActive.rawValue))
    }

    func testRuntimeUnknownBlocks() {
        var item = makeOllamaItem(model: "library/qwen3:4b")
        item.verification?.remoteReacquisitionProof = makeRemoteProof(model: "library/qwen3:4b", fresh: true)
        item.verification?.reacquisition = ObservationRecord(
            value: .true, confidence: .verified, completeness: .complete, source: .vendorRule
        )
        item.verification?.activeState = .unknown
        item.verification?.activeStateConfidence = .unknown
        item.verification?.referenceGraphConfidence = .verified
        let decision = ActionDecision(
            entityID: item.detected.entity.id,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true,
            explanationCodes: []
        )
        let gate = MutationGate.evaluate(MutationGateInput(
            item: item,
            action: .vendorNativeCleanup,
            actionDecision: decision,
            snapshot: nil,
            recommendation: nil,
            preflight: nil,
            runtimeResolution: nil,
            transactionContract: TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: .vendorNativeCleanup, item: item),
            approvalState: .scanDefault,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t"
        ))
        XCTAssertTrue(gate.blockingReasons.contains("OLLAMA_MODEL_RUNTIME_UNKNOWN")
            || gate.missingRequirements.contains("exact_model_inactive_verified"))
    }

    func testInactiveMayReachApprovalBoundary() {
        var item = makeOllamaItem(model: "library/qwen3:4b")
        item.verification?.remoteReacquisitionProof = makeRemoteProof(model: "library/qwen3:4b", fresh: true)
        item.verification?.reacquisition = ObservationRecord(
            value: .true, confidence: .verified, completeness: .complete, source: .vendorRule
        )
        item.verification?.activeState = .inactive
        item.verification?.activeStateConfidence = .verified
        item.verification?.referenceGraphConfidence = .verified
        let decision = ActionDecision(
            entityID: item.detected.entity.id,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true,
            explanationCodes: ["MODEL=library/qwen3:4b"]
        )
        let gate = MutationGate.evaluate(MutationGateInput(
            item: item,
            action: .vendorNativeCleanup,
            actionDecision: decision,
            snapshot: nil,
            recommendation: nil,
            preflight: nil,
            runtimeResolution: nil,
            transactionContract: TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: .vendorNativeCleanup, item: item),
            approvalState: .scanDefault,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t",
            freshPreflightReceipt: nil
        ))
        // Without fresh preflight receipt → PREFLIGHT_REQUIRED or APPROVAL_REQUIRED depending on gate stage.
        XCTAssertTrue(
            [
                MutationReadiness.preflightRequired.rawValue,
                MutationReadiness.approvalRequired.rawValue,
                MutationReadiness.contractSatisfiedReadOnly.rawValue,
            ].contains(gate.readiness)
        )
        XCTAssertFalse(gate.blockingReasons.contains("VENDOR_NATIVE_EXECUTOR_UNAVAILABLE"))
        XCTAssertTrue(gate.executorImplemented)
    }

    func testHFRegressionNotExecutable() {
        // Snapshot path: contract exists (P3.2B). Repo-wide / short-rev still out of mutation scope.
        let path = "\(home)/.cache/huggingface/hub/models--org--m/snapshots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let support = ActionExecutionCapabilityRegistry.support(
            for: .vendorNativeCleanup,
            entityID: "ai.hf.snapshot.org.m.aaaaaaaaaaaa",
            path: path
        )
        XCTAssertEqual(support, .implemented)
        let item = makeHFItem(path: path)
        let tx = TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item)
        XCTAssertNotNil(tx)
        XCTAssertEqual(tx?.version, HuggingFaceNativeCleanupExecutor.contractVersion)
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .repository
            ),
            .notImplemented
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .blob
            ),
            .notSupported
        )
    }

    func testCustomLocalProtected() {
        var item = makeOllamaItem(model: "mymodel:latest")
        item.detected.entity.id = "ai.ollama.model.mymodel:latest"
        item.verification?.vendorProofNotes = ["CUSTOM", "USER_ORIGINAL"]
        item.verification?.remoteReacquisitionProof = nil
        item.verification?.referenceGraphConfidence = .verified
        item.verification?.activeState = .inactive
        item.verification?.activeStateConfidence = .verified
        let decision = ActionDecision(
            entityID: item.detected.entity.id,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: false,
            blockedReasons: [.userOriginalRequiresPreservation],
            explanationCodes: []
        )
        let gate = MutationGate.evaluate(MutationGateInput(
            item: item,
            action: .vendorNativeCleanup,
            actionDecision: decision,
            snapshot: nil,
            recommendation: nil,
            preflight: nil,
            runtimeResolution: nil,
            transactionContract: TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: .vendorNativeCleanup, item: item),
            approvalState: .scanDefault,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t"
        ))
        XCTAssertEqual(gate.readiness, MutationReadiness.blocked.rawValue)
    }

    func testPlanDoesNotInvokeExecutor() {
        let fake = FakeProcessRunner()
        _ = OllamaNativeCleanupExecutor(processRunner: fake)
        let fact = OptimizationActionFact(
            entityID: "ai.ollama.model.library.qwen3:4b",
            displayName: "library/qwen3:4b",
            canonicalPath: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b",
            action: .vendorNativeCleanup,
            eligible: true,
            safetyClass: .unknown,
            expectedLogicalBytes: 2_497_293_931
        )
        let candidate = OptimizationCandidateBuilder.fromFact(fact)
        XCTAssertEqual(candidate.executionSupport, .implemented)
        XCTAssertEqual(candidate.tier, .approvalRequired)
        XCTAssertEqual(fake.invocations.count, 0)
    }

    func testOllamaPSServiceOnlyDoesNotMarkActive() {
        let stdout = """
        NAME    ID    SIZE    PROCESSOR    UNTIL
        """
        let names = OllamaRunningModelsObserver.parsePS(stdout)
        XCTAssertTrue(names.isEmpty)
        let snap = OllamaRunningModelsSnapshot(completeness: .complete, runningModelIdentities: names)
        let (state, conf) = snap.inactivity(for: "library/qwen3:4b")
        XCTAssertEqual(state, .inactive)
        XCTAssertEqual(conf, .verified)
    }

    // MARK: - Helpers

    private func makePermitBundle(model: String) throws -> (DryRunActionPlan, ExecutionPermit) {
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/\(model.replacingOccurrences(of: ":", with: "/"))"
        let entityID = "ai.ollama.model.\(model.replacingOccurrences(of: "/", with: "."))"
        let fp = ActionBindingFingerprint(
            entityID: entityID,
            action: .vendorNativeCleanup,
            canonicalPath: path,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t",
            transactionContractVersion: OllamaNativeCleanupExecutor.contractVersion,
            semanticBindingDigest: "abc"
        )
        let receipt = PreflightReceipt(
            receiptID: "r-ollama",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            requiredClaims: [],
            satisfiedClaims: [],
            missingClaims: [],
            staleClaims: [],
            conflictedClaims: [],
            observedAt: Date(),
            freshnessValidity: [.runtimeFresh, .remoteStateFresh],
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            result: PreflightResultCode.satisfiedReadOnly.rawValue
        )
        let approval = UserActionApproval(
            approvalID: "a-ollama",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            consequenceSummaryVersion: "P3.2A",
            expectedRecoveryBytes: 100,
            approvedAt: Date(),
            expiryPolicy: "single_use",
            scope: "ollama_model:\(model)"
        )
        let decision = ActionDecision(
            entityID: entityID,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true,
            explanationCodes: ["MODEL=\(model)"]
        )
        guard let permit = ExecutionPermit.generate(receipt: receipt, approval: approval, decision: decision) else {
            XCTFail("permit generation failed")
            throw ActionExecutionError.permitDenied("test")
        }
        let plan = DryRunActionPlan(
            entityID: entityID,
            path: path,
            action: StorageAction.vendorNativeCleanup.rawValue,
            readiness: MutationReadiness.approvalRequired.rawValue,
            steps: [],
            executorImplemented: true
        )
        return (plan, permit)
    }

    private func makeTrashPermit(path: String) throws -> ExecutionPermit {
        let entityID = "xcode.deriveddata.child"
        let fp = ActionBindingFingerprint(
            entityID: entityID,
            action: .moveToTrash,
            canonicalPath: path,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t",
            transactionContractVersion: TransactionContractRegistry.trashVersion
        )
        let receipt = PreflightReceipt(
            receiptID: "r-trash",
            entityID: entityID,
            action: .moveToTrash,
            bindingFingerprint: fp,
            requiredClaims: [],
            satisfiedClaims: [],
            missingClaims: [],
            staleClaims: [],
            conflictedClaims: [],
            observedAt: Date(),
            freshnessValidity: [.runtimeFresh],
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            result: PreflightResultCode.satisfiedReadOnly.rawValue
        )
        let approval = UserActionApproval(
            approvalID: "a-trash",
            entityID: entityID,
            action: .moveToTrash,
            bindingFingerprint: fp,
            consequenceSummaryVersion: "t",
            expectedRecoveryBytes: 1,
            approvedAt: Date(),
            expiryPolicy: "single_use",
            scope: "t"
        )
        let decision = ActionDecision(
            entityID: entityID, action: .moveToTrash, safetyClass: .green, eligible: true, explanationCodes: []
        )
        // May be nil if path not DerivedData — that's fine for rejection test.
        return ExecutionPermit(
            permitID: "permit-bad",
            entityID: entityID,
            action: .moveToTrash,
            bindingFingerprint: fp,
            preflightReceiptID: receipt.receiptID,
            approvalID: approval.approvalID,
            issuedAt: Date()
        )
    }

    private func makeOllamaItem(model: String) -> ClassifiedItem {
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/\(model.replacingOccurrences(of: ":", with: "/"))"
        let entityID = "ai.ollama.model.\(model.replacingOccurrences(of: "/", with: "."))"
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
        item.verification = VerificationAnnotation(
            vendorProofNotes: ["LOCAL_MANIFEST=\(model)"],
            referenceGraphConfidence: .verified
        )
        return item
    }

    private func makeHFItem(path: String) -> ClassifiedItem {
        let entity = StorageEntity(
            id: "ai.hf.snapshot.org.m.aaaaaaaaaaaa", kind: .cache, category: "AI_DEV", subcategory: "hf",
            displayName: "org/m@aaaaaaaaaaaa", path: path, logicalBytes: 3_084_000_000
        )
        let detected = DetectedEntity(
            entity: entity, bucket: .developer, domain: "AI Tools",
            associatedProcesses: [], identified: true, annotation: nil
        )
        let decision = SafetyDecision(
            entity: entity, action: .noAction, safetyClass: .unknown, safetyScore: nil,
            reasonCodes: [], sideEffects: [], matchedRuleID: nil, evaluationLayer: .unknownFallback,
            evidenceConfidence: 0, userExplanationJA: "t", growthCauses: [], requiresUserApproval: true, blockedBy: nil
        )
        return ClassifiedItem(
            detected: detected, decision: decision, semantic: SemanticResult(from: decision),
            allocatedBytes: 3_084_000_000, actionVariants: [:], inclusiveBytes: 3_084_000_000,
            exclusiveBytes: 3_084_000_000, resolution: .l3Product, unknownReason: nil, verification: nil
        )
    }

    private func makeRemoteProof(model: String, fresh: Bool) -> RemoteReacquisitionProof {
        let now = Date()
        return RemoteReacquisitionProof(
            vendor: .ollama,
            entityID: "ai.ollama.model.\(model.replacingOccurrences(of: "/", with: "."))",
            localIdentity: model,
            remoteIdentity: model,
            remoteRevisionOrDigest: "sha256-test",
            status: .verified,
            verifiedAt: now,
            freshUntil: now.addingTimeInterval(fresh ? 900 : -10),
            authenticationClass: .anonymous,
            proofMethod: .ollamaManifestGET,
            requiredObjectsChecked: 1,
            requiredObjectsVerified: 1,
            confidence: .verified,
            estimatedRedownloadBytes: 100,
            endpointClass: "ollama.registry"
        )
    }
}
