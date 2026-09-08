import Foundation
import SafetyCore

public struct P32A6BindingHardeningReport: Codable, Sendable {
    public var oldMismatchRootCause: String
    public var semanticBindingFields: [String]
    public var freshnessFields: [String]
    public var ephemeralFieldsExcluded: [String]
    public var consecutiveEquivalentPreflightStable: Bool
    public var materialChangeInvalidates: Bool
    public var freshnessExpiryBlocksPermit: Bool
    public var preExecutionRejectedSemantics: String
    public var postPermitRetrySemantics: String
    public var generatedAt: Date
}

public struct P32A6VerifiedActionReceiptReport: Codable, Sendable {
    public var entity: String
    public var model: String
    public var action: String
    public var approvalID: String?
    public var permitID: String?
    public var nativeExecutor: String
    public var logicalOutcome: String
    public var recoveryOutcome: String
    public var potentialRecoveryBytes: Int64
    public var verifiedRecoveredBytes: Int64
    public var diskFreeDeltaObserved: Int64?
    public var regeneration: String
    public var currentModelPresent: Bool
    public var attemptPhase: String
    public var userHeadline: String
    public var userLines: [String]
    public var checklist: [String]
    public var groundedInP325: Bool
    public var generatedAt: Date
}

public struct P32A6CurrentInventoryReport: Codable, Sendable {
    public var readyNowBytes: Int64
    public var approvalRequiredBytes: Int64
    public var verifiedFutureBytes: Int64
    public var requiresVendorRestorationBytes: Int64
    public var verifyMoreBytes: Int64
    public var protectedBytes: Int64
    public var ollamaVendorNativeBytes: Int64
    public var hfVendorNativeBytes: Int64
    public var ollamaStatus: String
    public var hfStatus: String
    public var qwen3StillCandidate: Bool
    public var topOpportunities: [String]
    public var falseGREEN: Int
    public var duplicateEvaluations: Int
    public var generatedAt: Date
}

public struct P32A6PlanAfterActionReport: Codable, Sendable {
    public var goalBytes: Int64
    public var verifiedRecoveredFromCompletedActions: Int64
    public var currentCandidatePotential: Int64
    public var remainingGoal: Int64
    public var currentEntryCount: Int
    public var completedRecentActions: [String]
    public var qwen3StillCandidate: Bool
    public var generatedAt: Date
}

public struct P32A6ActionHistoryIntegrationReport: Codable, Sendable {
    public var actionEventID: String
    public var entityID: String
    public var action: String
    public var permitID: String?
    public var logicalOutcome: String
    public var recoveryOutcome: String
    public var verifiedRecoveredBytes: Int64
    public var eligibleForFutureSnapshotCorrelation: Bool
    public var timestampOnlyCorrelationAllowed: Bool
    public var generatedAt: Date
}

public enum P32A6ReportBuilder {
    public static func bindingHardening(
        consecutiveStable: Bool,
        materialInvalidates: Bool,
        freshnessBlocks: Bool
    ) -> P32A6BindingHardeningReport {
        P32A6BindingHardeningReport(
            oldMismatchRootCause: "semanticBindingDigest included remote verifiedAt/freshUntil epoch seconds, so consecutive Fresh Preflights over identical material state diverged",
            semanticBindingFields: ActionSemanticBindingBuilder.semanticBindingFields,
            freshnessFields: ActionSemanticBindingBuilder.freshnessFields,
            ephemeralFieldsExcluded: ActionSemanticBindingBuilder.ephemeralFieldsExcluded,
            consecutiveEquivalentPreflightStable: consecutiveStable,
            materialChangeInvalidates: materialInvalidates,
            freshnessExpiryBlocksPermit: freshnessBlocks,
            preExecutionRejectedSemantics: "APPROVAL_BINDING_MISMATCH / gate failure before ExecutionPermit and before executor ⇒ PRE_EXECUTION_REJECTED; executorInvocationCount=0; not a native mutation attempt",
            postPermitRetrySemantics: "If permit issued/consumed or process start attempted ⇒ no automatic retry; require reconciliation + new Fresh Preflight + new human authorization when consent policy requires it",
            generatedAt: Date()
        )
    }

    public static func verifiedReceiptFromP325Orchestrator(
        jsonURL: URL,
        currentModelPresent: Bool
    ) throws -> P32A6VerifiedActionReceiptReport {
        let data = try Data(contentsOf: jsonURL)
        let exec = try JSONDecoder().decode(ActExecutionOrchestrator.OllamaNativeExecutionReport.self, from: data)
        let result = VerifiedActionResultBuilder.fromOllamaExecution(exec)
        return P32A6VerifiedActionReceiptReport(
            entity: exec.entityID,
            model: exec.canonicalModel,
            action: exec.action,
            approvalID: exec.approvalID,
            permitID: exec.permitID,
            nativeExecutor: "OllamaNativeCleanupExecutor",
            logicalOutcome: exec.postVerifyStatus ?? exec.outcome,
            recoveryOutcome: result.storageRecoveryOutcome.rawValue,
            potentialRecoveryBytes: exec.potentialRecoveryBytesBefore ?? 0,
            verifiedRecoveredBytes: exec.verifiedRecoveredBytes,
            diskFreeDeltaObserved: exec.diskFreeDeltaBytes,
            regeneration: (exec.regenerationDetected == true) ? "DETECTED" : "NONE",
            currentModelPresent: currentModelPresent,
            attemptPhase: exec.attemptPhase
                ?? (exec.logicalRemovalVerified
                    ? ExecutionAttemptPhase.postVerifyCompleted.rawValue
                    : ExecutionAttemptPhase.processCompleted.rawValue),
            userHeadline: result.userHeadline,
            userLines: result.userLines,
            checklist: VerifiedActionResultBuilder.receiptChecklist(from: result),
            groundedInP325: true,
            generatedAt: Date()
        )
    }

    public static func writeAll(
        outDir: URL,
        inventory: P32A6CurrentInventoryReport,
        plan: P32A6PlanAfterActionReport,
        history: P32A6ActionHistoryIntegrationReport,
        binding: P32A6BindingHardeningReport,
        receipt: P32A6VerifiedActionReceiptReport
    ) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(binding).write(to: outDir.appendingPathComponent("p3_2a_6_binding_hardening.json"))
        try encoder.encode(receipt).write(to: outDir.appendingPathComponent("p3_2a_6_verified_action_receipt.json"))
        try encoder.encode(inventory).write(to: outDir.appendingPathComponent("p3_2a_6_current_inventory.json"))
        try encoder.encode(plan).write(to: outDir.appendingPathComponent("p3_2a_6_plan_after_verified_action.json"))
        try encoder.encode(history).write(to: outDir.appendingPathComponent("p3_2a_6_action_history_integration.json"))
    }
}
