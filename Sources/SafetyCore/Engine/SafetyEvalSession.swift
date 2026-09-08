import Foundation

public struct SafetyEvalRuntimeReport: Codable, Sendable, Equatable {
    public var totalEvaluations: Int
    public var entitiesEvaluated: Int
    public var actionsEvaluated: Int
    public var rulesConsidered: Int
    public var rulesActuallyEvaluated: Int
    public var predicateEvaluations: Int
    public var predicatesSkippedByShortCircuit: Int
    public var auditorInvocations: Int
    public var auditorSkippedNonGreen: Int
    public var fullGreenAudits: Int
    public var resultCacheHits: Int
    public var resultCacheMisses: Int
    public var entitySnapshotCacheHits: Int
    public var entitySnapshotCacheMisses: Int
    public var snapshotsCreated: Int
    public var staticPredicatesComputed: Int
    public var staticPredicateReuse: Int
    public var ruleLookupMs: Int
    public var predicateEvaluationMs: Int
    public var scoreCalculationMs: Int
    public var greenAuditorMs: Int
    public var reportConstructionMs: Int
    public var snapshotFinalizationMs: Int
    public var totalSafetyEvalMs: Int
    public var averageRulesPerEntity: Double
    public var topSlowEvaluations: [SafetyEvalSlowRecord]
    public var referenceEquivalenceChecks: Int
    public var referenceEquivalenceMismatches: Int
}

public struct SafetyEvalSlowRecord: Codable, Sendable, Equatable {
    public var entityID: String
    public var action: String
    public var durationMs: Int
}

public struct PredicateCacheStats: Codable, Sendable, Equatable {
    public var hits: Int
    public var misses: Int
    public var staticHits: Int
    public var runtimeHits: Int
}

public struct GreenAuditorRuntimeReport: Codable, Sendable, Equatable {
    public var invocations: Int
    public var skippedNonGreen: Int
    public var fullAudits: Int
    public var downgrades: Int
    public var totalMs: Int
}

public struct SafetyEvalSession {
    public var engine: SafetyRuleEngine
    public private(set) var index: SafetyRuleIndex
    var profiler: SafetyEvalProfiler
    public var verifyReferenceEquivalence: Bool

    private var resultCache: [SafetyResultCacheKey: SafetyDecision] = [:]
    private var ruleCandidateCache: [RuleCandidateKey: [SafetyRule]] = [:]
    private var predicateMemo: [PredicateMemoKey: PredicateValue] = [:]
    private var predicateConfidenceMemo: [PredicateMemoKey: EvidenceConfidence] = [:]
    private var entitySnapshots: [EntitySnapshotCacheKey: EntitySafetySnapshot] = [:]
    private var greenAuditor: GreenCandidateAuditor
    var resolverTracker = ResolverRuntimeTracker()
    var snapshotTracker = EntitySnapshotRuntimeTracker()
    var actionEvalTracker = ActionEvalRuntimeTracker()

    public init(
        knowledge: KnowledgeBaseDocument,
        protection: UserProtectionStore = UserProtectionStore(),
        verifyReferenceEquivalence: Bool = false
    ) {
        self.engine = SafetyRuleEngine(knowledge: knowledge, protection: protection, loader: KnowledgeBaseLoader())
        self.index = SafetyRuleIndex(knowledge: knowledge, loader: engine.loader)
        self.profiler = SafetyEvalProfiler()
        self.verifyReferenceEquivalence = verifyReferenceEquivalence
        self.greenAuditor = GreenCandidateAuditor(knowledge: knowledge)
    }

