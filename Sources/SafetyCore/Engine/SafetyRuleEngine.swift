import Foundation

public struct EvaluationRequest: Sendable {
    public var entity: StorageEntity
    public var intendedAction: ActionMode
    public var evidence: EvidenceBundle
    public var state: RuntimeState

    public init(
        entity: StorageEntity,
        intendedAction: ActionMode,
        evidence: EvidenceBundle,
        state: RuntimeState
    ) {
        self.entity = entity
        self.intendedAction = intendedAction
        self.evidence = evidence
        self.state = state
    }
}

public struct SafetyRuleEngine {
    public var knowledge: KnowledgeBaseDocument
    public var protection: UserProtectionStore
    public var productVersionAllowsPermanentDelete: Bool
    public var loader: KnowledgeBaseLoader

    public init(
        knowledge: KnowledgeBaseDocument,
        protection: UserProtectionStore = UserProtectionStore(),
        productVersionAllowsPermanentDelete: Bool = false,
        loader: KnowledgeBaseLoader = KnowledgeBaseLoader()
    ) {
        self.knowledge = knowledge
        self.protection = protection
        self.productVersionAllowsPermanentDelete = productVersionAllowsPermanentDelete
        self.loader = loader
    }

    public func evaluate(_ request: EvaluationRequest) -> SafetyDecision {
        evaluateReference(request)
    }

    func evaluate(_ request: EvaluationRequest, index: inout SafetyRuleIndex, profiler: inout SafetyEvalProfiler) -> SafetyDecision {
        profiler.totalEvaluations += 1
        let started = Date()
        defer { profiler.ruleLookupMs += Self.msSince(started) }
        return evaluateCore(request) { path in
            index.matchingRules(for: path)
        }
    }

    public func evaluateReference(_ request: EvaluationRequest) -> SafetyDecision {
        evaluateCore(request) { path in
            knowledge.rules.filter { PathGlob.matches(path: path, pattern: $0.match.path) }
        }
    }

    func evaluateCore(
        _ request: EvaluationRequest,
        matchingRules: (String) -> [SafetyRule]
    ) -> SafetyDecision {
        let path = request.entity.path

        if HardSafetyGates.isHardBlocked(path: path) || request.evidence.sipProtected == .true {
            return blocked(
                request,
                action: .hardBlock,
                layer: .hardBlock,
                reasons: ["HARD_BLOCK", "SYSTEM_CRITICAL"],
                explanation: "システム保護領域です。整理候補に入れません。"
            )
        }

        if !productVersionAllowsPermanentDelete, request.intendedAction == .permanentDelete {
            return blocked(
                request,
                action: .hardBlock,
                layer: .hardBlock,
                reasons: ["PERMANENT_DELETE_FORBIDDEN_V0_1"],
                explanation: "このバージョンでは永久削除はできません。"
            )
        }

        if let rule = protection.matching(entity: request.entity) {
            return blocked(
                request,
                action: .hardBlock,
                layer: .userProtection,
                reasons: ["USER_PROTECTION", rule.id.uppercased()],
                explanation: "保護ルール「\(rule.label)」により整理しません。"
            )
        }

        if request.entity.path.lowercased().contains(".fcpbundle")
            || request.entity.path.lowercased().contains(".photoslibrary") {
            return blocked(
                request,
                action: .hardBlock,
                layer: .userProtection,
                reasons: ["USER_ORIGINAL", "MEDIA_LIBRARY"],
                explanation: "写真や動画の本体ライブラリです。削除候補にしません。"
            )
        }

        if request.state.isActivelyUsed {
            return decision(
                request,
                rule: nil,
                safetyClass: .red,
                action: .noAction,
                layer: .activeUse,
                reasons: ["ACTIVE_USE_BLOCK"],
                explanation: "いま使われている可能性があるため、整理を止めます。古いことは安全を意味しません。"
            )
        }

        if request.evidence.syncWouldDeleteRemote == .true, request.intendedAction != .cloudEvictOnly {
            return decision(
                request,
                rule: nil,
                safetyClass: .red,
                action: .hardBlock,
                layer: .syncBlastRadius,
                reasons: ["SYNC_BLAST_RADIUS", "CLOUD_DELETE_UNSAFE"],
                explanation: "この操作は他の端末の実体まで消す可能性があります。"
            )
        }

        if request.intendedAction == .permanentDelete {
            return blocked(
                request,
                action: .hardBlock,
                layer: .hardBlock,
                reasons: ["PERMANENT_DELETE_FORBIDDEN_V0_1"],
                explanation: "永久削除は実装していません。"
            )
        }

        let matching = matchingRules(path)
        guard let matched = Self.selectRule(matching, loader: loader) else {
            return unknownFallback(request)
        }

        if matched.sourceOfTruth, request.intendedAction != .cloudEvictOnly {
            return decision(
                request,
                rule: matched,
                safetyClass: .red,
                action: .noAction,
                layer: .sourceOfTruth,
                reasons: ["SOURCE_OF_TRUTH"],
                explanation: matched.explanationJA
            )
        }

        return applyRule(matched, request: request)
    }

