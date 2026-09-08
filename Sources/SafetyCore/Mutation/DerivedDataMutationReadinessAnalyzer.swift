import Foundation

public struct DerivedDataGateStep: Codable, Sendable, Equatable {
    public var step: Int
    public var claim: String
    public var satisfied: Bool
    public var value: String?
    public var reason: String?
}

public struct DerivedDataMutationReadinessEntry: Codable, Sendable, Equatable {
    public var entityID: String
    public var canonicalPath: String
    public var measurementBytes: Int64
    public var semanticIdentity: String?
    public var generatedBy: String?
    public var derivedFrom: String?
    public var sourceWorkspace: String?
    public var sourceWorkspaceExists: Bool?
    public var sourceOfTruth: String?
    public var sourceOfTruthConfidence: String?
    public var regenerability: String?
    public var regenerabilityConfidence: String?
    public var activeState: String?
    public var activeStateConfidence: String?
    public var openFileState: String?
    public var openFileConfidence: String?
    public var xcodeRunning: String?
    public var xcodebuildRunning: String?
    public var evidenceFreshness: String?
    public var evidenceCompleteness: String?
    public var evidenceConflicts: Bool
    public var moveToTrashSafetyClass: String?
    public var moveToTrashEligible: Bool
    public var matchedRuleID: String?
    public var recommendation: String?
    public var recommendationDisposition: String?
    public var preflightAllowed: Bool?
    public var mutationReadiness: String?
    public var firstBlockingGate: String?
    public var allBlockingReasons: [String]
    public var gateSteps: [DerivedDataGateStep]
    public var transactionContractAvailable: Bool
    public var postVerifyContractAvailable: Bool
    public var auditContractAvailable: Bool
    public var bindingFingerprintPossible: Bool
    public var rootCauseCategory: String?
    public var executorImplemented: Bool
}

public struct DerivedDataMutationReadinessReport: Codable, Sendable, Equatable {
    public var entries: [DerivedDataMutationReadinessEntry]
    public var entitiesDiscovered: Int
    public var moveToTrashSafetyGreen: Int
    public var recommendedMoveToTrash: Int
    public var preflightRequired: Int
    public var approvalRequired: Int
    public var contractSatisfiedReadOnly: Int
    public var executorImplemented: Bool
}

public struct DerivedDataReadinessDiffEntry: Codable, Sendable, Equatable {
    public var claim: String
    public var previousState: String?
    public var currentState: String?
    public var changed: Bool
    public var evidenceSource: String?
    public var reason: String?
}

public struct DerivedDataReadinessDiffReport: Codable, Sendable, Equatable {
    public var baselineEntityID: String
    public var baselineScan: String
    public var currentScan: String
    public var rootCauseCategory: String
    public var entries: [DerivedDataReadinessDiffEntry]
}

public enum DerivedDataMutationReadinessAnalyzer {
    public static let p112BaselineEntityID = "xcode.deriveddata.Runner-ckovnoskqurramhgydmrtirfscgd"

