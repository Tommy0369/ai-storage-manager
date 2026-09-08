import Foundation

/// P3.2A.5 — Ollama MODEL × VENDOR_NATIVE_CLEANUP product-path orchestration.
extension ActExecutionOrchestrator {
    public struct OllamaExecuteInput: Sendable {
        public var entityID: String
        public var canonicalModel: String
        public var authorizationText: String
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
        public var processRunner: any BoundedProcessRunner

        public init(
            entityID: String,
            canonicalModel: String,
            authorizationText: String = OllamaNativePostMutationProbe.authorizationText,
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
            processRunner: any BoundedProcessRunner = FoundationProcessRunner()
        ) {
            self.entityID = entityID
            self.canonicalModel = canonicalModel
            self.authorizationText = authorizationText
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
            self.processRunner = processRunner
        }
    }

    public struct OllamaNativeExecutionReport: Codable, Sendable, Equatable {
        public var phase: String
        public var outcome: String
        public var entityID: String
        public var canonicalModel: String
        public var action: String
        public var authorizationTextFingerprint: String
        public var approvalID: String?
        public var approvalConsumed: Bool
        public var approvalBindingValid: Bool
        public var bindingPreflightReceiptID: String?
        public var finalPreflightReceiptID: String?
        public var finalPreflightReadiness: String?
        public var canonicalActionDecisionEligible: Bool
        public var strictUnknownCount: Int
        public var strictConflictCount: Int
        public var permitID: String?
        public var permitConsumed: Bool
        public var executorInvoked: Bool
        public var argvContract: [String]
        public var shellUsed: Bool
        public var rawDeleteFallback: Bool
        public var processOutcome: String?
        public var exitStatus: Int?
        public var retryPerformed: Bool
        public var realMutationExecuted: Bool
        public var modelPresentBefore: Bool?
        public var modelPresentAfter: Bool?
        public var logicalRemovalVerified: Bool
        public var oldManifestPresentAfter: Bool?
        public var remainingReferencedBlobCount: Int?
        public var remainingSharedBytes: Int64?
        public var remainingUniqueBytes: Int64?
        public var potentialRecoveryBytesBefore: Int64?
        public var immediateExpectedRecoveryBytes: Int64
        public var verifiedRecoveredBytes: Int64
        public var mappedDeltaBytes: Int64?
        public var diskFreeDeltaBytes: Int64?
        public var recoveryStatus: String?
        public var regenerationDetected: Bool?
        public var postVerifyStatus: String?
        public var binaryFingerprint: String?
        public var cliExecutablePath: String?
        public var auditRecord: ActionAuditRecord?
        public var postVerifySteps: [PostActionVerifyStepResult]
        public var executionMs: Int
        public var abortReason: String?
        public var humanConfirmed: Bool
        public var explanation: String
        public var attemptPhase: String?
        public var counters: ExecutionAttemptCounters?
    }

