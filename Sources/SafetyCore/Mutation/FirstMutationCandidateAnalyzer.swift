import Foundation

public enum BlastRadiusClass: String, Codable, Sendable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case unknown = "UNKNOWN"
}

public enum TransactionComplexityClass: String, Codable, Sendable {
    case simple = "SIMPLE"
    case moderate = "MODERATE"
    case complex = "COMPLEX"
}

public enum FirstMutationFitnessTier: String, Codable, Sendable {
    case idealFirstMutation = "IDEAL_FIRST_MUTATION"
    case acceptableFirstMutation = "ACCEPTABLE_FIRST_MUTATION"
    case tooComplexForFirstMutation = "TOO_COMPLEX_FOR_FIRST_MUTATION"
    case blockedByEvidence = "BLOCKED_BY_EVIDENCE"
    case blockedByProductPolicy = "BLOCKED_BY_PRODUCT_POLICY"
    case tooBroadForFirstMutation = "TOO_BROAD_FOR_FIRST_MUTATION"
}

public enum FirstMutationSelectionOutcome: String, Codable, Sendable {
    case readyCandidateFound = "READY_CANDIDATE_FOUND"
    case noSafeRealMutationCandidate = "NO_SAFE_REAL_MUTATION_CANDIDATE"
    case candidateRequiresMorePreflight = "CANDIDATE_REQUIRES_MORE_PREFLIGHT"
}

public struct FirstMutationCandidateEntry: Codable, Sendable, Equatable {
    public var entityID: String
    public var semanticType: String?
    public var canonicalPath: String
    public var action: String
    public var safetyClass: String
    public var actionEligible: Bool
    public var recommendation: String?
    public var recommendationDisposition: String?
    public var mutationReadiness: String
    public var proofCompletenessScore: Int
    public var runtimeRequirements: [String]
    public var cloudRequirements: [String]
    public var transactionContractAvailable: Bool
    public var postVerifyContractAvailable: Bool
    public var auditContractAvailable: Bool
    public var bindingFingerprintPossible: Bool
    public var expectedLogicalBytes: Int64
    public var potentialLocalRecovery: Int64?
    public var reversibility: String
    public var blastRadius: String
    public var transactionComplexity: String
    public var fitnessTier: String
    public var fitnessScore: Int
    public var rankingEligible: Bool
    public var exactBoundedEntity: Bool
    public var blockingReasons: [String]
    public var missingRequirements: [String]
    public var executorImplemented: Bool
}

public struct FirstMutationCandidateInventoryReport: Codable, Sendable, Equatable {
    public var entries: [FirstMutationCandidateEntry]
    public var entitiesDiscovered: Int
    public var moveToTrashCandidates: Int
    public var moveToICloudCandidates: Int
    public var removeLocalDownloadCandidates: Int
    public var vendorNativeCandidates: Int
    public var exactBoundedEntities: Int
    public var broadRootEntitiesRejected: Int
    public var preflightRequired: Int
    public var approvalRequired: Int
    public var contractSatisfiedReadOnly: Int
    public var blockedCount: Int
    public var executorImplemented: Bool
}

public struct FirstMutationCandidateRankingEntry: Codable, Sendable, Equatable {
    public var rank: Int
    public var entityID: String
    public var action: String
    public var path: String
    public var fitnessTier: String
    public var fitnessScore: Int
    public var blastRadius: String
    public var transactionComplexity: String
    public var mutationReadiness: String
    public var rationale: String
}

public struct FirstMutationCandidateRankingReport: Codable, Sendable, Equatable {
    public var entries: [FirstMutationCandidateRankingEntry]
    public var rankingEligibleCount: Int
}

public struct DownloadsMoveToICloudAuditStep: Codable, Sendable, Equatable {
    public var claim: String
    public var satisfied: Bool
    public var value: String?
}

public struct DownloadsMoveToICloudAuditReport: Codable, Sendable, Equatable {
    public var entityID: String
    public var path: String
    public var isRootBucket: Bool
    public var entityGranularityBlocker: String?
    public var mutationReadiness: String?
    public var steps: [DownloadsMoveToICloudAuditStep]
    public var blockingReasons: [String]
}

