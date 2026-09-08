import Foundation

public enum DetectorTier: String, Codable, Sendable, Equatable {
    case core = "CORE"
    case should = "SHOULD"
    case optInProof = "OPT_IN_PROOF"
}

public struct DetectorRuntimeStat: Codable, Sendable, Equatable {
    public var detectorID: String
    public var tier: DetectorTier
    public var domain: String
    public var invocationCount: Int
    public var matchCount: Int
    public var totalDurationMs: Int
    public var averageDurationMs: Double
    public var maxDurationMs: Int
    public var directoryMeasureCount: Int
    public var cacheHitCount: Int
    public var cacheMissCount: Int
    public var semanticBytesUpgraded: Int64
    public var semanticValuePerSecond: Double

    public init(
        detectorID: String,
        tier: DetectorTier,
        domain: String,
        invocationCount: Int = 1,
        matchCount: Int = 0,
        totalDurationMs: Int = 0,
        averageDurationMs: Double = 0,
        maxDurationMs: Int = 0,
        directoryMeasureCount: Int = 0,
        cacheHitCount: Int = 0,
        cacheMissCount: Int = 0,
        semanticBytesUpgraded: Int64 = 0,
        semanticValuePerSecond: Double = 0
    ) {
        self.detectorID = detectorID
        self.tier = tier
        self.domain = domain
        self.invocationCount = invocationCount
        self.matchCount = matchCount
        self.totalDurationMs = totalDurationMs
        self.averageDurationMs = averageDurationMs
        self.maxDurationMs = maxDurationMs
        self.directoryMeasureCount = directoryMeasureCount
        self.cacheHitCount = cacheHitCount
        self.cacheMissCount = cacheMissCount
        self.semanticBytesUpgraded = semanticBytesUpgraded
        self.semanticValuePerSecond = semanticValuePerSecond
    }
}

public struct DetectorCatalogStageStat: Codable, Sendable, Equatable {
    public var stage: String
    public var durationMs: Int
    public var entityCount: Int
    public var note: String?

    public init(stage: String, durationMs: Int, entityCount: Int = 0, note: String? = nil) {
        self.stage = stage
        self.durationMs = durationMs
        self.entityCount = entityCount
        self.note = note
    }
}

public struct DetectorCatalogRuntimeReport: Codable, Sendable, Equatable {
    public var totalDurationMs: Int
    public var stages: [DetectorCatalogStageStat]
    public var perDetector: [DetectorRuntimeStat]
    public var slowestDetectors: [DetectorRuntimeStat]
    public var top10SlowestOperations: [String]
    public var directorySizeCacheHits: Int
    public var directorySizeCacheMisses: Int
    public var directorySizeCacheSpawns: Int
    public var directorySizeCacheTimeouts: Int
    public var scannedNodeCacheHits: Int
    public var scannedNodeCacheMisses: Int
    public var metadataCacheHits: Int
    public var metadataCacheMisses: Int
    public var coreDetectors: [String]
    public var shouldDetectors: [String]
    public var optInProofDetectors: [String]
    public var repeatedFilesystemCallsAvoided: Int

    public static func build(
        stages: [DetectorCatalogStageStat],
        perDetector: [DetectorRuntimeStat],
        totalMs: Int
    ) -> DetectorCatalogRuntimeReport {
        let sorted = perDetector.sorted { $0.totalDurationMs > $1.totalDurationMs }
        let sizeStats = DirectorySizeCache.stats()
        let scanStats = ScannedNodeCache.stats()
        let metaStats = SharedMetadataCache.stats()
        let core = perDetector.filter { $0.tier == .core }.map(\.detectorID).sorted()
        let should = perDetector.filter { $0.tier == .should }.map(\.detectorID).sorted()
        let optIn = perDetector.filter { $0.tier == .optInProof }.map(\.detectorID).sorted()
        let avoided = sizeStats.hits + scanStats.hits + metaStats.hits
        return DetectorCatalogRuntimeReport(
            totalDurationMs: totalMs,
            stages: stages,
            perDetector: perDetector,
            slowestDetectors: Array(sorted.prefix(10)),
            top10SlowestOperations: sorted.prefix(10).map {
                "\($0.detectorID):\($0.totalDurationMs)ms matches=\($0.matchCount)"
            },
            directorySizeCacheHits: sizeStats.hits,
            directorySizeCacheMisses: sizeStats.spawns,
            directorySizeCacheSpawns: sizeStats.spawns,
            directorySizeCacheTimeouts: sizeStats.timeouts,
            scannedNodeCacheHits: scanStats.hits,
            scannedNodeCacheMisses: scanStats.misses,
            metadataCacheHits: metaStats.hits,
            metadataCacheMisses: metaStats.misses,
            coreDetectors: core,
            shouldDetectors: should,
            optInProofDetectors: optIn,
            repeatedFilesystemCallsAvoided: avoided
        )
    }
}

public final class DetectorCatalogTelemetry: @unchecked Sendable {
    private var stages: [DetectorCatalogStageStat] = []
    private var detectors: [DetectorRuntimeStat] = []
    private let lock = NSLock()

    public init() {}

    @discardableResult
    public func measureStage<T>(_ stage: String, entityCount: Int = 0, note: String? = nil, _ body: () -> T) -> T {
        let started = Date()
        let result = body()
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        lock.lock()
        stages.append(DetectorCatalogStageStat(stage: stage, durationMs: ms, entityCount: entityCount, note: note))
        lock.unlock()
        return result
    }

    public func recordDetector(
        id: String,
        tier: DetectorTier,
        domain: String,
        durationMs: Int,
        matchCount: Int,
        dirMeasures: Int,
        cacheHits: Int,
        cacheMisses: Int,
        semanticBytes: Int64 = 0
    ) {
        let avg = Double(durationMs)
        let valuePerSec = durationMs > 0 ? Double(semanticBytes) / (Double(durationMs) / 1000.0) : 0
        lock.lock()
        detectors.append(DetectorRuntimeStat(
            detectorID: id,
            tier: tier,
            domain: domain,
            matchCount: matchCount,
            totalDurationMs: durationMs,
            averageDurationMs: avg,
            maxDurationMs: durationMs,
            directoryMeasureCount: dirMeasures,
            cacheHitCount: cacheHits,
            cacheMissCount: cacheMisses,
            semanticBytesUpgraded: semanticBytes,
            semanticValuePerSecond: valuePerSec
        ))
        lock.unlock()
    }

    public func snapshot() -> DetectorCatalogRuntimeReport {
        lock.lock()
        let stageCopy = stages
        let detCopy = detectors
        lock.unlock()
        let total = stageCopy.map(\.durationMs).reduce(0, +)
        return DetectorCatalogRuntimeReport.build(stages: stageCopy, perDetector: detCopy, totalMs: total)
    }
}
