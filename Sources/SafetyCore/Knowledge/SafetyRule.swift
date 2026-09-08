import Foundation

public struct RuleMatch: Codable, Sendable, Equatable {
    public var path: String
    public var owner: String?
    public var followSymlinks: Bool

    enum CodingKeys: String, CodingKey {
        case path, owner
        case followSymlinks = "follow_symlinks"
    }

    public init(path: String, owner: String? = "current_user", followSymlinks: Bool = false) {
        self.path = path
        self.owner = owner
        self.followSymlinks = followSymlinks
    }
}

public struct GrowthCause: Codable, Sendable, Equatable {
    public var code: String
    public var explanationJA: String

    enum CodingKeys: String, CodingKey {
        case code
        case explanationJA = "explanation_ja"
    }
}

public struct SafetyRule: Codable, Sendable, Equatable {
    public var id: String
    public var entity: String
    public var category: String
    public var subcategory: String
    public var match: RuleMatch
    public var defaultClass: SafetyClass
    public var baseScore: Int
    public var evaluationLayer: EvaluationLayer
    public var sourceOfTruth: Bool
    public var regenerable: Bool
    public var networkRequired: Bool
    public var requiredPredicates: [String]
    public var demoteToYellowIf: [String]
    public var demoteToRedIf: [String]
    public var hardBlockIf: [String]
    public var actionMode: ActionMode
    public var effects: [String]
    public var verification: [String]
    public var growthCauses: [GrowthCause]
    public var explanationJA: String
    public var reasonCodes: [String]

    enum CodingKeys: String, CodingKey {
        case id, entity, category, subcategory, match
        case defaultClass = "default_class"
        case baseScore = "base_score"
        case evaluationLayer = "evaluation_layer"
        case sourceOfTruth = "source_of_truth"
        case regenerable
        case networkRequired = "network_required"
        case requiredPredicates = "required_predicates"
        case demoteToYellowIf = "demote_to_yellow_if"
        case demoteToRedIf = "demote_to_red_if"
        case hardBlockIf = "hard_block_if"
        case actionMode = "action_mode"
        case effects, verification
        case growthCauses = "growth_causes"
        case explanationJA = "explanation_ja"
        case reasonCodes = "reason_codes"
    }
}

public struct KnowledgeBaseDocument: Codable, Sendable {
    public var version: String
    public var principle: String
    public var rules: [SafetyRule]

    public init(version: String, principle: String, rules: [SafetyRule]) {
        self.version = version
        self.principle = principle
        self.rules = rules
    }
}
