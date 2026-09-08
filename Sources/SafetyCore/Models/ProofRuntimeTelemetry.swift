import Foundation

public struct ProofRuntimeStage: Codable, Sendable, Equatable {
    public var stage: String
    public var durationMs: Int
    public var entityCount: Int
    public var processSpawnCount: Int
    public var timeoutCount: Int
    public var budgetExceeded: Bool
    public var cacheHits: Int
    public var note: String?

    public init(
        stage: String,
        durationMs: Int,
        entityCount: Int = 0,
        processSpawnCount: Int = 0,
        timeoutCount: Int = 0,
        budgetExceeded: Bool = false,
        cacheHits: Int = 0,
        note: String? = nil
    ) {
        self.stage = stage
        self.durationMs = durationMs
        self.entityCount = entityCount
        self.processSpawnCount = processSpawnCount
        self.timeoutCount = timeoutCount
        self.budgetExceeded = budgetExceeded
        self.cacheHits = cacheHits
        self.note = note
    }
}

public struct ProofRuntimeBreakdown: Codable, Sendable, Equatable {
    public var totalMs: Int
    public var proofOverheadPercent: Double
    public var slowestStage: String?
    public var stages: [ProofRuntimeStage]
    public var slowestOperations: [String]
    public var timeoutsCount: Int
    public var budgetExceededCount: Int

    public init(
        totalMs: Int = 0,
        proofOverheadPercent: Double = 0,
        slowestStage: String? = nil,
        stages: [ProofRuntimeStage] = [],
        slowestOperations: [String] = [],
        timeoutsCount: Int = 0,
        budgetExceededCount: Int = 0
    ) {
        self.totalMs = totalMs
        self.proofOverheadPercent = proofOverheadPercent
        self.slowestStage = slowestStage
        self.stages = stages
        self.slowestOperations = slowestOperations
        self.timeoutsCount = timeoutsCount
        self.budgetExceededCount = budgetExceededCount
    }

    public static func build(stages: [ProofRuntimeStage], totalMs: Int) -> ProofRuntimeBreakdown {
        let sorted = stages.sorted { $0.durationMs > $1.durationMs }
        let proofStages: Set<String> = [
            "cursor_metadata_proof", "deriveddata_proof", "claude_observation_window",
            "node_modules_proof", "process_snapshot", "open_file_snapshot"
        ]
        let proofMs = stages.filter { proofStages.contains($0.stage) }.map(\.durationMs).reduce(0, +)
        let overhead = totalMs == 0 ? 0 : Double(proofMs) / Double(totalMs) * 100
        return ProofRuntimeBreakdown(
            totalMs: totalMs,
            proofOverheadPercent: overhead,
            slowestStage: sorted.first?.stage,
            stages: stages,
            slowestOperations: sorted.prefix(10).map { "\($0.stage):\($0.durationMs)ms" },
            timeoutsCount: stages.map(\.timeoutCount).reduce(0, +),
            budgetExceededCount: stages.filter(\.budgetExceeded).count
        )
    }
}

public final class ProofRuntimeTelemetry: @unchecked Sendable {
    private var stages: [ProofRuntimeStage] = []
    private let lock = NSLock()

    public init() {}

    @discardableResult
    public func measure<T>(_ stage: String, entityCount: Int = 0, spawn: Int = 0, _ body: () -> T) -> T {
        let started = Date()
        let result = body()
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        lock.lock()
        stages.append(ProofRuntimeStage(stage: stage, durationMs: ms, entityCount: entityCount, processSpawnCount: spawn))
        lock.unlock()
        return result
    }

    public func record(_ stage: ProofRuntimeStage) {
        lock.lock()
        stages.append(stage)
        lock.unlock()
    }

    public func snapshot() -> [ProofRuntimeStage] {
        lock.lock(); defer { lock.unlock() }
        return stages
    }
}

public struct ObservationSourceStats: Codable, Sendable, Equatable {
    public var source: String
    public var total: Int
    public var complete: Int
    public var partial: Int
    public var unknown: Int
    public var timeouts: Int
    public var permissionLimitations: Int
    public var budgetLimitations: Int
    public var errors: Int
    public var impact: String

    public init(
        source: String,
        total: Int = 0,
        complete: Int = 0,
        partial: Int = 0,
        unknown: Int = 0,
        timeouts: Int = 0,
        permissionLimitations: Int = 0,
        budgetLimitations: Int = 0,
        errors: Int = 0,
        impact: String = ""
    ) {
        self.source = source
        self.total = total
        self.complete = complete
        self.partial = partial
        self.unknown = unknown
        self.timeouts = timeouts
        self.permissionLimitations = permissionLimitations
        self.budgetLimitations = budgetLimitations
        self.errors = errors
        self.impact = impact
    }
}

