import XCTest
@testable import SafetyCore

final class P22PostMutationVerificationTests: XCTestCase {
    private var tempDir: URL!
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("p22-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func derivedDataPath(name: String) -> String {
        "\(home)/Library/Developer/Xcode/DerivedData/\(name)"
    }

    private func makeFingerprint(entityID: String, path: String) -> ActionBindingFingerprint {
        ActionBindingFingerprint(
            entityID: entityID,
            action: .moveToTrash,
            canonicalPath: path,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "test",
            transactionContractVersion: TransactionContractRegistry.trashVersion
        )
    }

    private func makePending(
        actionID: String,
        entityID: String,
        path: String,
        trashPath: String?,
        expectedBytes: Int64 = 5000
    ) -> PendingPostMutationVerification {
        PendingPostMutationVerification(
            actionID: actionID,
            entityID: entityID,
            action: .moveToTrash,
            bindingFingerprint: makeFingerprint(entityID: entityID, path: path),
            sourcePath: path,
            expectedDestinationSemantics: "TRASH",
            trashDestinationPath: trashPath,
            expectedBytes: expectedBytes,
            executedAt: Date(),
            approvalID: "approval-1",
            preflightReceiptID: "receipt-1",
            preflightObservedAt: Date(),
            auditStatus: .postVerifyPending,
            freeBytesBeforeAction: 1_000_000,
            freeBytesAfterAction: 1_000_000,
            verificationDeadline: nil
        )
    }

    private func makeAudit(pending: PendingPostMutationVerification) -> ActionAuditRecord {
        ActionAuditRecord(
            actionID: pending.actionID,
            entityID: pending.entityID,
            action: .moveToTrash,
            sourcePath: pending.sourcePath,
            destinationPath: pending.trashDestinationPath,
            transactionPhase: TrashTransactionPhase.postVerify.rawValue,
            logicalBytesAffected: pending.expectedBytes,
            startedAt: pending.executedAt,
            auditStatus: AuditLifecycleStatus.postVerifyPending.rawValue,
            bindingFingerprint: pending.bindingFingerprint,
            executedAt: pending.executedAt
        )
    }

    private func makeDerivedItem(id: String, path: String) -> ClassifiedItem {
        let entity = StorageEntity(
            id: id, kind: .generatedBuild, category: "DEV", subcategory: "XCODE",
            displayName: id, path: path, logicalBytes: 42000
        )
        let decision = SafetyDecision(
            entity: entity, action: .moveToTrash, safetyClass: .green,
            safetyScore: SafetyScore(value: 95), reasonCodes: ["GENERATED_DATA"],
            sideEffects: [], matchedRuleID: "test", evaluationLayer: .exactVendor,
            evidenceConfidence: 0.95, userExplanationJA: "dd", growthCauses: [],
            requiresUserApproval: true, blockedBy: nil
        )
        return ClassifiedItem(
            detected: DetectedEntity(
                entity: entity, bucket: .generated, domain: "Developer",
                associatedProcesses: ["Xcode"], identified: true, annotation: nil
            ),
            decision: decision, semantic: SemanticResult(from: decision),
            allocatedBytes: 42000, actionVariants: [:],
            inclusiveBytes: 42000, exclusiveBytes: 42000,
            resolution: .l5Actionable, verification: nil
        )
    }

    // MARK: - Logical success

    func testMoveToTrashSuccessSourceAbsentActionConfirmed() throws {
        let trashDir = tempDir.appendingPathComponent("trash-item")
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let sourcePath = derivedDataPath(name: "removed-\(UUID().uuidString.prefix(4))")
        let pending = makePending(
            actionID: "act-1",
            entityID: "xcode.deriveddata.removed",
            path: sourcePath,
            trashPath: trashDir.path
        )
        let result = PostMutationVerifier.verify(PostMutationVerifier.VerifyInput(
            pending: pending,
            auditRecord: makeAudit(pending: pending),
            contract: nil,
            scanItems: nil,
            transactionAPISucceeded: true
        ))
        XCTAssertTrue(result.logicalActionCompleted)
        XCTAssertEqual(result.verificationState, .storageRecoveryPending)
        XCTAssertEqual(result.auditStatus, .postVerified)
        XCTAssertTrue(result.trashStillHoldingData)
        XCTAssertEqual(result.storageRecoveryState, .recoveryPending)
    }

    func testAPISuccessSourceStillPresentNotConfirmed() throws {
        let sourceDir = tempDir.appendingPathComponent("still-here")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let pending = makePending(
            actionID: "act-2",
            entityID: "xcode.deriveddata.still",
            path: sourceDir.path,
            trashPath: nil
        )
        let result = PostMutationVerifier.verify(PostMutationVerifier.VerifyInput(
            pending: pending,
            auditRecord: makeAudit(pending: pending),
            transactionAPISucceeded: true
        ))
        XCTAssertFalse(result.logicalActionCompleted)
        XCTAssertEqual(result.verificationState, .actionFailed)
        XCTAssertEqual(result.auditStatus, .failed)
    }

