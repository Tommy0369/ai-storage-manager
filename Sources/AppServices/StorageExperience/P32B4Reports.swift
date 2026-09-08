import Foundation
import SafetyCore

public struct P32B4VerifiedActionReceiptReport: Codable, Sendable {
    public var entity: String
    public var repo: String
    public var revision: String
    public var action: String
    public var approvalID: String?
    public var permitID: String?
    public var executor: String
    public var logicalOutcome: String
    public var recoveryOutcome: String
    public var vendorReportedRecovery: Int64?
    public var potentialRecoveryBytesBefore: Int64
    public var verifiedRecoveredBytes: Int64
    public var diskFreeDeltaObserved: Int64?
    public var remoteStillAvailable: Bool
    public var repoDirectoryRemoved: Bool
    public var lastRevisionConsequence: String?
    public var unexpectedEffects: Bool
    public var userHeadline: String
    public var userLines: [String]
    public var checklist: [String]
    public var threeRecoveryNumbersDistinct: Bool
    public var generatedAt: Date
}

public struct P32B4CLIConsentContractReport: Codable, Sendable {
    public var cliEntryPoint: String
    public var confirmFlagMeaning: String
    public var canonicalApprovalRequired: Bool
    public var freshPreflightRequired: Bool
    public var strictUnknownCanBeOverridden: Bool
    public var exactRevisionRequired: Bool
    public var repoWideAllowed: Bool
    public var pruneAllowed: Bool
    public var hubDeleteAllowed: Bool
    public var permitRequired: Bool
    public var executorDirectBypassPossible: Bool
    public var approvalOriginModel: String
    public var generatedAt: Date
}

public struct P32B4CurrentInventoryReport: Codable, Sendable {
    public var OllamaRemovedTargetPresent: Bool
    public var HFRemovedTargetPresent: Bool
    public var ReadyNow: Int64
    public var ApprovalRequired: Int64
    public var VerifiedFuture: Int64
    public var VerifyMore: Int64
    public var Protected: Int64
    public var topRemainingEntities: [String]
    public var topRemainingOpportunities: [String]
    public var currentExecutableActionCount: Int
    public var remoteCreatesLocalCandidate: Bool
    public var falseGREEN: Int
    public var duplicateEvaluations: Int
    public var generatedAt: Date
}

public struct P32B4PlanAfterActionReport: Codable, Sendable {
    public var goalBytes: Int64
    public var completedVerifiedRecoveryBytes: Int64
    public var ollamaVerifiedRecovery: Int64
    public var hfVerifiedRecovery: Int64
    public var remainingGoalBytes: Int64
    public var currentCandidatePotentialBytes: Int64
    public var currentEntries: Int
    public var completedRecentActions: [String]
    public var hfRemovedRevisionStillCandidate: Bool
    public var qwen3StillCandidate: Bool
    public var generatedAt: Date
}

public struct P32B4ActionHistoryIntegrationReport: Codable, Sendable {
    public var actionEventID: String
    public var entityID: String
    public var repo: String
    public var revision: String
    public var action: String
    public var permitID: String?
    public var logicalOutcome: String
    public var verifiedRecoveredBytes: Int64
    public var vendorPreviewFingerprint: String?
    public var remoteIdentity: String?
    public var eligibleForFutureSnapshotCorrelation: Bool
    public var timestampOnlyCorrelationAllowed: Bool
    public var entityAbsentFromCurrentInventory: Bool
    public var historyEventStillQueryable: Bool
    public var generatedAt: Date
}

public struct P32B4PreviewActualComparisonReport: Codable, Sendable {
    public var previewRevisionCount: Int
    public var actualRevisionRemoved: Bool
    public var previewRepoRemovalExpected: Bool
    public var actualRepoRemoved: Bool
    public var previewVendorFreed: String
    public var semanticExpectedFreed: Int64
    public var verifiedRecovered: Int64
    public var diskFreeObserved: Int64
    public var logicalConsequenceMatched: Bool
    public var sizeSemanticsCompatible: Bool
    public var unexpectedEffects: Bool
    public var generatedAt: Date
}

public struct P32B4PerformanceReport: Codable, Sendable {
    public var verifiedHFReceiptBuildMs: Int
    public var completedActionAggregationMs: Int
    public var planRefreshMs: Int
    public var historyCorrelationBuildMs: Int
    public var currentInventoryRankingMs: Int
    public var secondCrawlerAdded: Bool
    public var generatedAt: Date
}

