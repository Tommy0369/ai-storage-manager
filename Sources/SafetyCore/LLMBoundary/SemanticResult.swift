import Foundation

/// Snapshot handed to the LLM. Class is frozen. LLM may explain, not rewrite.
public struct SemanticResult: Codable, Sendable, Equatable {
    public let entity: String
    public let path: String
    public let sizeBytes: Int64
    public let safetyClass: SafetyClass
    public let safetyScore: Int?
    public let reasonCodes: [String]
    public let sideEffects: [String]
    public let userExplanationJA: String
    public let growthCauses: [String]
    public let recommendedAction: ActionMode
    public let requiresUserApproval: Bool

    public init(from decision: SafetyDecision) {
        entity = decision.entity.id
        path = decision.entity.path
        sizeBytes = decision.entity.logicalBytes
        safetyClass = decision.safetyClass
        safetyScore = decision.safetyClass == .unknown ? nil : decision.safetyScore?.value
        reasonCodes = decision.reasonCodes
        sideEffects = decision.sideEffects
        userExplanationJA = decision.userExplanationJA
        growthCauses = decision.growthCauses
        recommendedAction = decision.action
        requiresUserApproval = true
    }
}

public enum LLMBoundary {
    /// Architecture invariant: LLM output never mutates SafetyClass.
    public static func freeze(_ decision: SafetyDecision) -> SemanticResult {
        SemanticResult(from: decision)
    }
}
