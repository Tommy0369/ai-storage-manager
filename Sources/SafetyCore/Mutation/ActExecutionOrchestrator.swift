import Foundation

/// P2.1 — Orchestrates fresh preflight → approval → permit → first mutation → post-verify.
public enum ActExecutionOrchestrator {
    public struct ExecuteInput: Sendable {
        public var entityID: String
        public var action: StorageAction
        public var item: ClassifiedItem
        public var snapshot: EntitySafetySnapshot?
        public var scanDecision: ActionDecision
        public var scanGate: MutationGateResult
        public var scanRuntimeResolution: RuntimeStateResolution?
        public var postVerifyContract: PostActionVerificationContract?
        public var ruleVersion: String
        public var humanConfirmed: Bool
        public var expectedRecoveryBytes: Int64?
        public var engine: SafetyRuleEngine
        public var executor: any StorageActionExecutor
        public var processes: any ProcessRunningChecker
        public var handles: any OpenHandleChecker

        public init(
            entityID: String,
            action: StorageAction,
            item: ClassifiedItem,
            snapshot: EntitySafetySnapshot?,
            scanDecision: ActionDecision,
            scanGate: MutationGateResult,
            scanRuntimeResolution: RuntimeStateResolution?,
            postVerifyContract: PostActionVerificationContract?,
            ruleVersion: String,
            humanConfirmed: Bool,
            expectedRecoveryBytes: Int64?,
            engine: SafetyRuleEngine,
            executor: any StorageActionExecutor,
            processes: any ProcessRunningChecker = ProcessCheck(),
            handles: any OpenHandleChecker = LSOFHandleChecker()
        ) {
            self.entityID = entityID
            self.action = action
            self.item = item
            self.snapshot = snapshot
            self.scanDecision = scanDecision
            self.scanGate = scanGate
            self.scanRuntimeResolution = scanRuntimeResolution
            self.postVerifyContract = postVerifyContract
            self.ruleVersion = ruleVersion
            self.humanConfirmed = humanConfirmed
            self.expectedRecoveryBytes = expectedRecoveryBytes
            self.engine = engine
            self.executor = executor
            self.processes = processes
            self.handles = handles
        }
    }