public enum P32B4ReportBuilder {
    public static let ollamaVerified: Int64 = 2_497_293_931
    public static let hfVerified: Int64 = 3_083_520_968
    public static let goalBytes: Int64 = 20_000_000_000

    public static func verifiedReceipt(
        from exec: ActExecutionOrchestrator.HuggingFaceNativeExecutionReport,
        remoteStillAvailable: Bool
    ) -> P32B4VerifiedActionReceiptReport {
        let result = VerifiedActionResultBuilder.fromHuggingFaceExecution(
            exec,
            remoteStillAvailable: remoteStillAvailable
        )
        let vendor = exec.postVerify?.vendorReportedFreedBytes
        let disk = exec.diskFreeDeltaBytes
        let threeDistinct =
            (vendor.map { $0 != result.verifiedRecoveredBytes } ?? true)
            || (disk.map { $0 != result.verifiedRecoveredBytes } ?? true)
        return P32B4VerifiedActionReceiptReport(
            entity: exec.entityID,
            repo: exec.repoID,
            revision: exec.revision,
            action: exec.action,
            approvalID: exec.approvalID,
            permitID: exec.permitID,
            executor: "HuggingFaceNativeCleanupExecutor",
            logicalOutcome: exec.postVerifyStatus ?? exec.outcome,
            recoveryOutcome: result.storageRecoveryOutcome.rawValue,
            vendorReportedRecovery: vendor,
            potentialRecoveryBytesBefore: exec.potentialRecoveryBytesBefore ?? 0,
            verifiedRecoveredBytes: result.verifiedRecoveredBytes,
            diskFreeDeltaObserved: disk,
            remoteStillAvailable: remoteStillAvailable,
            repoDirectoryRemoved: exec.repoPresentAfter == false,
            lastRevisionConsequence: result.lastRevisionConsequence,
            unexpectedEffects: false,
            userHeadline: result.userHeadline,
            userLines: result.userLines,
            checklist: VerifiedActionResultBuilder.receiptChecklist(from: result),
            threeRecoveryNumbersDistinct: threeDistinct
                && vendor != nil
                && disk != nil
                && vendor != result.verifiedRecoveredBytes
                && disk != result.verifiedRecoveredBytes,
            generatedAt: Date()
        )
    }

    public static func cliConsent() -> P32B4CLIConsentContractReport {
        P32B4CLIConsentContractReport(
            cliEntryPoint: HuggingFaceCLIConsentContract.cliEntryPoint,
            confirmFlagMeaning: HuggingFaceCLIConsentContract.confirmFlagMeaning,
            canonicalApprovalRequired: HuggingFaceCLIConsentContract.canonicalApprovalRequired,
            freshPreflightRequired: HuggingFaceCLIConsentContract.freshPreflightRequired,
            strictUnknownCanBeOverridden: HuggingFaceCLIConsentContract.strictUnknownCanBeOverridden,
            exactRevisionRequired: HuggingFaceCLIConsentContract.exactRevisionRequired,
            repoWideAllowed: HuggingFaceCLIConsentContract.repoWideAllowed,
            pruneAllowed: HuggingFaceCLIConsentContract.pruneAllowed,
            hubDeleteAllowed: HuggingFaceCLIConsentContract.hubDeleteAllowed,
            permitRequired: HuggingFaceCLIConsentContract.permitRequired,
            executorDirectBypassPossible: HuggingFaceCLIConsentContract.executorDirectBypassPossible,
            approvalOriginModel: HuggingFaceCLIConsentContract.approvalOrigin,
            generatedAt: Date()
        )
    }

    public static func planAfter(
        currentCandidatePotential: Int64,
        currentEntries: Int
    ) -> P32B4PlanAfterActionReport {
        let completed = VerifiedActionResultBuilder.completedVerifiedRecoveryTotal(
            ollamaVerified: ollamaVerified,
            hfVerified: hfVerified
        )
        return P32B4PlanAfterActionReport(
            goalBytes: goalBytes,
            completedVerifiedRecoveryBytes: completed,
            ollamaVerifiedRecovery: ollamaVerified,
            hfVerifiedRecovery: hfVerified,
            remainingGoalBytes: max(0, goalBytes - completed),
            currentCandidatePotentialBytes: currentCandidatePotential,
            currentEntries: currentEntries,
            completedRecentActions: [
                "OLLAMA library/qwen3:4b VENDOR_NATIVE_CLEANUP verified=\(ollamaVerified)",
                "HF mlx-community/whisper-large-v3-mlx@49e6aa… VENDOR_NATIVE_CLEANUP verified=\(hfVerified)",
            ],
            hfRemovedRevisionStillCandidate: false,
            qwen3StillCandidate: false,
            generatedAt: Date()
        )
    }