public struct FirstMutationCandidateSelectionReport: Codable, Sendable, Equatable {
    public var outcome: String
    public var selectedEntityID: String?
    public var selectedAction: String?
    public var selectedPath: String?
    public var rationale: String?
    public var remainingHumanApprovalRequired: Bool
    public var executorImplemented: Bool
}

public struct FirstRealMutationGateReport: Codable, Sendable, Equatable {
    public var gate: String
    public var status: String
    public var selectedCandidate: String?
    public var selectedAction: String?
    public var reason: [String]
    public var selectionOutcome: String
    public var approvalRequiredCount: Int
    public var contractSatisfiedReadOnlyCount: Int
    public var preflightRequiredCount: Int
    public var rankingEligibleCount: Int
    public var executorImplemented: Bool
    public var previewExecutable: Bool
    public var destructiveActionsExecuted: Bool
    // Legacy compatibility
    public var realDerivedDataCandidates: Int
    public var approvalRequired: Int
    public var contractSatisfiedReadOnly: Int
    public var topBlockers: [String]
}

public enum FirstMutationCandidateAnalyzer {
    public static let mutatingActions: [StorageAction] = [
        .moveToTrash, .moveToICloud, .removeLocalDownload, .vendorNativeCleanup,
    ]

    public static func analyze(
        items: [ClassifiedItem],
        decisionCatalog: ActionDecisionCatalog,
        recommendations: [ActionRecommendationResult],
        preflights: [ActionPreflightResult],
        snapshotsByEntityID: [String: EntitySafetySnapshot],
        runtimeResolutions: [String: RuntimeStateResolution],
        mutationGate: MutationGateReport,
        ruleVersion: String,
        runtimeGeneration: Int
    ) -> (
        inventory: FirstMutationCandidateInventoryReport,
        ranking: FirstMutationCandidateRankingReport,
        selection: FirstMutationCandidateSelectionReport,
        downloadsAudit: DownloadsMoveToICloudAuditReport?,
        gate: FirstRealMutationGateReport
    ) {
        var recMap: [String: ActionRecommendationResult] = [:]
        for r in recommendations { recMap[r.entityID] = r }
        var preMap: [String: [StorageAction: ActionPreflightResult]] = [:]
        for p in preflights { preMap[p.entityID, default: [:]][p.action] = p }
        var gateMap: [String: MutationGateResult] = [:]
        for e in mutationGate.entries { gateMap["\(e.entityID):\(e.action)"] = e }

        var entries: [FirstMutationCandidateEntry] = []
        var broadRejected = 0

        for item in items {
            let snapshot = snapshotsByEntityID[item.detected.entity.id]
            let runtime = runtimeResolutions[item.detected.entity.id]
            let rec = recMap[item.detected.entity.id]
            let decisions = decisionCatalog.set(for: item.detected.entity.id)?.decisionMap ?? [:]
            let bounded = !isBroadAggregateRoot(item)

            for action in mutatingActions {
                guard let decision = decisions[action] else { continue }
                let supported = action != .vendorNativeCleanup || decision.eligible || !decision.blockedReasons.isEmpty
                if action == .vendorNativeCleanup, decision.safetyClass == .unknown, decision.blockedReasons.isEmpty { continue }
                if !supported, action == .keep { continue }

                let gateKey = "\(item.detected.entity.id):\(action.rawValue)"
                let gateResult: MutationGateResult
                if let cached = gateMap[gateKey] {
                    gateResult = cached
                } else {
                    let input = MutationGateInput(
                        item: item,
                        action: action,
                        actionDecision: decision,
                        snapshot: snapshot,
                        recommendation: rec,
                        preflight: preMap[item.detected.entity.id]?[action],
                        runtimeResolution: runtime,
                        transactionContract: TransactionContractRegistry.transactionContract(for: action, item: item),
                        postVerifyContract: TransactionContractRegistry.postVerifyContract(for: action, item: item),
                        auditContract: TransactionContractRegistry.auditContract(for: action, item: item),
                        approvalState: .scanDefault,
                        evidenceGeneration: snapshot?.evidence.snapshotVersion ?? 0,
                        verificationGeneration: snapshot?.verification.snapshotGeneration ?? 0,
                        runtimeGeneration: snapshot?.cacheKey.runtimeGeneration ?? runtimeGeneration,
                        ruleVersion: ruleVersion
                    )
                    gateResult = MutationGate.evaluate(input)
                }

                let blast = classifyBlastRadius(item: item, action: action)
                let complexity = classifyTransactionComplexity(action: action)
                let broad = !bounded
                if broad { broadRejected += 1 }
                let tier = classifyFitnessTier(
                    item: item,
                    action: action,
                    decision: decision,
                    gate: gateResult,
                    blast: blast,
                    complexity: complexity,
                    broad: broad
                )
                let proofScore = proofCompleteness(gate: gateResult)
                let rankingEligible = tier == FirstMutationFitnessTier.idealFirstMutation.rawValue
                    || tier == FirstMutationFitnessTier.acceptableFirstMutation.rawValue
                let fitnessScore = rankingEligible
                    ? computeFitnessScore(gate: gateResult, blast: blast, complexity: complexity, proofScore: proofScore, action: action)
                    : 0

                var blockers = gateResult.blockingReasons
                if broad { blockers.append("ENTITY_GRANULARITY_TOO_BROAD") }

                entries.append(FirstMutationCandidateEntry(
                    entityID: item.detected.entity.id,
                    semanticType: item.detected.annotation?.semanticType,
                    canonicalPath: snapshot?.evidence.canonicalPath ?? item.detected.entity.path,
                    action: action.rawValue,
                    safetyClass: decision.safetyClass.rawValue,
                    actionEligible: decision.eligible,
                    recommendation: rec?.recommendedAction.rawValue,
                    recommendationDisposition: dispositionLabel(rec?.disposition),
                    mutationReadiness: gateResult.readiness,
                    proofCompletenessScore: proofScore,
                    runtimeRequirements: gateResult.requiredFreshChecks.filter { $0.contains("runtime") || $0.contains("active") || $0.contains("open") },
                    cloudRequirements: gateResult.requiredFreshChecks.filter { $0.contains("cloud") || $0.contains("remote") },
                    transactionContractAvailable: gateResult.transactionContractAvailable,
                    postVerifyContractAvailable: gateResult.postVerifyContractAvailable,
                    auditContractAvailable: gateResult.auditContractAvailable,
                    bindingFingerprintPossible: gateResult.actionBindingFingerprint != nil,
                    expectedLogicalBytes: item.exclusiveBytes,
                    potentialLocalRecovery: decision.expectedLocalRecoveryBytes,
                    reversibility: reversibilityLabel(action: action),
                    blastRadius: blast.rawValue,
                    transactionComplexity: complexity.rawValue,
                    fitnessTier: tier,
                    fitnessScore: fitnessScore,
                    rankingEligible: rankingEligible,
                    exactBoundedEntity: bounded,
                    blockingReasons: Array(Set(blockers)).sorted(),
                    missingRequirements: Array(Set(gateResult.missingRequirements)).sorted(),
                    executorImplemented: false
                ))
            }
        }

        let inventory = FirstMutationCandidateInventoryReport(
            entries: entries.sorted { $0.entityID < $1.entityID || ($0.entityID == $1.entityID && $0.action < $1.action) },
            entitiesDiscovered: Set(entries.map(\.entityID)).count,
            moveToTrashCandidates: entries.filter { $0.action == StorageAction.moveToTrash.rawValue && ($0.actionEligible || !$0.blockingReasons.isEmpty) }.count,
            moveToICloudCandidates: entries.filter { $0.action == StorageAction.moveToICloud.rawValue && ($0.actionEligible || !$0.blockingReasons.isEmpty) }.count,
            removeLocalDownloadCandidates: entries.filter { $0.action == StorageAction.removeLocalDownload.rawValue && ($0.actionEligible || !$0.blockingReasons.isEmpty) }.count,
            vendorNativeCandidates: entries.filter { $0.action == StorageAction.vendorNativeCleanup.rawValue }.count,
            exactBoundedEntities: Set(entries.filter(\.exactBoundedEntity).map(\.entityID)).count,
            broadRootEntitiesRejected: broadRejected,
            preflightRequired: entries.filter { $0.mutationReadiness == MutationReadiness.preflightRequired.rawValue }.count,
            approvalRequired: entries.filter { $0.mutationReadiness == MutationReadiness.approvalRequired.rawValue }.count,
            contractSatisfiedReadOnly: entries.filter { $0.mutationReadiness == MutationReadiness.contractSatisfiedReadOnly.rawValue }.count,
            blockedCount: entries.filter { $0.mutationReadiness == MutationReadiness.blocked.rawValue }.count,
            executorImplemented: false
        )

        let ranking = buildRanking(from: entries)
        let downloadsAudit = buildDownloadsAudit(
            items: items,
            entries: entries,
            snapshotsByEntityID: snapshotsByEntityID,
            gateMap: gateMap
        )
        let selection = selectCandidate(inventory: inventory, ranking: ranking)
        let gate = buildGateReport(inventory: inventory, selection: selection, ranking: ranking)

        return (inventory, ranking, selection, downloadsAudit, gate)
    }

