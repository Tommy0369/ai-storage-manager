import Foundation

public struct EntityVerificationLoopResult: Sendable {
    public var draft: [(DetectedEntity, SafetyDecision, [String: String], EvidenceBundle, RuntimeState, VerificationAnnotation)]
    public var greenAudits: [GreenAuditRecord]
    public var evidenceTotals: [String: [String: Int]]
    public var loopReport: EntityVerificationLoopReport
    public var backlog: EntityVerificationBacklogReport
    public var strategyRuntime: VerificationStrategyRuntimeReport
    public var conflicts: [EvidenceConflictRecord]
    public var safetyEvalRuntime: SafetyEvalRuntimeReport
    public var ruleIndexStats: SafetyRuleIndexStats
    public var predicateCacheStats: PredicateCacheStats
    public var greenAuditorRuntime: GreenAuditorRuntimeReport
    public var backlogFeasibility: BacklogFeasibilityReport
    public var entitySnapshotsByID: [String: EntitySafetySnapshot]
    public var safetyDecisionsByEntityID: [String: [ActionMode: SafetyDecision]]
    public var resolverRuntime: ResolverRuntimeReport
    public var entitySnapshotRuntime: EntitySafetySnapshotRuntimeReport
    public var actionEvalRuntime: ActionEvalRuntimeReport
    public var runtimeBatchResolution: RuntimeBatchResolutionReport
    public var runtimeResolutionNeed: RuntimeResolutionNeedReport
    public var runtimeObservationIndex: RuntimeObservationIndexReport
    public var runtimeIndexHandle: RuntimeObservationIndex
    public var runtimeResolutionsByEntityID: [String: RuntimeStateResolution]
}

public struct EntityVerificationLoop {
    public var knowledge: KnowledgeBaseDocument
    public var protection: UserProtectionStore
    public var budget: VerificationBudgetConfig
    public var proofTargets: Set<String>

    public init(
        knowledge: KnowledgeBaseDocument,
        protection: UserProtectionStore = UserProtectionStore(),
        budget: VerificationBudgetConfig = .default,
        proofTargets: Set<String> = ["derived-data"]
    ) {
        self.knowledge = knowledge
        self.protection = protection
        self.budget = budget
        self.proofTargets = proofTargets
    }

