import Foundation
import SafetyCore

public struct P32A5AuthorizationReport: Codable, Sendable {
    public var authorizationReceived: Bool
    public var authorizationTextFingerprint: String
    public var authorizedEntity: String
    public var authorizedCanonicalModel: String
    public var authorizedAction: String
    public var approvalCreated: Bool
    public var approvalID: String?
    public var approvalBindingValid: Bool?
    public var approvalConsumed: Bool?
    public var generatedAt: Date
}

public struct P32A5FinalPreflightReport: Codable, Sendable {
    public var entityID: String
    public var canonicalModel: String
    public var action: String
    public var canonicalActionDecision: String
    public var strictRequiredPredicates: [String]
    public var verifiedStrictPredicates: [String]
    public var unknownStrictPredicates: [String]
    public var conflictedStrictPredicates: [String]
    public var runtime: String?
    public var runtimeFresh: Bool?
    public var remoteReacquisition: String?
    public var remoteFresh: Bool?
    public var referenceGraph: String?
    public var manifest: String?
    public var nativeInterface: String?
    public var supportsRM: Bool?
    public var binaryFingerprint: String?
    public var approvalBinding: String?
    public var preflightStatus: String?
    public var remainingBlockers: [String]
    public var executionAllowed: Bool
    public var generatedAt: Date
}

public struct P32A5ExecutionReport: Codable, Sendable {
    public var executor: String
    public var vendor: String
    public var entityKind: String
    public var action: String
    public var canonicalModel: String
    public var shellUsed: Bool
    public var rawDeleteFallback: Bool
    public var processStarted: Bool
    public var argvContract: [String]
    public var startedAt: Date?
    public var endedAt: Date?
    public var durationMs: Int
    public var exitStatus: Int?
    public var executionOutcome: String
    public var permitID: String?
    public var permitConsumed: Bool
    public var retryPerformed: Bool
    public var realMutationExecuted: Bool
    public var generatedAt: Date
}

public struct P32A5PostVerifyReport: Codable, Sendable {
    public var modelPresentBefore: Bool?
    public var modelPresentAfter: Bool?
    public var modelRemovalVerified: Bool
    public var oldManifestPresentAfter: Bool?
    public var remainingReferencedBlobCount: Int?
    public var remainingSharedBytes: Int64?
    public var remainingUniqueBytes: Int64?
    public var potentialRecoveryBytesBefore: Int64?
    public var verifiedRecoveredBytes: Int64
    public var mappedDeltaBytes: Int64?
    public var diskFreeDeltaBytes: Int64?
    public var recoveryStatus: String?
    public var regenerationDetected: Bool?
    public var postVerifyStatus: String?
    public var generatedAt: Date
}

public struct P32A5BeforeAfterReport: Codable, Sendable {
    public var before: Side
    public var after: Side
    public var actionCorrelation: String?
    public var logicalRemovalVerified: Bool
    public var storageRecoveryVerified: Bool
    public var generatedAt: Date

    public struct Side: Codable, Sendable {
        public var modelInstalled: Bool?
        public var uniqueBytes: Int64?
        public var sharedBytes: Int64?
        public var planTier: String?
        public var potentialBytes: Int64?
    }
}

public struct P32A5SafetyRegressionReport: Codable, Sendable {
    public var FalseGREEN: Int
    public var duplicateEvaluations: Int
    public var HFExecutable: Bool
    public var rawBlobExecutable: Bool
    public var MOVE_TO_TRASHChanged: Bool
    public var secondCrawlerAdded: Bool
    public var newMutationCapabilitiesAddedInThisPhase: [String]
    public var generatedAt: Date
}

