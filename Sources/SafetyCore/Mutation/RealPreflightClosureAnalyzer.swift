import Foundation

/// P2.0.6 — Orchestrates fresh read-only preflight for the canonical exact-bounded candidate.
public enum RealPreflightClosureAnalyzer {
    public struct ClosureBundle: Sendable, Equatable {
        public var report: RealPreflightClosureReport
        public var delta: PreflightStateDeltaReport
        public var updatedGate: FirstRealMutationGateReport
        public var updatedSelection: FirstMutationCandidateSelectionReport
        public var freshGateEntry: MutationGateResult?
    }

    public static func analyze(
        items: [ClassifiedItem],
        decisionCatalog: ActionDecisionCatalog,
        recommendations: [ActionRecommendationResult],
        preflights: [ActionPreflightResult],
        snapshotsByEntityID: [String: EntitySafetySnapshot],
        runtimeResolutions: [String: RuntimeStateResolution],
        mutationGate: MutationGateReport,
        inventory: FirstMutationCandidateInventoryReport,
        ranking: FirstMutationCandidateRankingReport,
        selection: FirstMutationCandidateSelectionReport,
        gate: FirstRealMutationGateReport,
        engine: SafetyRuleEngine,
        ruleVersion: String,
        processes: any ProcessRunningChecker = ProcessCheck(),
        handles: any OpenHandleChecker = LSOFHandleChecker()
    ) -> ClosureBundle {
        guard let candidate = resolveCandidate(
            selection: selection,
            inventory: inventory,
            ranking: ranking,
            gate: gate
        ) else {
            return noCandidateBundle(gate: gate, selection: selection)
        }

        let entityID = candidate.entityID
        let action = candidate.action
        guard let item = items.first(where: { $0.detected.entity.id == entityID }) else {
            return missingEntityBundle(entityID: entityID, action: action, gate: gate, selection: selection)
        }

        let snapshot = snapshotsByEntityID[entityID]
        let decisions = decisionCatalog.set(for: entityID)?.decisionMap ?? [:]
        guard let scanDecision = decisions[action] else {
            return missingDecisionBundle(entityID: entityID, action: action, gate: gate, selection: selection)
        }

        var recMap: [String: ActionRecommendationResult] = [:]
        for r in recommendations { recMap[r.entityID] = r }
        var preMap: [String: [StorageAction: ActionPreflightResult]] = [:]
        for p in preflights {
            preMap[p.entityID, default: [:]][p.action] = p
        }
        let gateEntry = mutationGate.entries.first { $0.entityID == entityID && $0.action == action.rawValue }
        let scanGate = gateEntry ?? MutationGateResult(
            entityID: entityID,
            path: item.detected.entity.path,
            action: action.rawValue,
            safetyClass: scanDecision.safetyClass.rawValue,
            recommendation: recMap[entityID]?.recommendedAction.rawValue,
            readiness: MutationReadiness.preflightRequired.rawValue,
            satisfiedRequirements: [],
            missingRequirements: ["fresh_runtime_preflight"],
            staleRequirements: [],
            conflictedRequirements: [],
            blockingReasons: [],
            requiredFreshChecks: ["fresh_runtime_preflight"],
            actionBindingFingerprint: ActionBindingFingerprintBuilder.compute(input: MutationGateInput(
                item: item, action: action, actionDecision: scanDecision, snapshot: snapshot,
                recommendation: recMap[entityID],
                preflight: preMap[entityID]?[action],
                runtimeResolution: runtimeResolutions[entityID],
                transactionContract: TransactionContractRegistry.transactionContract(for: action, item: item),
                postVerifyContract: TransactionContractRegistry.postVerifyContract(for: action, item: item),
                auditContract: TransactionContractRegistry.auditContract(for: action, item: item),
                approvalState: .scanDefault,
                evidenceGeneration: snapshot?.evidence.snapshotVersion ?? 0,
                verificationGeneration: snapshot?.verification.snapshotGeneration ?? 0,
                runtimeGeneration: snapshot?.cacheKey.runtimeGeneration ?? 0,
                ruleVersion: ruleVersion
            )),
            transactionContractAvailable: true,
            postVerifyContractAvailable: true,
            auditContractAvailable: true,
            freshRuntimeCheckRequired: true,
            freshCloudCheckRequired: false,
            approvalRequired: true,
            executorImplemented: false
        )

        let sessionID = "p206-\(entityID)-\(action.rawValue)-\(Int(Date().timeIntervalSince1970))"
        let run = FreshReadOnlyPreflightEngine.run(
            sessionID: sessionID,
            item: item,
            action: action,
            scanDecision: scanDecision,
            scanGate: scanGate,
            snapshot: snapshot,
            recommendation: recMap[entityID],
            preflight: preMap[entityID]?[action],
            scanRuntimeResolution: runtimeResolutions[entityID],
            ruleVersion: ruleVersion,
            engine: engine,
            processes: processes,
            handles: handles
        )

        let readiness = MutationReadiness(rawValue: run.freshGateResult.readiness)
        let humanApproval = readiness == .approvalRequired
        let gateStatus: String
        let outcome: String
        if readiness == .approvalRequired {
            gateStatus = P21GateStatusValue.readyForHumanAuthorization.rawValue
            outcome = "APPROVAL_REQUIRED"
        } else if run.receipt.result == PreflightResultCode.candidateChanged.rawValue {
            gateStatus = "CANDIDATE_CHANGED"
            outcome = "CANDIDATE_CHANGED"
        } else {
            gateStatus = P21GateStatusValue.blockedByRealEvidence.rawValue
            outcome = "BLOCKED_BY_REAL_EVIDENCE"
        }

        let report = RealPreflightClosureReport(
            phase: "P2.0.6",
            outcome: outcome,
            preflightSession: run.session,
            entityID: entityID,
            action: action.rawValue,
            path: item.detected.entity.path,
            previousMutationReadiness: scanGate.readiness,
            mutationReadinessAfterPreflight: run.freshGateResult.readiness,
            bindingValid: run.bindingValid,
            sourceUnchanged: run.sourceUnchanged,
            safetyClassBefore: scanDecision.safetyClass.rawValue,
            safetyClassAfter: run.freshDecision.safetyClass.rawValue,
            staticClaimsReused: run.staticClaimsReused,
            dynamicClaimsRefreshed: run.dynamicClaimsRefreshed,
            processCompleteness: run.freshRuntimeIndex.processCompleteness.rawValue,
            handleCompleteness: run.freshRuntimeIndex.handleCompleteness.rawValue,
            satisfiedClaims: run.receipt.satisfiedClaims.map(\.rawValue),
            missingClaims: run.receipt.missingClaims.map(\.rawValue),
            staleClaims: run.receipt.staleClaims.map(\.rawValue),
            conflictedClaims: run.receipt.conflictedClaims.map(\.rawValue),
            firstBlocker: run.firstBlocker,
            causalBlockerChain: run.causalBlockerChain,
            preflightReceipt: run.receipt,
            preflightReceiptResult: run.receipt.result,
            mutationGateReadiness: run.freshGateResult.readiness,
            humanApprovalRequired: humanApproval,
            userActionApprovalGenerated: false,
            executionPermitGenerated: false,
            executorImplemented: false,
            previewExecutable: false,
            destructiveActionsExecuted: false,
            firstRealMutationGateStatus: gateStatus,
            selectedCandidate: entityID,
            selectedAction: action.rawValue,
            explanation: explanation(for: run, readiness: readiness)
        )

        var updatedGate = gate
        updatedGate.status = gateStatus
        updatedGate.selectedCandidate = entityID
        updatedGate.selectedAction = action.rawValue
        updatedGate.reason = [report.explanation]
        if humanApproval {
            updatedGate.approvalRequiredCount = max(updatedGate.approvalRequiredCount, 1)
            updatedGate.approvalRequired = max(updatedGate.approvalRequired, 1)
        }
        if let blocker = run.firstBlocker {
            updatedGate.topBlockers = [blocker] + updatedGate.topBlockers.filter { $0 != blocker }
        }

        var updatedSelection = selection
        updatedSelection.selectedEntityID = entityID
        updatedSelection.selectedAction = action.rawValue
        updatedSelection.selectedPath = item.detected.entity.path
        if humanApproval {
            updatedSelection.outcome = FirstMutationSelectionOutcome.readyCandidateFound.rawValue
            updatedSelection.rationale = "Fresh read-only preflight passed; human approval is the remaining gate"
            updatedSelection.remainingHumanApprovalRequired = true
        } else if outcome == "CANDIDATE_CHANGED" {
            updatedSelection.outcome = FirstMutationSelectionOutcome.noSafeRealMutationCandidate.rawValue
            updatedSelection.rationale = "Candidate binding changed during fresh preflight"
            updatedSelection.remainingHumanApprovalRequired = false
        } else {
            updatedSelection.outcome = FirstMutationSelectionOutcome.candidateRequiresMorePreflight.rawValue
            updatedSelection.rationale = "Fresh preflight blocked: \(run.firstBlocker ?? "unknown")"
            updatedSelection.remainingHumanApprovalRequired = false
        }

        return ClosureBundle(
            report: report,
            delta: run.delta,
            updatedGate: updatedGate,
            updatedSelection: updatedSelection,
            freshGateEntry: run.freshGateResult
        )
    }