    public func run(
        detected: [DetectedEntity],
        context: VerificationLoopContext,
        telemetry: ProofRuntimeTelemetry
    ) -> EntityVerificationLoopResult {
        let loopStarted = Date()
        var entities = detected
        var evidenceTotals: [String: [String: Int]] = [:]
        var greenAudits: [GreenAuditRecord] = []
        var draft: [(DetectedEntity, SafetyDecision, [String: String], EvidenceBundle, RuntimeState, VerificationAnnotation)] = []
        var strategyResults: [VerificationStrategyResult] = []
        var conflicts: [EvidenceConflictRecord] = []
        var attemptRecords: [String: VerificationAttemptRecord] = [:]
        var backlogEntries: [EntityVerificationBacklogEntry] = []
        var feasibilityEntries: [BacklogFeasibilityEntry] = []
        let evidenceCache = EvidenceResolutionCache()
        var safetySession = SafetyEvalSession(knowledge: knowledge, protection: protection)

        let buildStarted = Date()
        let byteHints = byteHintsFor(detected: entities)
        let candidates = VerificationCandidateBuilder.build(from: entities, context: context, byteHints: byteHints)
        let candidateBuildingMs = msSince(buildStarted)

        let selectStarted = Date()
        var remainingBudgetMs = budget.totalBudgetMs
        var attemptedCandidates = 0
        var skippedCandidates = 0
        var blockedCandidates = 0
        var verifiedClaims = 0
        var inferredClaims = 0
        var unknownClaims = 0
        var conflictedClaims = 0
        var budgetExhausted = false
        var verifiedBytes: Int64 = 0

        var prioritized = candidates.filter { $0.attemptState != .blocked && $0.proofTier != .optIn }
        prioritized = Array(prioritized.prefix(budget.maxCandidates))
        let strategySelectionMs = msSince(selectStarted)

        let proofStarted = Date()
        for candidate in prioritized where remainingBudgetMs > 0 {
            guard let idx = entities.firstIndex(where: { $0.entity.id == candidate.entityID }) else { continue }
            var entity = entities[idx]
            var verification = initialVerification(for: entity)
            var evidence = evidenceCache.evidence(for: entity.entity.path, entity: entity, resolver: context.resolver)
            applySnapshotConfidence(&evidence, entity: entity, context: context, cache: evidenceCache)

            let dependencyBlockers = dependencyBlockersFor(entity: entity, verification: verification)
            var strategies = VerificationStrategySelector.select(candidate: candidate, dependencyBlockers: dependencyBlockers)
            strategies = strategies.filter { strategy in
                let assessment = ProofFeasibilityResolver.assess(entity: entity, strategy: strategy)
                feasibilityEntries.append(BacklogFeasibilityEntry(
                    entityID: candidate.entityID,
                    path: candidate.canonicalPath,
                    strategyID: strategy.rawValue,
                    claim: VerificationStrategies.primaryClaim(for: strategy).rawValue,
                    feasibility: assessment.feasibility,
                    reason: assessment.reason
                ))
                switch assessment.feasibility {
                case .explicitRouteAvailable, .notApplicable, .unknown, .expensiveOptInOnly:
                    return true
                case .explicitRouteNotFound, .ambiguousRoute:
                    backlogEntries.append(backlogEntry(
                        candidate: candidate,
                        attempted: false,
                        result: "BLOCKED",
                        reason: assessment.reason ?? assessment.feasibility.rawValue
                    ))
                    return false
                }
            }
            if strategies.isEmpty {
                blockedCandidates += 1
                continue
            }

            var entityAttempts = 0
            var entityAttempted = false
            for strategy in strategies {
                if remainingBudgetMs <= 0 {
                    budgetExhausted = true
                    break
                }
                if entityAttempts >= budget.maxAttemptsPerEntity { break }
                let claim = VerificationStrategies.primaryClaim(for: strategy)
                let feasibility = ProofFeasibilityResolver.assess(entity: entity, strategy: strategy)
                let attemptKey = "\(candidate.entityID)|\(strategy.rawValue)|\(claim.rawValue)|\(feasibility.feasibility.rawValue)"
                if let prior = attemptRecords[attemptKey], prior.state != .notAttempted {
                    skippedCandidates += 1
                    continue
                }
                if VerificationStrategies.isClaimAlreadyVerified(claim: claim, entity: entity, verification: verification) {
                    attemptRecords[attemptKey] = VerificationAttemptRecord(key: attemptKey, state: .verified, outcome: .verified)
                    skippedCandidates += 1
                    continue
                }

                let attemptStarted = Date()
                let perBudget = min(budget.perStrategyBudgetMs, remainingBudgetMs)
                var result = VerificationStrategies.attempt(
                    strategy: strategy,
                    entity: entity,
                    evidence: &evidence,
                    verification: &verification,
                    context: context,
                    budgetMs: perBudget
                )
                let used = max(1, result.runtimeMs)
                remainingBudgetMs = max(0, remainingBudgetMs - used)
                entityAttempts += 1
                entityAttempted = true
                strategyResults.append(result)

                switch result.outcome {
                case .verified:
                    verifiedClaims += 1
                    verifiedBytes += candidate.uniqueBytes
                    attemptRecords[attemptKey] = VerificationAttemptRecord(key: attemptKey, state: .verified, outcome: .verified)
                case .inferred:
                    inferredClaims += 1
                    attemptRecords[attemptKey] = VerificationAttemptRecord(key: attemptKey, state: .unknownNoEvidence, outcome: .inferred)
                case .unknown:
                    unknownClaims += 1
                    let state: VerificationAttemptState = result.reasonCodes.contains("PROOF_BUDGET_EXCEEDED") ? .unknownBudget : .unknownNoEvidence
                    attemptRecords[attemptKey] = VerificationAttemptRecord(key: attemptKey, state: state, outcome: .unknown)
                case .conflicted:
                    conflictedClaims += 1
                    attemptRecords[attemptKey] = VerificationAttemptRecord(key: attemptKey, state: .unknownConflict, outcome: .conflicted)
                    conflicts.append(EvidenceConflictRecord(
                        entityID: candidate.entityID,
                        path: candidate.canonicalPath,
                        claim: result.claim.rawValue,
                        conflictDescription: result.reasonCodes.joined(separator: ","),
                        reasonCode: "EVIDENCE_CONFLICT"
                    ))
                case .blocked:
                    attemptRecords[attemptKey] = VerificationAttemptRecord(key: attemptKey, state: .blocked, outcome: .blocked)
                }

                backlogEntries.append(backlogEntry(
                    candidate: candidate,
                    attempted: true,
                    result: result.outcome.rawValue,
                    reason: result.reasonCodes.first
                ))
                _ = attemptStarted
            }
            if entityAttempted { attemptedCandidates += 1 }
            evidenceCache.storeEvidence(path: entity.entity.path, bundle: evidence)
            evidenceCache.storeVerification(entityID: entity.entity.id, verification: verification)
            entities[idx] = entity
        }
        let proofExecutionMs = msSince(proofStarted)

        let claimUpdateStarted = Date()
        let claimUpdateMs = msSince(claimUpdateStarted)

        let safetyStarted = Date()
        var safetyActions = 0
        var entitySnapshotsByID: [String: EntitySafetySnapshot] = [:]
        var safetyDecisionsByEntityID: [String: [ActionMode: SafetyDecision]] = [:]

        let runtimeIndex = RuntimeObservationIndex.build(
            processes: context.processes,
            handles: context.handles,
            observedAt: context.observedAt
        )
        var runtimePlans: [String: RuntimeRequirementPlan] = [:]
        var verificationsForBatch: [String: VerificationAnnotation] = [:]
        for entity in entities {
            let verification = evidenceCache.verification(for: entity.entity.id) ?? initialVerification(for: entity)
            verificationsForBatch[entity.entity.id] = verification
            runtimePlans[entity.entity.id] = RuntimeResolutionNeedPlanner.plan(
                entity: entity,
                ruleIndex: safetySession.index,
                verification: verification
            )
        }
        let needReport = RuntimeResolutionNeedPlanner.buildNeedReport(plans: runtimePlans)
        let batchResult = RuntimeStateBatchResolver.resolveAll(
            entities: entities,
            verifications: verificationsForBatch,
            plans: runtimePlans,
            index: runtimeIndex,
            processCompleteness: context.processCompleteness,
            handleCompleteness: context.handleCompleteness
        )

        for d in entities {
            var entity = d
            var evidence = evidenceCache.evidence(for: entity.entity.path, entity: entity, resolver: context.resolver)
            var verification = verificationsForBatch[entity.entity.id] ?? initialVerification(for: entity)
            let runtimeResolution = batchResult.resolutions[entity.entity.id]

            let snapshot = safetySession.finalizeSnapshot(
                entity: &entity,
                evidence: &evidence,
                verification: &verification,
                context: context,
                cache: evidenceCache,
                runtimeResolution: runtimeResolution,
                runtimeIndex: runtimeIndex
            )
            entitySnapshotsByID[entity.entity.id] = snapshot
            evidenceCache.storeEvidence(path: entity.entity.path, bundle: evidence)
            evidenceCache.storeVerification(entityID: entity.entity.id, verification: verification)

            tally(&evidenceTotals, evidence)
            let includeCloud = entity.bucket == .cloud || entity.entity.id.contains("icloud") || entity.entity.id.contains("cloud")
            let batch = safetySession.evaluateActions(snapshot: snapshot, includeCloudVariants: includeCloud)
            var decision = batch.primary
            let variants = batch.variants
            safetyDecisionsByEntityID[entity.entity.id] = batch.decisions
            safetyActions += batch.actionsEvaluated
            let rule = safetySession.index.rule(id: decision.matchedRuleID)
            let predsOK = (rule?.requiredPredicates ?? []).allSatisfy { snapshot.evidence.satisfiesStrictPredicate($0) }
            var placeholder = ClassifiedItem(
                detected: entity,
                decision: decision,
                semantic: LLMBoundary.freeze(decision),
                allocatedBytes: entity.entity.logicalBytes,
                actionVariants: variants,
                inclusiveBytes: entity.entity.logicalBytes,
                exclusiveBytes: entity.entity.logicalBytes,
                resolution: ResolutionLevel.assign(entityID: entity.entity.id, path: entity.entity.path, predicatesAllTrue: predsOK, safetyClass: decision.safetyClass),
                verification: verification
            )
            let audited = safetySession.audit(item: placeholder, evidence: snapshot.evidence, state: snapshot.state)
            decision = audited.0
            placeholder.decision = decision
            placeholder.semantic = LLMBoundary.freeze(decision)
            if decision.safetyClass == .green, let record = audited.1 {
                greenAudits.append(record)
            } else if audited.1?.downgradedFromGreen == true, let record = audited.1 {
                greenAudits.append(record)
            }
            draft.append((entity, decision, variants, snapshot.evidence, snapshot.state, verification))
        }
        let safetyEvaluationMs = msSince(safetyStarted)
        let safetyEvalRuntime = safetySession.runtimeReport(
            totalMs: safetyEvaluationMs,
            entities: entities.count,
            actions: safetyActions
        )
        let blockedNoRoute = feasibilityEntries.filter { $0.feasibility == .explicitRouteNotFound }.count
        let explicitRoutes = feasibilityEntries.filter { $0.feasibility == .explicitRouteAvailable }.count
        let backlogFeasibility = BacklogFeasibilityReport(
            assessments: feasibilityEntries,
            blockedNoRouteCount: blockedNoRoute,
            explicitRouteAvailableCount: explicitRoutes
        )

        for candidate in candidates where !backlogEntries.contains(where: { $0.entityID == candidate.entityID }) {
            for claim in candidate.unresolvedClaims {
                backlogEntries.append(EntityVerificationBacklogEntry(
                    entityID: candidate.entityID,
                    path: candidate.canonicalPath,
                    uniqueBytes: candidate.uniqueBytes,
                    measurementKnown: candidate.measurementKnown,
                    semanticLevel: candidate.semanticLevel,
                    unresolvedClaim: claim.rawValue,
                    priority: candidate.priority,
                    estimatedProofCostMs: candidate.estimatedCostMs,
                    availableStrategy: candidate.strategiesAvailable.first?.rawValue,
                    attempted: false,
                    result: candidate.attemptState.rawValue,
                    blockingReason: candidate.blockingReasons.first
                ))
            }
        }

        let totalAttempts = strategyResults.count
        let yield = totalAttempts == 0 ? 0 : Double(verifiedClaims) / Double(totalAttempts)
        let loopReport = EntityVerificationLoopReport(
            candidatesDiscovered: candidates.count,
            candidatesAttempted: attemptedCandidates,
            candidatesSkipped: skippedCandidates,
            candidatesBlocked: blockedCandidates + candidates.filter { $0.attemptState == .blocked }.count,
            claimsVerified: verifiedClaims,
            claimsInferred: inferredClaims,
            claimsUnknown: unknownClaims,
            claimsConflicted: conflictedClaims,
            budgetExhausted: budgetExhausted,
            totalRuntimeMs: msSince(loopStarted),
            candidateBuildingMs: candidateBuildingMs,
            strategySelectionMs: strategySelectionMs,
            proofExecutionMs: proofExecutionMs,
            claimUpdateMs: claimUpdateMs,
            safetyEvaluationMs: safetyEvaluationMs,
            proofStrategyCounts: Dictionary(grouping: strategyResults, by: { $0.strategyID.rawValue }).mapValues(\.count),
            topSuccessfulProofs: strategyResults.filter { $0.outcome == .verified }.prefix(10).map { "\($0.strategyID.rawValue):\($0.entityID)" },
            topUnresolvedProofs: strategyResults.filter { $0.outcome == .unknown }.prefix(10).map { "\($0.strategyID.rawValue):\($0.entityID)" },
            verificationYield: yield,
            verifiedBytesImpacted: verifiedBytes,
            runtimePerVerifiedClaimMs: verifiedClaims == 0 ? 0 : Double(proofExecutionMs) / Double(verifiedClaims)
        )

        let backlog = EntityVerificationBacklogReport(
            entries: backlogEntries.sorted { $0.priority > $1.priority },
            totalCandidates: candidates.count,
            attemptedCount: attemptedCandidates,
            blockedCount: blockedCandidates
        )

        return EntityVerificationLoopResult(
            draft: draft,
            greenAudits: greenAudits,
            evidenceTotals: evidenceTotals,
            loopReport: loopReport,
            backlog: backlog,
            strategyRuntime: buildStrategyRuntime(strategyResults),
            conflicts: conflicts,
            safetyEvalRuntime: safetyEvalRuntime,
            ruleIndexStats: safetySession.ruleIndexStats(),
            predicateCacheStats: safetySession.predicateCacheStats(),
            greenAuditorRuntime: safetySession.greenAuditorRuntime(),
            backlogFeasibility: backlogFeasibility,
            entitySnapshotsByID: entitySnapshotsByID,
            safetyDecisionsByEntityID: safetyDecisionsByEntityID,
            resolverRuntime: safetySession.resolverRuntimeReport(),
            entitySnapshotRuntime: safetySession.entitySnapshotRuntimeReport(),
            actionEvalRuntime: safetySession.actionEvalRuntimeReport(),
            runtimeBatchResolution: batchResult.report,
            runtimeResolutionNeed: needReport,
            runtimeObservationIndex: runtimeIndex.report(),
            runtimeIndexHandle: runtimeIndex,
            runtimeResolutionsByEntityID: batchResult.resolutions
        )
    }