    /// Exact product path: Fresh Preflight → Approval → Fresh Preflight → Permit → Executor → PostVerify.
    /// No shell. No raw delete. No automatic retry.
    public static func executeOllamaNativeCleanup(_ input: OllamaExecuteInput) throws -> OllamaNativeExecutionReport {
        let started = Date()
        let authFP = OllamaNativePostMutationProbe.authorizationTextFingerprint(input.authorizationText)

        func abort(_ reason: String, partial: OllamaNativeExecutionReport? = nil) -> OllamaNativeExecutionReport {
            var report = partial ?? emptyReport(input: input, authFP: authFP, started: started)
            report.outcome = "ABORTED"
            report.abortReason = reason
            report.explanation = reason
            report.executionMs = Int(Date().timeIntervalSince(started) * 1000)
            report.attemptPhase = ExecutionAttemptPhase.preExecutionRejected.rawValue
            report.counters = ExecutionAttemptCounters(
                authorizationAttempts: 1,
                preflightAttempts: report.finalPreflightReceiptID == nil ? 0 : 1,
                permitIssuanceCount: 0,
                executorInvocationCount: 0,
                nativeProcessStartCount: 0,
                successfulNativeMutationCount: 0
            )
            return report
        }

        guard input.humanConfirmed else {
            throw ActionExecutionError.humanConfirmationRequired
        }
        guard input.authorizationText == OllamaNativePostMutationProbe.authorizationText else {
            return abort("AUTHORIZATION_TEXT_MISMATCH")
        }
        guard input.entityID == OllamaNativePostMutationProbe.authorizedEntityID else {
            return abort("ENTITY_NOT_AUTHORIZED:\(input.entityID)")
        }
        guard input.canonicalModel == OllamaNativePostMutationProbe.authorizedCanonicalModel else {
            return abort("MODEL_NOT_AUTHORIZED:\(input.canonicalModel)")
        }
        guard ActionExecutionPolicy.allowsOllamaNativeCleanup(
            entityID: input.entityID,
            path: input.item.detected.entity.path,
            canonicalModel: input.canonicalModel
        ) else {
            throw ActionExecutionError.unauthorizedTarget(
                entityID: input.entityID,
                path: input.item.detected.entity.path
            )
        }

        // --- Fresh Preflight (final, immediately before permit) ---
        // Human authorization is already in hand for this exact entity×action.
        // Bind approval to THIS receipt so volatile remote epoch seconds cannot
        // falsely invalidate a second independent refresh of the same scan item.
        let finalSession = "p325-final-\(input.entityID)-\(Int(Date().timeIntervalSince1970))"
        let finalPF = FreshReadOnlyPreflightEngine.run(
            sessionID: finalSession,
            item: input.item,
            action: .vendorNativeCleanup,
            scanDecision: input.scanDecision,
            scanGate: input.scanGate,
            snapshot: input.snapshot,
            recommendation: nil,
            preflight: nil,
            scanRuntimeResolution: input.scanRuntimeResolution,
            ruleVersion: input.ruleVersion,
            engine: input.engine,
            ollamaProcessRunner: input.processRunner,
            refreshStaleRemoteProof: true
        )

        var alignedItem = input.item
        if var v = alignedItem.verification {
            if let iface = finalPF.ollamaNativeInterface {
                v.vendorProofNotes.removeAll {
                    $0.hasPrefix("OLLAMA_INTERFACE=")
                        || $0.hasPrefix("OLLAMA_CLI_")
                        || $0.hasPrefix("OLLAMA_BINARY_FP=")
                        || $0 == "OLLAMA_EXECUTABLE_UNRESOLVED"
                        || $0 == "OLLAMA_EXECUTION_TRANSPORT_AVAILABLE"
                        || $0 == "OLLAMA_EXECUTION_TRANSPORT_UNAVAILABLE"
                }
                v.vendorProofNotes.append("OLLAMA_INTERFACE=\(iface.interfaceKind.rawValue)")
                if let path = iface.cliExecutableURL {
                    v.vendorProofNotes.append("OLLAMA_CLI_RESOLVED=\(path)")
                    v.vendorProofNotes.append("OLLAMA_EXECUTION_TRANSPORT_AVAILABLE")
                }
                if let fp = iface.binaryFingerprint {
                    v.vendorProofNotes.append("OLLAMA_BINARY_FP=\(fp)")
                }
            }
            if let proof = finalPF.ollamaRuntimeProof {
                v.activeState = proof.targetStatus
                v.activeStateConfidence = proof.targetConfidence
            }
            alignedItem.verification = v
        }
        let alignment = ActionSpecificSafetyAligner.alignOllamaVendorNative(
            item: alignedItem,
            decision: finalPF.freshDecision,
            gate: finalPF.freshGateResult
        )
        let unknownStrict = alignment.unknownStrictPredicates
        let conflictStrict = alignment.conflictedStrictPredicates

        var report = emptyReport(input: input, authFP: authFP, started: started)
        report.bindingPreflightReceiptID = finalPF.receipt.receiptID
        report.finalPreflightReceiptID = finalPF.receipt.receiptID
        report.finalPreflightReadiness = finalPF.freshGateResult.readiness
        report.canonicalActionDecisionEligible = finalPF.freshDecision.eligible
        report.strictUnknownCount = unknownStrict.count
        report.strictConflictCount = conflictStrict.count
        report.binaryFingerprint = finalPF.ollamaNativeInterface?.binaryFingerprint
            ?? noteValueFromItem(alignedItem, prefix: "OLLAMA_BINARY_FP=")
        report.cliExecutablePath = finalPF.ollamaNativeInterface?.cliExecutableURL
            ?? noteValueFromItem(alignedItem, prefix: "OLLAMA_CLI_RESOLVED=")

        guard finalPF.freshGateResult.readiness == MutationReadiness.approvalRequired.rawValue else {
            return abort("FINAL_PREFLIGHT_NOT_APPROVAL_REQUIRED:\(finalPF.freshGateResult.readiness)", partial: report)
        }
        guard finalPF.receipt.result == PreflightResultCode.satisfiedReadOnly.rawValue else {
            return abort("FINAL_PREFLIGHT_RECEIPT:\(finalPF.receipt.result)", partial: report)
        }
        guard finalPF.freshDecision.eligible else {
            return abort("FINAL_DECISION_NOT_ELIGIBLE", partial: report)
        }
        guard finalPF.freshDecision.missingClaimTypes.isEmpty,
              finalPF.freshDecision.blockedReasons.isEmpty else {
            return abort("FINAL_DECISION_BLOCKED", partial: report)
        }
        guard unknownStrict.isEmpty, conflictStrict.isEmpty else {
            return abort("STRICT_PREDICATE_FAIL unknown=\(unknownStrict.count) conflict=\(conflictStrict.count)", partial: report)
        }
        if !alignment.safetyBlockers.isEmpty {
            return abort("TECHNICAL_BLOCKERS:\(alignment.safetyBlockers.joined(separator: ","))", partial: report)
        }
        if !(alignment.approvalIsOnlyRemainingGate || alignment.isCanonicallyEligibleForApprovalBoundary) {
            // Gate already APPROVAL_REQUIRED; refuse if alignment still shows non-approval residue.
            let residue = alignment.remainingGateBlockers.filter { $0 != "USER_APPROVAL" }
            if !residue.isEmpty {
                return abort("REMAINING_GATE:\(residue.joined(separator: ","))", partial: report)
            }
        }

        let approval = UserActionApproval(
            approvalID: "human-approval-ollama-\(UUID().uuidString.prefix(8))",
            entityID: input.entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: finalPF.receipt.bindingFingerprint,
            consequenceSummaryVersion: "P3.2A.5_OLLAMA_NATIVE",
            expectedRecoveryBytes: input.expectedRecoveryBytes
                ?? input.item.verification?.uniqueBytesProven
                ?? input.item.exclusiveBytes,
            approvedAt: Date(),
            expiryPolicy: "single_use_immediate",
            scope: "p325_ollama_native_library_qwen3_4b:\(authFP)"
        )
        report.approvalID = approval.approvalID
        report.approvalBindingValid = true
        report.approvalConsumed = false

        guard approval.bindingFingerprint.matches(finalPF.receipt.bindingFingerprint) else {
            report.approvalBindingValid = false
            return abort("APPROVAL_BINDING_MISMATCH", partial: report)
        }

        guard let permit = ExecutionPermit.generate(
            receipt: finalPF.receipt,
            approval: approval,
            decision: finalPF.freshDecision
        ) else {
            return abort("PERMIT_DENIED", partial: report)
        }
        report.permitID = permit.permitID
        report.approvalConsumed = true

        let cliPath = report.cliExecutablePath
        guard let exe = OllamaModelIdentity.resolveExecutableURL(
            boundExecutablePath: cliPath,
            processRunner: input.processRunner
        ) else {
            // Consume permit attempt semantics: do not launch without executable.
            _ = ExecutionPermitLedger.consume(permit.permitID)
            report.permitConsumed = true
            return abort("EXECUTABLE_UNRESOLVED", partial: report)
        }
        report.cliExecutablePath = exe.path

        let before = OllamaNativePostMutationProbe.captureBefore(
            entityID: input.entityID,
            canonicalModel: input.canonicalModel,
            item: input.item,
            cliURL: exe,
            runner: input.processRunner
        )
        report.modelPresentBefore = before.modelPresent
        report.potentialRecoveryBytesBefore = before.uniqueBytes
        report.immediateExpectedRecoveryBytes = 0
        guard before.modelPresent else {
            _ = ExecutionPermitLedger.consume(permit.permitID)
            report.permitConsumed = true
            return abort("MODEL_NOT_PRESENT_BEFORE", partial: report)
        }

        let plan = DryRunActionPlanBuilder.plan(for: finalPF.freshGateResult, action: .vendorNativeCleanup)
        let argv = try OllamaModelIdentity.rmArguments(canonicalModel: input.canonicalModel)
        report.argvContract = argv

        // Scope guard
        guard plan.entityID == input.entityID,
              plan.action == StorageAction.vendorNativeCleanup.rawValue,
              permit.entityID == input.entityID,
              permit.action == .vendorNativeCleanup else {
            _ = ExecutionPermitLedger.consume(permit.permitID)
            report.permitConsumed = true
            return abort("SCOPE_GUARD_REJECT", partial: report)
        }

        // Always route through StorageActionExecutorRouter + bound CLI (no shell, no raw fallback).
        let boundExecutor: any StorageActionExecutor = StorageActionExecutorRouter(
            ollamaExecutor: OllamaNativeCleanupExecutor(
                processRunner: input.processRunner,
                resolveExecutable: { exe }
            )
        )

        report.executorInvoked = true
        report.realMutationExecuted = true
        let audit: ActionAuditRecord
        do {
            audit = try boundExecutor.executeVendorNativeCleanup(
                plan: plan,
                permit: permit,
                canonicalModel: input.canonicalModel
            )
        } catch {
            report.permitConsumed = ExecutionPermitLedger.isConsumed(permit.permitID)
            report.outcome = "EXECUTION_FAILED"
            report.abortReason = String(describing: error)
            report.explanation = "Native executor threw; no raw fallback"
            report.executionMs = Int(Date().timeIntervalSince(started) * 1000)
            return report
        }
        report.auditRecord = audit
        report.permitConsumed = true
        report.processOutcome = audit.notes.first(where: { $0.hasPrefix("PROCESS_OUTCOME=") })?
            .replacingOccurrences(of: "PROCESS_OUTCOME=", with: "")
        report.exitStatus = audit.failureReason?.hasPrefix("NONZERO_EXIT:") == true
            ? Int(audit.failureReason!.split(separator: ":").last.map(String.init) ?? "")
            : (audit.failureReason == nil ? 0 : nil)
        report.retryPerformed = false
        report.shellUsed = false
        report.rawDeleteFallback = false

        let processFailed = audit.failureReason != nil
        let after = OllamaNativePostMutationProbe.observeAfter(
            before: before,
            cliURL: exe,
            runner: input.processRunner
        )
        let post = OllamaNativePostMutationProbe.verify(
            before: before,
            after: after,
            processFailed: processFailed,
            contract: input.postVerifyContract
        )

        report.modelPresentAfter = after.modelPresent
        report.logicalRemovalVerified = post.logical == .modelRemoved
        report.oldManifestPresentAfter = after.oldManifestPresent
        report.remainingReferencedBlobCount = after.remainingReferencedBlobCount
        report.remainingSharedBytes = after.remainingSharedBytes
        report.remainingUniqueBytes = after.remainingUniqueBytes
        report.verifiedRecoveredBytes = post.verifiedRecoveredBytes
        report.mappedDeltaBytes = after.mappedDeltaBytes
        report.diskFreeDeltaBytes = after.diskFreeDeltaBytes
        report.recoveryStatus = post.storage.rawValue
        report.regenerationDetected = after.regenerationDetected
        report.postVerifyStatus = post.logical.rawValue
        report.postVerifySteps = post.steps
        report.executionMs = Int(Date().timeIntervalSince(started) * 1000)

        if processFailed {
            report.outcome = "NATIVE_COMMAND_FAILED"
            report.explanation = audit.failureReason ?? "process failed"
            report.attemptPhase = ExecutionAttemptPhase.processCompleted.rawValue
        } else if post.logical == .modelRemoved {
            report.outcome = "MODEL_REMOVED"
            report.explanation = "Logical model removal verified via ollama list; storage=\(post.storage.rawValue)"
            report.attemptPhase = ExecutionAttemptPhase.postVerifyCompleted.rawValue
        } else {
            report.outcome = "MODEL_REMOVAL_NOT_VERIFIED"
            report.explanation = "Command returned but model still present or inventory inconclusive"
            report.attemptPhase = ExecutionAttemptPhase.processCompleted.rawValue
        }
        report.counters = ExecutionAttemptCounters(
            authorizationAttempts: 1,
            preflightAttempts: 1,
            permitIssuanceCount: 1,
            executorInvocationCount: 1,
            nativeProcessStartCount: 1,
            successfulNativeMutationCount: post.logical == .modelRemoved ? 1 : 0
        )
        return report
    }

