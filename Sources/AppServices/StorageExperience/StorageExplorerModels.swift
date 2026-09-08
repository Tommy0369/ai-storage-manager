import Foundation
import SafetyCore

public enum StorageMapLens: String, Codable, Sendable, CaseIterable, Identifiable {
    case structure = "STRUCTURE"
    case meaning = "MEANING"
    case decision = "DECISION"

    public var id: String { rawValue }

    /// v0.2 UX FIX 001 — human-readable presentation label.
    ///
    /// Presentation only. `rawValue` stays STRUCTURE / MEANING / DECISION and is
    /// what every model, report and test keys off.
    public var title: String {
        switch self {
        case .structure: return L10n.t("lens.structure")
        case .meaning: return L10n.t("lens.meaning")
        case .decision: return L10n.t("lens.decision")
        }
    }

    public var question: String {
        switch self {
        case .structure: return "Where is the space?"
        case .meaning: return "What kind of data is this?"
        case .decision: return "What can I do about it?"
        }
    }
}

public enum StorageScanStage: String, Codable, Sendable {
    case idle
    case scanningFiles
    case hierarchyAvailable
    case understandingStorage
    case checkingSafety
    case complete
    case failed
}

public enum MapReadiness: String, Codable, Sendable, Equatable {
    case notReady = "NOT_READY"
    case structureReadyPartial = "STRUCTURE_READY_PARTIAL"
    case structureReadyMeasured = "STRUCTURE_READY_MEASURED"
    case semanticEnriched = "SEMANTIC_ENRICHED"
    case decisionEnriched = "DECISION_ENRICHED"
    case complete = "COMPLETE"
}

public struct StorageNodeDecisionSummary: Codable, Sendable, Equatable {
    public var state: StoragePresentationState
    public var label: String
    public var iconHint: String
    public var entityID: String?
    public var source: String

    public static var none: StorageNodeDecisionSummary {
        StorageNodeDecisionSummary(
            state: .noRecommendation,
            label: L10n.t("decision.noRecommendation.title"),
            iconHint: "minus.circle",
            entityID: nil,
            source: "none"
        )
    }

    public init(
        state: StoragePresentationState,
        label: String,
        iconHint: String,
        entityID: String?,
        source: String
    ) {
        self.state = state
        self.label = label
        self.iconHint = iconHint
        self.entityID = entityID
        self.source = source
    }
}

public struct StorageNodePresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var physical: PhysicalStorageNode
    public var title: String
    public var location: String
    public var whatIsThis: String
    public var whyLarge: String?
    public var semanticCategory: ProductStorageCategory
    public var decision: StorageNodeDecisionSummary
    public var children: [StorageNodePresentation]
    public var technicalEntityID: String?
    public var structureColorKey: String

    public var bytes: Int64 { physical.bytes }
    public var bytesKnown: Bool { physical.bytesKnown }

    public init(
        id: String,
        physical: PhysicalStorageNode,
        title: String,
        location: String,
        whatIsThis: String,
        whyLarge: String?,
        semanticCategory: ProductStorageCategory,
        decision: StorageNodeDecisionSummary,
        children: [StorageNodePresentation],
        technicalEntityID: String?,
        structureColorKey: String
    ) {
        self.id = id
        self.physical = physical
        self.title = title
        self.location = location
        self.whatIsThis = whatIsThis
        self.whyLarge = whyLarge
        self.semanticCategory = semanticCategory
        self.decision = decision
        self.children = children
        self.technicalEntityID = technicalEntityID
        self.structureColorKey = structureColorKey
    }
}

public struct StorageExplorerTelemetry: Codable, Sendable, Equatable {
    public var scanStartedAt: Date?
    public var firstHierarchyAvailableAt: Date?
    public var firstMapRenderedAt: Date?
    public var semanticEnrichmentCompleteAt: Date?
    public var safetyAnalysisCompleteAt: Date?
    public var timeToFirstHierarchyMs: Int?
    public var timeToFirstUsefulMapMs: Int?
    public var timeToPhysicalEnrichmentMs: Int?
    public var timeToSemanticEnrichmentMs: Int?
    public var timeToDecisionEnrichmentMs: Int?
    public var timeToSafetyEnrichmentMs: Int?
    public var physicalNodeCount: Int
    public var maxDepth: Int
    public var renderedNodeCount: Int
    public var largestFanout: Int

