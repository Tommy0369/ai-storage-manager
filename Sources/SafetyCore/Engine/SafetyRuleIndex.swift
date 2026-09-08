import Foundation

/// Per-scan immutable rule lookup index. Candidate superset must preserve reference semantics.
public struct SafetyRuleIndex: Sendable {
    public let rules: [SafetyRule]
    public let ruleByID: [String: SafetyRule]
    public let loader: KnowledgeBaseLoader
    public private(set) var stats: SafetyRuleIndexStats

    private let keywordToRuleIndices: [String: [Int]]
    private let universalRuleIndices: [Int]
    private var pathMatchCache: [String: [SafetyRule]]

    public init(knowledge: KnowledgeBaseDocument, loader: KnowledgeBaseLoader = KnowledgeBaseLoader()) {
        self.rules = knowledge.rules
        self.loader = loader
        self.ruleByID = Dictionary(uniqueKeysWithValues: knowledge.rules.map { ($0.id, $0) })
        self.pathMatchCache = [:]

        var inverted: [String: Set<Int>] = [:]
        var universal: [Int] = []
        for (idx, rule) in knowledge.rules.enumerated() {
            let tokens = Self.literalTokens(from: rule.match.path)
            if tokens.isEmpty {
                universal.append(idx)
                continue
            }
            for token in tokens {
                inverted[token, default: []].insert(idx)
            }
        }
        keywordToRuleIndices = inverted.mapValues { Array($0).sorted() }
        universalRuleIndices = universal
        stats = SafetyRuleIndexStats(
            totalRules: knowledge.rules.count,
            keywordBuckets: keywordToRuleIndices.count,
            universalRules: universalRuleIndices.count
        )
    }

    public mutating func matchingRules(for path: String) -> [SafetyRule] {
        let key = (PathGlob.expandHome(path) as NSString).standardizingPath
        if let cached = pathMatchCache[key] {
            stats.pathCacheHits += 1
            return cached
        }
        stats.pathCacheMisses += 1

        let reference = referenceMatchingRules(for: key)
        var candidateIndices = Set(universalRuleIndices)
        let lower = key.lowercased()
        for (token, indices) in keywordToRuleIndices where lower.contains(token) {
            candidateIndices.formUnion(indices)
        }
        if candidateIndices.count < rules.count {
            let candidates = candidateIndices.sorted().map { rules[$0] }
            let filtered = candidates.filter { PathGlob.matches(path: key, pattern: $0.match.path) }
            let indexedPick = SafetyRuleEngine.selectRule(filtered, loader: loader)
            let referencePick = SafetyRuleEngine.selectRule(reference, loader: loader)
            if indexedPick?.id == referencePick?.id {
                stats.indexedLookups += 1
                stats.rulesConsideredTotal += filtered.count
                pathMatchCache[key] = filtered
                return filtered
            }
            stats.indexFallbacks += 1
        }
        stats.referenceLookups += 1
        stats.rulesConsideredTotal += reference.count
        pathMatchCache[key] = reference
        return reference
    }

    public func rule(id: String?) -> SafetyRule? {
        guard let id else { return nil }
        return ruleByID[id]
    }

    public func referenceMatchingRules(for path: String) -> [SafetyRule] {
        rules.filter { PathGlob.matches(path: path, pattern: $0.match.path) }
    }

    static func literalTokens(from pattern: String) -> [String] {
        let expanded = PathGlob.expandHome(pattern).lowercased()
        let stripped = expanded
            .replacingOccurrences(of: "**", with: "/")
            .replacingOccurrences(of: "*", with: "")
        return stripped.split(separator: "/").map(String.init).filter { $0.count >= 3 }
    }
}

public struct SafetyRuleIndexStats: Codable, Sendable, Equatable {
    public var totalRules: Int
    public var keywordBuckets: Int
    public var universalRules: Int
    public var pathCacheHits: Int = 0
    public var pathCacheMisses: Int = 0
    public var indexedLookups: Int = 0
    public var referenceLookups: Int = 0
    public var indexFallbacks: Int = 0
    public var rulesConsideredTotal: Int = 0
}

public struct RuleCandidateKey: Hashable, Sendable {
    public var domain: String
    public var category: String
    public var subcategory: String
    public var action: String

    public init(entity: StorageEntity, action: ActionMode) {
        domain = entity.category
        category = entity.category
        subcategory = entity.subcategory
        self.action = action.rawValue
    }
}
