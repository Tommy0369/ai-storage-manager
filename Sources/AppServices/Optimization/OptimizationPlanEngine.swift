import Foundation
import SafetyCore

/// Deterministic constrained planner. Does not scan, decide Safety, approve, or execute.
public enum OptimizationPlanEngine {
    public static func plan(
        goal: OptimizationGoal,
        items: [UICandidateItem],
        extraFacts: [OptimizationActionFact] = [],
        snapshotID: String,
        changeReport: StorageChangeReport? = nil,
        history: [UIActionHistoryItem] = [],
        falseGREEN: Int = 0,
        duplicateEvaluations: Int = 0,
        now: Date = Date()
    ) -> OptimizationPlan {
        let totalStarted = Date()
        let buildStarted = Date()
        var candidates = OptimizationCandidateBuilder.build(
            items: items,
            extraFacts: extraFacts,
            history: history
        )
        if !goal.excludeEntityIDs.isEmpty {
            candidates = candidates.filter { !goal.excludeEntityIDs.contains($0.entityID) }
        }
        if !goal.excludeCategories.isEmpty {
            candidates = candidates.filter { !goal.excludeCategories.contains($0.category) }
        }
        if !goal.allowedActions.isEmpty {
            candidates = candidates.filter { goal.allowedActions.contains($0.action.rawValue) }
        }
        let buildMs = elapsedMs(since: buildStarted)

        let conflictStarted = Date()
        let (dedupedReady, conflicts, overlapPrevented) = resolveConflicts(
            candidates.filter { $0.tier == .executableNow }
        )
        let conflictMs = elapsedMs(since: conflictStarted)

        let selectStarted = Date()
        let selectedIDs = selectTowardGoal(dedupedReady, goalBytes: goal.targetBytes, maxCount: goal.maxActionCount)
        let selectMs = elapsedMs(since: selectStarted)

        let availableNow = uniqueBytes(dedupedReady)
        let future = uniqueBytes(candidates.filter { $0.tier == .verifiedButExecutorUnavailable })
        let vendorRestore = uniqueBytes(candidates.filter { $0.tier == .requiresVendorRestoration })
        let preflight = uniqueBytes(candidates.filter { $0.tier == .preflightRequired })
        let selectedBytes = uniqueBytes(dedupedReady.filter { selectedIDs.contains($0.candidateID) })
        let shortfall = max(0, goal.targetBytes &- selectedBytes)

        let entries: [OptimizationPlanEntry] = candidates.map { candidate in
            var copy = candidate
            if selectedIDs.contains(candidate.candidateID) {
                copy.whyIncluded = inclusionReasons(candidate)
                copy.whyExcluded = nil
            }
            return OptimizationPlanEntry(
                candidate: copy,
                selected: selectedIDs.contains(candidate.candidateID)
            )
        }

        let excluded = Dictionary(
            candidates.compactMap { candidate -> (String, OptimizationExcludedReason)? in
                guard !selectedIDs.contains(candidate.candidateID) else { return nil }
                guard candidate.logicalBytes >= 1_000_000_000 || candidate.tier == .protectedTier || candidate.tier == .verifyMore else {
                    return nil
                }
                return (candidate.entityID, OptimizationExcludedReason(
                    entityID: candidate.entityID,
                    displayName: candidate.displayName,
                    reason: candidate.whyExcluded ?? "Not selected for this goal.",
                    bytes: candidate.logicalBytes
                ))
            },
            uniquingKeysWith: { left, right in
                func rank(_ reason: String) -> Int {
                    if reason.lowercased().contains("protected") { return 0 }
                    if reason.lowercased().contains("verification") { return 1 }
                    if reason.lowercased().contains("not available") { return 2 }
                    return 3
                }
                return rank(left.reason) <= rank(right.reason) ? left : right
            }
        )
        .values
        .sorted { $0.bytes > $1.bytes }

        let status = goalStatus(
            selectedBytes: selectedBytes,
            goal: goal.targetBytes,
            availableNow: availableNow,
            future: future,
            preflight: preflight,
            verifyMore: uniqueBytes(candidates.filter { $0.tier == .verifyMore })
        )

        var warnings: [String] = []
        if selectedBytes > 0 {
            warnings.append("MOVE_TO_TRASH moves items out of place but does not immediately free disk capacity. Empty Trash is not offered.")
        }
        if availableNow == 0 {
            warnings.append("No actions are currently ready.")
        }

        var context: [String] = []
        if let change = changeReport, let delta = change.diskUsedDelta, delta > 0,
           let top = change.topGrowing.first {
            context.append(
                "Your disk used grew by \(UICandidateMapper.byteLabel(delta)) since the previous scan. \(top.displayName) was the largest identified increase. Growth does not make an item eligible."
            )
        }
        if let moved = history.first(where: { $0.logicalVerified }) {
            context.append("Already moved \(moved.displayName) to Trash. Completed actions are not current available candidates.")
        }

        let funnel = OptimizationCandidateFunnel(
            allEntityActionPairs: candidates.count,
            supportedActions: candidates.filter { $0.executionSupport == .implemented }.count,
            safetyEligible: candidates.filter { $0.safetyClass == .green }.count,
            exactBounded: candidates.filter { $0.blastRadius != .high }.count,
            nonOverlapping: dedupedReady.count,
            executionSupported: candidates.filter { $0.executionSupport == .implemented && $0.action == .moveToTrash }.count,
            preflightReady: candidates.filter { $0.tier == .executableNow || $0.tier == .preflightRequired }.count,
            selectedInPlan: selectedIDs.count,
            dropReasons: [
                "UNKNOWN/RED never enter Ready Now",
                "unsupported executors never marked executable",
                "overlapping paths counted once"
            ]
        )

        return OptimizationPlan(
            planID: UUID().uuidString,
            createdAt: now,
            goal: goal,
            planningSnapshotID: snapshotID,
            freshness: .current,
            entries: entries,
            availableNowPotentialBytes: availableNow,
            verifiedFuturePotentialBytes: future,
            requiresVendorRestorationPotentialBytes: vendorRestore,
            preflightPossibleBytes: preflight,
            requestedBytes: goal.targetBytes,
            shortfallBytes: shortfall,
            goalStatus: status,
            excludedSummary: Array(excluded.prefix(12)),
            conflicts: conflicts,
            overlapBytesPrevented: overlapPrevented,
            warnings: warnings,
            contextNotes: context,
            funnel: funnel,
            candidateBuildMs: buildMs,
            conflictResolutionMs: conflictMs,
            planSelectionMs: selectMs,
            planTotalMs: elapsedMs(since: totalStarted),
            falseGREEN: falseGREEN,
            duplicateEvaluations: duplicateEvaluations,
            approvalCreated: false,
            executionPermitCreated: false,
            executorCalled: false,
            bulkActionPresent: false
        )
    }