    func initialVerification(for entity: DetectedEntity) -> VerificationAnnotation {
        VerificationAnnotation(
            provenanceConfidence: entity.annotation?.provenance.confidence ?? .unknown,
            unknownReasons: entity.annotation?.unknownReasons ?? []
        )
    }

    func finalizeResolvers(
        entity: inout DetectedEntity,
        evidence: inout EvidenceBundle,
        verification: inout VerificationAnnotation,
        context: VerificationLoopContext,
        cache: EvidenceResolutionCache
    ) {
        let sot = SourceOfTruthResolver.resolve(entity: entity.entity, annotation: entity.annotation, evidence: evidence)
        let regen = RegenerabilityResolver.resolve(entity: entity.entity, annotation: entity.annotation, evidence: evidence, sourceOfTruth: sot)
        evidence.sourceOfTruth = sot.value
        evidence.regenerable = regen.value
        evidence.predicateConfidence["not_source_of_truth"] = sot.confidence
        evidence.predicateConfidence["regenerable"] = regen.confidence
        if sot.value == .false, sot.confidence == .verified {
            evidence.predicateConfidence["not_source_of_truth"] = .verified
        }

        let related = VerificationStrategies.claudeRelatedPaths(entity: entity)
        let (active, activeConf, activeComp, activeReasons) = ActiveStateResolver.resolve(
            entityPath: entity.entity.path,
            associatedProcesses: entity.associatedProcesses,
            processes: context.processes,
            handles: context.handles,
            processCompleteness: entity.associatedProcesses.isEmpty ? .unknown : context.processCompleteness,
            handleCompleteness: context.handleCompleteness,
            relatedPaths: related
        )
        if var life = entity.annotation?.lifecycle {
            life.activeState = active
            life.unknownReasons.append(contentsOf: activeReasons)
            entity.annotation?.lifecycle = life
        }

        verification.sourceOfTruth = sot
        verification.regenerable = regen
        verification.activeState = active
        verification.activeStateConfidence = activeConf
        verification.activeStateCompleteness = activeComp
        verification.provenanceConfidence = entity.annotation?.provenance.confidence ?? .unknown
        verification.unknownReasons = (entity.annotation?.unknownReasons ?? []) + activeReasons + [sot.reasonCode, regen.reasonCode].compactMap { $0 }
        verification.reconstructionMechanism = regen.reasonCode
    }