    public mutating func finalizeSnapshot(
        entity: inout DetectedEntity,
        evidence: inout EvidenceBundle,
        verification: inout VerificationAnnotation,
        context: VerificationLoopContext,
        cache: EvidenceResolutionCache,
        runtimeResolution: RuntimeStateResolution? = nil,
        runtimeIndex: RuntimeObservationIndex? = nil
    ) -> EntitySafetySnapshot {
        let key = EntitySnapshotCacheKey(
            entityID: entity.entity.id,
            evidenceVersion: evidence.snapshotVersion,
            verificationGeneration: verification.snapshotGeneration,
            runtimeGeneration: RuntimeSnapshotGeneration.from(context: context)
        )
        if let cached = entitySnapshots[key] {
            snapshotTracker.recordHit()
            profiler.entitySnapshotCacheHits += 1
            profiler.staticPredicateReuse += 1
            entity = cached.detected
            evidence = cached.evidence
            verification = cached.verification
            return cached
        }

        profiler.entitySnapshotCacheMisses += 1
        let started = Date()
        let predicates = EntitySafetySnapshotBuilder.build(
            entity: &entity,
            evidence: &evidence,
            verification: &verification,
            context: context,
            cache: cache,
            resolverTracker: &resolverTracker,
            runtimeResolution: runtimeResolution,
            runtimeIndex: runtimeIndex
        )
        let resolverMs = msSince(started)
        let finalizationMs = resolverMs
        profiler.snapshotFinalizationMs += finalizationMs
        profiler.staticPredicatesComputed += 1

        let state = RuntimeState(
            hasOpenHandles: evidence.openFileHandle == .true,
            owningProcessRunning: evidence.owningProcessRunning == .true,
            lockPresent: evidence.extra["lockfile_present"] == .true
        )
        let snapshot = EntitySafetySnapshot(
            entityID: entity.entity.id,
            entity: entity.entity,
            detected: entity,
            evidence: evidence,
            state: state,
            verification: verification,
            predicates: predicates,
            relationships: entity.annotation?.relationships ?? [],
            cacheKey: key,
            finalizedAt: Date(),
            finalizationMs: finalizationMs
        )
        entitySnapshots[key] = snapshot
        snapshotTracker.recordCreated(
            entityID: entity.entity.id,
            path: entity.entity.path,
            ms: finalizationMs,
            resolverMs: finalizationMs
        )
        return snapshot
    }

    public mutating func evaluateActions(
        snapshot: EntitySafetySnapshot,
        includeCloudVariants: Bool
    ) -> (primary: SafetyDecision, variants: [String: String], decisions: [ActionMode: SafetyDecision], actionsEvaluated: Int) {
        var decisions: [ActionMode: SafetyDecision] = [:]
        var actionsEvaluated = 0

        let userReview = evaluateSnapshotAction(snapshot: snapshot, action: .userReview)
        decisions[.userReview] = userReview
        actionsEvaluated += 1
        var variants = ["USER_REVIEW": userReview.safetyClass.rawValue]

        if includeCloudVariants {
            let del = evaluateSnapshotAction(snapshot: snapshot, action: .moveToTrash)
            let evict = evaluateSnapshotAction(snapshot: snapshot, action: .cloudEvictOnly)
            decisions[.moveToTrash] = del
            decisions[.cloudEvictOnly] = evict
            actionsEvaluated += 2
            variants["DELETE"] = del.safetyClass.rawValue
            variants["CLOUD_EVICT_ONLY"] = evict.safetyClass.rawValue
        }

        return (userReview, variants, decisions, actionsEvaluated)
    }

    mutating func evaluateSnapshotAction(snapshot: EntitySafetySnapshot, action: ActionMode) -> SafetyDecision {
        let started = Date()
        let rules = index.matchingRules(for: snapshot.entity.path).count
        let decision = evaluate(EvaluationRequest(
            entity: snapshot.entity,
            intendedAction: action,
            evidence: snapshot.evidence,
            state: snapshot.state
        ))
        actionEvalTracker.record(
            action: action,
            rulesConsidered: rules,
            reusedSnapshot: true,
            resolverReuse: true,
            ms: msSince(started)
        )
        return decision
    }

