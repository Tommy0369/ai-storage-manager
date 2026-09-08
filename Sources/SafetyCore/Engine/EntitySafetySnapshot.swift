import Foundation

/// Immutable entity-level facts resolved once per SafetyEvalSession.
public struct EntitySafetySnapshot: Sendable {
    public var entityID: String
    public var entity: StorageEntity
    public var detected: DetectedEntity
    public var evidence: EvidenceBundle
    public var state: RuntimeState
    public var verification: VerificationAnnotation
    public var predicates: EntityPredicateSnapshot
    public var relationships: [EntityRelationship]
    public var cacheKey: EntitySnapshotCacheKey
    public var finalizedAt: Date
    public var finalizationMs: Int
}

/// Static / entity predicates computed once — tri-state preserved via ObservationRecord.
public struct EntityPredicateSnapshot: Sendable, Equatable {
    public var sourceOfTruth: ObservationRecord
    public var regenerability: ObservationRecord
    public var activeState: ObservedActiveState
    public var activeStateConfidence: EvidenceConfidence
    public var openFileHandle: PredicateValue
    public var openFileConfidence: EvidenceConfidence
    public var isGitRepository: Bool
    public var isApplicationManaged: Bool
    public var isDerivedData: Bool
    public var isUserOwnedVerified: Bool
    public var hasEvidenceConflict: Bool
    public var hasCanonicalPath: Bool
    public var isSymlinkAmbiguity: Bool
    public var isUserOriginal: Bool
    public var isGeneratedArtifact: Bool
    public var isInsideProtectedRoot: Bool
    public var fileProviderBacked: Bool
    public var remoteBackingVerified: Bool
    public var syncSafeVerified: Bool
}

public struct EntitySnapshotCacheKey: Hashable, Sendable {
    public var entityID: String
    public var evidenceVersion: Int
    public var verificationGeneration: Int
    public var runtimeGeneration: Int
}

extension VerificationAnnotation {
    var snapshotGeneration: Int {
        var hasher = Hasher()
        hasher.combine(sourceOfTruth.value.rawValue)
        hasher.combine(sourceOfTruth.confidence.rawValue)
        hasher.combine(regenerable.value.rawValue)
        hasher.combine(regenerable.confidence.rawValue)
        hasher.combine(activeState.rawValue)
        hasher.combine(activeStateConfidence.rawValue)
        return hasher.finalize()
    }
}

public enum RuntimeSnapshotGeneration {
    public static func from(context: VerificationLoopContext) -> Int {
        var hasher = Hasher()
        hasher.combine(context.processCompleteness.rawValue)
        hasher.combine(context.handleCompleteness.rawValue)
        return hasher.finalize()
    }
}

public struct ResolverRuntimeStat: Codable, Sendable, Equatable {
    public var resolver: String
    public var invocations: Int
    public var uniqueEntities: Int
    public var cacheHits: Int
    public var cacheMisses: Int
    public var totalRuntimeMs: Int
    public var medianRuntimeMs: Int
    public var p95RuntimeMs: Int
    public var slowestEntities: [String]
    public var unknownResults: Int
    public var verifiedResults: Int
    public var conflictedResults: Int
}

public struct ResolverRuntimeReport: Codable, Sendable, Equatable {
    public var resolvers: [ResolverRuntimeStat]
}

public struct EntitySnapshotSlowRecord: Codable, Sendable, Equatable {
    public var entityID: String
    public var path: String
    public var durationMs: Int
    public var resolverContributionMs: Int
}

public struct EntitySafetySnapshotRuntimeReport: Codable, Sendable, Equatable {
    public var entitiesFinalized: Int
    public var snapshotsCreated: Int
    public var snapshotCacheHits: Int
    public var snapshotCacheMisses: Int
    public var averageFinalizationMs: Double
    public var p95FinalizationMs: Int
    public var slowestEntities: [EntitySnapshotSlowRecord]
    public var resolverContributionMs: Int
}

