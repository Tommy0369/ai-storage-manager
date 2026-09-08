import Foundation

public struct MutationCandidateFunnelReport: Codable, Sendable, Equatable {
    public var entitiesScanned: Int
    public var entitiesWithNonKeepPotential: Int
    public var entitiesWithActionDecision: Int
    public var entitiesRecommendedNonKeep: Int
    public var entitiesReachingPreflight: Int
    public var entitiesReachingReadiness: Int
    public var entitiesEnteringMutationGate: Int
    public var blockedBeforeGate: Int
    public var reasonDistribution: [String: Int]
    public var derivedDataDiscovered: Int
    public var derivedDataEvaluatedForTrash: Int
}

public enum MutationCandidateFunnel {
    public static func build(
        items: [ClassifiedItem],
        decisionCatalog: ActionDecisionCatalog,
        recommendations: [ActionRecommendationResult],
        preflights: [ActionPreflightResult],
        actReadiness: ActionReadinessReport,
        mutationGate: MutationGateReport,
        derivedDataReport: DerivedDataMutationReadinessReport
    ) -> MutationCandidateFunnelReport {
        var reasonDist: [String: Int] = [:]
        var nonKeepPotential = 0
        var recommendedNonKeep = 0
        var reachingPreflight = 0
        var reachingReadiness = 0

        for item in items {
            guard let set = decisionCatalog.set(for: item.detected.entity.id) else { continue }
            let hasPotential = StorageAction.allCases.contains { action in
                guard action != .keep, let d = set.decision(for: action) else { return false }
                return d.eligible || !d.blockedReasons.isEmpty
            }
            if hasPotential { nonKeepPotential += 1 }
        }

        for rec in recommendations {
            if rec.recommendedAction != .keep {
                recommendedNonKeep += 1
            }
            if case .actionable = rec.disposition {
                recommendedNonKeep += 0
            }
        }

        for entry in actReadiness.entries where entry.readiness == ActionReadinessState.preflightRequired.rawValue
            || entry.readiness == ActionReadinessState.preflightSatisfiedReadOnly.rawValue {
            reachingPreflight += 1
        }
        reachingReadiness = actReadiness.preflightSatisfiedReadOnlyCount + actReadiness.preflightRequiredCount

        for entry in mutationGate.entries {
            for reason in entry.blockingReasons {
                reasonDist[reason, default: 0] += 1
            }
        }

        let blockedBeforeGate = items.count - mutationGate.entries.count

        return MutationCandidateFunnelReport(
            entitiesScanned: items.count,
            entitiesWithNonKeepPotential: nonKeepPotential,
            entitiesWithActionDecision: decisionCatalog.setsByEntityID.count,
            entitiesRecommendedNonKeep: recommendations.filter { $0.recommendedAction != .keep }.count,
            entitiesReachingPreflight: preflights.count,
            entitiesReachingReadiness: reachingReadiness,
            entitiesEnteringMutationGate: mutationGate.entries.count,
            blockedBeforeGate: max(0, blockedBeforeGate),
            reasonDistribution: reasonDist,
            derivedDataDiscovered: derivedDataReport.entitiesDiscovered,
            derivedDataEvaluatedForTrash: derivedDataReport.entries.count
        )
    }
}