    static func isBroadAggregateRoot(_ item: ClassifiedItem) -> Bool {
        let path = (item.detected.entity.path as NSString).standardizingPath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let broadPaths = [
            "Downloads", "Documents", "Desktop",
            "Library/Application Support", "Library/Caches", "Library/Containers",
            "Library/Developer/Xcode/DerivedData",
        ].map { (home as NSString).appendingPathComponent($0) }
        if broadPaths.contains(path) { return true }
        let broadIDs: Set<String> = [
            "user.downloads", "user.documents", "user.desktop",
            "xcode.derived_data", "macos.application_support",
        ]
        if broadIDs.contains(item.detected.entity.id) { return true }
        if item.detected.entity.id.hasSuffix(".root") { return true }
        return false
    }

    static func classifyBlastRadius(item: ClassifiedItem, action: StorageAction) -> BlastRadiusClass {
        if ActionPolicy.isClaudeRuntime(item) || ActionPolicy.isIOSBackup(item) { return .high }
        if ActionPolicy.isVoiceMemo(item) { return .high }
        if ActionPolicy.isLibraryManagedPath(item.detected.entity.path) { return .high }
        if ActionPolicy.isGitRepository(item) { return .medium }
        if action == .moveToICloud { return .medium }
        if action == .removeLocalDownload { return .medium }
        if ActionPolicy.isDerivedData(item) || item.detected.annotation?.lifecycle.role == .generatedArtifact {
            return .low
        }
        if item.detected.entity.kind == .cache || item.detected.bucket == .generated { return .low }
        if ActionPolicy.userOwnedVerified(item), !isBroadAggregateRoot(item) { return .medium }
        if item.decision.safetyClass == .unknown { return .unknown }
        return .unknown
    }