public struct ActionEvalRuntimeStat: Codable, Sendable, Equatable {
    public var action: String
    public var entitiesEvaluated: Int
    public var averageRules: Double
    public var predicateSnapshotReuse: Int
    public var resolverReuse: Int
    public var totalRuntimeMs: Int
}

public struct ActionEvalRuntimeReport: Codable, Sendable, Equatable {
    public var actions: [ActionEvalRuntimeStat]
    public var totalActionsEvaluated: Int
    public var snapshotReuseCount: Int
}

public struct P112RuntimeComparison: Codable, Sendable, Equatable {
    public var p111TotalSeconds: Double
    public var p112TotalSeconds: Double
    public var safetyEvalP111Ms: Int
    public var safetyEvalP112Ms: Int
    public var entityVerificationLoopP111Ms: Int
    public var entityVerificationLoopP112Ms: Int
    public var proofExecutionP112Ms: Int
    public var snapshotFinalizationP112Ms: Int
    public var resolverTimeP112Ms: Int
    public var actionPredicateP112Ms: Int
    public var greenAuditorP112Ms: Int
    public var reportGenerationP112Ms: Int
}

extension P112RuntimeComparison {
    public static let p111Baseline = P112RuntimeComparison(
        p111TotalSeconds: 87.1,
        p112TotalSeconds: 0,
        safetyEvalP111Ms: 25_460,
        safetyEvalP112Ms: 0,
        entityVerificationLoopP111Ms: 31_000,
        entityVerificationLoopP112Ms: 0,
        proofExecutionP112Ms: 0,
        snapshotFinalizationP112Ms: 0,
        resolverTimeP112Ms: 0,
        actionPredicateP112Ms: 0,
        greenAuditorP112Ms: 0,
        reportGenerationP112Ms: 0
    )
}

struct ResolverInvocationRecord {
    var entityID: String
    var durationMs: Int
    var outcome: String
}

struct ResolverRuntimeTracker {
    var records: [String: [ResolverInvocationRecord]] = [:]
    var cacheHits: [String: Int] = [:]
    var cacheMisses: [String: Int] = [:]
    var uniqueEntities: [String: Set<String>] = [:]

    mutating func recordHit(resolver: String, entityID: String) {
        cacheHits[resolver, default: 0] += 1
        uniqueEntities[resolver, default: []].insert(entityID)
    }

    mutating func recordMiss(
        resolver: String,
        entityID: String,
        durationMs: Int,
        outcome: String
    ) {
        cacheMisses[resolver, default: 0] += 1
        uniqueEntities[resolver, default: []].insert(entityID)
        records[resolver, default: []].append(
            ResolverInvocationRecord(entityID: entityID, durationMs: durationMs, outcome: outcome)
        )
    }

    func report() -> ResolverRuntimeReport {
        let names = Set(records.keys).union(cacheHits.keys).union(cacheMisses.keys).sorted()
        let stats = names.map { name -> ResolverRuntimeStat in
            let rows = records[name] ?? []
            let runtimes = rows.map(\.durationMs).sorted()
            let median = runtimes.isEmpty ? 0 : runtimes[runtimes.count / 2]
            let p95Index = runtimes.isEmpty ? 0 : min(runtimes.count - 1, Int(Double(runtimes.count) * 0.95))
            let p95 = runtimes.isEmpty ? 0 : runtimes[p95Index]
            let slowest = Dictionary(grouping: rows, by: \.entityID)
                .mapValues { $0.reduce(0) { $0 + $1.durationMs } }
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map(\.key)
            return ResolverRuntimeStat(
                resolver: name,
                invocations: (cacheHits[name] ?? 0) + (cacheMisses[name] ?? 0),
                uniqueEntities: uniqueEntities[name]?.count ?? 0,
                cacheHits: cacheHits[name] ?? 0,
                cacheMisses: cacheMisses[name] ?? 0,
                totalRuntimeMs: runtimes.reduce(0, +),
                medianRuntimeMs: median,
                p95RuntimeMs: p95,
                slowestEntities: slowest,
                unknownResults: rows.filter { $0.outcome == "UNKNOWN" }.count,
                verifiedResults: rows.filter { $0.outcome == "VERIFIED" }.count,
                conflictedResults: rows.filter { $0.outcome == "CONFLICTED" }.count
            )
        }
        return ResolverRuntimeReport(resolvers: stats)
    }
}