    static func msSince(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    public static func selectRule(_ matching: [SafetyRule], loader: KnowledgeBaseLoader) -> SafetyRule? {
        matching.max { lhs, rhs in
            let ls = loader.globSpecificity(lhs.match.path)
            let rs = loader.globSpecificity(rhs.match.path)
            if ls != rs { return ls < rs }
            return rhs.evaluationLayer < lhs.evaluationLayer
        }
    }

    func applyRule(_ rule: SafetyRule, request: EvaluationRequest) -> SafetyDecision {
        if rule.hardBlockIf.contains(where: { request.evidence.value(for: $0) == .true }) {
            return blocked(
                request,
                action: .hardBlock,
                layer: .hardBlock,
                reasons: ["HARD_BLOCK", rule.id],
                explanation: rule.explanationJA
            )
        }

        var klass = rule.defaultClass
        var reasons = rule.reasonCodes
        var action = alignedAction(rule: rule, requested: request.intendedAction)

        if action == .permanentDelete {
            return blocked(
                request,
                action: .hardBlock,
                layer: .hardBlock,
                reasons: ["PERMANENT_DELETE_FORBIDDEN_V0_1"],
                explanation: "永久削除は実装していません。"
            )
        }

        // Cloud: evict can be GREEN candidate; delete is RED.
        if rule.actionMode == .cloudEvictOnly, request.intendedAction != .cloudEvictOnly {
            klass = .red
            action = .hardBlock
            reasons.append("CLOUD_DELETE_IS_RED")
            return decision(
                request,
                rule: rule,
                safetyClass: .red,
                action: .hardBlock,
                layer: .syncBlastRadius,
                reasons: reasons,
                explanation: "クラウド上のファイルを削除すると、他端末の実体まで消える可能性があります。ダウンロード解除だけが候補です。"
            )
        }

        if rule.demoteToRedIf.contains(where: { request.evidence.value(for: $0) == .true }) {
            klass = klass.demoted(to: .red)
            reasons.append("DEMOTED_RED")
        }
        if rule.demoteToYellowIf.contains(where: { request.evidence.value(for: $0) == .true }) {
            klass = klass.demoted(to: .yellow)
            reasons.append("DEMOTED_YELLOW")
        }

        if klass == .green {
            for predicate in rule.requiredPredicates {
                let v = request.evidence.value(for: predicate)
                switch v {
                case .true:
                    if !request.evidence.satisfiesStrictPredicate(predicate) {
                        klass = .unknown
                        reasons.append("PREDICATE_NOT_VERIFIED:\(predicate)")
                        return decision(
                            request,
                            rule: rule,
                            safetyClass: .unknown,
                            action: .userReview,
                            layer: .runtimePredicates,
                            reasons: reasons,
                            explanation: "証拠の信頼度が VERIFIED ではないため UNKNOWN です。",
                            score: nil
                        )
                    }
                    continue
                case .false:
                    klass = .yellow
                    reasons.append("PREDICATE_FAILED:\(predicate)")
                case .unknown:
                    // Absolute: UNKNOWN never auto-promotes to GREEN
                    klass = .unknown
                    reasons.append("PREDICATE_UNKNOWN:\(predicate)")
                    return decision(
                        request,
                        rule: rule,
                        safetyClass: .unknown,
                        action: .userReview,
                        layer: .runtimePredicates,
                        reasons: reasons,
                        explanation: "必要な確認が足りないため UNKNOWN です。推測で安全判定しません。",
                        score: nil
                    )
                }
            }
            if request.evidence.isSymlink == .true, rule.match.followSymlinks == false {
                klass = .unknown
                reasons.append("SYMLINK_NOT_FOLLOWED")
                return decision(
                    request,
                    rule: rule,
                    safetyClass: .unknown,
                    action: .userReview,
                    layer: .runtimePredicates,
                    reasons: reasons,
                    explanation: "シンボリックリンクのため、実体を確認するまで安全とは言いません。",
                    score: nil
                )
            }
        }

        let score: SafetyScore? = klass == .unknown ? nil : SafetyScore(value: rule.baseScore)
        let approval = true
        if klass == .green, productVersionAllowsPermanentDelete == false {
            // v0.1: even GREEN requires approval; never auto delete
        }

        return decision(
            request,
            rule: rule,
            safetyClass: klass,
            action: klass == .red ? .noAction : action,
            layer: rule.evaluationLayer,
            reasons: reasons,
            explanation: rule.explanationJA,
            score: score,
            approval: approval
        )
    }

    func alignedAction(rule: SafetyRule, requested: ActionMode) -> ActionMode {
        if requested == .userReview { return rule.actionMode }
        if requested == .noAction { return .noAction }
        if requested == .hardBlock { return .hardBlock }
        // Native cleanup specified by rule wins over raw trash when rule says so.
        if rule.actionMode == .cloudEvictOnly { return .cloudEvictOnly }
        if rule.actionMode == .toolCLIOnly || rule.actionMode == .packageManagerCommand || rule.actionMode == .osAPIOnly || rule.actionMode == .appAPIOnly {
            return rule.actionMode
        }
        return requested
    }

    func unknownFallback(_ request: EvaluationRequest) -> SafetyDecision {
        decision(
            request,
            rule: nil,
            safetyClass: .unknown,
            action: .userReview,
            layer: .unknownFallback,
            reasons: ["UNKNOWN_FALLBACK", "NO_TRUSTED_RULE"],
            explanation: "信頼できるルールや証拠がありません。UNKNOWN のまま表示します。",
            score: nil
        )
    }

    func blocked(
        _ request: EvaluationRequest,
        action: ActionMode,
        layer: EvaluationLayer,
        reasons: [String],
        explanation: String
    ) -> SafetyDecision {
        decision(
            request,
            rule: nil,
            safetyClass: .red,
            action: action,
            layer: layer,
            reasons: reasons,
            explanation: explanation,
            score: nil
        )
    }

    func decision(
        _ request: EvaluationRequest,
        rule: SafetyRule?,
        safetyClass: SafetyClass,
        action: ActionMode,
        layer: EvaluationLayer,
        reasons: [String],
        explanation: String,
        score: SafetyScore? = nil,
        approval: Bool = true
    ) -> SafetyDecision {
        SafetyDecision(
            entity: request.entity,
            action: action,
            safetyClass: safetyClass,
            safetyScore: score,
            reasonCodes: reasons,
            sideEffects: rule?.effects ?? [],
            matchedRuleID: rule?.id,
            evaluationLayer: layer,
            evidenceConfidence: request.evidence.confidence,
            userExplanationJA: explanation,
            growthCauses: rule?.growthCauses.map(\.explanationJA) ?? [],
            requiresUserApproval: approval,
            blockedBy: reasons.first
        )
    }
}