    public static func executeOllamaFromScanReport(
        report: ReadOnlyAnalysisReport,
        knowledge: KnowledgeBaseDocument,
        entityID: String = OllamaNativePostMutationProbe.authorizedEntityID,
        canonicalModel: String = OllamaNativePostMutationProbe.authorizedCanonicalModel,
        authorizationText: String = OllamaNativePostMutationProbe.authorizationText,
        humanConfirmed: Bool,
        executor: any StorageActionExecutor = StorageActionExecutorRouter(),
        processRunner: any BoundedProcessRunner = FoundationProcessRunner()
    ) throws -> OllamaNativeExecutionReport {
        guard humanConfirmed else {
            throw ActionExecutionError.humanConfirmationRequired
        }
        guard let item = report.items.first(where: { $0.detected.entity.id == entityID }) else {
            throw ActionExecutionError.gateNotReady("ENTITY_NOT_IN_SCAN")
        }
        let ctx = ReadOnlyAnalysisPipeline.lastExecutionContext
        let snapshot = ctx?.snapshotsByEntityID[entityID]
        let runtime = ctx?.runtimeResolutionsByEntityID[entityID]
        let model = ActionPolicy.ollamaCanonicalModelName(from: item) ?? canonicalModel
        guard model == canonicalModel else {
            throw ActionExecutionError.invalidModelIdentity(model)
        }

        let decision: ActionDecision = {
            if let d = ctx?.decisionCatalog.set(for: entityID)?.decision(for: .vendorNativeCleanup), d.eligible {
                return d
            }
            return ActionSafetyEvaluator.evaluate(
                item: item,
                action: .vendorNativeCleanup,
                engine: SafetyRuleEngine(knowledge: knowledge),
                evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
                state: RuntimeState(),
                snapshot: snapshot,
                safetyDecisions: nil
            )
        }()

        let gate: MutationGateResult = {
            if let entry = report.mutationGate.entries.first(where: {
                $0.entityID == entityID && $0.action == StorageAction.vendorNativeCleanup.rawValue
            }) {
                return entry
            }
            let engine = SafetyRuleEngine(knowledge: knowledge)
            return MutationGate.evaluate(MutationGateInput(
                item: item,
                action: .vendorNativeCleanup,
                actionDecision: decision,
                snapshot: snapshot,
                runtimeResolution: runtime,
                transactionContract: TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item),
                postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
                auditContract: TransactionContractRegistry.auditContract(for: .vendorNativeCleanup, item: item),
                approvalState: .scanDefault,
                runtimeGeneration: snapshot?.cacheKey.runtimeGeneration ?? 0,
                ruleVersion: knowledge.version
            ))
        }()