    func applySnapshotConfidence(
        _ evidence: inout EvidenceBundle,
        entity: DetectedEntity,
        context: VerificationLoopContext,
        cache: EvidenceResolutionCache
    ) {
        evidence.observationCompleteness["process"] = entity.associatedProcesses.isEmpty ? .unknown : context.processCompleteness
        evidence.observationCompleteness["open_file"] = context.handleCompleteness
        let open = cache.openHandle(path: entity.entity.path, handles: context.handles)
        evidence.openFileHandle = open
        if context.handleCompleteness == .complete, open != .unknown {
            evidence.predicateConfidence["no_open_file_handle"] = .verified
        } else if context.handleCompleteness != .complete {
            evidence.openFileHandle = .unknown
            evidence.predicateConfidence["no_open_file_handle"] = .unknown
        }
        if !entity.associatedProcesses.isEmpty, context.processCompleteness == .complete, evidence.owningProcessRunning != .unknown {
            evidence.predicateConfidence["owning_process_not_running"] = .verified
        } else if !entity.associatedProcesses.isEmpty, context.processCompleteness != .complete {
            evidence.owningProcessRunning = .unknown
            evidence.predicateConfidence["owning_process_not_running"] = .unknown
        }
    }

    func dependencyBlockersFor(entity: DetectedEntity, verification: VerificationAnnotation) -> Set<VerificationClaimType> {
        var blockers: Set<VerificationClaimType> = []
        let rels = entity.annotation?.relationships ?? []
        let hasDerived = rels.contains {
            ($0.type == .derivedFrom || $0.type == .belongsToWorkspace) && $0.confidence == .verified
        }
        if !hasDerived, entity.entity.path.lowercased().contains("deriveddata") {
            blockers.insert(.derivedFrom)
        }
        if verification.sourceOfTruth.confidence != .verified,
           entity.entity.path.lowercased().contains("deriveddata") || entity.entity.path.lowercased().contains("node_modules") {
            blockers.insert(.sourceOfTruth)
        }
        return blockers
    }