    public static func markStale(_ plan: OptimizationPlan, currentSnapshotID: String) -> OptimizationPlan {
        var copy = plan
        if copy.planningSnapshotID != currentSnapshotID {
            copy.freshness = .stale
            copy.entries = copy.entries.map { entry in
                var e = entry
                e.stale = true
                return e
            }
            copy.warnings.append("Plan is stale. Refresh from the current scan before acting. Fresh Preflight is still required per item.")
        }
        return copy
    }

    public static func removing(entityID: String, from plan: OptimizationPlan) -> OptimizationPlan {
        var goal = plan.goal
        goal.excludeEntityIDs.insert(entityID)
        let remainingItems = plan.entries
            .filter { $0.candidate.entityID != entityID }
            .compactMap { entry -> UICandidateItem? in
                // Rebuild is expected from live items; this path only drops selection without adding unsafe replacements.
                nil
            }
        _ = remainingItems
        var copy = plan
        copy.goal = goal
        copy.entries = plan.entries.map { entry in
            guard entry.candidate.entityID == entityID else { return entry }
            var e = entry
            e.selected = false
            return e
        }
        let selected = copy.entries.filter(\.selected).map(\.candidate)
        let selectedBytes = uniqueBytes(selected)
        copy.shortfallBytes = max(0, plan.requestedBytes &- selectedBytes)
        copy.goalStatus = goalStatus(
            selectedBytes: selectedBytes,
            goal: plan.requestedBytes,
            availableNow: plan.availableNowPotentialBytes,
            future: plan.verifiedFuturePotentialBytes,
            preflight: plan.preflightPossibleBytes,
            verifyMore: uniqueBytes(copy.entries.map(\.candidate).filter { $0.tier == .verifyMore })
        )
        return copy
    }

    public static func applyCompletion(
        _ plan: OptimizationPlan,
        entityID: String,
        outcome: UIExecutionOutcome
    ) -> OptimizationPlan {
        var copy = plan
        copy.entries = plan.entries.map { entry in
            guard entry.candidate.entityID == entityID else { return entry }
            var e = entry
            switch outcome.readiness {
            case .completed:
                e.completionState = "Completed"
            case .storageRecoveryPending, .postVerifyPending:
                e.completionState = "Recovery pending"
            case .regenerated:
                e.completionState = "Regenerated"
            default:
                e.completionState = outcome.logicalActionCompleted ? "Candidate changed" : "Candidate changed"
            }
            e.selected = false
            var cand = e.candidate
            if outcome.storageRecoveryState == .recoveryVerified {
                if let bytes = measuredVerifiedBytes(from: outcome), bytes > 0 {
                    cand.verifiedRecoveredBytes = bytes
                } else {
                    // Do not copy potential into verified when measured evidence is absent.
                    cand.verifiedRecoveredBytes = 0
                }
                cand.recoveryState = "STORAGE_RECOVERY_VERIFIED"
            } else {
                cand.verifiedRecoveredBytes = 0
                cand.immediateExpectedRecoveryBytes = 0
            }
            e.candidate = cand
            return e
        }
        return copy
    }

