import XCTest
@testable import SafetyCore

final class P200MutationGateTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private lazy var engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: []))

    private func verified(_ value: PredicateValue) -> ObservationRecord {
        ObservationRecord(value: value, confidence: .verified, completeness: .complete, source: .filesystemMetadata)
    }

    private func makeItem(
        id: String,
        path: String,
        bytes: Int64 = 36_000_000,
        bucket: SystemDataBucket = .generated,
        kind: EntityKind = .generatedBuild,
        safetyClass: SafetyClass = .green,
        verification: VerificationAnnotation? = nil,
        annotation: DetectionAnnotation? = nil
    ) -> ClassifiedItem {
        let entity = StorageEntity(id: id, kind: kind, category: "DEV", subcategory: "XCODE", displayName: id, path: path, logicalBytes: bytes)
        let decision = SafetyDecision(
            entity: entity,
            action: .moveToTrash,
            safetyClass: safetyClass,
            safetyScore: SafetyScore(value: 95),
            reasonCodes: ["GENERATED_DATA"],
            sideEffects: [],
            matchedRuleID: "test.derived",
            evaluationLayer: .exactVendor,
            evidenceConfidence: 0.95,
            userExplanationJA: "DerivedData",
            growthCauses: [],
            requiresUserApproval: true,
            blockedBy: nil
        )
        return ClassifiedItem(
            detected: DetectedEntity(entity: entity, bucket: bucket, domain: "Developer", associatedProcesses: ["Xcode"], identified: true, annotation: annotation),
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: bytes,
            actionVariants: [:],
            inclusiveBytes: bytes,
            exclusiveBytes: bytes,
            resolution: .l5Actionable,
            verification: verification
        )
    }

    private func derivedSnapshot(path: String, entityID: String) -> EntitySafetySnapshot {
        var evidence = EvidenceBundle(canonicalPath: path, sourceOfTruth: .false, regenerable: .true)
        evidence.openFileHandle = .false
        evidence.predicateConfidence["no_open_file_handle"] = .verified
        let verification = VerificationAnnotation(
            sourceOfTruth: verified(.false),
            regenerable: verified(.true),
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete
        )
        return EntitySafetySnapshot(
            entityID: entityID,
            entity: StorageEntity(id: entityID, kind: .generatedBuild, category: "DEV", subcategory: "XCODE", displayName: "dd", path: path, logicalBytes: 1),
            detected: DetectedEntity(
                entity: StorageEntity(id: entityID, kind: .generatedBuild, category: "DEV", subcategory: "XCODE", displayName: "dd", path: path, logicalBytes: 1),
                bucket: .generated,
                domain: "Developer",
                associatedProcesses: ["Xcode"],
                identified: true,
                annotation: DetectionAnnotation(detectorID: "t", specificity: 90, semanticType: "XCODE_DERIVED_DATA", lifecycle: LifecycleEvidence(role: .generatedArtifact, roleConfidence: .verified, activeState: .inactive))
            ),
            evidence: evidence,
            state: RuntimeState(),
            verification: verification,
            predicates: EntityPredicateSnapshot(
                sourceOfTruth: verified(.false),
                regenerability: verified(.true),
                activeState: .inactive,
                activeStateConfidence: .verified,
                openFileHandle: .false,
                openFileConfidence: .verified,
                isGitRepository: false,
                isApplicationManaged: true,
                isDerivedData: true,
                isUserOwnedVerified: false,
                hasEvidenceConflict: false,
                hasCanonicalPath: true,
                isSymlinkAmbiguity: false,
                isUserOriginal: false,
                isGeneratedArtifact: true,
                isInsideProtectedRoot: false,
                fileProviderBacked: false,
                remoteBackingVerified: false,
                syncSafeVerified: false
            ),
            relationships: [],
            cacheKey: EntitySnapshotCacheKey(entityID: entityID, evidenceVersion: 1, verificationGeneration: 1, runtimeGeneration: 1),
            finalizedAt: Date(),
            finalizationMs: 1
        )
    }

    private func gateInput(
        item: ClassifiedItem,
        action: StorageAction,
        decision: ActionDecision,
        snapshot: EntitySafetySnapshot? = nil,
        runtime: RuntimeStateResolution? = nil,
        recommendation: ActionRecommendationResult? = nil
    ) -> MutationGateInput {
        MutationGateInput(
            item: item,
            action: action,
            actionDecision: decision,
            snapshot: snapshot,
            recommendation: recommendation,
            preflight: nil,
            runtimeResolution: runtime,
            transactionContract: TransactionContractRegistry.transactionContract(for: action, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: action, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: action, item: item),
            approvalState: .scanDefault,
            evidenceGeneration: snapshot?.evidence.snapshotVersion ?? 1,
            verificationGeneration: snapshot?.verification.snapshotGeneration ?? 1,
            runtimeGeneration: snapshot?.cacheKey.runtimeGeneration ?? 1,
            ruleVersion: "t"
        )
    }

    func testGreenAloneCannotAuthorizeMutation() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/Runner-abc"
        let item = makeItem(id: "xcode.deriveddata.runner", path: path, safetyClass: .green)
        let snapshot = derivedSnapshot(path: path, entityID: item.detected.entity.id)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToTrash,
            engine: engine,
            evidence: snapshot.evidence,
            state: RuntimeState(),
            snapshot: snapshot,
            safetyDecisions: [.moveToTrash: item.decision]
        )
        let result = MutationGate.evaluate(gateInput(item: item, action: .moveToTrash, decision: decision, snapshot: snapshot))
        XCTAssertNotEqual(result.readiness, MutationReadiness.contractSatisfiedReadOnly.rawValue)
        XCTAssertFalse(result.readiness.contains("EXECUTABLE"))
        // Capability may be implemented; gate still must not equal authorization.
        XCTAssertTrue(result.approvalRequired || result.readiness == MutationReadiness.preflightRequired.rawValue
            || result.readiness == MutationReadiness.blocked.rawValue)
    }

    func testRecommendationAloneCannotAuthorize() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/Runner-abc"
        let item = makeItem(id: "xcode.deriveddata.runner", path: path)
        let snapshot = derivedSnapshot(path: path, entityID: item.detected.entity.id)
        let decision = ActionSafetyEvaluator.evaluate(item: item, action: .moveToTrash, engine: engine, evidence: snapshot.evidence, state: RuntimeState(), snapshot: snapshot)
        let rec = ActionRecommendationResult(
            entityID: item.detected.entity.id,
            path: path,
            disposition: .actionable(.moveToTrash),
            recommendedAction: .moveToTrash,
            alternatives: [.keep],
            recommendationReasons: ["GENERATED_DATA"],
            blockedActions: [],
            confidence: .verified,
            expectedLocalRecoveryBytes: 36_000_000,
            recoveryConfidence: .verified,
            missingProof: []
        )
        let result = MutationGate.evaluate(gateInput(item: item, action: .moveToTrash, decision: decision, snapshot: snapshot, recommendation: rec))
        XCTAssertTrue(result.approvalRequired)
        XCTAssertFalse(result.readiness.contains("EXECUTABLE"))
    }

    func testDerivedDataRequiresApprovalNotExecution() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/Runner-abc"
        let item = makeItem(id: "xcode.deriveddata.runner", path: path)
        let snapshot = derivedSnapshot(path: path, entityID: item.detected.entity.id)
        let runtime = RuntimeStateResolution(
            entityID: item.detected.entity.id,
            disposition: .resolved,
            deferReason: nil,
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete,
            openFileHandle: .false,
            openFileConfidence: .verified,
            unknownReasons: [],
            lookupMs: 1
        )
        let decision = ActionDecision(
            entityID: item.detected.entity.id,
            action: .moveToTrash,
            safetyClass: .green,
            eligible: true,
            requiredClaims: [
                ClaimRequirement(claimType: .sourceOfTruth, requiredPredicate: .false),
                ClaimRequirement(claimType: .regenerability, requiredPredicate: .true, freshness: .runtimeFresh),
                ClaimRequirement(claimType: .openFileState, requiredPredicate: .false, freshness: .runtimeFresh),
            ],
            satisfiedClaimTypes: [.canonicalPath, .sourceOfTruth, .regenerability, .openFileState],
            missingClaimTypes: [],
            blockedReasons: [],
            expectedLocalRecoveryBytes: 36_000_000,
            recoveryConfidence: .verified,
            explanationCodes: ["GENERATED_DATA"]
        )
        let result = MutationGate.evaluate(gateInput(item: item, action: .moveToTrash, decision: decision, snapshot: snapshot, runtime: runtime))
        XCTAssertTrue(result.transactionContractAvailable)
        XCTAssertTrue(result.postVerifyContractAvailable)
        XCTAssertTrue(result.auditContractAvailable)
        XCTAssertTrue(result.freshRuntimeCheckRequired)
        XCTAssertEqual(result.readiness, MutationReadiness.preflightRequired.rawValue)
        // Executor exists for MOVE_TO_TRASH, but Fresh Preflight / approval still required.
        XCTAssertTrue(result.executorImplemented)
        XCTAssertTrue(result.approvalRequired || result.freshRuntimeCheckRequired)
    }

    func testUnknownStrictPredicateBlocks() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/Partial-abc"
        let item = makeItem(
            id: "xcode.deriveddata.partial",
            path: path,
            verification: VerificationAnnotation(
                sourceOfTruth: verified(.false),
                regenerable: ObservationRecord(value: .unknown, confidence: .unknown, completeness: .partial, source: .unknown),
                activeState: .inactive,
                activeStateConfidence: .verified,
                activeStateCompleteness: .complete
            )
        )
        let decision = ActionDecision(
            entityID: item.detected.entity.id,
            action: .moveToTrash,
            safetyClass: .unknown,
            eligible: false,
            missingClaimTypes: [.regenerability],
            blockedReasons: [.regenerabilityUnknown]
        )
        let result = MutationGate.evaluate(gateInput(item: item, action: .moveToTrash, decision: decision))
        XCTAssertEqual(result.readiness, MutationReadiness.blocked.rawValue)
    }

    func testConflictBlocks() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/Runner-abc"
        let item = makeItem(id: "xcode.deriveddata.runner", path: path)
        var snapshot = derivedSnapshot(path: path, entityID: item.detected.entity.id)
        snapshot.predicates.hasEvidenceConflict = true
        let decision = ActionDecision(
            entityID: item.detected.entity.id,
            action: .moveToTrash,
            safetyClass: .green,
            eligible: false,
            blockedReasons: [.evidenceConflict]
        )
        let result = MutationGate.evaluate(gateInput(item: item, action: .moveToTrash, decision: decision, snapshot: snapshot))
        XCTAssertEqual(result.readiness, MutationReadiness.blocked.rawValue)
        XCTAssertTrue(result.conflictedRequirements.contains("evidence_conflict"))
    }

    func testBindingFingerprintStable() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/Runner-abc"
        let item = makeItem(id: "xcode.deriveddata.runner", path: path)
        let snapshot = derivedSnapshot(path: path, entityID: item.detected.entity.id)
        let decision = ActionSafetyEvaluator.evaluate(item: item, action: .moveToTrash, engine: engine, evidence: snapshot.evidence, state: RuntimeState(), snapshot: snapshot)
        let input = gateInput(item: item, action: .moveToTrash, decision: decision, snapshot: snapshot)
        let a = ActionBindingFingerprintBuilder.compute(input: input)
        let b = ActionBindingFingerprintBuilder.compute(input: input)
        XCTAssertEqual(a, b)
    }

    func testBindingInvalidatesOnActionChange() {
        let path = "\(home)/Documents/video.mp4"
        let item = makeItem(id: "user.video", path: path, bucket: .userData, kind: .userOriginal)
        let fpTrash = ActionBindingFingerprint(entityID: item.detected.entity.id, action: .moveToTrash, canonicalPath: path, evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1, ruleVersion: "t", transactionContractVersion: "x")
        let fpICloud = ActionBindingFingerprint(entityID: item.detected.entity.id, action: .moveToICloud, canonicalPath: path, evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1, ruleVersion: "t", transactionContractVersion: "y")
        XCTAssertFalse(fpTrash.matches(fpICloud))
    }

    func testBindingInvalidatesOnPathChange() {
        let approval = UserActionApproval(
            approvalID: "a1",
            entityID: "e1",
            action: .moveToTrash,
            bindingFingerprint: ActionBindingFingerprint(entityID: "e1", action: .moveToTrash, canonicalPath: "/a", evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1, ruleVersion: "t", transactionContractVersion: "v"),
            consequenceSummaryVersion: "1",
            expectedRecoveryBytes: 1,
            approvedAt: Date(),
            expiryPolicy: "runtime_fresh",
            scope: "entity_action"
        )
        let current = ActionBindingFingerprint(entityID: "e1", action: .moveToTrash, canonicalPath: "/b", evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1, ruleVersion: "t", transactionContractVersion: "v")
        let reasons = ActionBindingFingerprintBuilder.invalidationReasons(approval: approval, current: current, decision: ActionDecision(entityID: "e1", action: .moveToTrash, safetyClass: .green, eligible: true))
        XCTAssertTrue(reasons.contains("PATH_CHANGED"))
    }

    func testVoiceMemoGenericMoveBlocked() {
        let item = makeItem(
            id: "voicememos.recording",
            path: "\(home)/Library/Application Support/com.apple.voicememos/Recording",
            bucket: .userData,
            kind: .applicationSupport
        )
        let decision = ActionSafetyEvaluator.evaluate(item: item, action: .moveToICloud, engine: engine, evidence: EvidenceBundle(canonicalPath: item.detected.entity.path), state: RuntimeState())
        let result = MutationGate.evaluate(gateInput(item: item, action: .moveToICloud, decision: decision))
        XCTAssertEqual(result.readiness, MutationReadiness.blocked.rawValue)
        XCTAssertTrue(result.blockingReasons.contains(HardProductBlock.genericLibraryRelocation.rawValue))
    }

    func testGitGenericMoveBlocked() {
        let item = makeItem(
            id: "git.repo",
            path: "\(home)/Workspace/project/.git",
            bucket: .developer,
            kind: .gitMetadata,
            safetyClass: .yellow
        )
        let decision = ActionSafetyEvaluator.evaluate(item: item, action: .moveToICloud, engine: engine, evidence: EvidenceBundle(canonicalPath: item.detected.entity.path), state: RuntimeState())
        let result = MutationGate.evaluate(gateInput(item: item, action: .moveToICloud, decision: decision))
        XCTAssertEqual(result.readiness, MutationReadiness.blocked.rawValue)
    }

    func testSOTTrueAllowedForICloudPreservation() {
        let path = "\(home)/Documents/report.pdf"
        let base = makeItem(id: "user.doc", path: path, bucket: .userData, kind: .userOriginal, safetyClass: .yellow)
        let verification = VerificationAnnotation(sourceOfTruth: verified(.true), regenerable: verified(.false), activeState: .inactive, activeStateConfidence: .verified, activeStateCompleteness: .complete)
        let item = ClassifiedItem(
            detected: DetectedEntity(
                entity: base.detected.entity,
                bucket: base.detected.bucket,
                domain: base.detected.domain,
                associatedProcesses: [],
                identified: true,
                annotation: DetectionAnnotation(detectorID: "t", specificity: 80, semanticType: "USER_DOC", lifecycle: LifecycleEvidence(role: .userContent, roleConfidence: .verified, activeState: .inactive))
            ),
            decision: base.decision,
            semantic: base.semantic,
            allocatedBytes: base.allocatedBytes,
            actionVariants: base.actionVariants,
            inclusiveBytes: base.inclusiveBytes,
            exclusiveBytes: base.exclusiveBytes,
            resolution: base.resolution,
            verification: verification
        )
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToICloud,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: path, sourceOfTruth: .true),
            state: RuntimeState(),
            userContext: ActionUserContext(wantsMoreFreeSpace: true, iCloudEnabled: true, allowManualReview: true)
        )
        XCTAssertTrue(decision.explanationCodes.contains("SOT_TRUE_ALLOWED") || decision.satisfiedClaimTypes.contains(.preservationContract))
    }

    func testRemoveLocalDownloadNotDelete() {
        XCTAssertNotEqual(StorageAction.removeLocalDownload.rawValue, "DELETE")
        XCTAssertNotEqual(StorageAction.removeLocalDownload.rawValue, "PERMANENT_DELETE")
        let trash = TransactionContractRegistry.transactionContract(for: .moveToTrash, item: makeItem(id: "x", path: "/tmp/DerivedData/X"))
        let evict = TransactionContractRegistry.transactionContract(for: .removeLocalDownload, item: makeItem(id: "cloud.f", path: "\(home)/Library/Mobile Documents/com~apple~CloudDocs/file", bucket: .cloud, kind: .cloudLocalMaterialized))
        XCTAssertNotNil(trash)
        XCTAssertNotEqual(trash?.failureBehavior, evict?.failureBehavior)
    }

    func testExecutionPermitRejectsInvalidReceiptResult() {
        let receipt = PreflightReceipt(
            receiptID: "r1",
            entityID: "e1",
            action: .moveToTrash,
            bindingFingerprint: ActionBindingFingerprint(entityID: "e1", action: .moveToTrash, canonicalPath: "/a", evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1, ruleVersion: "t", transactionContractVersion: "v"),
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
            result: "TEST"
        )
        let approval = UserActionApproval(
            approvalID: "a1",
            entityID: "e1",
            action: .moveToTrash,
            bindingFingerprint: receipt.bindingFingerprint,
            consequenceSummaryVersion: "1",
            expectedRecoveryBytes: nil,
            approvedAt: Date(),
            expiryPolicy: "runtime_fresh",
            scope: "entity"
        )
        let permit = ExecutionPermit.generate(receipt: receipt, approval: approval, decision: ActionDecision(entityID: "e1", action: .moveToTrash, safetyClass: .green, eligible: true))
        XCTAssertNil(permit)
    }

    func testMutationSurfaceAuditPasses() {
        let audit = MutationSurfaceAudit.audit(repositoryRoot: FileManager.default.currentDirectoryPath)
        XCTAssertEqual(audit.actualMutationImplementations, 1)
        XCTAssertTrue(audit.auditPassed)
        XCTAssertTrue(audit.executorImplemented)
    }

    func testDryRunPlanHasNoShellCommands() {
        let entry = MutationGateResult(
            entityID: "e1",
            path: "/tmp/DerivedData/X",
            action: StorageAction.moveToTrash.rawValue,
            safetyClass: SafetyClass.green.rawValue,
            recommendation: StorageAction.moveToTrash.rawValue,
            readiness: MutationReadiness.preflightRequired.rawValue,
            satisfiedRequirements: [],
            missingRequirements: [],
            staleRequirements: [],
            conflictedRequirements: [],
            blockingReasons: [],
            requiredFreshChecks: ["fresh_runtime_preflight"],
            actionBindingFingerprint: nil,
            transactionContractAvailable: true,
            postVerifyContractAvailable: true,
            auditContractAvailable: true,
            freshRuntimeCheckRequired: true,
            freshCloudCheckRequired: false,
            approvalRequired: true,
            executorImplemented: false
        )
        let plan = DryRunActionPlanBuilder.plan(for: entry, action: .moveToTrash)
        XCTAssertTrue(plan.executorImplemented)
        XCTAssertTrue(plan.steps.allSatisfy { !$0.step.contains("rm ") && !$0.step.contains("mv ") })
        XCTAssertEqual(plan.steps.filter(\.mutates).count, 1)
    }

    func testDeferredIsNotEvidenceInGate() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/Runner-abc"
        let item = makeItem(id: "xcode.deriveddata.runner", path: path)
        let runtime = RuntimeStateResolution(
            entityID: item.detected.entity.id,
            disposition: .deferred,
            deferReason: .noRuntimePredicateInCandidateRule,
            activeState: .unknown,
            activeStateConfidence: .unknown,
            activeStateCompleteness: .unknown,
            openFileHandle: .unknown,
            openFileConfidence: .unknown,
            unknownReasons: ["DEFERRED"],
            lookupMs: 0
        )
        let decision = ActionDecision(entityID: item.detected.entity.id, action: .moveToTrash, safetyClass: .green, eligible: true)
        let result = MutationGate.evaluate(gateInput(item: item, action: .moveToTrash, decision: decision, runtime: runtime))
        XCTAssertTrue(result.staleRequirements.contains("runtime_deferred_not_evidence"))
    }
}
