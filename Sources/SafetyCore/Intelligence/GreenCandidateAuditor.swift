import Foundation

public struct GreenAuditRecord: Codable, Sendable, Equatable {
    public var entity: String
    public var path: String
    public var sizeBytes: Int64
    public var matchedRule: String?
    public var ruleVersion: String
    public var predicates: [String: String]
    public var sourceOfTruth: String
    public var regenerable: String
    public var activeUse: Bool
    public var syncBlastRadiusSafe: String
    public var safetyClass: SafetyClass
    public var safetyScore: Int?
    public var recommendedAction: ActionMode
    public var reasonCodes: [String]
    public var sideEffects: [String]
    public var verificationStatus: String
    public var requiredPredicatesSatisfied: Bool
    public var downgradedFromGreen: Bool
    public var downgradeReason: String?
}

public struct GreenCandidateAuditor {
    public var knowledge: KnowledgeBaseDocument

    public init(knowledge: KnowledgeBaseDocument) {
        self.knowledge = knowledge
    }

    public func audit(item: ClassifiedItem, evidence: EvidenceBundle, state: RuntimeState) -> (SafetyDecision, GreenAuditRecord) {
        var decision = item.decision
        let rule = knowledge.rules.first { $0.id == decision.matchedRuleID }
        var preds: [String: String] = [:]
        var satisfied = true
        if let rule {
            for key in rule.requiredPredicates {
                let v = evidence.value(for: key)
                preds[key] = v.rawValue
                if !evidence.satisfiesStrictPredicate(key) { satisfied = false }
            }
        }
        let sotOK = (evidence.sourceOfTruth == .false && evidence.confidence(for: "not_source_of_truth") == .verified)
            || (rule?.sourceOfTruth == false && evidence.sourceOfTruth != .true)
        let regenOK = evidence.satisfiesStrictPredicate("regenerable") || rule?.regenerable == false
        let syncOK = evidence.syncWouldDeleteRemote != .true
        var reason: String?
        if decision.safetyClass == .green {
            if !satisfied { reason = "REQUIRED_PREDICATE_NOT_VERIFIED" }
            else if evidence.sourceOfTruth != .false || evidence.confidence(for: "not_source_of_truth") != .verified {
                reason = "SOURCE_OF_TRUTH_NOT_VERIFIED_FALSE"
            }
            else if state.isActivelyUsed { reason = "ACTIVE_USE" }
            else if evidence.syncWouldDeleteRemote != .false && rule?.actionMode == .cloudEvictOnly {
                reason = "SYNC_BLAST_RADIUS_UNVERIFIED"
            } else if rule?.regenerable == true && !evidence.satisfiesStrictPredicate("regenerable") {
                reason = "REGENERABLE_NOT_VERIFIED"
            }
            if let reason {
                decision.safetyClass = reason.contains("UNVERIFIED") || reason.contains("PREDICATE") ? .unknown : .yellow
                decision.reasonCodes.append("GREEN_AUDIT_DOWNGRADE:\(reason)")
                decision.safetyScore = nil
                if decision.safetyClass == .unknown {
                    decision.action = .userReview
                }
            }
        }
        let record = GreenAuditRecord(
            entity: item.detected.entity.id,
            path: item.detected.entity.path,
            sizeBytes: item.detected.entity.logicalBytes,
            matchedRule: decision.matchedRuleID,
            ruleVersion: "0.1",
            predicates: preds,
            sourceOfTruth: evidence.sourceOfTruth.rawValue,
            regenerable: evidence.regenerable.rawValue,
            activeUse: state.isActivelyUsed,
            syncBlastRadiusSafe: syncOK ? evidence.syncWouldDeleteRemote.rawValue : "unsafe",
            safetyClass: decision.safetyClass,
            safetyScore: decision.safetyScore?.value,
            recommendedAction: decision.action,
            reasonCodes: decision.reasonCodes,
            sideEffects: decision.sideEffects,
            verificationStatus: (satisfied && sotOK && regenOK) ? "PREDICATES_VERIFIED" : "UNVERIFIED",
            requiredPredicatesSatisfied: satisfied && sotOK && regenOK,
            downgradedFromGreen: reason != nil,
            downgradeReason: reason
        )
        return (decision, record)
    }
}