    public mutating func evaluate(_ request: EvaluationRequest) -> SafetyDecision {
        let key = SafetyResultCacheKey(request: request)
        if let cached = resultCache[key] {
            profiler.resultCacheHits += 1
            return cached
        }
        profiler.resultCacheMisses += 1

        let started = Date()
        var decision = engine.evaluate(request, index: &index, profiler: &profiler)
        if verifyReferenceEquivalence {
            let reference = engine.evaluateReference(request)
            profiler.referenceEquivalenceChecks += 1
            if !SafetyDecision.equivalentForTests(decision, reference) {
                profiler.referenceEquivalenceMismatches += 1
                decision = reference
            }
        }
        profiler.ruleLookupMs += msSince(started)
        resultCache[key] = decision
        return decision
    }

    public mutating func audit(
        item: ClassifiedItem,
        evidence: EvidenceBundle,
        state: RuntimeState
    ) -> (SafetyDecision, GreenAuditRecord?) {
        let started = Date()
        profiler.auditorInvocations += 1
        if item.decision.safetyClass != .green {
            profiler.auditorSkippedNonGreen += 1
            profiler.greenAuditorMs += msSince(started)
            return (item.decision, nil)
        }
        profiler.fullGreenAudits += 1
        let result = greenAuditor.audit(item: item, evidence: evidence, state: state)
        if result.1.downgradedFromGreen { profiler.auditorDowngrades += 1 }
        profiler.greenAuditorMs += msSince(started)
        return result
    }

    public mutating func memoizedPredicateValue(_ name: String, evidence: EvidenceBundle, isRuntime: Bool) -> PredicateValue {
        let key = PredicateMemoKey(name: name, evidenceVersion: evidence.snapshotVersion, isRuntime: isRuntime)
        if let hit = predicateMemo[key] {
            profiler.predicateCacheHits += 1
            if isRuntime { profiler.runtimePredicateHits += 1 } else { profiler.staticPredicateHits += 1 }
            profiler.staticPredicateReuse += 1
            return hit
        }
        profiler.predicateCacheMisses += 1
        let value = evidence.value(for: name)
        predicateMemo[key] = value
        return value
    }

    public func runtimeReport(totalMs: Int, entities: Int, actions: Int) -> SafetyEvalRuntimeReport {
        let considered = index.stats.rulesConsideredTotal
        return SafetyEvalRuntimeReport(
            totalEvaluations: profiler.totalEvaluations,
            entitiesEvaluated: entities,
            actionsEvaluated: actions,
            rulesConsidered: considered,
            rulesActuallyEvaluated: considered,
            predicateEvaluations: profiler.predicateEvaluations,
            predicatesSkippedByShortCircuit: profiler.predicatesSkippedByShortCircuit,
            auditorInvocations: profiler.auditorInvocations,
            auditorSkippedNonGreen: profiler.auditorSkippedNonGreen,
            fullGreenAudits: profiler.fullGreenAudits,
            resultCacheHits: profiler.resultCacheHits,
            resultCacheMisses: profiler.resultCacheMisses,
            entitySnapshotCacheHits: profiler.entitySnapshotCacheHits,
            entitySnapshotCacheMisses: profiler.entitySnapshotCacheMisses,
            snapshotsCreated: snapshotTracker.created,
            staticPredicatesComputed: profiler.staticPredicatesComputed,
            staticPredicateReuse: profiler.staticPredicateReuse,
            ruleLookupMs: profiler.ruleLookupMs,
            predicateEvaluationMs: profiler.predicateEvaluationMs,
            scoreCalculationMs: profiler.scoreCalculationMs,
            greenAuditorMs: profiler.greenAuditorMs,
            reportConstructionMs: profiler.reportConstructionMs,
            snapshotFinalizationMs: profiler.snapshotFinalizationMs,
            totalSafetyEvalMs: totalMs,
            averageRulesPerEntity: entities == 0 ? 0 : Double(considered) / Double(entities),
            topSlowEvaluations: profiler.slowRecords.sorted { $0.durationMs > $1.durationMs }.prefix(20).map { $0 },
            referenceEquivalenceChecks: profiler.referenceEquivalenceChecks,
            referenceEquivalenceMismatches: profiler.referenceEquivalenceMismatches
        )
    }

