import Foundation

public struct SafetyDecision: Codable, Sendable, Equatable {
    public var entity: StorageEntity
    public var action: ActionMode
    public var safetyClass: SafetyClass
    public var safetyScore: SafetyScore?
    public var reasonCodes: [String]
    public var sideEffects: [String]
    public var matchedRuleID: String?
    public var evaluationLayer: EvaluationLayer
    public var evidenceConfidence: Double
    public var userExplanationJA: String
    public var growthCauses: [String]
    public var requiresUserApproval: Bool
    public var blockedBy: String?

    public init(
        entity: StorageEntity,
        action: ActionMode,
        safetyClass: SafetyClass,
        safetyScore: SafetyScore?,
        reasonCodes: [String],
        sideEffects: [String],
        matchedRuleID: String?,
        evaluationLayer: EvaluationLayer,
        evidenceConfidence: Double,
        userExplanationJA: String,
        growthCauses: [String],
        requiresUserApproval: Bool,
        blockedBy: String?
    ) {
        self.entity = entity
        self.action = action
        self.safetyClass = safetyClass
        self.safetyScore = safetyScore
        self.reasonCodes = reasonCodes
        self.sideEffects = sideEffects
        self.matchedRuleID = matchedRuleID
        self.evaluationLayer = evaluationLayer
        self.evidenceConfidence = evidenceConfidence
        self.userExplanationJA = userExplanationJA
        self.growthCauses = growthCauses
        self.requiresUserApproval = requiresUserApproval
        self.blockedBy = blockedBy
    }

    public var allowsCleanupCandidate: Bool {
        safetyClass == .green || safetyClass == .yellow
    }
}