public struct ObservationCompletenessReport: Codable, Sendable, Equatable {
    public var bySource: [ObservationSourceStats]
    public var negativeClaimsBlockedByIncompleteness: Int

    public init(bySource: [ObservationSourceStats] = [], negativeClaimsBlockedByIncompleteness: Int = 0) {
        self.bySource = bySource
        self.negativeClaimsBlockedByIncompleteness = negativeClaimsBlockedByIncompleteness
    }

    public static func build(
        items: [ClassifiedItem],
        processCompleteness: ObservationCompleteness,
        handleCompleteness: ObservationCompleteness,
        processFailure: String?,
        handleFailure: String?,
        cursorDiscovery: CursorMetadataDiscoveryReport?
    ) -> ObservationCompletenessReport {
        func bump(_ c: ObservationCompleteness, complete: inout Int, partial: inout Int, unknown: inout Int) {
            switch c {
            case .complete: complete += 1
            case .partial: partial += 1
            case .unknown: unknown += 1
            }
        }
        var procC = 0, procP = 0, procU = 0
        var openC = 0, openP = 0, openU = 0
        var blocked = 0
        for item in items {
            bump(item.verification?.activeStateCompleteness ?? .unknown, complete: &procC, partial: &procP, unknown: &procU)
            let openComp = item.detected.annotation?.lifecycle.activeState == .unknown && item.verification?.activeStateConfidence == .unknown
                ? ObservationCompleteness.unknown
                : (item.verification?.activeStateCompleteness ?? .unknown)
            bump(openComp, complete: &openC, partial: &openP, unknown: &openU)
            if item.verification?.activeState == .unknown,
               (item.verification?.unknownReasons ?? []).contains(where: { $0.contains("INCOMPLETE") || $0.contains("TIMEOUT") || $0.contains("PARTIAL") }) {
                blocked += 1
            }
        }
        let n = max(items.count, 1)
        var sources = [
            ObservationSourceStats(
                source: "PROCESS",
                total: n,
                complete: processCompleteness == .complete ? n : procC,
                partial: processCompleteness == .partial ? n : procP,
                unknown: processCompleteness == .unknown ? n : procU,
                timeouts: processFailure?.contains("TIMEOUT") == true ? 1 : 0,
                permissionLimitations: processFailure?.contains("PERMISSION") == true ? 1 : 0,
                impact: "ACTIVE/INACTIVE negative claims require COMPLETE"
            ),
            ObservationSourceStats(
                source: "OPEN_FILE",
                total: n,
                complete: handleCompleteness == .complete ? n : openC,
                partial: handleCompleteness == .partial ? n : openP,
                unknown: handleCompleteness == .unknown ? n : openU,
                timeouts: handleFailure?.contains("TIMEOUT") == true ? 1 : 0,
                permissionLimitations: handleFailure?.contains("PERMISSION") == true ? 1 : 0,
                impact: "open_file=false VERIFIED requires COMPLETE"
            ),
        ]
        if let d = cursorDiscovery {
            sources.append(ObservationSourceStats(
                source: "DB_QUERY",
                total: d.dbsQueried.count,
                complete: max(0, d.dbsQueried.count - d.timeouts),
                partial: d.budgetExceeded,
                unknown: d.timeouts,
                timeouts: d.timeouts,
                budgetLimitations: d.budgetExceeded,
                impact: "Cursor explicit metadata; timeout→UNKNOWN"
            ))
            sources.append(ObservationSourceStats(
                source: "METADATA",
                total: d.metadataSourcesFound.count,
                complete: d.verifiedMappings,
                partial: d.inferredMappings,
                unknown: d.unknownMappings,
                impact: "Cursor relationship confidence"
            ))
        }
        return ObservationCompletenessReport(bySource: sources, negativeClaimsBlockedByIncompleteness: blocked)
    }
}

/// Shared size cache to avoid N+1 du during proof enrichment.
enum DirectorySizeCache {
    nonisolated(unsafe) private static var map: [String: SizeMeasurement] = [:]
    nonisolated(unsafe) private static var hits: Int = 0
    nonisolated(unsafe) private static var spawns: Int = 0
    nonisolated(unsafe) private static var timeouts: Int = 0
    nonisolated(unsafe) private static var session: ScanSessionContext?

    static func bind(_ ctx: ScanSessionContext) { session = ctx }
    static func unbind() { session = nil }