    func byteHintsFor(detected: [DetectedEntity]) -> [String: Int64] {
        var hints: [String: Int64] = [:]
        for d in detected {
            let key = (d.entity.path as NSString).standardizingPath
            hints[key] = d.entity.logicalBytes
        }
        return hints
    }

    func backlogEntry(candidate: VerificationCandidate, attempted: Bool, result: String, reason: String?) -> EntityVerificationBacklogEntry {
        EntityVerificationBacklogEntry(
            entityID: candidate.entityID,
            path: candidate.canonicalPath,
            uniqueBytes: candidate.uniqueBytes,
            measurementKnown: candidate.measurementKnown,
            semanticLevel: candidate.semanticLevel,
            unresolvedClaim: candidate.unresolvedClaims.first?.rawValue ?? "UNKNOWN",
            priority: candidate.priority,
            estimatedProofCostMs: candidate.estimatedCostMs,
            availableStrategy: candidate.strategiesAvailable.first?.rawValue,
            attempted: attempted,
            result: result,
            blockingReason: reason
        )
    }

    func buildStrategyRuntime(_ results: [VerificationStrategyResult]) -> VerificationStrategyRuntimeReport {
        let grouped = Dictionary(grouping: results, by: { $0.strategyID.rawValue })
        let stats = grouped.map { id, rows -> VerificationStrategyRuntimeStat in
            let runtimes = rows.map(\.runtimeMs).sorted()
            let median = runtimes.isEmpty ? 0 : runtimes[runtimes.count / 2]
            return VerificationStrategyRuntimeStat(
                strategyID: id,
                attempts: rows.count,
                totalRuntimeMs: rows.reduce(0) { $0 + $1.runtimeMs },
                medianRuntimeMs: median,
                verifiedResults: rows.filter { $0.outcome == .verified }.count,
                unknownResults: rows.filter { $0.outcome == .unknown }.count,
                conflictResults: rows.filter { $0.outcome == .conflicted }.count,
                budgetFailures: rows.filter { $0.reasonCodes.contains("PROOF_BUDGET_EXCEEDED") }.count
            )
        }.sorted { $0.totalRuntimeMs > $1.totalRuntimeMs }
        return VerificationStrategyRuntimeReport(strategies: stats)
    }