    static func classifyTransactionComplexity(action: StorageAction) -> TransactionComplexityClass {
        switch action {
        case .moveToTrash: return .simple
        case .removeLocalDownload: return .moderate
        case .moveToICloud: return .complex
        case .vendorNativeCleanup: return .moderate
        case .keep: return .simple
        }
    }

    static func classifyFitnessTier(
        item: ClassifiedItem,
        action: StorageAction,
        decision: ActionDecision,
        gate: MutationGateResult,
        blast: BlastRadiusClass,
        complexity: TransactionComplexityClass,
        broad: Bool
    ) -> String {
        if broad { return FirstMutationFitnessTier.tooBroadForFirstMutation.rawValue }
        if ActionPolicy.isVoiceMemo(item) || ActionPolicy.isIOSBackup(item) || ActionPolicy.isClaudeRuntime(item) {
            return FirstMutationFitnessTier.blockedByProductPolicy.rawValue
        }
        if ActionPolicy.isGitRepository(item), action == .moveToICloud {
            return FirstMutationFitnessTier.blockedByProductPolicy.rawValue
        }
        if gate.blockingReasons.contains(HardProductBlock.genericLibraryRelocation.rawValue)
            || gate.blockingReasons.contains(HardProductBlock.permanentDelete.rawValue) {
            return FirstMutationFitnessTier.blockedByProductPolicy.rawValue
        }
        let readiness = MutationReadiness(rawValue: gate.readiness)
        if readiness == .blocked || readiness == .verifyMore { return FirstMutationFitnessTier.blockedByEvidence.rawValue }
        if decision.safetyClass == .red || decision.safetyClass == .unknown { return FirstMutationFitnessTier.blockedByEvidence.rawValue }
        if !decision.eligible { return FirstMutationFitnessTier.blockedByEvidence.rawValue }
        if complexity == .complex { return FirstMutationFitnessTier.tooComplexForFirstMutation.rawValue }
        if blast == .high || blast == .unknown { return FirstMutationFitnessTier.blockedByEvidence.rawValue }
        if readiness == .approvalRequired || readiness == .contractSatisfiedReadOnly {
            if blast == .low && complexity == .simple { return FirstMutationFitnessTier.idealFirstMutation.rawValue }
            return FirstMutationFitnessTier.acceptableFirstMutation.rawValue
        }
        if readiness == .preflightRequired {
            if blast == .low && complexity == .simple { return FirstMutationFitnessTier.acceptableFirstMutation.rawValue }
            return FirstMutationFitnessTier.tooComplexForFirstMutation.rawValue
        }
        return FirstMutationFitnessTier.blockedByEvidence.rawValue
    }

