import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P32A6BindingAndRecoveryUXTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private let entityID = "ai.ollama.model.library.qwen3:4b"
    private let model = "library/qwen3:4b"

    override func setUp() {
        super.setUp()
        ExecutionPermitLedger.reset()
    }

    // MARK: - Semantic digest stability

    func testSemanticDigestStableAcrossDifferentTimestamps() {
        let a = makeGateInput(remoteVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let b = makeGateInput(remoteVerifiedAt: Date(timeIntervalSince1970: 1_700_000_005))
        let digA = ActionBindingFingerprintBuilder.semanticDigest(input: a)
        let digB = ActionBindingFingerprintBuilder.semanticDigest(input: b)
        XCTAssertEqual(digA, digB)
        let bindA = ActionSemanticBindingBuilder.build(from: a)
        let bindB = ActionSemanticBindingBuilder.build(from: b)
        XCTAssertEqual(bindA.digest, bindB.digest)
        XCTAssertTrue(ActionSemanticBindingBuilder.materialDifferenceReasons(bindA, bindB).isEmpty)
    }

    func testFreshnessEnvelopeSeparatesFromIdentity() {
        let fresh = makeGateInput(remoteVerifiedAt: Date(), freshUntilOffset: 900)
        let stale = makeGateInput(remoteVerifiedAt: Date().addingTimeInterval(-10_000), freshUntilOffset: -100)
        XCTAssertEqual(
            ActionBindingFingerprintBuilder.semanticDigest(input: fresh),
            ActionBindingFingerprintBuilder.semanticDigest(input: stale)
        )
        let envFresh = ActionSemanticBindingBuilder.freshnessEnvelope(from: fresh)
        let envStale = ActionSemanticBindingBuilder.freshnessEnvelope(from: stale)
        XCTAssertTrue(envFresh.remoteValidNow)
        XCTAssertFalse(envStale.remoteValidNow)
        XCTAssertNotEqual(envFresh.remoteFreshClass, envStale.remoteFreshClass)
    }

    func testMaterialChangeInvalidatesBinding() {
        let a = makeGateInput()
        var bItem = a.item
        bItem.verification?.vendorProofNotes = ["LOCAL_MANIFEST=library/qwen3:4b-CHANGED"]
        let b = MutationGateInput(
            item: bItem,
            action: .vendorNativeCleanup,
            actionDecision: a.actionDecision,
            snapshot: a.snapshot,
            runtimeResolution: a.runtimeResolution,
            transactionContract: a.transactionContract,
            postVerifyContract: a.postVerifyContract,
            ruleVersion: a.ruleVersion
        )
        let reasons = ActionSemanticBindingBuilder.materialDifferenceReasons(
            ActionSemanticBindingBuilder.build(from: a),
            ActionSemanticBindingBuilder.build(from: b)
        )
        XCTAssertTrue(reasons.contains("MANIFEST_CHANGED") || reasons.contains("SEMANTIC_DIGEST_CHANGED"))
        XCTAssertNotEqual(
            ActionBindingFingerprintBuilder.semanticDigest(input: a),
            ActionBindingFingerprintBuilder.semanticDigest(input: b)
        )
    }

    func testFreshnessExpiryBlocksPermitWhileDigestStable() throws {
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        let fp = ActionBindingFingerprint(
            entityID: entityID,
            action: .vendorNativeCleanup,
            canonicalPath: path,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t",
            transactionContractVersion: OllamaNativeCleanupExecutor.contractVersion,
            semanticBindingDigest: "stable"
        )
        let receipt = PreflightReceipt(
            receiptID: "r",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            requiredClaims: [],
            satisfiedClaims: [],
            missingClaims: [],
            staleClaims: [],
            conflictedClaims: [],
            observedAt: Date(),
            freshnessValidity: [.remoteStateFresh],
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            result: PreflightResultCode.satisfiedReadOnly.rawValue
        )
        let approval = UserActionApproval(
            approvalID: "a",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            consequenceSummaryVersion: "t",
            expectedRecoveryBytes: 100,
            approvedAt: Date(),
            expiryPolicy: "single_use",
            scope: "t"
        )
        // Decision blocked by stale remote — eligibility false ⇒ no permit.
        let blocked = ActionDecision(
            entityID: entityID,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: false,
            blockedReasons: [.reacquisitionNotStrictVerified],
            explanationCodes: ["STALE"]
        )
        XCTAssertNil(ExecutionPermit.generate(receipt: receipt, approval: approval, decision: blocked))

        let eligible = ActionDecision(
            entityID: entityID,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true,
            explanationCodes: ["OK"]
        )
        XCTAssertNotNil(ExecutionPermit.generate(receipt: receipt, approval: approval, decision: eligible))
    }

    // MARK: - Lifecycle / retry

    func testPreExecutionRejectionNotMutationAttempt() {
        let record = ExecutionAttemptRecord.preExecutionRejected(
            entityID: entityID,
            action: .vendorNativeCleanup,
            approvalID: "human-approval-ollama-7C01E730",
            reason: "APPROVAL_BINDING_MISMATCH"
        )
        XCTAssertEqual(record.phase, .preExecutionRejected)
        XCTAssertFalse(record.executorInvoked)
        XCTAssertFalse(record.processStarted)
        XCTAssertFalse(record.nativeMutationAttempted)
    }

    func testApprovalLifecycleConsumeAndInvalidate() {
        let fp = ActionBindingFingerprint(
            entityID: entityID, action: .vendorNativeCleanup,
            canonicalPath: "/tmp", evidenceGeneration: 1, verificationGeneration: 1,
            runtimeGeneration: 1, ruleVersion: "t",
            transactionContractVersion: "t", semanticBindingDigest: "d"
        )
        let approval = UserActionApproval(
            approvalID: "a", entityID: entityID, action: .vendorNativeCleanup,
            bindingFingerprint: fp, consequenceSummaryVersion: "t",
            expectedRecoveryBytes: 1, approvedAt: Date(), expiryPolicy: "single_use", scope: "t"
        )
        var record = UserActionApprovalRecord(approval: approval, semanticBindingDigest: "d")
        record.markValid()
        XCTAssertEqual(record.lifecycle, .valid)
        XCTAssertTrue(ActionRetryPolicy.mayReuseApprovalAfterPreExecutionRejection(
            approvalLifecycle: record.lifecycle,
            semanticUnchanged: true,
            freshPreflightEligible: true
        ))
        record.consume()
        XCTAssertEqual(record.lifecycle, .consumed)
        XCTAssertFalse(ActionRetryPolicy.mayReuseApprovalAfterPreExecutionRejection(
            approvalLifecycle: record.lifecycle,
            semanticUnchanged: true,
            freshPreflightEligible: true
        ))
        XCTAssertFalse(ActionRetryPolicy.automaticRetryAfterPermitOrProcess)
        XCTAssertFalse(ActionRetryPolicy.unknownOutcomeAllowsReplay)
    }

    func testPermitReplayRejectedAfterConsume() throws {
        let fake = FakeProcessRunner(nextResult: BoundedProcessResult(outcome: .commandAccepted, exitCode: 0))
        let executor = OllamaNativeCleanupExecutor(
            processRunner: fake,
            resolveExecutable: { URL(fileURLWithPath: "/usr/local/bin/ollama") }
        )
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        let fp = ActionBindingFingerprint(
            entityID: entityID, action: .vendorNativeCleanup, canonicalPath: path,
            evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1,
            ruleVersion: "t", transactionContractVersion: OllamaNativeCleanupExecutor.contractVersion,
            semanticBindingDigest: "x"
        )
        let receipt = PreflightReceipt(
            receiptID: "r", entityID: entityID, action: .vendorNativeCleanup,
            bindingFingerprint: fp, requiredClaims: [], satisfiedClaims: [],
            missingClaims: [], staleClaims: [], conflictedClaims: [],
            observedAt: Date(), freshnessValidity: [], evidenceGeneration: 1,
            verificationGeneration: 1, runtimeGeneration: 1,
            result: PreflightResultCode.satisfiedReadOnly.rawValue
        )
        let approval = UserActionApproval(
            approvalID: "a", entityID: entityID, action: .vendorNativeCleanup,
            bindingFingerprint: fp, consequenceSummaryVersion: "t",
            expectedRecoveryBytes: 1, approvedAt: Date(), expiryPolicy: "s", scope: "s"
        )
        let decision = ActionDecision(
            entityID: entityID, action: .vendorNativeCleanup,
            safetyClass: .unknown, eligible: true, explanationCodes: []
        )
        guard let permit = ExecutionPermit.generate(receipt: receipt, approval: approval, decision: decision) else {
            return XCTFail("permit")
        }
        let plan = DryRunActionPlan(
            entityID: entityID, path: path,
            action: StorageAction.vendorNativeCleanup.rawValue,
            readiness: MutationReadiness.approvalRequired.rawValue,
            steps: [], executorImplemented: true
        )
        _ = try executor.execute(plan: plan, permit: permit, canonicalModel: model)
        XCTAssertThrowsError(try executor.execute(plan: plan, permit: permit, canonicalModel: model))
        XCTAssertEqual(fake.invocations.count, 1)
    }

    // MARK: - Presentation

    func testVerifiedSuccessPresentationUsesVerifiedNotPotential() {
        let exec = sampleExec(
            potential: 2_497_293_931,
            verified: 2_497_293_931,
            disk: 2_497_445_888,
            removed: true,
            recovery: "MODEL_REMOVED_STORAGE_RECOVERED"
        )
        let result = VerifiedActionResultBuilder.fromOllamaExecution(exec)
        XCTAssertEqual(result.verifiedRecoveredBytes, 2_497_293_931)
        XCTAssertEqual(result.storageRecoveryOutcome, .completedRecoveryVerified)
        XCTAssertTrue(result.userHeadline.contains("removed using Ollama"))
        XCTAssertFalse(result.userLines.contains(where: { $0.lowercased().contains("cache cleaned") }))
        XCTAssertEqual(result.observedDiskFreeDelta, 2_497_445_888)
        let checklist = VerifiedActionResultBuilder.receiptChecklist(from: result)
        XCTAssertTrue(checklist.contains(where: { $0.contains("2.50 GB verified") }))
    }

    func testPotentialNotCopiedWhenVerifiedLower() {
        let exec = sampleExec(
            potential: 2_500_000_000,
            verified: 1_200_000_000,
            disk: 1_200_000_000,
            removed: true,
            recovery: "MODEL_REMOVED_STORAGE_PARTIALLY_RECOVERED"
        )
        let result = VerifiedActionResultBuilder.fromOllamaExecution(exec)
        XCTAssertEqual(result.verifiedRecoveredBytes, 1_200_000_000)
        XCTAssertNotEqual(result.verifiedRecoveredBytes, result.potentialRecoveryBytes)
        XCTAssertTrue(result.userLines.contains(where: { $0.contains("1.20 GB") }))
        XCTAssertFalse(result.userLines.contains(where: { $0.contains("2.50 GB") }))
    }

    func testDiskDeltaNotCausalTruth() {
        let exec = sampleExec(
            potential: 2_500_000_000,
            verified: 2_500_000_000,
            disk: 3_200_000_000,
            removed: true,
            recovery: "MODEL_REMOVED_STORAGE_RECOVERED"
        )
        let result = VerifiedActionResultBuilder.fromOllamaExecution(exec)
        XCTAssertEqual(result.verifiedRecoveredBytes, 2_500_000_000)
        XCTAssertEqual(result.observedDiskFreeDelta, 3_200_000_000)
        XCTAssertTrue(result.technicalDetailLines.contains(where: { $0.contains("not causal claim") }))
        XCTAssertFalse(result.userLines.contains(where: { $0.contains("3.20") }))
    }

    func testUnknownOutcomeReconciliationCopy() {
        var exec = sampleExec(potential: 100, verified: 0, disk: nil, removed: false, recovery: nil)
        exec.processOutcome = "UNKNOWN_OUTCOME"
        exec.outcome = "UNKNOWN"
        exec.logicalRemovalVerified = false
        exec.postVerifyStatus = nil
        exec.recoveryStatus = nil
        exec.realMutationExecuted = true
        exec.executorInvoked = true
        let result = VerifiedActionResultBuilder.fromOllamaExecution(exec)
        XCTAssertEqual(result.storageRecoveryOutcome, .outcomeUnknown)
        XCTAssertTrue(result.userHeadline.contains("could not verify"))
        XCTAssertTrue(result.userLines.contains(where: { $0.contains("Re-check") }))
        XCTAssertFalse(ActionRetryPolicy.unknownOutcomeAllowsReplay)
    }

    func testHistoryExactCorrelationNotTimestampAlone() {
        let event = VerifiedStorageActionEvent(
            actionEventID: "permit-abc",
            entityID: entityID,
            action: .vendorNativeCleanup,
            executedAt: Date(),
            logicalOutcome: "MODEL_REMOVED",
            recoveryOutcome: ProductRecoveryPresentation.completedRecoveryVerified.rawValue,
            verifiedRecoveredBytes: 2_497_293_931,
            permitID: "permit-abc"
        )
        XCTAssertTrue(VerifiedActionResultBuilder.canCorrelate(
            event: event, entityID: entityID, action: .vendorNativeCleanup, permitID: "permit-abc"
        ))
        XCTAssertFalse(VerifiedActionResultBuilder.canCorrelate(
            event: event, entityID: entityID, action: .vendorNativeCleanup, permitID: "permit-other"
        ))
        XCTAssertFalse(VerifiedActionResultBuilder.timestampOnlyCorrelationAllowed)
    }

    func testHFRawTrashRegressions() {
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
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .ollama, entityKind: .blob
            ),
            .notSupported
        )
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToTrash), .implemented)
    }

    func testPlanCompletionDoesNotCopyPotentialAsVerified() {
        let outcome = UIExecutionOutcome(
            entityID: entityID,
            action: .vendorNativeCleanup,
            readiness: .completed,
            logicalActionCompleted: true,
            storageRecoveryState: .recoveryVerified,
            recoveryLabel: "verified",
            potentialRecoveryLabel: "2.50 GB",
            movedBytesLabel: nil,
            trashWarning: nil,
            userLines: [],
            executionReport: ActFirstMutationExecutionReport(
                phase: "P3.2A.5",
                outcome: "MODEL_REMOVED",
                entityID: entityID,
                action: StorageAction.vendorNativeCleanup.rawValue,
                path: "/tmp",
                measuredRecoveryBytes: 1_200_000_000,
                humanConfirmed: true,
                executorImplemented: true,
                destructiveActionsExecuted: true,
                explanation: "t"
            ),
            postVerification: nil,
            errorMessage: nil
        )
        XCTAssertEqual(OptimizationPlanEngine.measuredVerifiedBytes(from: outcome), 1_200_000_000)
        let empty = UIExecutionOutcome(
            entityID: entityID,
            action: .vendorNativeCleanup,
            readiness: .completed,
            logicalActionCompleted: true,
            storageRecoveryState: .recoveryVerified,
            recoveryLabel: "verified",
            userLines: [],
            executionReport: nil,
            postVerification: nil,
            errorMessage: nil
        )
        XCTAssertNil(OptimizationPlanEngine.measuredVerifiedBytes(from: empty))
    }

    // MARK: - helpers

    private func makeGateInput(
        remoteVerifiedAt: Date = Date(),
        freshUntilOffset: TimeInterval = 900,
        manifest: String = "LOCAL_MANIFEST=library/qwen3:4b"
    ) -> MutationGateInput {
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
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
                manifest,
                "OLLAMA_CLI_RESOLVED=/Applications/Ollama.app/Contents/Resources/ollama",
                "OLLAMA_BINARY_FP=path=/Applications/Ollama.app/Contents/Resources/ollama;size=1;mtime=1",
                "OLLAMA_EXECUTION_TRANSPORT_AVAILABLE",
            ],
            uniqueBytesProven: 2_497_293_931,
            sharedBytesProven: 0,
            referenceGraphConfidence: .verified,
            remoteReacquisitionProof: RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entityID,
                localIdentity: model,
                remoteIdentity: model,
                remoteRevisionOrDigest: "sha256-fixed",
                status: .verified,
                verifiedAt: remoteVerifiedAt,
                freshUntil: remoteVerifiedAt.addingTimeInterval(freshUntilOffset),
                authenticationClass: .anonymous,
                proofMethod: .ollamaManifestGET,
                requiredObjectsChecked: 1,
                requiredObjectsVerified: 1,
                confidence: .verified,
                estimatedRedownloadBytes: 2_497_293_931,
                endpointClass: "ollama.registry"
            )
        )
        let decision = ActionDecision(
            entityID: entityID, action: .vendorNativeCleanup,
            safetyClass: .unknown, eligible: true, explanationCodes: []
        )
        return MutationGateInput(
            item: item,
            action: .vendorNativeCleanup,
            actionDecision: decision,
            runtimeResolution: RuntimeStateResolution(
                entityID: entityID,
                disposition: .resolved,
                deferReason: nil,
                activeState: .inactive,
                activeStateConfidence: .verified,
                activeStateCompleteness: .complete,
                openFileHandle: .false,
                openFileConfidence: .verified,
                unknownReasons: [],
                lookupMs: 1
            ),
            transactionContract: TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
            ruleVersion: "t"
        )
    }

    private func sampleExec(
        potential: Int64,
        verified: Int64,
        disk: Int64?,
        removed: Bool,
        recovery: String?
    ) -> ActExecutionOrchestrator.OllamaNativeExecutionReport {
        ActExecutionOrchestrator.OllamaNativeExecutionReport(
            phase: "P3.2A.5",
            outcome: removed ? "MODEL_REMOVED" : "MODEL_REMOVAL_NOT_VERIFIED",
            entityID: entityID,
            canonicalModel: model,
            action: StorageAction.vendorNativeCleanup.rawValue,
            authorizationTextFingerprint: "af43f204f346b7aa",
            approvalID: "human-approval-ollama-FF421CEE",
            approvalConsumed: true,
            approvalBindingValid: true,
            bindingPreflightReceiptID: "pf",
            finalPreflightReceiptID: "pf",
            finalPreflightReadiness: "APPROVAL_REQUIRED",
            canonicalActionDecisionEligible: true,
            strictUnknownCount: 0,
            strictConflictCount: 0,
            permitID: "permit-ai.ollama.model.library.qwen3:4b-VENDOR_NATIVE_CLEANUP-61E62746",
            permitConsumed: true,
            executorInvoked: true,
            argvContract: ["rm", model],
            shellUsed: false,
            rawDeleteFallback: false,
            processOutcome: "COMMAND_ACCEPTED",
            exitStatus: 0,
            retryPerformed: false,
            realMutationExecuted: true,
            modelPresentBefore: true,
            modelPresentAfter: !removed,
            logicalRemovalVerified: removed,
            oldManifestPresentAfter: !removed,
            remainingReferencedBlobCount: 0,
            remainingSharedBytes: 0,
            remainingUniqueBytes: removed ? 0 : potential,
            potentialRecoveryBytesBefore: potential,
            immediateExpectedRecoveryBytes: 0,
            verifiedRecoveredBytes: verified,
            mappedDeltaBytes: verified,
            diskFreeDeltaBytes: disk,
            recoveryStatus: recovery,
            regenerationDetected: false,
            postVerifyStatus: removed ? "MODEL_REMOVED" : "MODEL_REMOVAL_NOT_VERIFIED",
            binaryFingerprint: "fp",
            cliExecutablePath: "/Applications/Ollama.app/Contents/Resources/ollama",
            auditRecord: nil,
            postVerifySteps: [],
            executionMs: 1,
            abortReason: nil,
            humanConfirmed: true,
            explanation: "fixture",
            attemptPhase: removed
                ? ExecutionAttemptPhase.postVerifyCompleted.rawValue
                : ExecutionAttemptPhase.processCompleted.rawValue,
            counters: ExecutionAttemptCounters(
                authorizationAttempts: 1, preflightAttempts: 1, permitIssuanceCount: 1,
                executorInvocationCount: 1, nativeProcessStartCount: 1,
                successfulNativeMutationCount: removed ? 1 : 0
            )
        )
    }
}
