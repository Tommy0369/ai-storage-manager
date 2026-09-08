import Foundation

/// Read-only preflight preview. Answers "would this action be executable NOW?" without mutation.
public enum ActionPreflightEngine {
    /// P2.0.1: consumes canonical ActionDecisionSet — does not re-evaluate Safety.
    public static func preview(
        items: [ClassifiedItem],
        recommendations: [ActionRecommendationResult],
        decisionCatalog: ActionDecisionCatalog
    ) -> [ActionPreflightResult] {
        var recMap: [String: ActionRecommendationResult] = [:]
        for rec in recommendations {
            recMap[rec.entityID] = rec
        }
        var out: [ActionPreflightResult] = []
        for item in items {
            let decisions = decisionCatalog.set(for: item.detected.entity.id)?.decisionMap ?? [:]
            let rec = recMap[item.detected.entity.id]
            let targetActions: [StorageAction]
            if case .actionable(let a)? = rec?.disposition {
                targetActions = [a, .keep]
            } else {
                targetActions = [.keep, .moveToTrash, .moveToICloud, .removeLocalDownload]
            }
            for action in targetActions {
                guard let decision = decisions[action] else { continue }
                out.append(preflight(item: item, action: action, decision: decision))
            }
        }
        return out
    }

    static func preflight(item: ClassifiedItem, action: StorageAction, decision: ActionDecision) -> ActionPreflightResult {
        let stale: [ClaimType] = decision.requiredClaims
            .filter { $0.freshness != .staticClaim }
            .map(\.claimType)
            .filter { decision.missingClaimTypes.contains($0) }

        return ActionPreflightResult(
            action: action,
            entityID: item.detected.entity.id,
            path: item.detected.entity.path,
            allowed: decision.eligible,
            satisfied: decision.satisfiedClaimTypes,
            missing: decision.missingClaimTypes,
            stale: stale,
            conflicted: decision.blockedReasons.contains(.evidenceConflict) ? decision.missingClaimTypes : [],
            blockedReasons: decision.blockedReasons,
            wouldExecuteNow: false
        )
    }

    public static func blockedSummaries(from recommendations: [ActionRecommendationResult]) -> [ActionBlockedSummary] {
        recommendations.flatMap { rec in
            rec.blockedActions.map { blocked in
                ActionBlockedSummary(
                    entityID: rec.entityID,
                    path: rec.path,
                    action: blocked.action,
                    reasons: blocked.reasons
                )
            }
        }
    }

    public static func buildReport(
        items: [ClassifiedItem],
        decisionCatalog: ActionDecisionCatalog
    ) -> ActionArchitectureReport {
        let recommendations = ActionRecommendationEngine.recommend(
            items: items,
            decisionCatalog: decisionCatalog
        )
        let preflight = preview(
            items: items,
            recommendations: recommendations,
            decisionCatalog: decisionCatalog
        )
        let blocked = blockedSummaries(from: recommendations)
        let iCloud = recommendations.filter {
            if case .actionable(.moveToICloud) = $0.disposition { return true }
            return $0.recommendedAction == .moveToICloud
        }
        let evict = recommendations.filter {
            if case .actionable(.removeLocalDownload) = $0.disposition { return true }
            return $0.recommendedAction == .removeLocalDownload
        }
        return ActionArchitectureReport(
            recommendations: recommendations,
            preflightPreviews: preflight,
            blockedSummaries: blocked,
            iCloudMoveCandidates: iCloud,
            removeLocalDownloadCandidates: evict,
            previewExecutable: false,
            destructiveActionsExecuted: false
        )
    }

    /// Legacy test helper — builds a fresh catalog then delegates to canonical path.
    public static func buildReport(
        items: [ClassifiedItem],
        engine: SafetyRuleEngine,
        evidenceByEntityID: [String: EvidenceBundle] = [:],
        stateByEntityID: [String: RuntimeState] = [:],
        userContext: ActionUserContext = .default,
        snapshotsByEntityID: [String: EntitySafetySnapshot] = [:],
        safetyDecisionsByEntityID: [String: [ActionMode: SafetyDecision]] = [:]
    ) -> ActionArchitectureReport {
        _ = evidenceByEntityID
        _ = stateByEntityID
        let catalog = ActionDecisionBuilder.buildCatalog(
            items: items,
            engine: engine,
            snapshotsByEntityID: snapshotsByEntityID,
            safetyDecisionsByEntityID: safetyDecisionsByEntityID,
            userContext: userContext,
            evidenceByEntityID: evidenceByEntityID,
            stateByEntityID: stateByEntityID
        )
        return buildReport(items: items, decisionCatalog: catalog)
    }
}