    static func proofCompleteness(gate: MutationGateResult) -> Int {
        let total = gate.satisfiedRequirements.count + gate.missingRequirements.count + gate.blockingReasons.count
        guard total > 0 else { return gate.transactionContractAvailable ? 50 : 0 }
        return min(100, (gate.satisfiedRequirements.count * 100) / max(1, total))
    }

    static func computeFitnessScore(
        gate: MutationGateResult,
        blast: BlastRadiusClass,
        complexity: TransactionComplexityClass,
        proofScore: Int,
        action: StorageAction
    ) -> Int {
        var score = proofScore
        switch blast {
        case .low: score += 40
        case .medium: score += 20
        case .high, .unknown: score += 0
        }
        switch complexity {
        case .simple: score += 30
        case .moderate: score += 15
        case .complex: score += 0
        }
        if action == .moveToTrash { score += 20 }
        if gate.transactionContractAvailable { score += 10 }
        if gate.postVerifyContractAvailable { score += 10 }
        if gate.auditContractAvailable { score += 10 }
        let readiness = MutationReadiness(rawValue: gate.readiness)
        if readiness == .approvalRequired || readiness == .contractSatisfiedReadOnly { score += 25 }
        else if readiness == .preflightRequired { score += 10 }
        return score
    }

    static func buildRanking(from entries: [FirstMutationCandidateEntry]) -> FirstMutationCandidateRankingReport {
        let eligible = entries.filter(\.rankingEligible)
            .sorted {
                if $0.fitnessScore != $1.fitnessScore { return $0.fitnessScore > $1.fitnessScore }
                if $0.blastRadius != $1.blastRadius { return $0.blastRadius < $1.blastRadius }
                return $0.transactionComplexity < $1.transactionComplexity
            }
        var ranked: [FirstMutationCandidateRankingEntry] = []
        for (idx, e) in eligible.enumerated() {
            ranked.append(FirstMutationCandidateRankingEntry(
                rank: idx + 1,
                entityID: e.entityID,
                action: e.action,
                path: e.canonicalPath,
                fitnessTier: e.fitnessTier,
                fitnessScore: e.fitnessScore,
                blastRadius: e.blastRadius,
                transactionComplexity: e.transactionComplexity,
                mutationReadiness: e.mutationReadiness,
                rationale: rankingRationale(e)
            ))
        }
        return FirstMutationCandidateRankingReport(entries: ranked, rankingEligibleCount: ranked.count)
    }

    static func rankingRationale(_ e: FirstMutationCandidateEntry) -> String {
        "blast=\(e.blastRadius) complexity=\(e.transactionComplexity) proof=\(e.proofCompletenessScore) readiness=\(e.mutationReadiness)"
    }

