import Foundation

/// Recommendation answers "what should the user probably do?" — never overrides Safety.
public enum ActionRecommendationEngine {
    /// P2.0.1: consumes canonical ActionDecisionSet — does not re-evaluate Safety.
    public static func recommend(
        items: [ClassifiedItem],
        decisionCatalog: ActionDecisionCatalog
    ) -> [ActionRecommendationResult] {
        items.map { item in
            let decisions = decisionCatalog.set(for: item.detected.entity.id)?.decisionMap ?? [:]
            return recommendOne(item: item, decisions: decisions)
        }
    }

    /// Legacy path for isolated unit tests only — production pipeline must use `decisionCatalog`.
    public static func recommend(
        items: [ClassifiedItem],
        engine: SafetyRuleEngine,
        evidenceByEntityID: [String: EvidenceBundle] = [:],
        stateByEntityID: [String: RuntimeState] = [:],
        userContext: ActionUserContext = .default,
        snapshotsByEntityID: [String: EntitySafetySnapshot] = [:],
        safetyDecisionsByEntityID: [String: [ActionMode: SafetyDecision]] = [:]
    ) -> [ActionRecommendationResult] {
        let catalog = ActionDecisionBuilder.buildCatalog(
            items: items,
            engine: engine,
            snapshotsByEntityID: snapshotsByEntityID,
            safetyDecisionsByEntityID: safetyDecisionsByEntityID,
            userContext: userContext,
            evidenceByEntityID: evidenceByEntityID,
            stateByEntityID: stateByEntityID
        )
        return recommend(items: items, decisionCatalog: catalog)
    }

    static func recommendOne(item: ClassifiedItem, decisions: [StorageAction: ActionDecision]) -> ActionRecommendationResult {
        let id = item.detected.entity.id
        let path = item.detected.entity.path
        var blockedActions: [BlockedAction] = []

        for action in StorageAction.allCases where action != .keep {
            if let d = decisions[action], !d.eligible, !d.blockedReasons.isEmpty {
                blockedActions.append(BlockedAction(action: action, reasons: d.blockedReasons))
            }
        }

        let disposition = chooseDisposition(item: item, decisions: decisions)
        let (recommended, alternatives, reasons, confidence, recovery, recoveryConf, missing) = rank(
            item: item,
            disposition: disposition,
            decisions: decisions
        )

        return ActionRecommendationResult(
            entityID: id,
            path: path,
            disposition: disposition,
            recommendedAction: recommended,
            alternatives: alternatives,
            recommendationReasons: reasons,
            blockedActions: blockedActions,
            confidence: confidence,
            expectedLocalRecoveryBytes: recovery,
            recoveryConfidence: recoveryConf,
            missingProof: missing
        )
    }

    static func chooseDisposition(
        item: ClassifiedItem,
        decisions: [StorageAction: ActionDecision]
    ) -> RecommendationDisposition {
        if ActionPolicy.isGitRepository(item) {
            return .keep
        }
        if ActionPolicy.isVoiceMemo(item) {
            return .keep
        }
        if ActionPolicy.isIOSBackup(item) {
            return .keep
        }
        if ActionPolicy.isClaudeRuntime(item) {
            if decisions[.moveToTrash]?.eligible == false, decisions[.moveToICloud]?.eligible == false {
                return .verifyMore([.activeState, .sourceOfTruth])
            }
            return .keep
        }

        if ActionPolicy.isAIVendorModelStorage(item) {
            var missing: [ClaimType] = [.reacquisition]
            if item.verification?.referenceGraphConfidence != .verified {
                missing.append(.referenceGraph)
            }
            return .verifyMore(missing)
        }

        if let trash = decisions[.moveToTrash], trash.eligible, ActionPolicy.isDerivedData(item) {
            return .actionable(.moveToTrash)
        }

        if let iCloud = decisions[.moveToICloud], iCloud.eligible {
            if item.exclusiveBytes > 500_000_000, ActionPolicy.isUserOwnedRoot(item.detected.entity.path) {
                return .actionable(.moveToICloud)
            }
            if ActionPolicy.userOwnedVerified(item), ActionPolicy.isUserOwnedRoot(item.detected.entity.path) {
                return .actionable(.moveToICloud)
            }
        }

        if let evict = decisions[.removeLocalDownload], evict.eligible {
            return .actionable(.removeLocalDownload)
        }

        if let trash = decisions[.moveToTrash], trash.eligible {
            return .actionable(.moveToTrash)
        }

        if item.decision.safetyClass == .unknown || item.decision.safetyClass == .red {
            return .keep
        }

        let missing = decisions.values.flatMap(\.missingClaimTypes)
        if !missing.isEmpty {
            return .verifyMore(Array(Set(missing)))
        }
        return .keep
    }

    static func rank(
        item: ClassifiedItem,
        disposition: RecommendationDisposition,
        decisions: [StorageAction: ActionDecision]
    ) -> (StorageAction, [StorageAction], [String], EvidenceConfidence, Int64?, EvidenceConfidence, [ClaimType]) {
        switch disposition {
        case .actionable(let action):
            var alts: [StorageAction] = [.keep]
            if action == .moveToICloud { alts.append(.moveToTrash) }
            if action == .moveToTrash { alts.append(.keep) }
            if action == .removeLocalDownload { alts.append(.keep) }
            let d = decisions[action]
            var reasons = d?.explanationCodes ?? []
            if action == .moveToICloud { reasons.append("PRESERVATION_NOT_DELETION"); reasons.append("SOT_TRUE_ALLOWED") }
            if action == .moveToTrash, ActionPolicy.isDerivedData(item) {
                reasons.append("GENERATED_ARTIFACT"); reasons.append("SOT_FALSE_VERIFIED")
            }
            return (
                action,
                alts.filter { $0 != action },
                reasons,
                d?.recoveryConfidence ?? .verified,
                d?.expectedLocalRecoveryBytes,
                d?.recoveryConfidence ?? .unknown,
                d?.missingClaimTypes ?? []
            )
        case .keep:
            return (.keep, [], ["KEEP_RECOMMENDED"], .verified, nil, .unknown, [])
        case .verifyMore(let claims):
            return (.keep, [], ["VERIFY_MORE"], .unknown, nil, .unknown, claims)
        }
    }
}