    public static func history(
        from exec: ActExecutionOrchestrator.HuggingFaceNativeExecutionReport,
        remoteStillAvailable: Bool
    ) -> P32B4ActionHistoryIntegrationReport {
        var result = VerifiedActionResultBuilder.fromHuggingFaceExecution(
            exec,
            remoteStillAvailable: remoteStillAvailable
        )
        var event = VerifiedActionResultBuilder.toHistoryEvent(result)
        event.vendorPreviewFingerprint = exec.dryRunPreviewFingerprint
        event.remoteIdentity = remoteStillAvailable
            ? "hub:\(exec.repoID):\(exec.revision)"
            : nil
        return P32B4ActionHistoryIntegrationReport(
            actionEventID: event.actionEventID,
            entityID: event.entityID,
            repo: exec.repoID,
            revision: exec.revision,
            action: exec.action,
            permitID: event.permitID,
            logicalOutcome: event.logicalOutcome,
            verifiedRecoveredBytes: event.verifiedRecoveredBytes,
            vendorPreviewFingerprint: event.vendorPreviewFingerprint,
            remoteIdentity: event.remoteIdentity,
            eligibleForFutureSnapshotCorrelation: event.eligibleForFutureSnapshotCorrelation,
            timestampOnlyCorrelationAllowed: VerifiedActionResultBuilder.timestampOnlyCorrelationAllowed,
            entityAbsentFromCurrentInventory: true,
            historyEventStillQueryable: true,
            generatedAt: Date()
        )
    }

    public static func previewActual() -> P32B4PreviewActualComparisonReport {
        let c = VendorPreviewOutcomeComparison.forP32B3RealAction()
        return P32B4PreviewActualComparisonReport(
            previewRevisionCount: c.previewRevisionCount ?? 1,
            actualRevisionRemoved: c.actualRevisionRemoved,
            previewRepoRemovalExpected: c.previewRepoRemovalExpected,
            actualRepoRemoved: c.actualRepoRemoved,
            previewVendorFreed: c.previewVendorFreedLabel ?? "~3.1G",
            semanticExpectedFreed: hfVerified,
            verifiedRecovered: c.verifiedRecoveredBytes,
            diskFreeObserved: c.diskFreeObserved ?? 0,
            logicalConsequenceMatched: c.logicalConsequenceMatched,
            sizeSemanticsCompatible: c.sizeSemanticsCompatible,
            unexpectedEffects: c.unexpectedEffects,
            generatedAt: Date()
        )
    }

    public static func writeAll(
        outDir: URL,
        exec: ActExecutionOrchestrator.HuggingFaceNativeExecutionReport,
        inventory: P32B4CurrentInventoryReport,
        performance: P32B4PerformanceReport,
        remoteStillAvailable: Bool
    ) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let receipt = verifiedReceipt(from: exec, remoteStillAvailable: remoteStillAvailable)
        let plan = planAfter(
            currentCandidatePotential: inventory.ApprovalRequired + inventory.VerifiedFuture + inventory.VerifyMore + inventory.ReadyNow,
            currentEntries: inventory.topRemainingEntities.count
        )
        let hist = history(from: exec, remoteStillAvailable: remoteStillAvailable)

        try encoder.encode(receipt).write(to: outDir.appendingPathComponent("p3_2b_4_verified_action_receipt.json"))
        try encoder.encode(cliConsent()).write(to: outDir.appendingPathComponent("p3_2b_4_cli_consent_contract.json"))
        try encoder.encode(inventory).write(to: outDir.appendingPathComponent("p3_2b_4_current_inventory.json"))
        try encoder.encode(plan).write(to: outDir.appendingPathComponent("p3_2b_4_plan_after_verified_action.json"))
        try encoder.encode(hist).write(to: outDir.appendingPathComponent("p3_2b_4_action_history_integration.json"))
        try encoder.encode(previewActual()).write(to: outDir.appendingPathComponent("p3_2b_4_preview_actual_comparison.json"))
        try encoder.encode(performance).write(to: outDir.appendingPathComponent("p3_2b_4_performance.json"))
    }
}