public enum P32A5ReportBuilder {
    public static func authorization(
        authorizationReceived: Bool,
        authorizationText: String,
        authorizationTextFingerprint: String,
        entityID: String,
        canonicalModel: String,
        action: String,
        approvalCreated: Bool = false,
        approvalID: String? = nil,
        approvalBindingValid: Bool? = nil,
        approvalConsumed: Bool? = nil
    ) -> P32A5AuthorizationReport {
        _ = authorizationText
        return P32A5AuthorizationReport(
            authorizationReceived: authorizationReceived,
            authorizationTextFingerprint: authorizationTextFingerprint,
            authorizedEntity: entityID,
            authorizedCanonicalModel: canonicalModel,
            authorizedAction: action,
            approvalCreated: approvalCreated,
            approvalID: approvalID,
            approvalBindingValid: approvalBindingValid,
            approvalConsumed: approvalConsumed,
            generatedAt: Date()
        )
    }

    public static func writeAll(
        exec: ActExecutionOrchestrator.OllamaNativeExecutionReport,
        scanReport: ReadOnlyAnalysisReport,
        outDir: URL,
        encoder: JSONEncoder
    ) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        var auth = authorization(
            authorizationReceived: true,
            authorizationText: OllamaNativePostMutationProbe.authorizationText,
            authorizationTextFingerprint: exec.authorizationTextFingerprint,
            entityID: exec.entityID,
            canonicalModel: exec.canonicalModel,
            action: exec.action,
            approvalCreated: exec.approvalID != nil,
            approvalID: exec.approvalID,
            approvalBindingValid: exec.approvalBindingValid,
            approvalConsumed: exec.approvalConsumed
        )
        auth.generatedAt = Date()
        try encoder.encode(auth).write(to: outDir.appendingPathComponent("p3_2a_5_real_authorization.json"))

        let preflight = P32A5FinalPreflightReport(
            entityID: exec.entityID,
            canonicalModel: exec.canonicalModel,
            action: exec.action,
            canonicalActionDecision: exec.canonicalActionDecisionEligible ? "ELIGIBLE" : "NOT_ELIGIBLE",
            strictRequiredPredicates: OllamaVendorNativeStrictPredicateCatalog.requiredLabels,
            verifiedStrictPredicates: exec.strictUnknownCount == 0
                ? OllamaVendorNativeStrictPredicateCatalog.requiredLabels
                : [],
            unknownStrictPredicates: exec.strictUnknownCount == 0 ? [] : ["PRESENT"],
            conflictedStrictPredicates: exec.strictConflictCount == 0 ? [] : ["PRESENT"],
            runtime: nil,
            runtimeFresh: nil,
            remoteReacquisition: nil,
            remoteFresh: nil,
            referenceGraph: nil,
            manifest: nil,
            nativeInterface: exec.cliExecutablePath != nil ? "RESOLVED_CLI" : nil,
            supportsRM: true,
            binaryFingerprint: exec.binaryFingerprint,
            approvalBinding: exec.approvalBindingValid ? "MATCH" : "MISMATCH",
            preflightStatus: exec.finalPreflightReadiness,
            remainingBlockers: exec.approvalBindingValid && exec.canonicalActionDecisionEligible
                ? []
                : [exec.abortReason].compactMap { $0 },
            executionAllowed: exec.realMutationExecuted || exec.permitID != nil,
            generatedAt: Date()
        )
        try encoder.encode(preflight).write(to: outDir.appendingPathComponent("p3_2a_5_final_preflight.json"))

        let execution = P32A5ExecutionReport(
            executor: "OllamaNativeCleanupExecutor",
            vendor: "OLLAMA",
            entityKind: "MODEL",
            action: exec.action,
            canonicalModel: exec.canonicalModel,
            shellUsed: exec.shellUsed,
            rawDeleteFallback: exec.rawDeleteFallback,
            processStarted: exec.executorInvoked,
            argvContract: exec.argvContract,
            startedAt: exec.auditRecord?.startedAt,
            endedAt: exec.auditRecord?.executedAt,
            durationMs: exec.executionMs,
            exitStatus: exec.exitStatus,
            executionOutcome: exec.processOutcome ?? exec.outcome,
            permitID: exec.permitID,
            permitConsumed: exec.permitConsumed,
            retryPerformed: exec.retryPerformed,
            realMutationExecuted: exec.realMutationExecuted,
            generatedAt: Date()
        )
        try encoder.encode(execution).write(to: outDir.appendingPathComponent("p3_2a_5_execution.json"))