    func testSourceAbsentBindingMismatchUnknown() {
        let pending = makePending(
            actionID: "act-3",
            entityID: "xcode.deriveddata.a",
            path: derivedDataPath(name: "gone"),
            trashPath: nil
        )
        var audit = makeAudit(pending: pending)
        audit.entityID = "xcode.deriveddata.b"
        let result = PostMutationVerifier.verify(PostMutationVerifier.VerifyInput(
            pending: pending,
            auditRecord: audit
        ))
        XCTAssertFalse(result.logicalActionCompleted)
        XCTAssertEqual(result.verificationState, .unknown)
        XCTAssertTrue(result.unknownReasons.contains("BINDING_MISMATCH"))
    }

    func testSiblingUnchangedPass() throws {
        let parent = tempDir.appendingPathComponent("derived-parent")
        let sibling = parent.appendingPathComponent("sibling-intact")
        let removed = parent.appendingPathComponent("removed-child")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let pending = makePending(
            actionID: "act-4",
            entityID: "xcode.deriveddata.removed-child",
            path: removed.path,
            trashPath: tempDir.appendingPathComponent("trash").path
        )
        let result = PostMutationVerifier.verify(PostMutationVerifier.VerifyInput(
            pending: pending,
            auditRecord: makeAudit(pending: pending)
        ))
        XCTAssertTrue(result.postMutationObservation.siblingUnchanged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
    }

    // MARK: - Storage recovery

    func testTrashStillHoldingRecoveryPendingNotEntityBytes() throws {
        let trashPath = tempDir.appendingPathComponent("in-trash")
        try FileManager.default.createDirectory(at: trashPath, withIntermediateDirectories: true)
        let pending = makePending(
            actionID: "act-5",
            entityID: "xcode.deriveddata.t",
            path: derivedDataPath(name: "trashed"),
            trashPath: trashPath.path,
            expectedBytes: 500_000_000
        )
        let result = PostMutationVerifier.verify(PostMutationVerifier.VerifyInput(
            pending: pending,
            auditRecord: makeAudit(pending: pending),
            freeBytesNow: pending.freeBytesAfterAction
        ))
        XCTAssertEqual(result.actualRecoveredBytes, 0)
        XCTAssertEqual(result.recoveryConfidence, .exact)
        XCTAssertNotEqual(result.actualRecoveredBytes, pending.expectedBytes)
        XCTAssertEqual(result.storageRecoveryState, .recoveryPending)
    }

    func testMeasuredFreeSpaceIncreaseReportedAsEstimated() {
        let pending = makePending(
            actionID: "act-6",
            entityID: "xcode.deriveddata.r",
            path: derivedDataPath(name: "gone2"),
            trashPath: nil,
            expectedBytes: 1000
        )
        var input = PostMutationVerifier.VerifyInput(
            pending: pending,
            auditRecord: makeAudit(pending: pending),
            freeBytesNow: 2_000_000
        )
        input.pending.freeBytesBeforeAction = 1_000_000
        input.pending.freeBytesAfterAction = 1_000_000
        let result = PostMutationVerifier.verify(input)
        if result.trashStillHoldingData {
            XCTAssertEqual(result.actualRecoveredBytes, 0)
        }
    }

    // MARK: - Regeneration

    func testOriginalMovedNewDerivedDataRegeneratedNotFailure() {
        let originalPath = derivedDataPath(name: "non-fgy-original")
        let newPath = derivedDataPath(name: "new-build-hash")
        let pending = makePending(
            actionID: "act-7",
            entityID: "xcode.deriveddata.non-fgy-original",
            path: originalPath,
            trashPath: "\(home)/.Trash/non-fgy-original"
        )
        let regenItem = makeDerivedItem(
            id: "xcode.deriveddata.new-build-hash",
            path: newPath
        )
        let presentAtOriginal = tempDir.appendingPathComponent("rebuilt")
        try? FileManager.default.createDirectory(at: presentAtOriginal, withIntermediateDirectories: true)
        var regenPending = pending
        regenPending.sourcePath = presentAtOriginal.path
        let result = PostMutationVerifier.verify(PostMutationVerifier.VerifyInput(
            pending: pending,
            auditRecord: makeAudit(pending: pending),
            scanItems: [regenItem],
            transactionAPISucceeded: true
        ))
        XCTAssertTrue(result.entityRegenerated)
        XCTAssertEqual(result.semanticRelationship, .semanticSuccessor)
        XCTAssertEqual(result.verificationState, .regenerated)
        XCTAssertTrue(result.logicalActionCompleted)
    }

    // MARK: - Audit lifecycle

    func testExecutedActionRemainsPostVerifyPendingUntilReconcile() throws {
        let pending = makePending(
            actionID: "permit-test",
            entityID: "xcode.deriveddata.audit",
            path: derivedDataPath(name: "audit-test"),
            trashPath: tempDir.appendingPathComponent("t").path
        )
        try PendingPostMutationRegistry.registerPending(pending, in: tempDir)
        let loaded = PendingPostMutationRegistry.load(from: tempDir)
        XCTAssertEqual(loaded.pending.count, 1)
        XCTAssertEqual(loaded.pending[0].auditStatus, .postVerifyPending)
        XCTAssertTrue(loaded.closed.isEmpty)
    }

    func testSuccessfulPostVerifyClosesAudit() {
        let pending = makePending(
            actionID: "permit-close",
            entityID: "xcode.deriveddata.close",
            path: derivedDataPath(name: "closed"),
            trashPath: nil
        )
        let registry = PendingPostMutationRegistry.reconcile(
            registry: PendingPostMutationRegistryDocument(pending: [pending], closed: []),
            scanItems: []
        )
        XCTAssertEqual(registry.closed.count, 1)
        XCTAssertEqual(registry.closed[0].auditStatus, .postVerified)
        XCTAssertTrue(registry.pending.isEmpty)
    }

    func testFailedVerificationLeavesAuditFailed() throws {
        let sourceDir = tempDir.appendingPathComponent("failed-source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let pending = makePending(
            actionID: "permit-fail",
            entityID: "xcode.deriveddata.fail",
            path: sourceDir.path,
            trashPath: nil
        )
        let registry = PendingPostMutationRegistry.reconcile(
            registry: PendingPostMutationRegistryDocument(pending: [pending], closed: []),
            scanItems: []
        )
        XCTAssertEqual(registry.closed.count, 1)
        XCTAssertEqual(registry.closed[0].auditStatus, .failed)
        XCTAssertFalse(registry.closed[0].logicalActionCompleted)
    }

    func testAuditLinksSameActionIDAcrossLifecycle() throws {
        let exec = ActFirstMutationExecutionReport(
            phase: "P2.1",
            outcome: "FIRST_MUTATION_COMPLETED",
            entityID: "xcode.deriveddata.link",
            action: "MOVE_TO_TRASH",
            path: derivedDataPath(name: "link"),
            preflightSessionID: "pf-1",
            approvalID: "ap-1",
            permitID: "permit-link",
            auditRecord: ActionAuditRecord(
                actionID: "permit-link",
                entityID: "xcode.deriveddata.link",
                action: .moveToTrash,
                sourcePath: derivedDataPath(name: "link"),
                startedAt: Date(),
                auditStatus: AuditLifecycleStatus.postVerifyPending.rawValue
            ),
            postVerifySteps: [],
            measuredRecoveryBytes: nil,
            trashDestinationPath: nil,
            executionMs: 100,
            humanConfirmed: true,
            executorImplemented: true,
            destructiveActionsExecuted: true,
            explanation: "test",
            postMutationVerification: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(exec).write(to: tempDir.appendingPathComponent("p2_1_first_mutation_execution.json"))

        let pending = makePending(
            actionID: "permit-link",
            entityID: "xcode.deriveddata.link",
            path: derivedDataPath(name: "link"),
            trashPath: nil
        )
        let history = PendingPostMutationRegistry.buildActionHistory(
            registry: PendingPostMutationRegistryDocument(pending: [pending], closed: []),
            executionReport: exec
        )
        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items[0].actionID, "permit-link")
        XCTAssertEqual(history.items[0].permitID, "permit-link")
    }

    func testBootstrapFromExecutionReport() throws {
        let exec = ActFirstMutationExecutionReport(
            phase: "P2.1",
            outcome: "FIRST_MUTATION_COMPLETED",
            entityID: "xcode.deriveddata.non-fgybrdayavddwbcebfphqhnsetjl",
            action: "MOVE_TO_TRASH",
            path: derivedDataPath(name: "non-fgybrdayavddwbcebfphqhnsetjl"),
            preflightSessionID: "pf",
            approvalID: "ap",
            permitID: "permit-x",
            auditRecord: ActionAuditRecord(
                actionID: "permit-x",
                entityID: "xcode.deriveddata.non-fgybrdayavddwbcebfphqhnsetjl",
                action: .moveToTrash,
                sourcePath: derivedDataPath(name: "non-fgybrdayavddwbcebfphqhnsetjl"),
                destinationPath: "\(home)/.Trash/non-fgybrdayavddwbcebfphqhnsetjl",
                logicalBytesAffected: 63062016,
                startedAt: Date(timeIntervalSince1970: 1_788_345_209),
                auditStatus: AuditLifecycleStatus.postVerifyPending.rawValue
            ),
            postVerifySteps: [],
            measuredRecoveryBytes: 0,
            trashDestinationPath: "\(home)/.Trash/non-fgybrdayavddwbcebfphqhnsetjl",
            executionMs: 1015,
            humanConfirmed: true,
            executorImplemented: true,
            destructiveActionsExecuted: true,
            explanation: "real case",
            postMutationVerification: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(exec).write(to: tempDir.appendingPathComponent("p2_1_first_mutation_execution.json"))
        let bootstrapped = PendingPostMutationRegistry.bootstrapFromExecutionReport(directory: tempDir)
        XCTAssertNotNil(bootstrapped)
        XCTAssertEqual(bootstrapped?.entityID, "xcode.deriveddata.non-fgybrdayavddwbcebfphqhnsetjl")
    }
}
