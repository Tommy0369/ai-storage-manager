import Foundation

public enum RuntimeResolutionNeedPlanner {
    private static let runtimeRulePredicates: Set<String> = [
        "no_open_file_handle",
        "owning_process_not_running",
    ]

    public static func plan(
        entity: DetectedEntity,
        ruleIndex: SafetyRuleIndex,
        verification: VerificationAnnotation
    ) -> RuntimeRequirementPlan {
        if verification.activeStateConfidence == .verified {
            let matching = ruleIndex.referenceMatchingRules(for: entity.entity.path)
            let ruleNeedsOpen = matching.contains { $0.requiredPredicates.contains("no_open_file_handle") }
            let derivedData = ActionPolicy.isDerivedData(placeholderItem(entity: entity, verification: verification))
            let claude = ActionPolicy.isClaudeRuntime(placeholderItem(entity: entity, verification: verification))
            if !ruleNeedsOpen, !derivedData, !claude {
                return RuntimeRequirementPlan(
                    needsActive: false,
                    needsOpenFile: false,
                    need: .requiredNow,
                    deferReason: nil,
                    deferReasons: []
                )
            }
        }

        let matching = ruleIndex.referenceMatchingRules(for: entity.entity.path)
        let ruleNeedsRuntime = matching.contains { rule in
            rule.requiredPredicates.contains(where: { runtimeRulePredicates.contains($0) })
        }

        var deferReasons: [RuntimeDeferReason] = []
        let item = placeholderItem(entity: entity, verification: verification)

        let voiceMemo = ActionPolicy.isVoiceMemo(item)
        let iosBackup = ActionPolicy.isIOSBackup(item)
        let git = ActionPolicy.isGitRepository(item)
        let derivedData = ActionPolicy.isDerivedData(item)
        let claude = ActionPolicy.isClaudeRuntime(item)

        let iCloudStaticBlock = voiceMemo || iosBackup || git || derivedData || claude
            || ActionPolicy.isLibraryManagedPath(entity.entity.path)
        let trashStaticBlock = voiceMemo || iosBackup || claude
        let evictStaticBlock = voiceMemo || iosBackup

        if voiceMemo { deferReasons.append(.nativeSyncRequired) }
        if iosBackup { deferReasons.append(.deviceAwareMigrationRequired) }
        if git { deferReasons.append(.relocationContractMissing) }
        if derivedData || claude || ActionPolicy.isLibraryManagedPath(entity.entity.path) {
            deferReasons.append(.relocationContractMissing)
        }

        var needsActive = ruleNeedsRuntime || !entity.associatedProcesses.isEmpty
        var needsOpenFile = ruleNeedsRuntime

        if derivedData {
            needsActive = true
            needsOpenFile = true
        }
        if claude {
            needsActive = true
            needsOpenFile = true
        }
        if entity.entity.kind == .userOriginal || entity.annotation?.lifecycle.role == .userContent {
            needsActive = true
            needsOpenFile = true
        }

        let allActionsStaticallyBlocked = iCloudStaticBlock && trashStaticBlock && evictStaticBlock
        if !needsActive, !needsOpenFile, !ruleNeedsRuntime {
            return RuntimeRequirementPlan(
                needsActive: false,
                needsOpenFile: false,
                need: .notRequiredForCurrentDecision,
                deferReason: .noRuntimePredicateInCandidateRule,
                deferReasons: [.noRuntimePredicateInCandidateRule]
            )
        }

        if allActionsStaticallyBlocked, !derivedData, !claude, !ruleNeedsRuntime {
            let primary = deferReasons.first ?? .staticHardBlock
            return RuntimeRequirementPlan(
                needsActive: false,
                needsOpenFile: false,
                need: .notRequiredForCurrentDecision,
                deferReason: primary,
                deferReasons: deferReasons
            )
        }

        if derivedData || claude || ruleNeedsRuntime {
            return RuntimeRequirementPlan(
                needsActive: needsActive,
                needsOpenFile: needsOpenFile,
                need: .requiredNow,
                deferReason: nil,
                deferReasons: []
            )
        }

        return RuntimeRequirementPlan(
            needsActive: needsActive,
            needsOpenFile: needsOpenFile,
            need: .requiredForPotentialAction,
            deferReason: nil,
            deferReasons: []
        )
    }

    public static func buildNeedReport(plans: [String: RuntimeRequirementPlan]) -> RuntimeResolutionNeedReport {
        var requiredNow = 0
        var potential = 0
        var deferred = 0
        var entries: [RuntimeResolutionNeedEntry] = []
        for (entityID, plan) in plans.sorted(by: { $0.key < $1.key }) {
            switch plan.need {
            case .requiredNow: requiredNow += 1
            case .requiredForPotentialAction: potential += 1
            case .notRequiredForCurrentDecision: deferred += 1
            }
            var reasons = plan.deferReasons.map(\.rawValue)
            if reasons.isEmpty, plan.need != .notRequiredForCurrentDecision {
                reasons.append(plan.need.rawValue)
            }
            entries.append(RuntimeResolutionNeedEntry(
                entityID: entityID,
                need: plan.need.rawValue,
                needsActive: plan.needsActive,
                needsOpenFile: plan.needsOpenFile,
                reasons: reasons
            ))
        }
        return RuntimeResolutionNeedReport(
            requiredNow: requiredNow,
            requiredForPotentialAction: potential,
            notRequiredForCurrentDecision: deferred,
            entries: entries
        )
    }

    private static func placeholderItem(entity: DetectedEntity, verification: VerificationAnnotation) -> ClassifiedItem {
        let decision = SafetyDecision(
            entity: entity.entity,
            action: .userReview,
            safetyClass: .unknown,
            safetyScore: nil,
            reasonCodes: [],
            sideEffects: [],
            matchedRuleID: nil,
            evaluationLayer: .unknownFallback,
            evidenceConfidence: 0.5,
            userExplanationJA: "",
            growthCauses: [],
            requiresUserApproval: true,
            blockedBy: nil
        )
        return ClassifiedItem(
            detected: entity,
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: entity.entity.logicalBytes,
            actionVariants: [:],
            inclusiveBytes: entity.entity.logicalBytes,
            exclusiveBytes: entity.entity.logicalBytes,
            resolution: .l2Domain,
            verification: verification
        )
    }
}
