import XCTest
@testable import SafetyCore

final class P206RealPreflightClosureTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private lazy var engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: []))

    private func verified(_ value: PredicateValue) -> ObservationRecord {
        ObservationRecord(value: value, confidence: .verified, completeness: .complete, source: .filesystemMetadata)
    }

    private func makeDerivedItem(id: String, path: String) -> ClassifiedItem {
        let entity = StorageEntity(id: id, kind: .generatedBuild, category: "DEV", subcategory: "XCODE", displayName: id, path: path, logicalBytes: 36_000_000)
        let decision = SafetyDecision(
            entity: entity,
            action: .moveToTrash,
            safetyClass: .green,
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
            detected: DetectedEntity(entity: entity, bucket: .generated, domain: "Developer", associatedProcesses: ["Xcode"], identified: true, annotation: nil),
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: 36_000_000,
            actionVariants: [:],
            inclusiveBytes: 36_000_000,
            exclusiveBytes: 36_000_000,
            resolution: .l5Actionable,
            verification: VerificationAnnotation(
                sourceOfTruth: verified(.false),
                regenerable: verified(.true),
                activeState: .inactive,
                activeStateConfidence: .verified,
                activeStateCompleteness: .complete
            )
        )
    }

    private func derivedSnapshot(path: String, entityID: String, runtimeGen: Int = 1) -> EntitySafetySnapshot {
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
            cacheKey: EntitySnapshotCacheKey(entityID: entityID, evidenceVersion: 1, verificationGeneration: 1, runtimeGeneration: runtimeGen),
            finalizedAt: Date(),
            finalizationMs: 1
        )
    }

    private func inactiveRuntime(entityID: String) -> RuntimeStateResolution {
        RuntimeStateResolution(
            entityID: entityID,
            disposition: .resolved,
            deferReason: nil,
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete,
            openFileHandle: .false,
            openFileConfidence: .verified,
            unknownReasons: [],
            lookupMs: 0
        )
    }

    private func activeRuntime(entityID: String) -> RuntimeStateResolution {
        RuntimeStateResolution(
            entityID: entityID,
            disposition: .resolved,
            deferReason: nil,
            activeState: .active,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete,
            openFileHandle: .false,
            openFileConfidence: .verified,
            unknownReasons: [],
            lookupMs: 0
        )
    }

    private func openHandleRuntime(entityID: String) -> RuntimeStateResolution {
        RuntimeStateResolution(
            entityID: entityID,
            disposition: .resolved,
            deferReason: nil,
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete,
            openFileHandle: .true,
            openFileConfidence: .verified,
            unknownReasons: [],
            lookupMs: 0
        )
    }

    private func incompleteOpenRuntime(entityID: String) -> RuntimeStateResolution {
        RuntimeStateResolution(
            entityID: entityID,
            disposition: .resolved,
            deferReason: nil,
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete,
            openFileHandle: .unknown,
            openFileConfidence: .unknown,
            unknownReasons: ["UNKNOWN_EVIDENCE_INCOMPLETE"],
            lookupMs: 0
        )
    }

    private func procSnap(names: Set<String> = [], commandLines: [String] = []) -> ProcessTableSnapshot {
        ProcessTableSnapshot(names: names, commandLines: commandLines, snapshotFailed: false, failureReason: nil, completeness: .complete)
    }

    private func fileSnap(openPaths: [String] = [], completeness: ObservationCompleteness = .complete, failed: Bool = false) -> OpenFileSnapshot {
        OpenFileSnapshot(openPaths: openPaths, snapshotFailed: failed, failureReason: failed ? "TIMEOUT" : nil, completeness: completeness)
    }

    private func gateInput(item: ClassifiedItem, decision: ActionDecision, snapshot: EntitySafetySnapshot, runtime: RuntimeStateResolution) -> MutationGateInput {
        MutationGateInput(
            item: item,
            action: .moveToTrash,
            actionDecision: decision,
            snapshot: snapshot,
            recommendation: nil,
            preflight: nil,
            runtimeResolution: runtime,
            transactionContract: TransactionContractRegistry.transactionContract(for: .moveToTrash, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .moveToTrash, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: .moveToTrash, item: item),
            approvalState: .scanDefault,
            evidenceGeneration: snapshot.evidence.snapshotVersion,
            verificationGeneration: snapshot.verification.snapshotGeneration,
            runtimeGeneration: snapshot.cacheKey.runtimeGeneration,
            ruleVersion: "t"
        )
    }

    func testFreshPreflightPerformsNoMutation() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/P206NoMutation-\(UUID().uuidString.prefix(6))"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let id = "xcode.deriveddata.p206nomutation"
        let item = makeDerivedItem(id: id, path: path)
        let snapshot = derivedSnapshot(path: path, entityID: id)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item, action: .moveToTrash, engine: engine,
            evidence: snapshot.evidence, state: RuntimeState(), snapshot: snapshot,
            safetyDecisions: [.moveToTrash: item.decision]
        )
        let scanGate = MutationGate.evaluate(gateInput(item: item, decision: decision, snapshot: snapshot, runtime: inactiveRuntime(entityID: id)))

        let run = FreshReadOnlyPreflightEngine.run(
            sessionID: "test-no-mutation",
            item: item,
            action: .moveToTrash,
            scanDecision: decision,
            scanGate: scanGate,
            snapshot: snapshot,
            recommendation: nil,
            preflight: nil,
            scanRuntimeResolution: inactiveRuntime(entityID: id),
            ruleVersion: "t",
            engine: engine,
            processes: procSnap(),
            handles: fileSnap()
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertNotEqual(run.receipt.result, PreflightResultCode.satisfiedReadOnly.rawValue + "_MUTATED")
    }

    func testStaleRuntimeCannotReachApprovalRequired() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/P206Stale-\(UUID().uuidString.prefix(6))"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let id = "xcode.deriveddata.p206stale"
        let item = makeDerivedItem(id: id, path: path)
        let snapshot = derivedSnapshot(path: path, entityID: id)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item, action: .moveToTrash, engine: engine,
            evidence: snapshot.evidence, state: RuntimeState(), snapshot: snapshot,
            safetyDecisions: [.moveToTrash: item.decision]
        )
        let scanGate = MutationGate.evaluate(gateInput(item: item, decision: decision, snapshot: snapshot, runtime: inactiveRuntime(entityID: id)))

        let run = FreshReadOnlyPreflightEngine.run(
            sessionID: "test-active-block",
            item: item,
            action: .moveToTrash,
            scanDecision: decision,
            scanGate: scanGate,
            snapshot: snapshot,
            recommendation: nil,
            preflight: nil,
            scanRuntimeResolution: inactiveRuntime(entityID: id),
            ruleVersion: "t",
            engine: engine,
            processes: procSnap(names: ["Xcode"], commandLines: [path]),
            handles: fileSnap()
        )
        XCTAssertNotEqual(run.freshGateResult.readiness, MutationReadiness.approvalRequired.rawValue)
        XCTAssertEqual(run.freshRuntimeResolution.activeState, .active)
    }

    func testOpenHandleBlocksReadiness() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/P206Open-\(UUID().uuidString.prefix(6))"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let id = "xcode.deriveddata.p206open"
        let item = makeDerivedItem(id: id, path: path)
        let snapshot = derivedSnapshot(path: path, entityID: id)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item, action: .moveToTrash, engine: engine,
            evidence: snapshot.evidence, state: RuntimeState(), snapshot: snapshot,
            safetyDecisions: [.moveToTrash: item.decision]
        )
        let scanGate = MutationGate.evaluate(gateInput(item: item, decision: decision, snapshot: snapshot, runtime: inactiveRuntime(entityID: id)))

        let run = FreshReadOnlyPreflightEngine.run(
            sessionID: "test-open-block",
            item: item,
            action: .moveToTrash,
            scanDecision: decision,
            scanGate: scanGate,
            snapshot: snapshot,
            recommendation: nil,
            preflight: nil,
            scanRuntimeResolution: inactiveRuntime(entityID: id),
            ruleVersion: "t",
            engine: engine,
            processes: procSnap(),
            handles: fileSnap(openPaths: [path])
        )
        XCTAssertNotEqual(run.freshGateResult.readiness, MutationReadiness.approvalRequired.rawValue)
        XCTAssertEqual(run.freshRuntimeResolution.openFileHandle, .true)
    }

    func testIncompleteLsofCannotProveOpenSafe() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/P206Lsof-\(UUID().uuidString.prefix(6))"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let id = "xcode.deriveddata.p206lsof"
        let item = makeDerivedItem(id: id, path: path)
        let snapshot = derivedSnapshot(path: path, entityID: id)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item, action: .moveToTrash, engine: engine,
            evidence: snapshot.evidence, state: RuntimeState(), snapshot: snapshot,
            safetyDecisions: [.moveToTrash: item.decision]
        )
        let scanGate = MutationGate.evaluate(gateInput(item: item, decision: decision, snapshot: snapshot, runtime: inactiveRuntime(entityID: id)))

        let run = FreshReadOnlyPreflightEngine.run(
            sessionID: "test-lsof-incomplete",
            item: item,
            action: .moveToTrash,
            scanDecision: decision,
            scanGate: scanGate,
            snapshot: snapshot,
            recommendation: nil,
            preflight: nil,
            scanRuntimeResolution: inactiveRuntime(entityID: id),
            ruleVersion: "t",
            engine: engine,
            processes: procSnap(),
            handles: fileSnap(completeness: .unknown, failed: true)
        )
        XCTAssertNotEqual(run.freshGateResult.readiness, MutationReadiness.approvalRequired.rawValue)
        XCTAssertTrue(run.receipt.staleClaims.contains(.openFileState) || run.receipt.missingClaims.contains(.openFileState))
    }

    func testBindingMismatchInvalidatesPreflight() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/P206Bind-\(UUID().uuidString.prefix(6))"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let id = "xcode.deriveddata.p206bind"
        let item = makeDerivedItem(id: id, path: path)
        let snapshot = derivedSnapshot(path: path, entityID: id)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item, action: .moveToTrash, engine: engine,
            evidence: snapshot.evidence, state: RuntimeState(), snapshot: snapshot,
            safetyDecisions: [.moveToTrash: item.decision]
        )
        var scanGate = MutationGate.evaluate(gateInput(item: item, decision: decision, snapshot: snapshot, runtime: inactiveRuntime(entityID: id)))
        if var fp = scanGate.actionBindingFingerprint {
            fp.canonicalPath = "/wrong/path"
            scanGate.actionBindingFingerprint = fp
        }

        let run = FreshReadOnlyPreflightEngine.run(
            sessionID: "test-binding",
            item: item,
            action: .moveToTrash,
            scanDecision: decision,
            scanGate: scanGate,
            snapshot: snapshot,
            recommendation: nil,
            preflight: nil,
            scanRuntimeResolution: inactiveRuntime(entityID: id),
            ruleVersion: "t",
            engine: engine,
            processes: procSnap(),
            handles: fileSnap()
        )
        XCTAssertEqual(run.receipt.result, PreflightResultCode.candidateChanged.rawValue)
    }

    func testValidFreshPreflightReachesApprovalRequired() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/P206Valid-\(UUID().uuidString.prefix(6))"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let id = "xcode.deriveddata.p206valid"
        let item = makeDerivedItem(id: id, path: path)
        let snapshot = derivedSnapshot(path: path, entityID: id)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item, action: .moveToTrash, engine: engine,
            evidence: snapshot.evidence, state: RuntimeState(), snapshot: snapshot,
            safetyDecisions: [.moveToTrash: item.decision]
        )
        let scanGate = MutationGate.evaluate(gateInput(item: item, decision: decision, snapshot: snapshot, runtime: inactiveRuntime(entityID: id)))
        XCTAssertEqual(scanGate.readiness, MutationReadiness.preflightRequired.rawValue)

        let run = FreshReadOnlyPreflightEngine.run(
            sessionID: "test-approval",
            item: item,
            action: .moveToTrash,
            scanDecision: decision,
            scanGate: scanGate,
            snapshot: snapshot,
            recommendation: nil,
            preflight: nil,
            scanRuntimeResolution: inactiveRuntime(entityID: id),
            ruleVersion: "t",
            engine: engine,
            processes: procSnap(),
            handles: fileSnap()
        )
        XCTAssertEqual(run.receipt.result, PreflightResultCode.satisfiedReadOnly.rawValue)
        XCTAssertEqual(run.freshGateResult.readiness, MutationReadiness.approvalRequired.rawValue)
        XCTAssertTrue(run.freshGateResult.approvalRequired)
        // Capability implemented ≠ execution authorized.
        XCTAssertTrue(run.freshGateResult.executorImplemented)
        XCTAssertNotEqual(run.freshGateResult.readiness, MutationReadiness.contractSatisfiedReadOnly.rawValue)
    }

    func testApprovalRequiredDoesNotGenerateExecutionPermit() {
        let permit = ExecutionPermit.generate(
            receipt: PreflightReceipt(
                receiptID: "r", entityID: "e", action: .moveToTrash,
                bindingFingerprint: ActionBindingFingerprint(
                    entityID: "e", action: .moveToTrash, canonicalPath: "/p",
                    evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1,
                    ruleVersion: "t", transactionContractVersion: "1"
                ),
                requiredClaims: [], satisfiedClaims: [], missingClaims: [], staleClaims: [], conflictedClaims: [],
                observedAt: Date(), freshnessValidity: [.runtimeFresh],
                evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1,
                result: PreflightResultCode.satisfiedReadOnly.rawValue
            ),
            approval: UserActionApproval(
                approvalID: "a", entityID: "e", action: .moveToTrash,
                bindingFingerprint: ActionBindingFingerprint(
                    entityID: "e", action: .moveToTrash, canonicalPath: "/p",
                    evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1,
                    ruleVersion: "t", transactionContractVersion: "1"
                ),
                consequenceSummaryVersion: "1", expectedRecoveryBytes: nil,
                approvedAt: Date(), expiryPolicy: "session", scope: "single"
            ),
            decision: ActionDecision(entityID: "e", action: .moveToTrash, safetyClass: .green, eligible: true, explanationCodes: [])
        )
        XCTAssertNil(permit)
    }

    func testFreshPreflightReceiptSatisfiesMutationGate() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/P206Gate-\(UUID().uuidString.prefix(6))"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let id = "xcode.deriveddata.p206gate"
        let item = makeDerivedItem(id: id, path: path)
        let snapshot = derivedSnapshot(path: path, entityID: id)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item, action: .moveToTrash, engine: engine,
            evidence: snapshot.evidence, state: RuntimeState(), snapshot: snapshot,
            safetyDecisions: [.moveToTrash: item.decision]
        )
        let scanGate = MutationGate.evaluate(gateInput(item: item, decision: decision, snapshot: snapshot, runtime: inactiveRuntime(entityID: id)))
        let run = FreshReadOnlyPreflightEngine.run(
            sessionID: "test-gate",
            item: item,
            action: .moveToTrash,
            scanDecision: decision,
            scanGate: scanGate,
            snapshot: snapshot,
            recommendation: nil,
            preflight: nil,
            scanRuntimeResolution: inactiveRuntime(entityID: id),
            ruleVersion: "t",
            engine: engine,
            processes: procSnap(),
            handles: fileSnap()
        )
        XCTAssertTrue(run.freshGateResult.satisfiedRequirements.contains("fresh_runtime_preflight"))
    }

    func testCandidateResolverUsesInventoryFallback() {
        let inventory = FirstMutationCandidateInventoryReport(
            entries: [
                FirstMutationCandidateEntry(
                    entityID: "xcode.deriveddata.child",
                    semanticType: nil,
                    canonicalPath: "/tmp/child",
                    action: StorageAction.moveToTrash.rawValue,
                    safetyClass: SafetyClass.green.rawValue,
                    actionEligible: true,
                    recommendation: nil,
                    recommendationDisposition: nil,
                    mutationReadiness: MutationReadiness.preflightRequired.rawValue,
                    proofCompletenessScore: 90,
                    runtimeRequirements: [],
                    cloudRequirements: [],
                    transactionContractAvailable: true,
                    postVerifyContractAvailable: true,
                    auditContractAvailable: true,
                    bindingFingerprintPossible: true,
                    expectedLogicalBytes: 1000,
                    potentialLocalRecovery: 1000,
                    reversibility: "HIGH",
                    blastRadius: BlastRadiusClass.low.rawValue,
                    transactionComplexity: TransactionComplexityClass.simple.rawValue,
                    fitnessTier: FirstMutationFitnessTier.blockedByEvidence.rawValue,
                    fitnessScore: 80,
                    rankingEligible: false,
                    exactBoundedEntity: true,
                    blockingReasons: [],
                    missingRequirements: ["fresh_runtime_preflight"],
                    executorImplemented: false
                ),
            ],
            entitiesDiscovered: 1,
            moveToTrashCandidates: 1,
            moveToICloudCandidates: 0,
            removeLocalDownloadCandidates: 0,
            vendorNativeCandidates: 0,
            exactBoundedEntities: 1,
            broadRootEntitiesRejected: 0,
            preflightRequired: 1,
            approvalRequired: 0,
            contractSatisfiedReadOnly: 0,
            blockedCount: 0,
            executorImplemented: false
        )
        let selection = FirstMutationCandidateSelectionReport(
            outcome: FirstMutationSelectionOutcome.noSafeRealMutationCandidate.rawValue,
            selectedEntityID: nil,
            selectedAction: nil,
            selectedPath: nil,
            rationale: nil,
            remainingHumanApprovalRequired: false,
            executorImplemented: false
        )
        let resolved = RealPreflightClosureAnalyzer.resolveCandidate(
            selection: selection,
            inventory: inventory,
            ranking: FirstMutationCandidateRankingReport(entries: [], rankingEligibleCount: 0),
            gate: nil
        )
        XCTAssertEqual(resolved?.entityID, "xcode.deriveddata.child")
        XCTAssertEqual(resolved?.action, .moveToTrash)
    }

    func testCandidateResolverPrefersDerivedDataTrashOverKeychain() {
        let inventory = FirstMutationCandidateInventoryReport(
            entries: [
                FirstMutationCandidateEntry(
                    entityID: "macos.keychain",
                    semanticType: nil,
                    canonicalPath: "/Library/Keychains",
                    action: StorageAction.moveToICloud.rawValue,
                    safetyClass: SafetyClass.green.rawValue,
                    actionEligible: true,
                    recommendation: "KEEP",
                    recommendationDisposition: "keep",
                    mutationReadiness: MutationReadiness.preflightRequired.rawValue,
                    proofCompletenessScore: 75,
                    runtimeRequirements: [],
                    cloudRequirements: [],
                    transactionContractAvailable: true,
                    postVerifyContractAvailable: true,
                    auditContractAvailable: true,
                    bindingFingerprintPossible: true,
                    expectedLogicalBytes: 1000,
                    potentialLocalRecovery: 0,
                    reversibility: "PRESERVATION_NOT_DELETION",
                    blastRadius: BlastRadiusClass.low.rawValue,
                    transactionComplexity: TransactionComplexityClass.complex.rawValue,
                    fitnessTier: FirstMutationFitnessTier.tooComplexForFirstMutation.rawValue,
                    fitnessScore: 0,
                    rankingEligible: false,
                    exactBoundedEntity: true,
                    blockingReasons: [],
                    missingRequirements: ["fresh_runtime_preflight"],
                    executorImplemented: false
                ),
                FirstMutationCandidateEntry(
                    entityID: "xcode.deriveddata.child",
                    semanticType: "XCODE_DERIVEDDATA_INSTANCE",
                    canonicalPath: "/tmp/child",
                    action: StorageAction.moveToTrash.rawValue,
                    safetyClass: SafetyClass.green.rawValue,
                    actionEligible: true,
                    recommendation: "MOVE_TO_TRASH",
                    recommendationDisposition: "actionable:MOVE_TO_TRASH",
                    mutationReadiness: MutationReadiness.preflightRequired.rawValue,
                    proofCompletenessScore: 84,
                    runtimeRequirements: [],
                    cloudRequirements: [],
                    transactionContractAvailable: true,
                    postVerifyContractAvailable: true,
                    auditContractAvailable: true,
                    bindingFingerprintPossible: true,
                    expectedLogicalBytes: 1000,
                    potentialLocalRecovery: 1000,
                    reversibility: "TRASH_REVERSIBLE",
                    blastRadius: BlastRadiusClass.high.rawValue,
                    transactionComplexity: TransactionComplexityClass.simple.rawValue,
                    fitnessTier: FirstMutationFitnessTier.blockedByEvidence.rawValue,
                    fitnessScore: 0,
                    rankingEligible: false,
                    exactBoundedEntity: true,
                    blockingReasons: [],
                    missingRequirements: ["fresh_runtime_preflight"],
                    executorImplemented: false
                ),
            ],
            entitiesDiscovered: 2,
            moveToTrashCandidates: 1,
            moveToICloudCandidates: 1,
            removeLocalDownloadCandidates: 0,
            vendorNativeCandidates: 0,
            exactBoundedEntities: 2,
            broadRootEntitiesRejected: 0,
            preflightRequired: 2,
            approvalRequired: 0,
            contractSatisfiedReadOnly: 0,
            blockedCount: 0,
            executorImplemented: false
        )
        let selection = FirstMutationCandidateSelectionReport(
            outcome: FirstMutationSelectionOutcome.noSafeRealMutationCandidate.rawValue,
            selectedEntityID: nil,
            selectedAction: nil,
            selectedPath: nil,
            rationale: nil,
            remainingHumanApprovalRequired: false,
            executorImplemented: false
        )
        let resolved = RealPreflightClosureAnalyzer.resolveCandidate(
            selection: selection,
            inventory: inventory,
            ranking: FirstMutationCandidateRankingReport(entries: [], rankingEligibleCount: 0)
        )
        XCTAssertEqual(resolved?.entityID, "xcode.deriveddata.child")
        XCTAssertEqual(resolved?.action, .moveToTrash)
    }
}