struct EntitySnapshotRuntimeTracker {
    var finalized = 0
    var created = 0
    var cacheHits = 0
    var cacheMisses = 0
    var finalizationMs: [Int] = []
    var slowRecords: [EntitySnapshotSlowRecord] = []
    var resolverContributionMs = 0

    mutating func recordCreated(entityID: String, path: String, ms: Int, resolverMs: Int) {
        finalized += 1
        created += 1
        cacheMisses += 1
        finalizationMs.append(ms)
        resolverContributionMs += resolverMs
        slowRecords.append(EntitySnapshotSlowRecord(
            entityID: entityID,
            path: path,
            durationMs: ms,
            resolverContributionMs: resolverMs
        ))
    }

    mutating func recordHit() {
        finalized += 1
        cacheHits += 1
    }

    func report() -> EntitySafetySnapshotRuntimeReport {
        let sorted = finalizationMs.sorted()
        let avg = sorted.isEmpty ? 0 : Double(sorted.reduce(0, +)) / Double(sorted.count)
        let p95Index = sorted.isEmpty ? 0 : min(sorted.count - 1, Int(Double(sorted.count) * 0.95))
        let p95 = sorted.isEmpty ? 0 : sorted[p95Index]
        return EntitySafetySnapshotRuntimeReport(
            entitiesFinalized: finalized,
            snapshotsCreated: created,
            snapshotCacheHits: cacheHits,
            snapshotCacheMisses: cacheMisses,
            averageFinalizationMs: avg,
            p95FinalizationMs: p95,
            slowestEntities: slowRecords.sorted { $0.durationMs > $1.durationMs }.prefix(20).map { $0 },
            resolverContributionMs: resolverContributionMs
        )
    }
}

struct ActionEvalRuntimeTracker {
    var byAction: [String: ActionEvalAccumulator] = [:]
    var totalActionsEvaluated = 0
    var snapshotReuseCount = 0

    mutating func record(action: ActionMode, rulesConsidered: Int, reusedSnapshot: Bool, resolverReuse: Bool, ms: Int) {
        let key = action.rawValue
        var acc = byAction[key] ?? ActionEvalAccumulator()
        acc.entities += 1
        acc.rules += rulesConsidered
        if reusedSnapshot { acc.predicateReuse += 1 }
        if resolverReuse { acc.resolverReuse += 1 }
        acc.totalMs += ms
        byAction[key] = acc
        totalActionsEvaluated += 1
        if reusedSnapshot { snapshotReuseCount += 1 }
    }

    func report() -> ActionEvalRuntimeReport {
        ActionEvalRuntimeReport(
            actions: byAction.map { action, acc in
                ActionEvalRuntimeStat(
                    action: action,
                    entitiesEvaluated: acc.entities,
                    averageRules: acc.entities == 0 ? 0 : Double(acc.rules) / Double(acc.entities),
                    predicateSnapshotReuse: acc.predicateReuse,
                    resolverReuse: acc.resolverReuse,
                    totalRuntimeMs: acc.totalMs
                )
            }.sorted { $0.action < $1.action },
            totalActionsEvaluated: totalActionsEvaluated,
            snapshotReuseCount: snapshotReuseCount
        )
    }
}

struct ActionEvalAccumulator {
    var entities = 0
    var rules = 0
    var predicateReuse = 0
    var resolverReuse = 0
    var totalMs = 0
}
