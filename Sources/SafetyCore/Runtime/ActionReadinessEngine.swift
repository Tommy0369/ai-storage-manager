import Foundation

/// Read-only ACT readiness — feeds MutationGate in P2.0. Does not execute mutations.
public enum ActionReadinessEngine {
    public static func buildReport(
        items: [ClassifiedItem],
        recommendations: [ActionRecommendationResult],
        snapshotsByEntityID: [String: EntitySafetySnapshot],
        runtimeResolutions: [String: RuntimeStateResolution],
        preflights: [ActionPreflightResult] = [],
        actionDecisions: [String: [StorageAction: ActionDecision]] = [:],
        ruleVersion: String = "unknown",
        runtimeGeneration: Int = 0
    ) -> ActionReadinessReport {
        let mutationGate = MutationGate.buildReport(
            items: items,
            recommendations: recommendations,
            preflights: preflights,
            actionDecisions: actionDecisions,
            snapshotsByEntityID: snapshotsByEntityID,
            runtimeResolutions: runtimeResolutions,
            ruleVersion: ruleVersion,
            runtimeGeneration: runtimeGeneration
        )
        var gateByKey: [String: MutationGateResult] = [:]
        for entry in mutationGate.entries {
            gateByKey["\(entry.entityID):\(entry.action)"] = entry
        }

        var recMap: [String: ActionRecommendationResult] = [:]
        for rec in recommendations {
            recMap[rec.entityID] = rec
        }

        var entries: [ActionReadinessEntry] = []
        var recommendable = 0
        var preflightRequired = 0
        var preflightSatisfied = 0

        for item in items {
            guard let rec = recMap[item.detected.entity.id] else { continue }
            let snapshot = snapshotsByEntityID[item.detected.entity.id]
            let runtime = runtimeResolutions[item.detected.entity.id]
            let assessed = assess(
                item: item,
                recommendation: rec,
                snapshot: snapshot,
                runtime: runtime,
                gate: gateByKey["\(item.detected.entity.id):\(rec.recommendedAction.rawValue)"]
            )
            entries.append(assessed.entry)
            switch assessed.state {
            case .recommendable: recommendable += 1
            case .preflightRequired: preflightRequired += 1
            case .preflightSatisfiedReadOnly: preflightSatisfied += 1
            default: break
            }
        }

        return ActionReadinessReport(
            entries: entries.sorted { $0.entityID < $1.entityID },
            recommendableCount: recommendable,
            preflightRequiredCount: preflightRequired,
            preflightSatisfiedReadOnlyCount: preflightSatisfied,
            executorImplemented: false
        )
    }

    private static func assess(
        item: ClassifiedItem,
        recommendation: ActionRecommendationResult,
        snapshot: EntitySafetySnapshot?,
        runtime: RuntimeStateResolution?,
        gate: MutationGateResult?
    ) -> (state: ActionReadinessState, entry: ActionReadinessEntry) {
        let recommendedAction = recommendation.recommendedAction
        let safetyDecision = item.decision
        var runtimeRequired = runtimePredicates(for: recommendedAction)
        var runtimeSatisfied: [String] = []
        var freshRequirements: [String] = recommendation.missingProof.map(\.rawValue)

        if let gate {
            freshRequirements.append(contentsOf: gate.requiredFreshChecks)
            freshRequirements.append(contentsOf: gate.missingRequirements.filter { $0.contains("fresh") })
        }

        if let runtime {
            switch runtime.disposition {
            case .deferred:
                runtimeRequired = runtimeRequired.filter { !isRuntimePredicate($0) }
            case .resolved:
                if runtime.activeStateConfidence == .verified {
                    runtimeSatisfied.append("active_state")
                }
                if runtime.openFileConfidence == .verified {
                    runtimeSatisfied.append("no_open_file_handle")
                }
                if runtime.activeStateConfidence == .unknown {
                    freshRequirements.append("fresh_active_state")
                }
                if runtime.openFileConfidence == .unknown {
                    freshRequirements.append("fresh_open_file_state")
                }
            }
        } else if snapshot != nil {
            freshRequirements.append("runtime_batch_resolution")
        }

        let staticOK = safetyDecision.safetyClass != .unknown && safetyDecision.blockedBy == nil
        let actionable: Bool
        if case .actionable = recommendation.disposition {
            actionable = true
        } else {
            actionable = false
        }

        let state: ActionReadinessState
        if let gate, let mutation = MutationReadiness(rawValue: gate.readiness) {
            switch mutation {
            case .blocked:
                state = .blocked
            case .verifyMore:
                state = .verifyMore
            case .preflightRequired:
                state = .preflightRequired
            case .approvalRequired:
                state = .preflightRequired
            case .contractSatisfiedReadOnly:
                state = .preflightSatisfiedReadOnly
            }
        } else if !actionable || safetyDecision.safetyClass == .red {
            state = .blocked
        } else if case .verifyMore = recommendation.disposition {
            state = .verifyMore
        } else if !freshRequirements.isEmpty
            || runtimeRequired.contains(where: { !runtimeSatisfied.contains($0) && isRuntimePredicate($0) }) {
            state = .preflightRequired
        } else if actionable, staticOK {
            state = .preflightSatisfiedReadOnly
        } else if actionable {
            state = .recommendable
        } else {
            state = .blocked
        }

        let entry = ActionReadinessEntry(
            entityID: item.detected.entity.id,
            path: item.detected.entity.path,
            recommendedAction: recommendedAction.rawValue,
            safetyClass: safetyDecision.safetyClass.rawValue,
            readiness: state.rawValue,
            mutationReadiness: gate?.readiness,
            staticPredicatesSatisfied: staticOK,
            runtimePredicatesRequired: runtimeRequired,
            runtimePredicatesSatisfied: runtimeSatisfied,
            freshPreflightRequirements: Array(Set(freshRequirements)).sorted(),
            transactionContractAvailable: gate?.transactionContractAvailable ?? transactionContract(for: recommendedAction),
            postVerifyContractAvailable: gate?.postVerifyContractAvailable ?? postVerifyContract(for: recommendedAction),
            executorImplemented: false
        )
        return (state, entry)
    }

    private static func runtimePredicates(for action: StorageAction) -> [String] {
        switch action {
        case .moveToTrash:
            return ["active_state", "no_open_file_handle", "owning_process_not_running"]
        case .moveToICloud:
            return ["active_state", "source_stability"]
        case .removeLocalDownload:
            return ["no_current_local_write", "active_state"]
        case .keep, .vendorNativeCleanup:
            return []
        }
    }

    private static func isRuntimePredicate(_ name: String) -> Bool {
        ["active_state", "no_open_file_handle", "owning_process_not_running", "source_stability", "no_current_local_write"].contains(name)
    }

    private static func transactionContract(for action: StorageAction) -> Bool {
        switch action {
        case .moveToTrash, .moveToICloud, .removeLocalDownload: return true
        case .keep, .vendorNativeCleanup: return false
        }
    }

    private static func postVerifyContract(for action: StorageAction) -> Bool {
        switch action {
        case .moveToTrash, .moveToICloud, .removeLocalDownload: return true
        case .keep, .vendorNativeCleanup: return false
        }
    }
}
