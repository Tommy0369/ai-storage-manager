import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P32A4ActionSafetyAlignmentTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private let entityID = "ai.ollama.model.library.qwen3:4b"
    private let model = "library/qwen3:4b"

    override func setUp() {
        super.setUp()
        ExecutionPermitLedger.reset()
    }

    func testCrossActionSeparationTrashBlockedNativeEligible() {
        var item = makeOllamaItem(remoteFresh: true, inactive: true, transportOK: true)
        item.decision = SafetyDecision(
            entity: item.detected.entity, action: .noAction, safetyClass: .red, safetyScore: nil,
            reasonCodes: [], sideEffects: [], matchedRuleID: nil, evaluationLayer: .unknownFallback,
            evidenceConfidence: 0, userExplanationJA: "t", growthCauses: [], requiresUserApproval: true, blockedBy: nil
        )
        let kb = KnowledgeBaseDocument(version: "t", principle: "t", rules: [])
        let engine = SafetyRuleEngine(knowledge: kb)
        let trash = ActionSafetyEvaluator.evaluate(
            item: item, action: .moveToTrash, engine: engine,
            evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
            state: RuntimeState(),
            safetyDecisions: [.moveToTrash: item.decision]
        )
        let native = ActionSafetyEvaluator.evaluate(
            item: item, action: .vendorNativeCleanup, engine: engine,
            evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
            state: RuntimeState()
        )
        XCTAssertTrue(trash.blockedReasons.contains(.safetyClassRed) || trash.blockedReasons.contains(.applicationManagedData))
        XCTAssertFalse(trash.eligible)
        XCTAssertTrue(native.eligible)
        XCTAssertFalse(native.blockedReasons.contains(.safetyClassRed))
        XCTAssertEqual(native.safetyClass, .unknown)
    }

    func testVendorStrictUnknownNeverApprovalRequired() {
        var item = makeOllamaItem(remoteFresh: false, inactive: true, transportOK: true)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item, action: .vendorNativeCleanup,
            engine: SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: [])),
            evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
            state: RuntimeState()
        )
        XCTAssertFalse(decision.eligible)
        XCTAssertTrue(decision.blockedReasons.contains(.reacquisitionNotStrictVerified))
        XCTAssertFalse(decision.blockedReasons.contains(.regenerabilityUnknown))

        let gate = MutationGate.evaluate(MutationGateInput(
            item: item,
            action: .vendorNativeCleanup,
            actionDecision: decision,
            transactionContract: TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: .vendorNativeCleanup, item: item),
            ruleVersion: "t"
        ))
        XCTAssertNotEqual(gate.readiness, MutationReadiness.approvalRequired.rawValue)
        XCTAssertTrue(
            gate.readiness == MutationReadiness.verifyMore.rawValue
                || gate.readiness == MutationReadiness.blocked.rawValue
        )
    }

    func testHumanApprovalCannotOverrideUnknown() throws {
        var item = makeOllamaItem(remoteFresh: false, inactive: true, transportOK: true)
        let decision = ActionDecision(
            entityID: entityID,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: false,
            missingClaimTypes: [.reacquisition],
            blockedReasons: [.reacquisitionNotStrictVerified]
        )
        let fp = ActionBindingFingerprint(
            entityID: entityID,
            action: .vendorNativeCleanup,
            canonicalPath: item.detected.entity.path,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t",
            transactionContractVersion: "1",
            semanticBindingDigest: "x"
        )
        let receipt = PreflightReceipt(
            receiptID: "r",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            requiredClaims: [.reacquisition],
            satisfiedClaims: [],
            missingClaims: [.reacquisition],
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
            approvalID: "a",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            consequenceSummaryVersion: "1",
            expectedRecoveryBytes: nil,
            approvedAt: Date(),
            expiryPolicy: "runtime_fresh",
            scope: "entity"
        )
        // Even with forged satisfied receipt text, missingClaims + decision.blocked reject permit.
        XCTAssertNil(ExecutionPermit.generate(receipt: receipt, approval: approval, decision: decision))

        // Eligible-looking decision with missing claims still rejected.
        let eligibleButMissing = ActionDecision(
            entityID: entityID,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true,
            missingClaimTypes: [.reacquisition],
            blockedReasons: []
        )
        let cleanReceipt = PreflightReceipt(
            receiptID: "r2",
            entityID: entityID,
            action: .vendorNativeCleanup,
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
        XCTAssertNil(ExecutionPermit.generate(receipt: cleanReceipt, approval: approval, decision: eligibleButMissing))
        _ = item
    }

    func testReacquirableNotRegenerable() {
        XCTAssertTrue(OllamaVendorNativeStrictPredicateCatalog.reacquirabilityRequired)
        XCTAssertFalse(OllamaVendorNativeStrictPredicateCatalog.regenerabilityRequired)

        var item = makeOllamaItem(remoteFresh: true, inactive: true, transportOK: true)
        item.verification?.regenerable = ObservationRecord(
            value: .unknown, confidence: .unknown, completeness: .unknown, source: .vendorRule
        )
        let decision = ActionSafetyEvaluator.evaluate(
            item: item, action: .vendorNativeCleanup,
            engine: SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: [])),
            evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
            state: RuntimeState()
        )
        XCTAssertTrue(decision.eligible)
        XCTAssertFalse(decision.blockedReasons.contains(.regenerabilityUnknown))

        // Case 2: no reacquisition → blocked with reacquisition reason, not regenerability alias.
        var bad = makeOllamaItem(remoteFresh: false, inactive: true, transportOK: true)
        bad.verification?.regenerable = ObservationRecord(
            value: .true, confidence: .verified, completeness: .complete, source: .vendorRule
        )
        let blocked = ActionSafetyEvaluator.evaluate(
            item: bad, action: .vendorNativeCleanup,
            engine: SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: [])),
            evidence: EvidenceBundle(canonicalPath: bad.detected.entity.path),
            state: RuntimeState()
        )
        XCTAssertFalse(blocked.eligible)
        XCTAssertTrue(blocked.blockedReasons.contains(.reacquisitionNotStrictVerified))
    }

    func testPlanDoesNotProtectEligibleVendorNative() {
        let fact = OptimizationActionFact(
            entityID: entityID,
            displayName: model,
            canonicalPath: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b",
            action: .vendorNativeCleanup,
            eligible: true,
            safetyClass: .unknown,
            expectedLogicalBytes: 2_497_293_931,
            blockedReasons: [],
            explanation: "ACTION_SPECIFIC"
        )
        let candidate = OptimizationCandidateBuilder.fromFact(fact)
        XCTAssertEqual(candidate.tier, .approvalRequired)
        XCTAssertEqual(candidate.potentialRecoveryBytes, 2_497_293_931)
        XCTAssertEqual(candidate.immediateExpectedRecoveryBytes, 0)
        XCTAssertNotEqual(candidate.tier, .protectedTier)
    }

    func testAssignTierVendorNativeIgnoresGenericRed() {
        let tier = OptimizationCandidateBuilder.assignTier(
            safetyClass: .red,
            group: .protected,
            readiness: .approvalRequired,
            support: .implemented,
            action: .vendorNativeCleanup
        )
        XCTAssertEqual(tier, .approvalRequired)
    }

    func testRawBlobAndHFUnchanged() {
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .ollama, entityKind: .blob
            ),
            .notSupported
        )
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
        XCTAssertFalse(ActionExecutionPolicy.allowsFirstMutationTrash(
            entityID: entityID,
            path: "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        ))
    }

    func testAlignmentApprovalOnlyWhenStrictClear() {
        var item = makeOllamaItem(remoteFresh: true, inactive: true, transportOK: true)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item, action: .vendorNativeCleanup,
            engine: SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: [])),
            evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
            state: RuntimeState()
        )
        XCTAssertTrue(decision.eligible)
        let snap = ActionSpecificSafetyAligner.alignOllamaVendorNative(
            item: item,
            decision: decision,
            gate: nil
        )
        XCTAssertTrue(snap.unknownStrictPredicates.isEmpty)
        XCTAssertTrue(snap.safetyBlockers.isEmpty)
        XCTAssertTrue(snap.approvalIsOnlyRemainingGate)
        XCTAssertEqual(snap.remainingGateBlockers, ["USER_APPROVAL"])
        XCTAssertFalse(snap.regenerabilityRequired)
        XCTAssertTrue(snap.reacquirabilityRequired)
    }

    // MARK: - Helpers

    private func makeOllamaItem(remoteFresh: Bool, inactive: Bool, transportOK: Bool) -> ClassifiedItem {
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        let entity = StorageEntity(
            id: entityID, kind: .cache, category: "AI_DEV", subcategory: "ollama",
            displayName: model, path: path, logicalBytes: 2_497_293_931
        )
        let detected = DetectedEntity(
            entity: entity, bucket: .developer, domain: "AI Tools",
            associatedProcesses: ["ollama"], identified: true, annotation: nil
        )
        let decision = SafetyDecision(
            entity: entity, action: .noAction, safetyClass: .red, safetyScore: nil,
            reasonCodes: [], sideEffects: [], matchedRuleID: nil, evaluationLayer: .unknownFallback,
            evidenceConfidence: 0, userExplanationJA: "t", growthCauses: [], requiresUserApproval: true, blockedBy: nil
        )
        var item = ClassifiedItem(
            detected: detected, decision: decision, semantic: SemanticResult(from: decision),
            allocatedBytes: 2_497_293_931, actionVariants: [:], inclusiveBytes: 2_497_293_931,
            exclusiveBytes: 0, resolution: .l3Product, unknownReason: nil, verification: nil
        )
        let now = Date()
        var notes = ["LOCAL_MANIFEST=\(model)"]
        if transportOK {
            notes.append("OLLAMA_EXECUTION_TRANSPORT_AVAILABLE")
            notes.append("OLLAMA_CLI_RESOLVED=/usr/local/bin/ollama")
        }
        item.verification = VerificationAnnotation(
            vendorProofNotes: notes,
            referenceGraphConfidence: .verified,
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
        item.verification?.uniqueBytesProven = 2_497_293_931
        item.verification?.sharedBytesProven = 0
        item.verification?.activeState = inactive ? .inactive : .active
        item.verification?.activeStateConfidence = .verified
        item.verification?.activeStateCompleteness = .complete
        return item
    }
}