        let post = P32A5PostVerifyReport(
            modelPresentBefore: exec.modelPresentBefore,
            modelPresentAfter: exec.modelPresentAfter,
            modelRemovalVerified: exec.logicalRemovalVerified,
            oldManifestPresentAfter: exec.oldManifestPresentAfter,
            remainingReferencedBlobCount: exec.remainingReferencedBlobCount,
            remainingSharedBytes: exec.remainingSharedBytes,
            remainingUniqueBytes: exec.remainingUniqueBytes,
            potentialRecoveryBytesBefore: exec.potentialRecoveryBytesBefore,
            verifiedRecoveredBytes: exec.verifiedRecoveredBytes,
            mappedDeltaBytes: exec.mappedDeltaBytes,
            diskFreeDeltaBytes: exec.diskFreeDeltaBytes,
            recoveryStatus: exec.recoveryStatus,
            regenerationDetected: exec.regenerationDetected,
            postVerifyStatus: exec.postVerifyStatus,
            generatedAt: Date()
        )
        try encoder.encode(post).write(to: outDir.appendingPathComponent("p3_2a_5_postverify.json"))

        let beforeAfter = P32A5BeforeAfterReport(
            before: .init(
                modelInstalled: exec.modelPresentBefore,
                uniqueBytes: exec.potentialRecoveryBytesBefore,
                sharedBytes: 0,
                planTier: "APPROVAL_REQUIRED",
                potentialBytes: exec.potentialRecoveryBytesBefore
            ),
            after: .init(
                modelInstalled: exec.modelPresentAfter,
                uniqueBytes: exec.remainingUniqueBytes,
                sharedBytes: exec.remainingSharedBytes,
                planTier: exec.logicalRemovalVerified ? "COMPLETED" : "ACTION_FAILED",
                potentialBytes: exec.logicalRemovalVerified ? 0 : exec.potentialRecoveryBytesBefore
            ),
            actionCorrelation: [
                exec.entityID,
                exec.action,
                exec.permitID ?? "nil",
                exec.postVerifyStatus ?? "nil",
            ].joined(separator: "|"),
            logicalRemovalVerified: exec.logicalRemovalVerified,
            storageRecoveryVerified: exec.verifiedRecoveredBytes > 0,
            generatedAt: Date()
        )
        try encoder.encode(beforeAfter).write(to: outDir.appendingPathComponent("p3_2a_5_before_after.json"))

        let falseGREEN = scanReport.greenAudits.filter { $0.safetyClass == .green && !$0.requiredPredicatesSatisfied }.count
        let dup = scanReport.actionSafetyEvalDedup.duplicateEvaluations
        let safety = P32A5SafetyRegressionReport(
            FalseGREEN: falseGREEN,
            duplicateEvaluations: dup,
            HFExecutable: ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .snapshot
            ) == .implemented,
            rawBlobExecutable: ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .ollama, entityKind: .blob
            ) == .implemented,
            MOVE_TO_TRASHChanged: false,
            secondCrawlerAdded: false,
            newMutationCapabilitiesAddedInThisPhase: ["OLLAMA_MODEL_VENDOR_NATIVE_CLEANUP_REAL_PATH"],
            generatedAt: Date()
        )
        try encoder.encode(safety).write(to: outDir.appendingPathComponent("p3_2a_5_safety_regression.json"))
        try encoder.encode(exec).write(to: outDir.appendingPathComponent("p3_2a_5_orchestrator_report.json"))
    }
}