    // MARK: - Candidate resolution

    static func resolveCandidate(
        selection: FirstMutationCandidateSelectionReport,
        inventory: FirstMutationCandidateInventoryReport,
        ranking: FirstMutationCandidateRankingReport,
        gate: FirstRealMutationGateReport? = nil
    ) -> (entityID: String, action: StorageAction)? {
        if let id = selection.selectedEntityID,
           let actionStr = selection.selectedAction,
           let action = StorageAction(rawValue: actionStr),
           selection.outcome != FirstMutationSelectionOutcome.noSafeRealMutationCandidate.rawValue {
            return (id, action)
        }

        if let id = gate?.selectedCandidate,
           let actionStr = gate?.selectedAction,
           let action = StorageAction(rawValue: actionStr),
           !id.isEmpty {
            return (id, action)
        }

        if let ranked = ranking.entries.first(where: {
            $0.mutationReadiness == MutationReadiness.preflightRequired.rawValue
        }),
           let action = StorageAction(rawValue: ranked.action) {
            return (ranked.entityID, action)
        }

        let eligible = inventory.entries.filter {
            $0.exactBoundedEntity
                && $0.mutationReadiness == MutationReadiness.preflightRequired.rawValue
                && $0.safetyClass == SafetyClass.green.rawValue
        }
        guard let best = eligible.max(by: { preflightResolverRank($0) < preflightResolverRank($1) }),
            let action = StorageAction(rawValue: best.action) else {
            return nil
        }
        return (best.entityID, action)
    }

