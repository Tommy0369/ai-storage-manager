import XCTest
@testable import SafetyCore

final class P211FirstMutatingExecutorTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    private func makeReceipt(entityID: String, path: String) -> PreflightReceipt {
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
        return PreflightReceipt(
            receiptID: "r1",
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
    }

    private func makeApproval(entityID: String, path: String) -> UserActionApproval {
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
        return UserActionApproval(
            approvalID: "a1",
            entityID: entityID,
            action: .moveToTrash,
            bindingFingerprint: fp,
            consequenceSummaryVersion: "P2.1",
            expectedRecoveryBytes: 1000,
            approvedAt: Date(),
            expiryPolicy: "single_use",
            scope: "test"
        )
    }

    func testExecutionPermitValidInputsGeneratesPermit() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/TestChild-\(UUID().uuidString.prefix(4))"
        let receipt = makeReceipt(entityID: "xcode.deriveddata.testchild", path: path)
        let approval = makeApproval(entityID: "xcode.deriveddata.testchild", path: path)
        let decision = ActionDecision(
            entityID: "xcode.deriveddata.testchild",
            action: .moveToTrash,
            safetyClass: .green,
            eligible: true,
            explanationCodes: []
        )
        let permit = ExecutionPermit.generate(receipt: receipt, approval: approval, decision: decision)
        XCTAssertNotNil(permit)
        XCTAssertEqual(permit?.action, .moveToTrash)
    }

    func testExecutionPermitRejectsNonDerivedDataPath() {
        let path = "\(home)/Documents/file.txt"
        let receipt = makeReceipt(entityID: "user.documents", path: path)
        let approval = makeApproval(entityID: "user.documents", path: path)
        let decision = ActionDecision(entityID: "user.documents", action: .moveToTrash, safetyClass: .green, eligible: true, explanationCodes: [])
        XCTAssertNil(ExecutionPermit.generate(receipt: receipt, approval: approval, decision: decision))
    }

    func testExecutionPermitRejectsStaleReceipt() {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/Child"
        var receipt = makeReceipt(entityID: "xcode.deriveddata.child", path: path)
        receipt.staleClaims = [.activeState]
        let approval = makeApproval(entityID: "xcode.deriveddata.child", path: path)
        let decision = ActionDecision(entityID: "xcode.deriveddata.child", action: .moveToTrash, safetyClass: .green, eligible: true, explanationCodes: [])
        XCTAssertNil(ExecutionPermit.generate(receipt: receipt, approval: approval, decision: decision))
    }

    func testTrashExecutorMovesToTrashWithoutDelete() throws {
        let dir = makeTempDerivedDataChild()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        var trashed: URL?
        let executor = FirstMutatingExecutor { source in
            let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("trash-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let moved = dest.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: moved)
            trashed = moved
            return moved
        }

        let path = dir
        let entityID = "xcode.deriveddata.p211exec"
        let fp = ActionBindingFingerprint(
            entityID: entityID, action: .moveToTrash, canonicalPath: path,
            evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1,
            ruleVersion: "t", transactionContractVersion: TransactionContractRegistry.trashVersion
        )
        let permit = ExecutionPermit(
            permitID: "p1", entityID: entityID, action: .moveToTrash,
            bindingFingerprint: fp, preflightReceiptID: "r1", approvalID: "a1", issuedAt: Date()
        )
        let plan = DryRunActionPlan(
            entityID: entityID, path: path, action: StorageAction.moveToTrash.rawValue,
            readiness: MutationReadiness.approvalRequired.rawValue, steps: [], executorImplemented: true
        )

        let audit = try executor.executeTrash(plan: plan, permit: permit)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertNotNil(trashed)
        XCTAssertEqual(audit.destinationPath, trashed?.path)
    }

    func testICloudExecutorNotImplemented() {
        let executor = FirstMutatingExecutor.shared
        let plan = DryRunActionPlan(entityID: "e", path: "/p", action: "MOVE_TO_ICLOUD", readiness: "BLOCKED", steps: [], executorImplemented: true)
        let permit = ExecutionPermit(
            permitID: "p", entityID: "e", action: .moveToICloud,
            bindingFingerprint: ActionBindingFingerprint(
                entityID: "e", action: .moveToICloud, canonicalPath: "/p",
                evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1,
                ruleVersion: "t", transactionContractVersion: "x"
            ),
            preflightReceiptID: "r", approvalID: "a", issuedAt: Date()
        )
        XCTAssertThrowsError(try executor.executeICloudMove(plan: plan, permit: permit)) { error in
            guard case ActionExecutionError.executorNotImplemented(let action) = error else {
                return XCTFail("expected executorNotImplemented, got \(error)")
            }
            XCTAssertEqual(action, .moveToICloud)
        }
    }

    func testMutationSurfaceAuditAllowsAuthorizedExecutor() {
        let root = FileManager.default.currentDirectoryPath
        let audit = MutationSurfaceAudit.audit(repositoryRoot: root)
        XCTAssertTrue(audit.executorImplemented)
        XCTAssertEqual(audit.actualMutationImplementations, 1)
        XCTAssertTrue(audit.auditPassed)
    }

    func testHumanConfirmationRequired() {
        let path = makeTempDerivedDataChild()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let item = makeDerivedItem(id: "xcode.deriveddata.p211", path: path)
        let engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: []))
        let snapshot = derivedSnapshot(path: path, entityID: item.detected.entity.id)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item, action: .moveToTrash, engine: engine,
            evidence: snapshot.evidence, state: RuntimeState(), snapshot: snapshot,
            safetyDecisions: [.moveToTrash: item.decision]
        )
        let gate = MutationGate.evaluate(gateInput(item: item, decision: decision, snapshot: snapshot))
        XCTAssertThrowsError(try ActExecutionOrchestrator.executeFirstMutationTrash(
            ActExecutionOrchestrator.ExecuteInput(
                entityID: item.detected.entity.id,
                action: .moveToTrash,
                item: item,
                snapshot: snapshot,
                scanDecision: decision,
                scanGate: gate,
                scanRuntimeResolution: inactiveRuntime(entityID: item.detected.entity.id),
                postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .moveToTrash, item: item),
                ruleVersion: "t",
                humanConfirmed: false,
                expectedRecoveryBytes: 100,
                engine: engine,
                executor: FirstMutatingExecutor { _ in URL(fileURLWithPath: "/tmp/x") },
                processes: procSnap(),
                handles: fileSnap()
            )
        )) { error in
            XCTAssertEqual(error as? ActionExecutionError, .humanConfirmationRequired)
        }
    }

    // MARK: - Helpers

    private func makeTempDerivedDataChild() -> String {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/P211-\(UUID().uuidString.prefix(6))"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try? "test".write(toFile: "\(path)/build.dat", atomically: true, encoding: .utf8)
        return path
    }

    private func makeDerivedItem(id: String, path: String) -> ClassifiedItem {
        let entity = StorageEntity(id: id, kind: .generatedBuild, category: "DEV", subcategory: "XCODE", displayName: id, path: path, logicalBytes: 1000)
        let decision = SafetyDecision(
            entity: entity, action: .moveToTrash, safetyClass: .green,
            safetyScore: SafetyScore(value: 95), reasonCodes: ["GENERATED_DATA"],
            sideEffects: [], matchedRuleID: "test", evaluationLayer: .exactVendor,
            evidenceConfidence: 0.95, userExplanationJA: "dd", growthCauses: [],
            requiresUserApproval: true, blockedBy: nil
        )
        return ClassifiedItem(
            detected: DetectedEntity(entity: entity, bucket: .generated, domain: "Developer", associatedProcesses: ["Xcode"], identified: true, annotation: nil),
            decision: decision, semantic: SemanticResult(from: decision),
            allocatedBytes: 1000, actionVariants: [:], inclusiveBytes: 1000, exclusiveBytes: 1000,
            resolution: .l5Actionable,
            verification: VerificationAnnotation(
                sourceOfTruth: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
                regenerable: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
                activeState: .inactive, activeStateConfidence: .verified, activeStateCompleteness: .complete
            )
        )
    }

    private func derivedSnapshot(path: String, entityID: String) -> EntitySafetySnapshot {
        var evidence = EvidenceBundle(canonicalPath: path, sourceOfTruth: .false, regenerable: .true)
        evidence.openFileHandle = .false
        return EntitySafetySnapshot(
            entityID: entityID,
            entity: StorageEntity(id: entityID, kind: .generatedBuild, category: "DEV", subcategory: "XCODE", displayName: "d", path: path, logicalBytes: 1),
            detected: DetectedEntity(
                entity: StorageEntity(id: entityID, kind: .generatedBuild, category: "DEV", subcategory: "XCODE", displayName: "d", path: path, logicalBytes: 1),
                bucket: .generated, domain: "Developer", associatedProcesses: ["Xcode"], identified: true, annotation: nil
            ),
            evidence: evidence,
            state: RuntimeState(),
            verification: VerificationAnnotation(
                sourceOfTruth: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
                regenerable: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
                activeState: .inactive, activeStateConfidence: .verified, activeStateCompleteness: .complete
            ),
            predicates: EntityPredicateSnapshot(
                sourceOfTruth: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
                regenerability: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
                activeState: .inactive, activeStateConfidence: .verified,
                openFileHandle: .false, openFileConfidence: .verified,
                isGitRepository: false, isApplicationManaged: true, isDerivedData: true,
                isUserOwnedVerified: false, hasEvidenceConflict: false, hasCanonicalPath: true,
                isSymlinkAmbiguity: false, isUserOriginal: false, isGeneratedArtifact: true,
                isInsideProtectedRoot: false, fileProviderBacked: false, remoteBackingVerified: false, syncSafeVerified: false
            ),
            relationships: [],
            cacheKey: EntitySnapshotCacheKey(entityID: entityID, evidenceVersion: 1, verificationGeneration: 1, runtimeGeneration: 1),
            finalizedAt: Date(), finalizationMs: 1
        )
    }

    private func inactiveRuntime(entityID: String) -> RuntimeStateResolution {
        RuntimeStateResolution(
            entityID: entityID, disposition: .resolved, deferReason: nil,
            activeState: .inactive, activeStateConfidence: .verified, activeStateCompleteness: .complete,
            openFileHandle: .false, openFileConfidence: .verified, unknownReasons: [], lookupMs: 0
        )
    }

    private func gateInput(item: ClassifiedItem, decision: ActionDecision, snapshot: EntitySafetySnapshot) -> MutationGateInput {
        MutationGateInput(
            item: item, action: .moveToTrash, actionDecision: decision, snapshot: snapshot,
            recommendation: nil, preflight: nil,
            runtimeResolution: inactiveRuntime(entityID: item.detected.entity.id),
            transactionContract: TransactionContractRegistry.transactionContract(for: .moveToTrash, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .moveToTrash, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: .moveToTrash, item: item),
            approvalState: .scanDefault,
            evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1, ruleVersion: "t"
        )
    }

    private func procSnap() -> ProcessTableSnapshot {
        ProcessTableSnapshot(names: [], commandLines: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
    }

    private func fileSnap() -> OpenFileSnapshot {
        OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
    }
}

extension ActionExecutionError: Equatable {
    public static func == (lhs: ActionExecutionError, rhs: ActionExecutionError) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}