    static func buildDownloadsAudit(
        items: [ClassifiedItem],
        entries: [FirstMutationCandidateEntry],
        snapshotsByEntityID: [String: EntitySafetySnapshot],
        gateMap: [String: MutationGateResult]
    ) -> DownloadsMoveToICloudAuditReport? {
        guard let item = items.first(where: { $0.detected.entity.id == "user.downloads" }) else { return nil }
        let entry = entries.first { $0.entityID == "user.downloads" && $0.action == StorageAction.moveToICloud.rawValue }
        let gate = gateMap["user.downloads:MOVE_TO_ICLOUD"]
        let snapshot = snapshotsByEntityID["user.downloads"]
        let isRoot = isBroadAggregateRoot(item)
        let v = snapshot?.verification ?? item.verification

        func step(_ claim: String, _ ok: Bool, _ value: String? = nil) -> DownloadsMoveToICloudAuditStep {
            DownloadsMoveToICloudAuditStep(claim: claim, satisfied: ok, value: value)
        }

        let steps = [
            step("user_owned_verified", ActionPolicy.userOwnedVerified(item)),
            step("canonical_path_verified", !(snapshot?.evidence.canonicalPath ?? item.detected.entity.path).isEmpty),
            step("entity_identity_verified", !item.detected.entity.id.isEmpty, item.detected.entity.id),
            step("exact_bounded_entity", !isRoot),
            step("not_application_managed", !ActionPolicy.isLibraryManagedPath(item.detected.entity.path)),
            step("not_git_block", !ActionPolicy.isGitRepository(item)),
            step("relocation_contract", gate?.transactionContractAvailable == true),
            step("sot_true_allowed_for_preservation", v?.sourceOfTruth.value == .true || ActionPolicy.userOwnedVerified(item)),
            step("icloud_available", entry?.cloudRequirements.isEmpty != false),
            step("destination_known", false, "requires_fresh_preflight"),
            step("quota_known", false, "requires_fresh_preflight"),
            step("conflict_state_known", false, "requires_fresh_preflight"),
            step("copy_verification_contract", gate?.postVerifyContractAvailable == true),
            step("remote_persistence_contract", gate?.postVerifyContractAvailable == true),
            step("source_release_contract", gate?.transactionContractAvailable == true),
            step("post_verify_contract", gate?.postVerifyContractAvailable == true),
            step("audit_contract", gate?.auditContractAvailable == true),
            step("fresh_preflight_required", true, "required_at_execution"),
        ]

        return DownloadsMoveToICloudAuditReport(
            entityID: item.detected.entity.id,
            path: item.detected.entity.path,
            isRootBucket: isRoot,
            entityGranularityBlocker: isRoot ? "ENTITY_GRANULARITY_TOO_BROAD" : nil,
            mutationReadiness: gate?.readiness ?? entry?.mutationReadiness,
            steps: steps,
            blockingReasons: entry?.blockingReasons ?? gate?.blockingReasons ?? []
        )
    }

    static func selectCandidate(
        inventory: FirstMutationCandidateInventoryReport,
        ranking: FirstMutationCandidateRankingReport
    ) -> FirstMutationCandidateSelectionReport {
        let ready = inventory.entries.filter {
            $0.mutationReadiness == MutationReadiness.approvalRequired.rawValue
                || $0.mutationReadiness == MutationReadiness.contractSatisfiedReadOnly.rawValue
        }.filter { $0.exactBoundedEntity && $0.rankingEligible }

        if let best = ready.max(by: { $0.fitnessScore < $1.fitnessScore }) {
            return FirstMutationCandidateSelectionReport(
                outcome: FirstMutationSelectionOutcome.readyCandidateFound.rawValue,
                selectedEntityID: best.entityID,
                selectedAction: best.action,
                selectedPath: best.canonicalPath,
                rationale: "Lowest blast-radius eligible candidate with readiness \(best.mutationReadiness)",
                remainingHumanApprovalRequired: true,
                executorImplemented: false
            )
        }

        let preflightBest = ranking.entries.first { $0.mutationReadiness == MutationReadiness.preflightRequired.rawValue }
        if let preflightBest {
            return FirstMutationCandidateSelectionReport(
                outcome: FirstMutationSelectionOutcome.candidateRequiresMorePreflight.rawValue,
                selectedEntityID: preflightBest.entityID,
                selectedAction: preflightBest.action,
                selectedPath: preflightBest.path,
                rationale: "Best near-candidate requires fresh preflight before approval gate",
                remainingHumanApprovalRequired: true,
                executorImplemented: false
            )
        }

        return FirstMutationCandidateSelectionReport(
            outcome: FirstMutationSelectionOutcome.noSafeRealMutationCandidate.rawValue,
            selectedEntityID: nil,
            selectedAction: nil,
            selectedPath: nil,
            rationale: "No current entity satisfies exact-bounded first-mutation gate with strict proof",
            remainingHumanApprovalRequired: false,
            executorImplemented: false
        )
    }

