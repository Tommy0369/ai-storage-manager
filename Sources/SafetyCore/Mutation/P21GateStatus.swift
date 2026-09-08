import Foundation

public enum P21GateStatusValue: String, Codable, Sendable {
    case readyForHumanAuthorization = "READY_FOR_HUMAN_AUTHORIZATION"
    case blockedByRealEvidence = "BLOCKED_BY_REAL_EVIDENCE"
    case blockedByArchitecture = "BLOCKED_BY_ARCHITECTURE"
}

public struct P21GateStatusReport: Codable, Sendable, Equatable {
    public var status: String
    public var realDerivedDataCandidates: Int
    public var approvalRequired: Int
    public var contractSatisfiedReadOnly: Int
    public var topBlockers: [String]
    public var executorImplemented: Bool
    public var previewExecutable: Bool
    public var destructiveActionsExecuted: Bool
}

public enum P21GateStatusEvaluator {
    public static func evaluate(
        derivedDataReport: DerivedDataMutationReadinessReport,
        dedupReport: ActionSafetyEvalDedupReport,
        mutationSurfaceAudit: MutationSurfaceAuditReport
    ) -> P21GateStatusReport {
        let approval = derivedDataReport.approvalRequired
        let satisfied = derivedDataReport.contractSatisfiedReadOnly
        let realCandidates = approval + satisfied

        var blockers: [String: Int] = [:]
        for entry in derivedDataReport.entries {
            if let first = entry.firstBlockingGate {
                blockers[first, default: 0] += 1
            }
            for reason in entry.allBlockingReasons {
                blockers[reason, default: 0] += 1
            }
        }
        let top = blockers.sorted { $0.value > $1.value }.prefix(5).map(\.key)

        let status: P21GateStatusValue
        if realCandidates > 0, dedupReport.duplicateEvaluations == 0, mutationSurfaceAudit.auditPassed {
            status = .readyForHumanAuthorization
        } else if dedupReport.duplicateEvaluations > 0 || !mutationSurfaceAudit.auditPassed {
            status = .blockedByArchitecture
        } else {
            status = .blockedByRealEvidence
        }

        return P21GateStatusReport(
            status: status.rawValue,
            realDerivedDataCandidates: realCandidates,
            approvalRequired: approval,
            contractSatisfiedReadOnly: satisfied,
            topBlockers: Array(top),
            executorImplemented: false,
            previewExecutable: false,
            destructiveActionsExecuted: false
        )
    }
}

public struct P201RuntimeComparison: Codable, Sendable, Equatable {
    public var p113TotalSeconds: Double
    public var p20TotalSeconds: Double
    public var p201TotalSeconds: Double
    public var p113SafetyEvalMs: Int
    public var p20SafetyEvalMs: Int
    public var p201SafetyEvalMs: Int
    public var actionDecisionBuildMs: Int
    public var recommendationMs: Int
    public var preflightMs: Int
    public var readinessMs: Int
    public var mutationGateMs: Int
    public var reportGenerationMs: Int
    public var runtimeBatchMs: Int
    public var duplicateEvaluations: Int
    public var decisionReuseCount: Int
}