    static func preflightResolverRank(_ entry: FirstMutationCandidateEntry) -> Int {
        var score = entry.fitnessScore * 1_000 + entry.proofCompletenessScore
        if entry.action == StorageAction.moveToTrash.rawValue { score += 500 }
        if entry.recommendationDisposition?.contains("actionable") == true { score += 200 }
        if entry.entityID.lowercased().contains("deriveddata") { score += 100 }
        if entry.action == StorageAction.moveToICloud.rawValue { score -= 300 }
        return score
    }

    // MARK: - Private helpers

    private static func explanation(for run: FreshReadOnlyPreflightEngine.RunResult, readiness: MutationReadiness?) -> String {
        if readiness == .approvalRequired {
            return "Fresh read-only preflight satisfied all dynamic requirements; only explicit human approval remains"
        }
        if run.receipt.result == PreflightResultCode.candidateChanged.rawValue {
            return "TOCTOU binding mismatch invalidated scan-time readiness"
        }
        return "Fresh preflight blocked by real evidence: \(run.firstBlocker ?? run.receipt.result)"
    }

    private static func noCandidateBundle(
        gate: FirstRealMutationGateReport,
        selection: FirstMutationCandidateSelectionReport
    ) -> ClosureBundle {
        let report = RealPreflightClosureReport(
            phase: "P2.0.6",
            outcome: "NO_EXACT_BOUNDED_PREFLIGHT_CANDIDATE",
            preflightSession: nil,
            entityID: nil,
            action: nil,
            path: nil,
            previousMutationReadiness: nil,
            mutationReadinessAfterPreflight: nil,
            bindingValid: false,
            sourceUnchanged: false,
            safetyClassBefore: nil,
            safetyClassAfter: nil,
            staticClaimsReused: [],
            dynamicClaimsRefreshed: [],
            processCompleteness: nil,
            handleCompleteness: nil,
            satisfiedClaims: [],
            missingClaims: [],
            staleClaims: [],
            conflictedClaims: [],
            firstBlocker: "NO_EXACT_BOUNDED_PREFLIGHT_CANDIDATE",
            causalBlockerChain: ["NO_EXACT_BOUNDED_PREFLIGHT_CANDIDATE"],
            preflightReceipt: nil,
            preflightReceiptResult: nil,
            mutationGateReadiness: nil,
            humanApprovalRequired: false,
            userActionApprovalGenerated: false,
            executionPermitGenerated: false,
            executorImplemented: false,
            previewExecutable: false,
            destructiveActionsExecuted: false,
            firstRealMutationGateStatus: gate.status,
            selectedCandidate: selection.selectedEntityID,
            selectedAction: selection.selectedAction,
            explanation: "No exact-bounded entity at PREFLIGHT_REQUIRED with resolvable identity"
        )
        return ClosureBundle(
            report: report,
            delta: PreflightStateDeltaReport(
                entityID: "", action: "", scanBindingFingerprint: nil, freshBindingFingerprint: nil,
                bindingValid: false, sourceUnchanged: false, entries: []
            ),
            updatedGate: gate,
            updatedSelection: selection,
            freshGateEntry: nil
        )
    }