    static func reset() {
        map = [:]
        hits = 0
        spawns = 0
        timeouts = 0
    }

    static func stats() -> (hits: Int, spawns: Int, timeouts: Int) {
        (hits, spawns, timeouts)
    }

    static func measurement(at path: String, caller: String = "DirectorySizeCache", timeoutSeconds: Double = 2.0) -> SizeMeasurement {
        if let session {
            return session.measure(path: path, caller: caller, timeoutSeconds: timeoutSeconds)
        }
        let key = (path as NSString).standardizingPath
        if let hit = map[key] {
            hits += 1
            return hit
        }
        spawns += 1
        if let bytes = QuickDirectorySizer.bytes(at: key, timeoutSeconds: timeoutSeconds) {
            let m = SizeMeasurement.exact(bytes: bytes, method: "bounded_du")
            map[key] = m
            return m
        }
        timeouts += 1
        let m = SizeMeasurement.unknown(reason: "DU_TIMEOUT", timedOut: true, method: "bounded_du")
        map[key] = m
        return m
    }

    static func bytes(at path: String, timeoutSeconds: Double = 2.0) -> Int64? {
        let m = measurement(at: path, timeoutSeconds: timeoutSeconds)
        return m.isKnown ? m.bytes : nil
    }
}

/// Avoid repeated scanNode / du on identical detector paths within one catalog run.
enum ScannedNodeCache {
    nonisolated(unsafe) private static var map: [String: ScannedNode] = [:]
    nonisolated(unsafe) private static var hits: Int = 0
    nonisolated(unsafe) private static var misses: Int = 0
    nonisolated(unsafe) private static var session: ScanSessionContext?

    static func bind(_ ctx: ScanSessionContext) { session = ctx }
    static func unbind() { session = nil }

    static func reset() {
        map = [:]
        hits = 0
        misses = 0
    }

    static func stats() -> (hits: Int, misses: Int) {
        (hits, misses)
    }

    static func getOrScan(path: String, scanner: ReadOnlyStorageScanner, caller: String = "ScannedNodeCache") -> ScannedNode? {
        if let session {
            return session.getOrScanNode(path: path, scanner: scanner, caller: caller)
        }
        let key = (PathGlob.expandHome(path) as NSString).standardizingPath
        if let hit = map[key] {
            hits += 1
            return hit
        }
        misses += 1
        guard let node = scanner.scanNode(path: path, caller: caller) else { return nil }
        map[key] = node
        return node
    }
}

/// Bounded shared metadata cache (existence, canonical path, small reads). Not for volatile runtime evidence.
enum SharedMetadataCache {
    nonisolated(unsafe) private static var existsMap: [String: Bool] = [:]
    nonisolated(unsafe) private static var canonicalMap: [String: String] = [:]
    nonisolated(unsafe) private static var smallFileMap: [String: Data] = [:]
    nonisolated(unsafe) private static var hits: Int = 0
    nonisolated(unsafe) private static var misses: Int = 0
    nonisolated(unsafe) private static var session: ScanSessionContext?
    static let maxSmallFiles = 512

    static func bind(_ ctx: ScanSessionContext) { session = ctx }
    static func unbind() { session = nil }

    static func reset() {
        existsMap = [:]
        canonicalMap = [:]
        smallFileMap = [:]
        hits = 0
        misses = 0
    }

    static func stats() -> (hits: Int, misses: Int) {
        (hits, misses)
    }

    static func pathExists(_ path: String) -> Bool {
        let key = (path as NSString).standardizingPath
        if let hit = existsMap[key] {
            hits += 1
            return hit
        }
        misses += 1
        let v = FileManager.default.fileExists(atPath: key)
        existsMap[key] = v
        return v
    }

    static func canonicalPath(_ path: String) -> String {
        let expanded = PathGlob.expandHome(path)
        if let hit = canonicalMap[expanded] {
            hits += 1
            return hit
        }
        misses += 1
        let v = (expanded as NSString).standardizingPath
        canonicalMap[expanded] = v
        return v
    }

    static func readSmallFile(at path: String, maxBytes: Int = 256_000) -> Data? {
        let key = (path as NSString).standardizingPath
        if let hit = smallFileMap[key] {
            hits += 1
            return hit
        }
        misses += 1
        guard smallFileMap.count < maxSmallFiles else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: key), options: [.mappedIfSafe]) else { return nil }
        let clipped = data.count > maxBytes ? data.prefix(maxBytes) : data
        let stored = Data(clipped)
        smallFileMap[key] = stored
        return stored
    }
}