    /// Prefer post-verify measured recovery; never treat potential estimate as verified.
    static func measuredVerifiedBytes(from outcome: UIExecutionOutcome) -> Int64? {
        if let measured = outcome.postVerification?.actualRecoveredBytes, measured > 0 {
            return measured
        }
        if let measured = outcome.executionReport?.measuredRecoveryBytes, measured > 0 {
            return measured
        }
        return nil
    }

    public static func pathsOverlap(_ a: String, _ b: String) -> Bool {
        let left = (a as NSString).standardizingPath
        let right = (b as NSString).standardizingPath
        if left == right { return true }
        return right.hasPrefix(left + "/") || left.hasPrefix(right + "/")
    }

    // MARK: - Internals

    static func resolveConflicts(
        _ candidates: [OptimizationCandidate]
    ) -> ([OptimizationCandidate], [OptimizationCandidateConflict], Int64) {
        var kept: [OptimizationCandidate] = []
        var conflicts: [OptimizationCandidateConflict] = []
        var overlap: Int64 = 0
        let ranked = candidates.sorted(by: preference)
        for candidate in ranked {
            if let hit = kept.first(where: { existing in
                existing.entityID == candidate.entityID
                    || pathsOverlap(existing.canonicalPath, candidate.canonicalPath)
            }) {
                conflicts.append(OptimizationCandidateConflict(
                    leftID: hit.candidateID,
                    rightID: candidate.candidateID,
                    kind: hit.entityID == candidate.entityID ? "SAME_ENTITY_ACTION" : "PARENT_CHILD_OVERLAP"
                ))
                overlap &+= candidate.potentialRecoveryBytes
                continue
            }
            kept.append(candidate)
        }
        return (kept, conflicts, overlap)
    }

    static func selectTowardGoal(
        _ candidates: [OptimizationCandidate],
        goalBytes: Int64,
        maxCount: Int?
    ) -> Set<String> {
        let ordered = candidates.sorted(by: preference)
        var selected: [OptimizationCandidate] = []
        var total: Int64 = 0
        let limit = maxCount ?? ordered.count
        for candidate in ordered {
            if selected.count >= limit { break }
            if total >= goalBytes { break }
            let next = total &+ candidate.potentialRecoveryBytes
            let overshoot = next > goalBytes ? next - goalBytes : 0
            if overshoot > goalBytes / 2, candidate.potentialRecoveryBytes > goalBytes {
                let remaining = max(Int64(0), goalBytes &- total)
                let smallerFits = ordered.contains { other in
                    other.candidateID != candidate.candidateID
                        && !selected.contains(where: { $0.candidateID == other.candidateID })
                        && other.potentialRecoveryBytes <= remaining
                }
                if smallerFits { continue }
            }
            selected.append(candidate)
            total = next
        }
        return Set(selected.map(\.candidateID))
    }

    static func preference(_ a: OptimizationCandidate, _ b: OptimizationCandidate) -> Bool {
        if a.blastRadius != b.blastRadius {
            return blastRank(a.blastRadius) < blastRank(b.blastRadius)
        }
        if a.transactionComplexity != b.transactionComplexity {
            return complexityRank(a.transactionComplexity) < complexityRank(b.transactionComplexity)
        }
        return a.potentialRecoveryBytes < b.potentialRecoveryBytes
    }

    static func uniqueBytes(_ candidates: [OptimizationCandidate]) -> Int64 {
        candidates.reduce(Int64(0)) { $0 &+ $1.potentialRecoveryBytes }
    }

    static func goalStatus(
        selectedBytes: Int64,
        goal: Int64,
        availableNow: Int64,
        future: Int64,
        preflight: Int64,
        verifyMore: Int64
    ) -> OptimizationGoalStatus {
        if availableNow <= 0 && future <= 0 && preflight <= 0 {
            return verifyMore > 0 ? .needsMoreVerification : .noSafeOptions
        }
        if selectedBytes >= goal {
            return .achievableNow
        }
        if availableNow > 0 {
            if availableNow &+ future >= goal {
                return .achievableWithFutureCapabilities
            }
            return .partiallyAchievable
        }
        if future >= goal {
            return .achievableWithFutureCapabilities
        }
        if preflight > 0 || verifyMore > 0 {
            return .needsMoreVerification
        }
        return .noSafeOptions
    }

    private static func inclusionReasons(_ candidate: OptimizationCandidate) -> [String] {
        var lines = [
            "Canonical ActionDecision already authorizes considering \(candidate.action.rawValue).",
            "Executor support: \(candidate.executionSupport.rawValue)."
        ]
        if candidate.action == .moveToTrash {
            lines.append("Bytes can be moved to Trash. Disk recovery is not immediate.")
        }
        lines.append("Blast radius: \(candidate.blastRadius.rawValue).")
        return lines
    }

    private static func blastRank(_ value: BlastRadiusClass) -> Int {
        switch value {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .unknown: return 3
        }
    }

    private static func complexityRank(_ value: TransactionComplexityClass) -> Int {
        switch value {
        case .simple: return 0
        case .moderate: return 1
        case .complex: return 2
        }
    }

    private static func elapsedMs(since: Date) -> Int {
        Int(Date().timeIntervalSince(since) * 1000)
    }
}