    func msSince(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    func tally(_ totals: inout [String: [String: Int]], _ evidence: EvidenceBundle) {
        func add(_ key: String, _ value: PredicateValue) {
            totals[key, default: [:]][value.rawValue, default: 0] += 1
        }
        add("canonical_path", evidence.canonicalPath.isEmpty ? .unknown : .true)
        add("symlink", evidence.isSymlink)
        add("owner", evidence.ownerIsCurrentUser)
        add("open_file", evidence.openFileHandle)
        add("process", evidence.owningProcessRunning)
        add("source_of_truth", evidence.sourceOfTruth)
        add("regenerable", evidence.regenerable)
        add("manifest", evidence.manifestExists)
        add("lockfile", evidence.lockfileExists)
        add("cloud", evidence.cloudFileProvider)
    }
}

public enum VerificationLoopCoverageBuilder {
    public static func build(
        items: [ClassifiedItem],
        loopReport: EntityVerificationLoopReport,
        measurementCoverage: SizeMeasurementCoverageReport,
        semanticCoverage: SemanticCoverage
    ) -> VerificationLoopCoverageReport {
        let verification = VerificationCoverageBuilder.build(items)
        let attempted = loopReport.candidatesAttempted
        let verifiedEntities = Set(items.filter {
            ($0.verification?.sourceOfTruth.confidence == .verified)
                || ($0.verification?.regenerable.confidence == .verified)
                || ($0.verification?.activeStateConfidence == .verified)
        }.map { $0.detected.entity.id }).count
        let loopPct = items.isEmpty ? 0 : Double(attempted) / Double(items.count) * 100
        return VerificationLoopCoverageReport(
            measurementCoveragePercent: measurementCoverage.byteMeasurementCoveragePercent,
            semanticL3PlusPercent: semanticCoverage.l3PlusPercent,
            provenanceVerifiedPercent: verification.provenanceVerifiedPercent,
            verifiedRelationshipPercent: verification.verifiedRelationshipPercent,
            sourceOfTruthKnownPercent: verification.sourceOfTruthKnownPercent,
            regenerabilityKnownPercent: verification.regenerabilityKnownPercent,
            runtimeStateKnownPercent: verification.runtimeStateKnownPercent,
            verificationLoopCoveragePercent: loopPct,
            entitiesWithAttemptedProof: attempted,
            entitiesWithVerifiedClaim: verifiedEntities
        )
    }
}

public enum ClassificationChangeTracker {
    public static func compare(before: [ClassifiedItem], after: [ClassifiedItem]) -> [[String: String]] {
        let beforeMap = Dictionary(uniqueKeysWithValues: before.map { ($0.detected.entity.id, $0.decision.safetyClass.rawValue) })
        return after.compactMap { item -> [String: String]? in
            guard let prev = beforeMap[item.detected.entity.id], prev != item.decision.safetyClass.rawValue else { return nil }
            return [
                "entityID": item.detected.entity.id,
                "path": item.detected.entity.path,
                "before": prev,
                "after": item.decision.safetyClass.rawValue,
            ]
        }
    }
}