    public init(
        scanStartedAt: Date? = nil,
        firstHierarchyAvailableAt: Date? = nil,
        firstMapRenderedAt: Date? = nil,
        semanticEnrichmentCompleteAt: Date? = nil,
        safetyAnalysisCompleteAt: Date? = nil,
        timeToFirstHierarchyMs: Int? = nil,
        timeToFirstUsefulMapMs: Int? = nil,
        timeToPhysicalEnrichmentMs: Int? = nil,
        timeToSemanticEnrichmentMs: Int? = nil,
        timeToDecisionEnrichmentMs: Int? = nil,
        timeToSafetyEnrichmentMs: Int? = nil,
        physicalNodeCount: Int = 0,
        maxDepth: Int = 0,
        renderedNodeCount: Int = 0,
        largestFanout: Int = 0
    ) {
        self.scanStartedAt = scanStartedAt
        self.firstHierarchyAvailableAt = firstHierarchyAvailableAt
        self.firstMapRenderedAt = firstMapRenderedAt
        self.semanticEnrichmentCompleteAt = semanticEnrichmentCompleteAt
        self.safetyAnalysisCompleteAt = safetyAnalysisCompleteAt
        self.timeToFirstHierarchyMs = timeToFirstHierarchyMs
        self.timeToFirstUsefulMapMs = timeToFirstUsefulMapMs
        self.timeToPhysicalEnrichmentMs = timeToPhysicalEnrichmentMs
        self.timeToSemanticEnrichmentMs = timeToSemanticEnrichmentMs
        self.timeToDecisionEnrichmentMs = timeToDecisionEnrichmentMs
        self.timeToSafetyEnrichmentMs = timeToSafetyEnrichmentMs
        self.physicalNodeCount = physicalNodeCount
        self.maxDepth = maxDepth
        self.renderedNodeCount = renderedNodeCount
        self.largestFanout = largestFanout
    }
}

public struct StorageExplorerSnapshot: Codable, Sendable, Equatable {
    public var snapshotID: String
    public var diskCapacity: DiskCapacitySnapshot
    public var physicalRoot: PhysicalStorageNode
    public var presentedRoot: StorageNodePresentation
    public var insights: [StorageInsight]
    public var scanStage: StorageScanStage
    public var telemetry: StorageExplorerTelemetry
    public var uniqueClassifiedBytes: Int64
    public var unclassifiedBytes: Int64
    public var physicalMapBytes: Int64
    public var mapAccounting: PhysicalMapAccounting?
    public var accountingValid: Bool
    public var structureLensAvailable: Bool
    public var meaningLensAvailable: Bool
    public var decisionLensAvailable: Bool
    public var mapReadiness: MapReadiness
    public var generation: Int
    public var generatedAt: Date

    public init(
        snapshotID: String = UUID().uuidString,
        diskCapacity: DiskCapacitySnapshot,
        physicalRoot: PhysicalStorageNode,
        presentedRoot: StorageNodePresentation,
        insights: [StorageInsight] = [],
        scanStage: StorageScanStage,
        telemetry: StorageExplorerTelemetry,
        uniqueClassifiedBytes: Int64,
        unclassifiedBytes: Int64,
        physicalMapBytes: Int64,
        mapAccounting: PhysicalMapAccounting? = nil,
        accountingValid: Bool,
        structureLensAvailable: Bool = true,
        meaningLensAvailable: Bool = false,
        decisionLensAvailable: Bool = false,
        mapReadiness: MapReadiness = .notReady,
        generation: Int = 0,
        generatedAt: Date = Date()
    ) {
        self.snapshotID = snapshotID
        self.diskCapacity = diskCapacity
        self.physicalRoot = physicalRoot
        self.presentedRoot = presentedRoot
        self.insights = insights
        self.scanStage = scanStage
        self.telemetry = telemetry
        self.uniqueClassifiedBytes = uniqueClassifiedBytes
        self.unclassifiedBytes = unclassifiedBytes
        self.physicalMapBytes = physicalMapBytes
        self.mapAccounting = mapAccounting
        self.accountingValid = accountingValid
        self.structureLensAvailable = structureLensAvailable
        self.meaningLensAvailable = meaningLensAvailable
        self.decisionLensAvailable = decisionLensAvailable
        self.mapReadiness = mapReadiness
        self.generation = generation
        self.generatedAt = generatedAt
    }
}