    public func predicateCacheStats() -> PredicateCacheStats {
        PredicateCacheStats(
            hits: profiler.predicateCacheHits,
            misses: profiler.predicateCacheMisses,
            staticHits: profiler.staticPredicateHits,
            runtimeHits: profiler.runtimePredicateHits
        )
    }

    public func greenAuditorRuntime() -> GreenAuditorRuntimeReport {
        GreenAuditorRuntimeReport(
            invocations: profiler.auditorInvocations,
            skippedNonGreen: profiler.auditorSkippedNonGreen,
            fullAudits: profiler.fullGreenAudits,
            downgrades: profiler.auditorDowngrades,
            totalMs: profiler.greenAuditorMs
        )
    }

    public func ruleIndexStats() -> SafetyRuleIndexStats { index.stats }

    public func resolverRuntimeReport() -> ResolverRuntimeReport { resolverTracker.report() }

    public func entitySnapshotRuntimeReport() -> EntitySafetySnapshotRuntimeReport { snapshotTracker.report() }

    public func actionEvalRuntimeReport() -> ActionEvalRuntimeReport { actionEvalTracker.report() }

    private func msSince(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}

struct SafetyResultCacheKey: Hashable {
    var entityID: String
    var action: String
    var evidenceVersion: Int
    var stateKey: String

    init(request: EvaluationRequest) {
        entityID = request.entity.id
        action = request.intendedAction.rawValue
        evidenceVersion = request.evidence.snapshotVersion
        stateKey = "\(request.state.hasOpenHandles)|\(request.state.owningProcessRunning)|\(request.state.lockPresent)"
    }
}

struct PredicateMemoKey: Hashable {
    var name: String
    var evidenceVersion: Int
    var isRuntime: Bool
}

struct SafetyEvalProfiler {
    var totalEvaluations: Int = 0
    var predicateEvaluations: Int = 0
    var predicatesSkippedByShortCircuit: Int = 0
    var resultCacheHits: Int = 0
    var resultCacheMisses: Int = 0
    var entitySnapshotCacheHits: Int = 0
    var entitySnapshotCacheMisses: Int = 0
    var staticPredicatesComputed: Int = 0
    var staticPredicateReuse: Int = 0
    var snapshotFinalizationMs: Int = 0
    var ruleLookupMs: Int = 0
    var predicateEvaluationMs: Int = 0
    var scoreCalculationMs: Int = 0
    var greenAuditorMs: Int = 0
    var reportConstructionMs: Int = 0
    var auditorInvocations: Int = 0
    var auditorSkippedNonGreen: Int = 0
    var fullGreenAudits: Int = 0
    var auditorDowngrades: Int = 0
    var predicateCacheHits: Int = 0
    var predicateCacheMisses: Int = 0
    var staticPredicateHits: Int = 0
    var runtimePredicateHits: Int = 0
    var referenceEquivalenceChecks: Int = 0
    var referenceEquivalenceMismatches: Int = 0
    var slowRecords: [SafetyEvalSlowRecord] = []
}

extension EvidenceBundle {
    var snapshotVersion: Int {
        var hasher = Hasher()
        hasher.combine(canonicalPath)
        hasher.combine(sourceOfTruth.rawValue)
        hasher.combine(regenerable.rawValue)
        hasher.combine(openFileHandle.rawValue)
        hasher.combine(owningProcessRunning.rawValue)
        hasher.combine(syncWouldDeleteRemote.rawValue)
        hasher.combine(isSymlink.rawValue)
        return hasher.finalize()
    }
}

extension SafetyDecision {
    static func equivalentForTests(_ lhs: SafetyDecision, _ rhs: SafetyDecision) -> Bool {
        lhs.safetyClass == rhs.safetyClass
            && lhs.action == rhs.action
            && lhs.matchedRuleID == rhs.matchedRuleID
            && lhs.evaluationLayer == rhs.evaluationLayer
            && Set(lhs.reasonCodes) == Set(rhs.reasonCodes)
    }
}