    static func buildGateReport(
        inventory: FirstMutationCandidateInventoryReport,
        selection: FirstMutationCandidateSelectionReport,
        ranking: FirstMutationCandidateRankingReport
    ) -> FirstRealMutationGateReport {
        var reasons: [String] = []
        var status: String

        switch FirstMutationSelectionOutcome(rawValue: selection.outcome) {
        case .readyCandidateFound:
            status = P21GateStatusValue.readyForHumanAuthorization.rawValue
            reasons.append("Candidate \(selection.selectedEntityID ?? "?") × \(selection.selectedAction ?? "?") reached read-only approval gate")
        case .candidateRequiresMorePreflight:
            status = P21GateStatusValue.blockedByRealEvidence.rawValue
            reasons.append("Best candidate requires fresh preflight: \(selection.selectedEntityID ?? "?")")
            if selection.selectedEntityID == "user.downloads" {
                reasons.append("Downloads root rejected for first mutation granularity")
            }
        case .noSafeRealMutationCandidate, .none:
            status = "NO_SAFE_REAL_MUTATION_CANDIDATE"
            reasons.append("No exact-bounded entity at APPROVAL_REQUIRED or CONTRACT_SATISFIED_READ_ONLY")
        }

        var blockers: [String: Int] = [:]
        for e in inventory.entries {
            for b in e.blockingReasons { blockers[b, default: 0] += 1 }
        }
        let top = blockers.sorted { $0.value > $1.value }.prefix(5).map(\.key)

        return FirstRealMutationGateReport(
            gate: "FIRST_REAL_MUTATION_GATE",
            status: status,
            selectedCandidate: selection.selectedEntityID,
            selectedAction: selection.selectedAction,
            reason: reasons,
            selectionOutcome: selection.outcome,
            approvalRequiredCount: inventory.approvalRequired,
            contractSatisfiedReadOnlyCount: inventory.contractSatisfiedReadOnly,
            preflightRequiredCount: inventory.preflightRequired,
            rankingEligibleCount: ranking.rankingEligibleCount,
            executorImplemented: false,
            previewExecutable: false,
            destructiveActionsExecuted: false,
            realDerivedDataCandidates: inventory.entries.filter {
                $0.entityID.lowercased().contains("deriveddata")
                    && ($0.mutationReadiness == MutationReadiness.approvalRequired.rawValue
                        || $0.mutationReadiness == MutationReadiness.contractSatisfiedReadOnly.rawValue)
            }.count,
            approvalRequired: inventory.approvalRequired,
            contractSatisfiedReadOnly: inventory.contractSatisfiedReadOnly,
            topBlockers: Array(top)
        )
    }

    static func dispositionLabel(_ disposition: RecommendationDisposition?) -> String? {
        guard let disposition else { return nil }
        switch disposition {
        case .actionable(let a): return "actionable:\(a.rawValue)"
        case .keep: return "keep"
        case .verifyMore(let c): return "verifyMore:\(c.map(\.rawValue).joined(separator: ","))"
        }
    }

    static func reversibilityLabel(action: StorageAction) -> String {
        switch action {
        case .moveToTrash: return "TRASH_REVERSIBLE"
        case .moveToICloud: return "PRESERVATION_NOT_DELETION"
        case .removeLocalDownload: return "LOCAL_EVICTION_REVERSIBLE_VIA_CLOUD"
        case .vendorNativeCleanup: return "VENDOR_NATIVE"
        case .keep: return "N/A"
        }
    }
}

extension FirstRealMutationGateReport {
    public var asLegacyP21: P21GateStatusReport {
        P21GateStatusReport(
            status: status,
            realDerivedDataCandidates: realDerivedDataCandidates,
            approvalRequired: approvalRequired,
            contractSatisfiedReadOnly: contractSatisfiedReadOnly,
            topBlockers: topBlockers,
            executorImplemented: executorImplemented,
            previewExecutable: previewExecutable,
            destructiveActionsExecuted: destructiveActionsExecuted
        )
    }
}