    public static func executeFirstMutationTrash(_ input: ExecuteInput) throws -> ActFirstMutationExecutionReport {
        guard input.humanConfirmed else {
            throw ActionExecutionError.humanConfirmationRequired
        }
        guard input.action == .moveToTrash else {
            throw ActionExecutionError.unauthorizedAction(input.action)
        }
        guard ActionExecutionPolicy.allowsFirstMutationTrash(
            entityID: input.entityID,
            path: input.item.detected.entity.path
        ) else {
            throw ActionExecutionError.unauthorizedTarget(
                entityID: input.entityID,
                path: input.item.detected.entity.path
            )
        }

        let started = Date()
        let freeBytesBefore = StorageCapacityMeasurer.freeBytes()
        let sessionID = "p211-exec-\(input.entityID)-\(Int(Date().timeIntervalSince1970))"
        let preflight = FreshReadOnlyPreflightEngine.run(
            sessionID: sessionID,
            item: input.item,
            action: .moveToTrash,
            scanDecision: input.scanDecision,
            scanGate: input.scanGate,
            snapshot: input.snapshot,
            recommendation: nil,
            preflight: nil,
            scanRuntimeResolution: input.scanRuntimeResolution,
            ruleVersion: input.ruleVersion,
            engine: input.engine,
            processes: input.processes,
            handles: input.handles
        )

        guard preflight.freshGateResult.readiness == MutationReadiness.approvalRequired.rawValue else {
            throw ActionExecutionError.preflightNotReady(preflight.freshGateResult.readiness)
        }
        let receipt = preflight.receipt
        guard receipt.result == PreflightResultCode.satisfiedReadOnly.rawValue else {
            throw ActionExecutionError.preflightNotReady(receipt.result)
        }

        let approval = UserActionApproval(
            approvalID: "human-approval-\(input.entityID)-\(UUID().uuidString.prefix(8))",
            entityID: input.entityID,
            action: .moveToTrash,
            bindingFingerprint: receipt.bindingFingerprint,
            consequenceSummaryVersion: "P2.1_FIRST_MUTATION",
            expectedRecoveryBytes: input.expectedRecoveryBytes ?? input.item.exclusiveBytes,
            approvedAt: Date(),
            expiryPolicy: "single_use_immediate",
            scope: "first_mutation_deriveddata_trash"
        )

        guard let permit = ExecutionPermit.generate(
            receipt: receipt,
            approval: approval,
            decision: preflight.freshDecision
        ) else {
            throw ActionExecutionError.permitDenied("ExecutionPermit validation failed")
        }

        let plan = DryRunActionPlanBuilder.plan(for: preflight.freshGateResult, action: .moveToTrash)
        var audit = try input.executor.executeTrash(plan: plan, permit: permit)
        let executedAt = Date()
        let freeBytesAfter = StorageCapacityMeasurer.freeBytes()

        let verify = TrashPostActionVerifierBridge.verify(
            sourcePath: plan.path,
            trashDestination: audit.destinationPath,
            contract: input.postVerifyContract,
            bindingFingerprint: receipt.bindingFingerprint,
            actionID: permit.permitID,
            entityID: input.entityID,
            expectedBytes: input.expectedRecoveryBytes ?? input.item.exclusiveBytes,
            executedAt: executedAt,
            freeBytesBefore: freeBytesBefore,
            freeBytesAfter: freeBytesAfter
        )
        let postResult = verify.result
        guard postResult.logicalActionCompleted else {
            let failed = verify.steps.filter { !$0.satisfied }.map(\.step).joined(separator: ",")
            throw ActionExecutionError.postVerifyFailed(failed.isEmpty ? postResult.verificationState.rawValue : failed)
        }

        audit.transactionPhase = TrashTransactionPhase.postVerify.rawValue
        audit.auditStatus = AuditLifecycleStatus.postVerifyPending.rawValue
        audit.bindingFingerprint = receipt.bindingFingerprint
        audit.approvalID = approval.approvalID
        audit.preflightReceiptID = receipt.receiptID
        audit.executedAt = executedAt
        audit.freeBytesBeforeAction = freeBytesBefore
        audit.freeBytesAfterAction = freeBytesAfter
        audit.measuredRecoveryBytes = postResult.actualRecoveredBytes
        audit.logicalBytesAffected = input.expectedRecoveryBytes ?? input.item.exclusiveBytes

        let pending = PendingPostMutationVerification(
            actionID: permit.permitID,
            entityID: input.entityID,
            action: .moveToTrash,
            bindingFingerprint: receipt.bindingFingerprint,
            sourcePath: plan.path,
            expectedDestinationSemantics: "TRASH",
            trashDestinationPath: audit.destinationPath,
            expectedBytes: input.expectedRecoveryBytes ?? input.item.exclusiveBytes,
            executedAt: executedAt,
            approvalID: approval.approvalID,
            preflightReceiptID: receipt.receiptID,
            preflightObservedAt: receipt.observedAt,
            auditStatus: .postVerifyPending,
            freeBytesBeforeAction: freeBytesBefore,
            freeBytesAfterAction: freeBytesAfter,
            verificationDeadline: nil
        )
        let reportsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("reports/case001")
        try? PendingPostMutationRegistry.registerPending(pending, in: reportsDir)

        return ActFirstMutationExecutionReport(
            phase: "P2.1",
            outcome: "FIRST_MUTATION_COMPLETED",
            entityID: input.entityID,
            action: StorageAction.moveToTrash.rawValue,
            path: plan.path,
            preflightSessionID: preflight.session.preflightSessionID,
            approvalID: approval.approvalID,
            permitID: permit.permitID,
            auditRecord: audit,
            postVerifySteps: verify.steps,
            measuredRecoveryBytes: postResult.actualRecoveredBytes,
            trashDestinationPath: audit.destinationPath,
            executionMs: Int(Date().timeIntervalSince(started) * 1000),
            humanConfirmed: true,
            executorImplemented: true,
            destructiveActionsExecuted: true,
            explanation: "DerivedData child moved to Trash; audit POST_VERIFY_PENDING until scan reconciliation",
            postMutationVerification: postResult
        )
    }