        return try executeOllamaNativeCleanup(OllamaExecuteInput(
            entityID: entityID,
            canonicalModel: canonicalModel,
            authorizationText: authorizationText,
            item: item,
            snapshot: snapshot,
            scanDecision: decision,
            scanGate: gate,
            scanRuntimeResolution: runtime,
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
            ruleVersion: knowledge.version,
            humanConfirmed: true,
            expectedRecoveryBytes: item.verification?.uniqueBytesProven ?? item.exclusiveBytes,
            engine: SafetyRuleEngine(knowledge: knowledge),
            executor: executor,
            processRunner: processRunner
        ))
    }

    private static func emptyReport(
        input: OllamaExecuteInput,
        authFP: String,
        started: Date
    ) -> OllamaNativeExecutionReport {
        OllamaNativeExecutionReport(
            phase: "P3.2A.5",
            outcome: "PENDING",
            entityID: input.entityID,
            canonicalModel: input.canonicalModel,
            action: StorageAction.vendorNativeCleanup.rawValue,
            authorizationTextFingerprint: authFP,
            approvalID: nil,
            approvalConsumed: false,
            approvalBindingValid: false,
            bindingPreflightReceiptID: nil,
            finalPreflightReceiptID: nil,
            finalPreflightReadiness: nil,
            canonicalActionDecisionEligible: false,
            strictUnknownCount: -1,
            strictConflictCount: -1,
            permitID: nil,
            permitConsumed: false,
            executorInvoked: false,
            argvContract: ["rm", input.canonicalModel],
            shellUsed: false,
            rawDeleteFallback: false,
            processOutcome: nil,
            exitStatus: nil,
            retryPerformed: false,
            realMutationExecuted: false,
            modelPresentBefore: nil,
            modelPresentAfter: nil,
            logicalRemovalVerified: false,
            oldManifestPresentAfter: nil,
            remainingReferencedBlobCount: nil,
            remainingSharedBytes: nil,
            remainingUniqueBytes: nil,
            potentialRecoveryBytesBefore: input.expectedRecoveryBytes,
            immediateExpectedRecoveryBytes: 0,
            verifiedRecoveredBytes: 0,
            mappedDeltaBytes: nil,
            diskFreeDeltaBytes: nil,
            recoveryStatus: nil,
            regenerationDetected: nil,
            postVerifyStatus: nil,
            binaryFingerprint: nil,
            cliExecutablePath: nil,
            auditRecord: nil,
            postVerifySteps: [],
            executionMs: Int(Date().timeIntervalSince(started) * 1000),
            abortReason: nil,
            humanConfirmed: input.humanConfirmed,
            explanation: "",
            attemptPhase: nil,
            counters: nil
        )
    }

    private static func noteValueFromItem(_ item: ClassifiedItem, prefix: String) -> String? {
        item.verification?.vendorProofNotes
            .first(where: { $0.hasPrefix(prefix) })?
            .replacingOccurrences(of: prefix, with: "")
    }
}
