import Foundation
import SafetyCore

public struct P32A4ActionSafetyAlignmentReport: Codable, Sendable {
    public var entityID: String
    public var canonicalModel: String
    public var action: String
    public var genericEntitySafetyClass: String
    public var moveToTrashDecision: String
    public var keepRecommendation: String
    public var vendorNativeDecision: String
    public var vendorNativeSafetyClassOrState: String
    public var requiredStrictPredicates: [String]
    public var verifiedStrictPredicates: [String]
    public var unknownStrictPredicates: [String]
    public var conflictedStrictPredicates: [String]
    public var vendorNativeBlockers: [String]
    public var reacquirabilityPredicateStatus: String
    public var regenerabilityPredicateStatus: String
    public var remoteCanonicalStatus: String
    public var runtimeStatus: String
    public var referenceGraphStatus: String
    public var nativeInterfaceStatus: String
    public var preflightStatus: String
    public var remainingBlockers: [String]
    public var approvalIsOnlyRemainingGate: Bool
    public var planTier: String
    public var planPotentialBytes: Int64
    public var immediateExpectedRecoveryBytes: Int64
    public var verifiedRecoveredBytes: Int64
    public var rawDeleteBlocked: Bool
    public var HFExecutable: Bool
    public var FalseGREEN: Int
    public var duplicateEvaluations: Int
    public var mutationGateUsesExactActionDecision: Bool
    public var permitRejectsStrictUnknown: Bool
    public var realApprovalCreated: Bool
    public var cleanupExecutionPermitCreated: Bool
    public var cleanupExecutorInvoked: Bool
    public var ollamaRmExecuted: Bool
    public var generatedAt: Date
}

public enum P32A4ReportBuilder {
    public static func alignment(
        snapshot: ActionSpecificSafetySnapshot,
        canonicalModel: String,
        moveToTrashEligible: Bool,
        keepRecommended: Bool,
        runtimeStatus: String,
        referenceGraphStatus: String,
        nativeInterfaceStatus: String,
        preflightStatus: String,
        planTier: String,
        planPotentialBytes: Int64,
        falseGREEN: Int,
        duplicateEvaluations: Int
    ) -> P32A4ActionSafetyAlignmentReport {
        P32A4ActionSafetyAlignmentReport(
            entityID: snapshot.entityID,
            canonicalModel: canonicalModel,
            action: snapshot.action.rawValue,
            genericEntitySafetyClass: snapshot.genericEntitySafetyClass.rawValue,
            moveToTrashDecision: moveToTrashEligible ? "ELIGIBLE" : "BLOCKED",
            keepRecommendation: keepRecommended ? "KEEP" : "OTHER",
            vendorNativeDecision: snapshot.actionDecisionEligible ? "ELIGIBLE" : "NOT_ELIGIBLE",
            vendorNativeSafetyClassOrState: snapshot.actionSpecificSafetyClass.rawValue,
            requiredStrictPredicates: snapshot.requiredStrictPredicates,
            verifiedStrictPredicates: snapshot.verifiedStrictPredicates,
            unknownStrictPredicates: snapshot.unknownStrictPredicates,
            conflictedStrictPredicates: snapshot.conflictedStrictPredicates,
            vendorNativeBlockers: snapshot.safetyBlockers,
            reacquirabilityPredicateStatus: snapshot.reacquirabilityStatus,
            regenerabilityPredicateStatus: snapshot.regenerabilityStatus,
            remoteCanonicalStatus: snapshot.reacquirabilityStatus,
            runtimeStatus: runtimeStatus,
            referenceGraphStatus: referenceGraphStatus,
            nativeInterfaceStatus: nativeInterfaceStatus,
            preflightStatus: preflightStatus,
            remainingBlockers: snapshot.remainingGateBlockers,
            approvalIsOnlyRemainingGate: snapshot.approvalIsOnlyRemainingGate,
            planTier: planTier,
            planPotentialBytes: planPotentialBytes,
            immediateExpectedRecoveryBytes: 0,
            verifiedRecoveredBytes: 0,
            rawDeleteBlocked: true,
            HFExecutable: false,
            FalseGREEN: falseGREEN,
            duplicateEvaluations: duplicateEvaluations,
            mutationGateUsesExactActionDecision: true,
            permitRejectsStrictUnknown: true,
            realApprovalCreated: false,
            cleanupExecutionPermitCreated: false,
            cleanupExecutorInvoked: false,
            ollamaRmExecuted: false,
            generatedAt: snapshot.observedAt
        )
    }
}
