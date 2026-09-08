import Foundation
import SafetyCore

public struct P304ScanPerformanceReport: Codable, Sendable, Equatable {
    public var baselineTimeToFirstHierarchyMs: Int
    public var timeToFirstUsefulMapMs: Int?
    public var timeToFirstHierarchyMs: Int?
    public var timeToPhysicalEnrichmentMs: Int?
    public var timeToSemanticEnrichmentMs: Int?
    public var timeToDecisionEnrichmentMs: Int?
    public var timeToSafetyEnrichmentMs: Int?
    public var totalScanMs: Int?
    public var measurementRequests: Int
    public var uniqueMeasurementKeys: Int
    /// Measurement-layer lookup hits. Same population as measurementRequests (excluding coalesced waits).
    public var measurementCacheHits: Int
    /// Measurement-layer provider invocations (misses).
    public var measurementCacheMisses: Int
    /// Aggregated cache hits across measurement + scanned-node layers (legacy/total).
    public var cacheHits: Int
    /// Aggregated cache misses across measurement + scanned-node layers (legacy/total).
    public var cacheMisses: Int
    public var nodeCacheHits: Int
    public var nodeCacheMisses: Int
    public var coalescedRequests: Int
    public var maxMeasurementConcurrency: Int
    public var metricSemantics: String
    public var rootMeasurementMs: Int?
    public var rootTimedOut: Bool
    public var firstMapAccountingBasis: String
    public var firstMapCoverage: String
    public var firstMapMappedBytes: Int64
    public var firstMapNodeCount: Int
    public var finalMapNodeCount: Int
    public var secondCrawlerAdded: Bool
    public var falseGREEN: Int
    public var duplicateEvaluations: Int
    public var primaryBottleneck: String
    public var generatedAt: Date

    public static let baselineFirstHierarchyMs = 48_560
}

public struct P304BeforeAfterReport: Codable, Sendable, Equatable {
    public var beforeFirstUsefulMap: Int
    public var afterFirstUsefulMap: Int?
    public var improvementMs: Int?
    public var improvementPercent: Double?
    public var beforeHierarchy: Int
    public var afterHierarchy: Int?
    public var beforeSafety: Int
    public var afterSafety: Int?
    public var architectureChanges: [String]
    public var truthSemanticsChanged: Bool
    public var safetySemanticsChanged: Bool
    public var generatedAt: Date
}

public enum P304ScanPerformanceBuilder {
    public static func performance(
        snapshot: StorageExplorerSnapshot,
        session: ScanSessionContext?,
        totalScanMs: Int?,
        falseGREEN: Int,
        duplicateEvaluations: Int,
        firstMapNodeCount: Int
    ) -> P304ScanPerformanceReport {
        let accounting = snapshot.mapAccounting ?? PhysicalMapAccountingResolver.resolve(for: snapshot.physicalRoot)
        let rootSpan = session?.performanceTrace.snapshot().first { $0.name == "root_measurement" }
        return P304ScanPerformanceReport(
            baselineTimeToFirstHierarchyMs: P304ScanPerformanceReport.baselineFirstHierarchyMs,
            timeToFirstUsefulMapMs: snapshot.telemetry.timeToFirstUsefulMapMs,
            timeToFirstHierarchyMs: snapshot.telemetry.timeToFirstHierarchyMs,
            timeToPhysicalEnrichmentMs: snapshot.telemetry.timeToPhysicalEnrichmentMs ?? snapshot.telemetry.timeToFirstHierarchyMs,
            timeToSemanticEnrichmentMs: snapshot.telemetry.timeToSemanticEnrichmentMs,
            timeToDecisionEnrichmentMs: snapshot.telemetry.timeToDecisionEnrichmentMs ?? snapshot.telemetry.timeToSafetyEnrichmentMs,
            timeToSafetyEnrichmentMs: snapshot.telemetry.timeToSafetyEnrichmentMs,
            totalScanMs: totalScanMs,
            measurementRequests: session?.measurementRequests ?? 0,
            uniqueMeasurementKeys: session?.uniqueMeasurementKeys ?? 0,
            measurementCacheHits: session?.measurementCacheHits ?? 0,
            measurementCacheMisses: session?.measurementCacheMisses ?? 0,
            cacheHits: session?.cacheHits ?? 0,
            cacheMisses: session?.cacheMisses ?? 0,
            nodeCacheHits: session?.nodeCacheHits ?? 0,
            nodeCacheMisses: session?.nodeCacheMisses ?? 0,
            coalescedRequests: session?.coalescedRequests ?? 0,
            maxMeasurementConcurrency: session?.maxMeasurementConcurrency ?? 1,
            metricSemantics: "measurementRequests counts measure() callers; measurementCacheHits+Misses cover size cache only; nodeCache* cover ScannedNode cache; cacheHits/Misses are aggregated totals across both layers; coalescedRequests are in-flight joins (not misses).",
            rootMeasurementMs: rootSpan?.durationMs,
            rootTimedOut: accounting.rootMeasurementStatus == .timeout,
            firstMapAccountingBasis: accounting.basis.rawValue,
            firstMapCoverage: accounting.coverage.rawValue,
            firstMapMappedBytes: accounting.reportMappedBytes,
            firstMapNodeCount: firstMapNodeCount,
            finalMapNodeCount: snapshot.telemetry.physicalNodeCount,
            secondCrawlerAdded: false,
            falseGREEN: falseGREEN,
            duplicateEvaluations: duplicateEvaluations,
            primaryBottleneck: "ROOT_DU_BLOCKING",
            generatedAt: Date()
        )
    }

    public static func beforeAfter(from report: P304ScanPerformanceReport) -> P304BeforeAfterReport {
        let beforeUseful = P304ScanPerformanceReport.baselineFirstHierarchyMs
        let afterUseful = report.timeToFirstUsefulMapMs
        let improvement = afterUseful.map { beforeUseful - $0 }
        let percent = improvement.map { Double($0) / Double(beforeUseful) * 100 }
        return P304BeforeAfterReport(
            beforeFirstUsefulMap: beforeUseful,
            afterFirstUsefulMap: afterUseful,
            improvementMs: improvement,
            improvementPercent: percent,
            beforeHierarchy: beforeUseful,
            afterHierarchy: report.timeToFirstHierarchyMs,
            beforeSafety: 157_000,
            afterSafety: report.timeToSafetyEnrichmentMs,
            architectureChanges: [
                "Root du no longer blocks first map publication",
                "Direct-child-first measurement with bounded concurrency",
                "In-flight measurement coalescing",
                "Progressive immutable explorer snapshots"
            ],
            truthSemanticsChanged: false,
            safetySemanticsChanged: false,
            generatedAt: Date()
        )
    }
}

final class ProgressiveScanBox: @unchecked Sendable {
    var telemetry: StorageExplorerTelemetry
    var firstMapNodeCount: Int = 0
    init(telemetry: StorageExplorerTelemetry) {
        self.telemetry = telemetry
    }
}