    public static func analyze(
        items: [ClassifiedItem],
        decisionCatalog: ActionDecisionCatalog,
        recommendations: [ActionRecommendationResult],
        preflights: [ActionPreflightResult],
        snapshotsByEntityID: [String: EntitySafetySnapshot],
        runtimeResolutions: [String: RuntimeStateResolution],
        runtimeIndex: RuntimeObservationIndex?,
        ruleVersion: String
    ) -> DerivedDataMutationReadinessReport {
        var recMap: [String: ActionRecommendationResult] = [:]
        for r in recommendations { recMap[r.entityID] = r }
        var preMap: [String: ActionPreflightResult] = [:]
        for p in preflights where p.action == .moveToTrash { preMap[p.entityID] = p }

        var entries: [DerivedDataMutationReadinessEntry] = []
        var green = 0, recTrash = 0, preflight = 0, approval = 0, satisfied = 0

        let derivedItems = items.filter { ActionPolicy.isDerivedData($0) || isDerivedDataEntity($0) }
        for item in derivedItems {
            let snapshot = snapshotsByEntityID[item.detected.entity.id]
            let set = decisionCatalog.set(for: item.detected.entity.id)
            let trashDecision = set?.decision(for: .moveToTrash)
            if trashDecision?.safetyClass == .green { green += 1 }

            let rec = recMap[item.detected.entity.id]
            if rec?.recommendedAction == .moveToTrash { recTrash += 1 }
            if case .actionable(.moveToTrash) = rec?.disposition { recTrash += 0 }

            let runtime = runtimeResolutions[item.detected.entity.id]
            let gateInput = MutationGateInput(
                item: item,
                action: .moveToTrash,
                actionDecision: trashDecision ?? ActionDecision(entityID: item.detected.entity.id, action: .moveToTrash, safetyClass: .unknown, eligible: false),
                snapshot: snapshot,
                recommendation: rec,
                preflight: preMap[item.detected.entity.id],
                runtimeResolution: runtime,
                transactionContract: TransactionContractRegistry.transactionContract(for: .moveToTrash, item: item),
                postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .moveToTrash, item: item),
                auditContract: TransactionContractRegistry.auditContract(for: .moveToTrash, item: item),
                approvalState: .scanDefault,
                evidenceGeneration: snapshot?.evidence.snapshotVersion ?? 0,
                verificationGeneration: snapshot?.verification.snapshotGeneration ?? 0,
                runtimeGeneration: snapshot?.cacheKey.runtimeGeneration ?? runtimeIndex?.runtimeGeneration ?? 0,
                ruleVersion: ruleVersion
            )
            let gate = MutationGate.evaluate(gateInput)
            switch MutationReadiness(rawValue: gate.readiness) {
            case .preflightRequired: preflight += 1
            case .approvalRequired: approval += 1
            case .contractSatisfiedReadOnly: satisfied += 1
            default: break
            }

            let steps = gateSteps(item: item, snapshot: snapshot, runtime: runtime, runtimeIndex: runtimeIndex, trashDecision: trashDecision)
            let firstFail = steps.first(where: { !$0.satisfied })?.claim
            let rel = item.detected.annotation?.relationships.first { $0.type == .derivedFrom }

            entries.append(DerivedDataMutationReadinessEntry(
                entityID: item.detected.entity.id,
                canonicalPath: snapshot?.evidence.canonicalPath ?? item.detected.entity.path,
                measurementBytes: item.exclusiveBytes,
                semanticIdentity: item.detected.annotation?.semanticType,
                generatedBy: item.detected.annotation?.lifecycle.role == .generatedArtifact ? "XCODE" : item.detected.entity.subcategory,
                derivedFrom: rel?.target,
                sourceWorkspace: rel?.target,
                sourceWorkspaceExists: rel.map { $0.presence == .present },
                sourceOfTruth: snapshot?.verification.sourceOfTruth.value.rawValue ?? item.verification?.sourceOfTruth.value.rawValue,
                sourceOfTruthConfidence: snapshot?.verification.sourceOfTruth.confidence.rawValue ?? item.verification?.sourceOfTruth.confidence.rawValue,
                regenerability: snapshot?.verification.regenerable.value.rawValue ?? item.verification?.regenerable.value.rawValue,
                regenerabilityConfidence: snapshot?.verification.regenerable.confidence.rawValue ?? item.verification?.regenerable.confidence.rawValue,
                activeState: snapshot?.predicates.activeState.rawValue ?? item.verification?.activeState.rawValue,
                activeStateConfidence: snapshot?.predicates.activeStateConfidence.rawValue ?? item.verification?.activeStateConfidence.rawValue,
                openFileState: snapshot?.predicates.openFileHandle.rawValue ?? snapshot?.evidence.openFileHandle.rawValue,
                openFileConfidence: snapshot?.predicates.openFileConfidence.rawValue,
                xcodeRunning: xcodeState(runtimeIndex: runtimeIndex),
                xcodebuildRunning: xcodebuildState(runtimeIndex: runtimeIndex),
                evidenceFreshness: runtime.map { $0.disposition.rawValue },
                evidenceCompleteness: snapshot?.verification.activeStateCompleteness.rawValue,
                evidenceConflicts: snapshot?.predicates.hasEvidenceConflict ?? false,
                moveToTrashSafetyClass: trashDecision?.safetyClass.rawValue,
                moveToTrashEligible: trashDecision?.eligible ?? false,
                matchedRuleID: item.decision.matchedRuleID,
                recommendation: rec?.recommendedAction.rawValue,
                recommendationDisposition: dispositionLabel(rec?.disposition),
                preflightAllowed: preMap[item.detected.entity.id]?.allowed,
                mutationReadiness: gate.readiness,
                firstBlockingGate: firstFail ?? gate.blockingReasons.first,
                allBlockingReasons: Array(Set(gate.blockingReasons + gate.missingRequirements)).sorted(),
                gateSteps: steps,
                transactionContractAvailable: gate.transactionContractAvailable,
                postVerifyContractAvailable: gate.postVerifyContractAvailable,
                auditContractAvailable: gate.auditContractAvailable,
                bindingFingerprintPossible: gate.actionBindingFingerprint != nil,
                rootCauseCategory: categorizeRootCause(steps: steps, gate: gate, trashDecision: trashDecision),
                executorImplemented: false
            ))
        }