public struct P301StorageExplorerReport: Codable, Sendable, Equatable {
    public var diskTotalBytes: Int64?
    public var diskUsedBytes: Int64?
    public var diskFreeBytes: Int64?
    public var physicalMapBytes: Int64
    public var physicalMapAccountingBasis: String?
    public var physicalMapCoverage: String?
    public var rootMeasurementStatus: String?
    public var rootMeasuredBytes: Int64?
    public var rootTotalKnown: Bool?
    public var knownChildMappedBytes: Int64?
    public var fallbackUsed: Bool?
    public var unknownRemainderKnown: Bool?
    public var uniqueClassifiedBytes: Int64
    public var unclassifiedBytes: Int64
    public var physicalNodeCount: Int
    public var maxHierarchyDepth: Int
    public var structureLensAvailable: Bool
    public var meaningLensAvailable: Bool
    public var decisionLensAvailable: Bool
    public var quickLookAvailable: Bool
    public var searchAvailable: Bool
    public var breadcrumbAvailable: Bool
    public var accountingValid: Bool
    public var falseGREEN: Int
    public var duplicateEvaluations: Int
    public var generatedAt: Date
}

public struct P301ExplorerPerformanceReport: Codable, Sendable, Equatable {
    public var timeToFirstHierarchyMs: Int?
    public var timeToFirstUsefulMapMs: Int?
    public var timeToSemanticEnrichmentMs: Int?
    public var timeToSafetyEnrichmentMs: Int?
    public var physicalNodeCount: Int
    public var maxDepth: Int
    public var renderedNodeCount: Int
    public var largestFanout: Int
    public var rootMeasurementTimedOut: Bool?
    public var fallbackAccountingUsed: Bool?
    public var generatedAt: Date

    public init(
        timeToFirstHierarchyMs: Int? = nil,
        timeToFirstUsefulMapMs: Int? = nil,
        timeToSemanticEnrichmentMs: Int? = nil,
        timeToSafetyEnrichmentMs: Int? = nil,
        physicalNodeCount: Int = 0,
        maxDepth: Int = 0,
        renderedNodeCount: Int = 0,
        largestFanout: Int = 0,
        rootMeasurementTimedOut: Bool? = nil,
        fallbackAccountingUsed: Bool? = nil,
        generatedAt: Date = Date()
    ) {
        self.timeToFirstHierarchyMs = timeToFirstHierarchyMs
        self.timeToFirstUsefulMapMs = timeToFirstUsefulMapMs
        self.timeToSemanticEnrichmentMs = timeToSemanticEnrichmentMs
        self.timeToSafetyEnrichmentMs = timeToSafetyEnrichmentMs
        self.physicalNodeCount = physicalNodeCount
        self.maxDepth = maxDepth
        self.renderedNodeCount = renderedNodeCount
        self.largestFanout = largestFanout
        self.rootMeasurementTimedOut = rootMeasurementTimedOut
        self.fallbackAccountingUsed = fallbackAccountingUsed
        self.generatedAt = generatedAt
    }
}

public struct SunburstArc: Equatable, Sendable, Identifiable {
    public var id: String
    public var nodeID: String
    public var ringIndex: Int
    public var startDegrees: Double
    public var endDegrees: Double
    public var title: String
    public var bytes: Int64

    public init(
        id: String,
        nodeID: String,
        ringIndex: Int,
        startDegrees: Double,
        endDegrees: Double,
        title: String,
        bytes: Int64
    ) {
        self.id = id
        self.nodeID = nodeID
        self.ringIndex = ringIndex
        self.startDegrees = startDegrees
        self.endDegrees = endDegrees
        self.title = title
        self.bytes = bytes
    }
}