    private static func missingEntityBundle(
        entityID: String,
        action: StorageAction,
        gate: FirstRealMutationGateReport,
        selection: FirstMutationCandidateSelectionReport
    ) -> ClosureBundle {
        var g = gate
        g.status = "CANDIDATE_CHANGED"
        g.reason = ["Selected entity \(entityID) not found in scan inventory"]
        let report = RealPreflightClosureReport(
            phase: "P2.0.6", outcome: "CANDIDATE_CHANGED",
            preflightSession: nil, entityID: entityID, action: action.rawValue, path: nil,
            previousMutationReadiness: nil, mutationReadinessAfterPreflight: nil,
            bindingValid: false, sourceUnchanged: false,
            safetyClassBefore: nil, safetyClassAfter: nil,
            staticClaimsReused: [], dynamicClaimsRefreshed: [],
            processCompleteness: nil, handleCompleteness: nil,
            satisfiedClaims: [], missingClaims: [], staleClaims: [], conflictedClaims: [],
            firstBlocker: "ENTITY_NOT_IN_SCAN", causalBlockerChain: ["ENTITY_NOT_IN_SCAN"],
            preflightReceipt: nil, preflightReceiptResult: PreflightResultCode.candidateChanged.rawValue,
            mutationGateReadiness: nil, humanApprovalRequired: false,
            userActionApprovalGenerated: false, executionPermitGenerated: false,
            executorImplemented: false, previewExecutable: false, destructiveActionsExecuted: false,
            firstRealMutationGateStatus: g.status, selectedCandidate: entityID, selectedAction: action.rawValue,
            explanation: "Selected candidate disappeared from scan inventory"
        )
        return ClosureBundle(report: report, delta: emptyDelta(entityID: entityID, action: action.rawValue),
                             updatedGate: g, updatedSelection: selection, freshGateEntry: nil)
    }

    private static func missingDecisionBundle(
        entityID: String,
        action: StorageAction,
        gate: FirstRealMutationGateReport,
        selection: FirstMutationCandidateSelectionReport
    ) -> ClosureBundle {
        let report = RealPreflightClosureReport(
            phase: "P2.0.6", outcome: "CANDIDATE_CHANGED",
            preflightSession: nil, entityID: entityID, action: action.rawValue, path: nil,
            previousMutationReadiness: nil, mutationReadinessAfterPreflight: nil,
            bindingValid: false, sourceUnchanged: false,
            safetyClassBefore: nil, safetyClassAfter: nil,
            staticClaimsReused: [], dynamicClaimsRefreshed: [],
            processCompleteness: nil, handleCompleteness: nil,
            satisfiedClaims: [], missingClaims: [], staleClaims: [], conflictedClaims: [],
            firstBlocker: "ACTION_DECISION_MISSING", causalBlockerChain: ["ACTION_DECISION_MISSING"],
            preflightReceipt: nil, preflightReceiptResult: PreflightResultCode.candidateChanged.rawValue,
            mutationGateReadiness: nil, humanApprovalRequired: false,
            userActionApprovalGenerated: false, executionPermitGenerated: false,
            executorImplemented: false, previewExecutable: false, destructiveActionsExecuted: false,
            firstRealMutationGateStatus: gate.status, selectedCandidate: entityID, selectedAction: action.rawValue,
            explanation: "Canonical ActionDecision missing for selected candidate"
        )
        return ClosureBundle(report: report, delta: emptyDelta(entityID: entityID, action: action.rawValue),
                             updatedGate: gate, updatedSelection: selection, freshGateEntry: nil)
    }

    private static func emptyDelta(entityID: String, action: String) -> PreflightStateDeltaReport {
        PreflightStateDeltaReport(
            entityID: entityID, action: action,
            scanBindingFingerprint: nil, freshBindingFingerprint: nil,
            bindingValid: false, sourceUnchanged: false, entries: []
        )
    }
}