    public static func executeFromScanReport(
        report: ReadOnlyAnalysisReport,
        knowledge: KnowledgeBaseDocument,
        entityID: String? = nil,
        humanConfirmed: Bool,
        executor: any StorageActionExecutor = FirstMutatingExecutor.shared,
        processes: any ProcessRunningChecker = ProcessCheck(),
        handles: any OpenHandleChecker = LSOFHandleChecker()
    ) throws -> ActFirstMutationExecutionReport {
        let targetID = entityID
            ?? report.realPreflightClosure.selectedCandidate
            ?? report.realPreflightClosure.entityID
        guard let targetID else {
            throw ActionExecutionError.gateNotReady("NO_PREFLIGHT_CANDIDATE")
        }
        guard humanConfirmed else {
            throw ActionExecutionError.humanConfirmationRequired
        }
        guard report.firstRealMutationGate.status == P21GateStatusValue.readyForHumanAuthorization.rawValue
            || report.realPreflightClosure.humanApprovalRequired else {
            throw ActionExecutionError.gateNotReady(report.firstRealMutationGate.status)
        }
        guard let item = report.items.first(where: { $0.detected.entity.id == targetID }) else {
            throw ActionExecutionError.gateNotReady("ENTITY_NOT_IN_SCAN")
        }

        let ctx = ReadOnlyAnalysisPipeline.lastExecutionContext
        let snapshot = ctx?.snapshotsByEntityID[targetID]
        let runtime = ctx?.runtimeResolutionsByEntityID[targetID]
        guard let decision = ctx?.decisionCatalog.set(for: targetID)?.decision(for: .moveToTrash) else {
            throw ActionExecutionError.gateNotReady("NO_MOVE_TO_TRASH_DECISION")
        }
        guard let gateEntry = report.mutationGate.entries.first(where: {
            $0.entityID == targetID && $0.action == StorageAction.moveToTrash.rawValue
        }) else {
            throw ActionExecutionError.gateNotReady("NO_GATE_ENTRY")
        }

        let engine = SafetyRuleEngine(knowledge: knowledge)
        return try executeFirstMutationTrash(ExecuteInput(
            entityID: targetID,
            action: .moveToTrash,
            item: item,
            snapshot: snapshot,
            scanDecision: decision,
            scanGate: gateEntry,
            scanRuntimeResolution: runtime,
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .moveToTrash, item: item),
            ruleVersion: knowledge.version,
            humanConfirmed: true,
            expectedRecoveryBytes: item.exclusiveBytes,
            engine: engine,
            executor: executor,
            processes: processes,
            handles: handles
        ))
    }

    // Legacy snapshot builders kept for tests without full pipeline context.
    static func buildApproval(
        entityID: String,
        action: StorageAction,
        fingerprint: ActionBindingFingerprint,
        expectedRecoveryBytes: Int64?
    ) -> UserActionApproval {
        UserActionApproval(
            approvalID: "human-approval-\(entityID)-\(UUID().uuidString.prefix(8))",
            entityID: entityID,
            action: action,
            bindingFingerprint: fingerprint,
            consequenceSummaryVersion: "P2.1_FIRST_MUTATION",
            expectedRecoveryBytes: expectedRecoveryBytes,
            approvedAt: Date(),
            expiryPolicy: "single_use_immediate",
            scope: "first_mutation_deriveddata_trash"
        )
    }
}
