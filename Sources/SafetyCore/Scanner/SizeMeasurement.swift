import Foundation

public enum MeasurementQuality: String, Codable, Sendable, Equatable {
    case exact = "EXACT"
    case bounded = "BOUNDED"
    case partial = "PARTIAL"
    case unknown = "UNKNOWN"
}

public struct SizeMeasurement: Codable, Sendable, Equatable {
    public var bytes: Int64?
    public var quality: MeasurementQuality
    public var method: String
    public var complete: Bool
    public var timedOut: Bool
    public var reason: String?
    public var observedAt: Date

    public init(
        bytes: Int64?,
        quality: MeasurementQuality,
        method: String,
        complete: Bool = true,
        timedOut: Bool = false,
        reason: String? = nil,
        observedAt: Date = Date()
    ) {
        self.bytes = bytes
        self.quality = quality
        self.method = method
        self.complete = complete
        self.timedOut = timedOut
        self.reason = reason
        self.observedAt = observedAt
    }

    public var isKnown: Bool {
        guard let bytes, bytes >= 0 else { return false }
        return quality == .exact || quality == .bounded
    }

    public var accountingBytes: Int64 {
        switch quality {
        case .exact, .bounded:
            return isKnown ? (bytes ?? 0) : 0
        case .partial:
            return max(0, bytes ?? 0)
        case .unknown:
            return 0
        }
    }

    public static func exact(bytes: Int64, method: String) -> SizeMeasurement {
        SizeMeasurement(bytes: max(0, bytes), quality: .exact, method: method, complete: true)
    }

    public static func unknown(reason: String, timedOut: Bool = false, method: String = "unknown") -> SizeMeasurement {
        SizeMeasurement(bytes: nil, quality: .unknown, method: method, complete: false, timedOut: timedOut, reason: reason)
    }

    public static func partial(bytes: Int64?, reason: String, method: String) -> SizeMeasurement {
        SizeMeasurement(bytes: bytes, quality: .partial, method: method, complete: false, reason: reason)
    }
}

public struct ScanBudgetConfig: Codable, Sendable, Equatable {
    public var scannerRootBudgetMs: Int
    public var directoryMeasurementBudgetMs: Int
    public var maxDirectoryNodes: Int
    public var duTimeoutMs: Int
    public var folderDecomposerMaxChildren: Int
    public var maxConcurrentMeasurements: Int

    public static let `default` = ScanBudgetConfig(
        scannerRootBudgetMs: 60_000,
        directoryMeasurementBudgetMs: 4_000,
        maxDirectoryNodes: 500_000,
        duTimeoutMs: 3_000,
        folderDecomposerMaxChildren: 80,
        maxConcurrentMeasurements: 4
    )
}

public struct ScannerPathTiming: Codable, Sendable, Equatable {
    public var path: String
    public var operation: String
    public var durationMs: Int
    public var depth: Int
    public var childrenCount: Int
    public var measurementMode: String
    public var cacheHit: Bool
    public var timedOut: Bool
    public var bytesResult: Int64?
    public var measurementQuality: MeasurementQuality
    public var caller: String
}

public struct ScannerIODuplicationEntry: Codable, Sendable, Equatable {
    public var path: String
    public var operation: String
    public var count: Int
    public var estimatedDuplicatedRuntimeMs: Int
    public var callers: [String]
    public var cacheable: Bool
}

public struct ScannerBudgetEvent: Codable, Sendable, Equatable {
    public var event: String
    public var path: String?
    public var budgetMs: Int
    public var elapsedMs: Int
    public var note: String?
}

public struct ScannerRootTiming: Codable, Sendable, Equatable {
    public var rootPath: String
    public var durationMs: Int
    public var measurementQuality: MeasurementQuality
    public var bytes: Int64?
    public var timedOut: Bool
}

public struct ScannerFilesystemRuntimeReport: Codable, Sendable, Equatable {
    public var totalDurationMs: Int
    public var roots: [ScannerRootTiming]
    public var directoriesVisited: Int
    public var directoryEnumerations: Int
    public var sizeCalculations: Int
    public var metadataReads: Int
    public var cacheHits: Int
    public var cacheMisses: Int
    public var duSpawns: Int
    public var duTimeouts: Int
    public var budgetExceeded: Int
    public var errors: Int
    public var slowestPaths: [ScannerPathTiming]
}

public struct ScannerIODuplicationReport: Codable, Sendable, Equatable {
    public var entries: [ScannerIODuplicationEntry]
    public var totalDuplicatedOperations: Int
    public var estimatedDuplicatedRuntimeMs: Int
}

public struct SizeMeasurementCoverageReport: Codable, Sendable, Equatable {
    public var exactBytes: Int64
    public var boundedBytes: Int64
    public var partialBytes: Int64
    public var unknownMeasurementEntities: Int
    public var unknownMeasurementBytesEstimate: Int64
    public var byteMeasurementCoveragePercent: Double
    public var accountingCompletenessPercent: Double
    public var totalKnownUniqueBytes: Int64
    public var denominatorBytes: Int64
}

public struct P19RuntimeComparison: Codable, Sendable, Equatable {
    public var p18TotalSeconds: Double
    public var p19TotalSeconds: Double
    public var scannerFilesystemWalkP18Ms: Int
    public var scannerFilesystemWalkP19Ms: Int
    public var detectorCatalogP18Ms: Int
    public var detectorCatalogP19Ms: Int
    public var duSpawnsP19: Int
    public var duTimeoutsP19: Int
    public var duplicateMeasurementCountP19: Int
}