        return DerivedDataMutationReadinessReport(
            entries: entries.sorted { $0.entityID < $1.entityID },
            entitiesDiscovered: entries.count,
            moveToTrashSafetyGreen: green,
            recommendedMoveToTrash: entries.filter {
                $0.recommendation == StorageAction.moveToTrash.rawValue
                    || $0.recommendationDisposition == "actionable:\(StorageAction.moveToTrash.rawValue)"
            }.count,
            preflightRequired: preflight,
            approvalRequired: approval,
            contractSatisfiedReadOnly: satisfied,
            executorImplemented: false
        )
    }

    public static func diff(
        report: DerivedDataMutationReadinessReport,
        items: [ClassifiedItem]
    ) -> DerivedDataReadinessDiffReport {
        let baseline = p112BaselineClaims()
        let current = report.entries.first { $0.entityID == p112BaselineEntityID }
            ?? report.entries.first { $0.entityID.lowercased().contains("runner") }
            ?? report.entries.first

        var entries: [DerivedDataReadinessDiffEntry] = []
        for (claim, prev) in baseline {
            let cur = currentValue(claim: claim, entry: current, items: items)
            entries.append(DerivedDataReadinessDiffEntry(
                claim: claim,
                previousState: prev,
                currentState: cur,
                changed: prev != cur,
                evidenceSource: evidenceSource(for: claim),
                reason: prev != cur ? changeReason(claim: claim, prev: prev, cur: cur) : nil
            ))
        }

        let category = rootCauseFromDiff(entries: entries, entry: current)
        return DerivedDataReadinessDiffReport(
            baselineEntityID: p112BaselineEntityID,
            baselineScan: "P1.12 Case Study",
            currentScan: "P2.0.1 Case Study",
            rootCauseCategory: category,
            entries: entries
        )
    }

    static func isDerivedDataEntity(_ item: ClassifiedItem) -> Bool {
        item.detected.entity.id.lowercased().contains("deriveddata")
            || item.detected.entity.path.lowercased().contains("deriveddata")
    }

    static func gateSteps(
        item: ClassifiedItem,
        snapshot: EntitySafetySnapshot?,
        runtime: RuntimeStateResolution?,
        runtimeIndex: RuntimeObservationIndex?,
        trashDecision: ActionDecision?
    ) -> [DerivedDataGateStep] {
        let v = snapshot?.verification ?? item.verification
        let preds = snapshot?.predicates
        let rel = item.detected.annotation?.relationships.first { $0.type == .derivedFrom }
        func step(_ n: Int, _ claim: String, _ ok: Bool, _ value: String? = nil, _ reason: String? = nil) -> DerivedDataGateStep {
            DerivedDataGateStep(step: n, claim: claim, satisfied: ok, value: value, reason: reason)
        }
        let xcodeInactive = runtimeIndex.map { $0.isRunning(executableNames: ["Xcode"]) == .false } ?? false
        let xcodebuildInactive = runtimeIndex.map { $0.isRunning(executableNames: ["xcodebuild"]) == .false } ?? false
        let openSafe = preds?.openFileHandle == .false && preds?.openFileConfidence == .verified
            || snapshot?.evidence.openFileHandle == .false
        return [
            step(1, "canonical_path_verified", preds?.hasCanonicalPath != false, snapshot?.evidence.canonicalPath),
            step(2, "entity_identity_verified", !item.detected.entity.id.isEmpty, item.detected.entity.id),
            step(3, "generated_by_xcode_verified", item.detected.annotation.map { $0.semanticType.contains("XCODE") } == true || ActionPolicy.isDerivedData(item), item.detected.annotation?.semanticType),
            step(4, "derived_from_workspace_verified", rel?.confidence == .verified, rel?.target),
            step(5, "source_workspace_exists_verified", rel?.presence == .present, rel?.target),
            step(6, "sot_false_verified", v?.sourceOfTruth.value == .false && v?.sourceOfTruth.confidence == .verified, v?.sourceOfTruth.value.rawValue),
            step(7, "regenerable_true_verified", v?.regenerable.value == .true && v?.regenerable.confidence == .verified, v?.regenerable.value.rawValue),
            step(8, "runtime_evidence_fresh", runtime?.disposition == .resolved, runtime?.disposition.rawValue),
            step(9, "xcode_inactive_verified", xcodeInactive, xcodeInactive ? "inactive" : "active_or_unknown"),
            step(10, "xcodebuild_inactive_verified", xcodebuildInactive, xcodebuildInactive ? "inactive" : "active_or_unknown"),
            step(11, "open_file_safe_verified", openSafe, preds?.openFileHandle.rawValue),
            step(12, "no_evidence_conflict", preds?.hasEvidenceConflict != true),
            step(13, "no_symlink_ambiguity", preds?.isSymlinkAmbiguity != true),
            step(14, "move_to_trash_safety_green", trashDecision?.safetyClass == .green, trashDecision?.safetyClass.rawValue),
            step(15, "transaction_contract_available", TransactionContractRegistry.transactionContract(for: .moveToTrash, item: item) != nil),
            step(16, "post_verify_contract_available", TransactionContractRegistry.postVerifyContract(for: .moveToTrash, item: item) != nil),
            step(17, "audit_contract_available", TransactionContractRegistry.auditContract(for: .moveToTrash, item: item) != nil),
            step(18, "fresh_execution_preflight_required", true, "required_at_execution"),
            step(19, "explicit_user_approval", false, "missing"),
            step(20, "executor_absent", true, "NOT_STARTED"),
        ]
    }

    static func xcodeState(runtimeIndex: RuntimeObservationIndex?) -> String? {
        guard let runtimeIndex else { return "unknown" }
        switch runtimeIndex.isRunning(executableNames: ["Xcode"]) {
        case .true: return "running"
        case .false: return "inactive"
        case .unknown: return "unknown"
        }
    }

    static func xcodebuildState(runtimeIndex: RuntimeObservationIndex?) -> String? {
        guard let runtimeIndex else { return "unknown" }
        switch runtimeIndex.isRunning(executableNames: ["xcodebuild"]) {
        case .true: return "running"
        case .false: return "inactive"
        case .unknown: return "unknown"
        }
    }

    static func dispositionLabel(_ disposition: RecommendationDisposition?) -> String? {
        guard let disposition else { return nil }
        switch disposition {
        case .actionable(let a): return "actionable:\(a.rawValue)"
        case .keep: return "keep"
        case .verifyMore(let c): return "verifyMore:\(c.map(\.rawValue).joined(separator: ","))"
        }
    }

    static func categorizeRootCause(steps: [DerivedDataGateStep], gate: MutationGateResult, trashDecision: ActionDecision?) -> String {
        if steps.first(where: { $0.claim == "xcode_inactive_verified" })?.satisfied == false { return "REAL_STATE_CHANGED" }
        if steps.first(where: { $0.claim == "open_file_safe_verified" })?.satisfied == false { return "OPEN_FILE_CHANGED" }
        if steps.first(where: { $0.claim == "regenerable_true_verified" })?.satisfied == false { return "REGENERABILITY_PROOF_CHANGED" }
        if steps.first(where: { $0.claim == "sot_false_verified" })?.satisfied == false { return "SOT_PROOF_CHANGED" }
        if steps.first(where: { $0.claim == "move_to_trash_safety_green" })?.satisfied == false { return "PIPELINE_DECISION_DIVERGENCE" }
        if !gate.blockingReasons.isEmpty { return "REAL_STATE_BLOCKED" }
        if trashDecision?.eligible == true { return "READY_PENDING_APPROVAL" }
        return "OTHER"
    }

    static func p112BaselineClaims() -> [String: String] {
        [
            "safety_class": "GREEN",
            "recommendation": "MOVE_TO_TRASH",
            "sot": "FALSE_VERIFIED",
            "regenerability": "TRUE_VERIFIED",
            "active_state": "INACTIVE_VERIFIED",
            "open_file": "FALSE_VERIFIED",
            "mutation_readiness": "PREFLIGHT_REQUIRED",
        ]
    }

    static func currentValue(claim: String, entry: DerivedDataMutationReadinessEntry?, items: [ClassifiedItem]) -> String? {
        guard let entry else {
            if claim == "safety_class" { return items.first { $0.detected.entity.id == p112BaselineEntityID }?.decision.safetyClass.rawValue }
            return "ENTITY_NOT_FOUND"
        }
        switch claim {
        case "safety_class": return entry.moveToTrashSafetyClass ?? entry.moveToTrashEligible.description
        case "recommendation": return entry.recommendation
        case "sot": return "\(entry.sourceOfTruth ?? "?")_\(entry.sourceOfTruthConfidence ?? "?")"
        case "regenerability": return "\(entry.regenerability ?? "?")_\(entry.regenerabilityConfidence ?? "?")"
        case "active_state": return "\(entry.activeState ?? "?")_\(entry.activeStateConfidence ?? "?")"
        case "open_file": return "\(entry.openFileState ?? "?")_\(entry.openFileConfidence ?? "?")"
        case "mutation_readiness": return entry.mutationReadiness
        default: return nil
        }
    }

    static func evidenceSource(for claim: String) -> String {
        switch claim {
        case "sot", "regenerability", "active_state": return "EntitySafetySnapshot/Verification"
        case "open_file": return "RuntimeObservationIndex/EntitySafetySnapshot"
        default: return "ActionDecisionSet/MutationGate"
        }
    }

    static func changeReason(claim: String, prev: String?, cur: String?) -> String? {
        if claim == "active_state", cur?.contains("active") == true { return "Xcode or process activity may have changed" }
        if claim == "regenerability", cur?.contains("unknown") == true { return "Proof target or verification budget changed" }
        if claim == "safety_class" { return "Safety evaluation or evidence transport changed" }
        return "Evidence or pipeline state differs from P1.12 baseline"
    }

    static func rootCauseFromDiff(entries: [DerivedDataReadinessDiffEntry], entry: DerivedDataMutationReadinessEntry?) -> String {
        if entry?.rootCauseCategory == "REAL_STATE_CHANGED" { return "REAL_STATE_CHANGED" }
        if entries.contains(where: { $0.changed && ($0.claim == "regenerability" || $0.claim == "sot") }) {
            return "EVIDENCE_FRESHNESS_CHANGED"
        }
        if entries.contains(where: { $0.changed && $0.claim == "safety_class" }) {
            return "PIPELINE_DECISION_DIVERGENCE"
        }
        return entry?.rootCauseCategory ?? "OTHER"
    }
}
