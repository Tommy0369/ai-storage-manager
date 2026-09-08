import Foundation
import SafetyCore

public let storageHistorySchemaVersion = 1
public let storageHistoryRetentionLimit = 30

/// Compact historical observation derived from an existing explorer snapshot.
/// Privacy: no file contents, secrets, or arbitrary metadata blobs.
public struct StorageHistorySnapshot: Codable, Sendable, Equatable {
    public var snapshotID: String
    public var schemaVersion: Int
    public var generatedAt: Date
    public var volumeIdentity: String
    public var rootScopeIdentity: String
    public var diskCapacity: DiskCapacitySnapshot
    public var physicalMapAccounting: PhysicalMapAccounting
    public var physicalNodeSummaries: [HistoryNodeSummary]
    public var semanticCategoryTotals: [HistoryCategoryTotal]
    public var selectedEntitySummaries: [HistoryEntitySummary]
    public var actionStateSummaries: [HistoryActionSummary]
    public var scanCoverage: HistoryScanCoverage

    public init(
        snapshotID: String,
        schemaVersion: Int = storageHistorySchemaVersion,
        generatedAt: Date = Date(),
        volumeIdentity: String,
        rootScopeIdentity: String,
        diskCapacity: DiskCapacitySnapshot,
        physicalMapAccounting: PhysicalMapAccounting,
        physicalNodeSummaries: [HistoryNodeSummary],
        semanticCategoryTotals: [HistoryCategoryTotal],
        selectedEntitySummaries: [HistoryEntitySummary] = [],
        actionStateSummaries: [HistoryActionSummary] = [],
        scanCoverage: HistoryScanCoverage
    ) {
        self.snapshotID = snapshotID
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.volumeIdentity = volumeIdentity
        self.rootScopeIdentity = rootScopeIdentity
        self.diskCapacity = diskCapacity
        self.physicalMapAccounting = physicalMapAccounting
        self.physicalNodeSummaries = physicalNodeSummaries
        self.semanticCategoryTotals = semanticCategoryTotals
        self.selectedEntitySummaries = selectedEntitySummaries
        self.actionStateSummaries = actionStateSummaries
        self.scanCoverage = scanCoverage
    }
}

public struct HistoryNodeSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { stableIdentity }
    public var stableIdentity: String
    public var parentIdentity: String?
    public var displayName: String
    public var bytes: Int64?
    public var bytesKnown: Bool
    public var nodeKind: String
    public var semanticCategory: String?
    public var depth: Int

    public var identityStability: String?

    public init(
        stableIdentity: String,
        parentIdentity: String? = nil,
        displayName: String,
        bytes: Int64?,
        bytesKnown: Bool,
        nodeKind: String,
        semanticCategory: String? = nil,
        depth: Int,
        identityStability: String? = "canonical"
    ) {
        self.stableIdentity = stableIdentity
        self.parentIdentity = parentIdentity
        self.displayName = displayName
        self.bytes = bytes
        self.bytesKnown = bytesKnown
        self.nodeKind = nodeKind
        self.semanticCategory = semanticCategory
        self.depth = depth
        self.identityStability = identityStability
    }
}

public struct HistoryCategoryTotal: Codable, Sendable, Equatable {
    public var category: String
    public var bytes: Int64

    public init(category: String, bytes: Int64) {
        self.category = category
        self.bytes = bytes
    }
}

public struct HistoryEntitySummary: Codable, Sendable, Equatable {
    public var entityID: String
    public var displayName: String
    public var bytes: Int64?
    public var semanticCategory: String?
    public var decisionSummary: String?

    public init(
        entityID: String,
        displayName: String,
        bytes: Int64? = nil,
        semanticCategory: String? = nil,
        decisionSummary: String? = nil
    ) {
        self.entityID = entityID
        self.displayName = displayName
        self.bytes = bytes
        self.semanticCategory = semanticCategory
        self.decisionSummary = decisionSummary
    }
}

public struct HistoryActionSummary: Codable, Sendable, Equatable {
    public var actionID: String
    public var entityID: String
    public var action: String
    public var auditStatus: String
    public var verificationState: String?
    public var executedAt: Date?
    public var logicalActionCompleted: Bool?
    public var permitID: String?
    public var verifiedRecoveredBytes: Int64?

    public init(
        actionID: String,
        entityID: String,
        action: String,
        auditStatus: String,
        verificationState: String? = nil,
        executedAt: Date? = nil,
        logicalActionCompleted: Bool? = nil,
        permitID: String? = nil,
        verifiedRecoveredBytes: Int64? = nil
    ) {
        self.actionID = actionID
        self.entityID = entityID
        self.action = action
        self.auditStatus = auditStatus
        self.verificationState = verificationState
        self.executedAt = executedAt
        self.logicalActionCompleted = logicalActionCompleted
        self.permitID = permitID
        self.verifiedRecoveredBytes = verifiedRecoveredBytes
    }
}

public struct HistoryScanCoverage: Codable, Sendable, Equatable {
    public var physicalNodeCount: Int
    public var maxDepth: Int
    public var accountingValid: Bool
    public var mapCoverage: String
    public var mapBasis: String

    public init(
        physicalNodeCount: Int,
        maxDepth: Int,
        accountingValid: Bool,
        mapCoverage: String,
        mapBasis: String
    ) {
        self.physicalNodeCount = physicalNodeCount
        self.maxDepth = maxDepth
        self.accountingValid = accountingValid
        self.mapCoverage = mapCoverage
        self.mapBasis = mapBasis
    }
}

public enum StorageComparisonQuality: String, Codable, Sendable, Equatable {
    case fullyComparable = "FULLY_COMPARABLE"
    case partiallyComparable = "PARTIALLY_COMPARABLE"
    case notComparable = "NOT_COMPARABLE"
    case noComparisonYet = "NO_COMPARISON_YET"
}

public enum StorageChangeKind: String, Codable, Sendable, Equatable {
    case grew = "GREW"
    case shrank = "SHRANK"
    case new = "NEW"
    case removed = "REMOVED"
    case moved = "MOVED"
    case unchanged = "UNCHANGED"
    case unknownMatch = "UNKNOWN_MATCH"
}

public enum StorageMatchConfidence: String, Codable, Sendable, Equatable {
    case matched = "MATCHED"
    case new = "NEW"
    case removed = "REMOVED"
    case movedVerified = "MOVED_VERIFIED"
    case unknownMatch = "UNKNOWN_MATCH"
}

public struct StorageChangeItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { identity }
    public var identity: String
    public var displayName: String
    public var previousBytes: Int64?
    public var currentBytes: Int64?
    public var deltaBytes: Int64?
    public var changeKind: StorageChangeKind
    public var semanticCategory: String?
    public var nodeKind: String?
    public var comparisonConfidence: StorageMatchConfidence
    public var decisionSummary: String?

    public init(
        identity: String,
        displayName: String,
        previousBytes: Int64?,
        currentBytes: Int64?,
        deltaBytes: Int64?,
        changeKind: StorageChangeKind,
        semanticCategory: String? = nil,
        nodeKind: String? = nil,
        comparisonConfidence: StorageMatchConfidence,
        decisionSummary: String? = nil
    ) {
        self.identity = identity
        self.displayName = displayName
        self.previousBytes = previousBytes
        self.currentBytes = currentBytes
        self.deltaBytes = deltaBytes
        self.changeKind = changeKind
        self.semanticCategory = semanticCategory
        self.nodeKind = nodeKind
        self.comparisonConfidence = comparisonConfidence
        self.decisionSummary = decisionSummary
    }
}

public struct StorageCategoryDelta: Codable, Sendable, Equatable {
    public var category: String
    public var previousBytes: Int64
    public var currentBytes: Int64
    public var deltaBytes: Int64

    public init(category: String, previousBytes: Int64, currentBytes: Int64, deltaBytes: Int64) {
        self.category = category
        self.previousBytes = previousBytes
        self.currentBytes = currentBytes
        self.deltaBytes = deltaBytes
    }
}

public struct StorageVerifiedActionCorrelation: Codable, Sendable, Equatable {
    public var actionID: String
    public var entityID: String
    public var relatedChangeIdentity: String
    public var correlation: String
    public var note: String

    public init(
        actionID: String,
        entityID: String,
        relatedChangeIdentity: String,
        correlation: String = "RELATED_TO_VERIFIED_ACTION",
        note: String
    ) {
        self.actionID = actionID
        self.entityID = entityID
        self.relatedChangeIdentity = relatedChangeIdentity
        self.correlation = correlation
        self.note = note
    }
}

public struct StorageRegenerationCorrelation: Codable, Sendable, Equatable {
    public var previousEntityID: String
    public var successorEntityID: String
    public var successorBytes: Int64?
    public var note: String

    public init(
        previousEntityID: String,
        successorEntityID: String,
        successorBytes: Int64? = nil,
        note: String
    ) {
        self.previousEntityID = previousEntityID
        self.successorEntityID = successorEntityID
        self.successorBytes = successorBytes
        self.note = note
    }
}

public struct StorageChangeExplanation: Codable, Sendable, Equatable {
    public var headline: String
    public var bodyLines: [String]
    public var usesLowerBoundLanguage: Bool
    public var firstRun: Bool

    public init(headline: String, bodyLines: [String], usesLowerBoundLanguage: Bool, firstRun: Bool) {
        self.headline = headline
        self.bodyLines = bodyLines
        self.usesLowerBoundLanguage = usesLowerBoundLanguage
        self.firstRun = firstRun
    }
}

public struct StorageChangeReport: Codable, Sendable, Equatable {
    public var currentSnapshotID: String
    public var comparisonSnapshotID: String?
    public var comparisonWindow: String
    public var comparisonQuality: StorageComparisonQuality
    public var diskUsedPrevious: Int64?
    public var diskUsedCurrent: Int64
    public var diskUsedDelta: Int64?
    public var diskFreePrevious: Int64?
    public var diskFreeCurrent: Int64
    public var diskFreeDelta: Int64?
    public var mappedPrevious: Int64?
    public var mappedCurrent: Int64?
    public var mappedDelta: Int64?
    public var identifiedGrowthBytes: Int64
    public var identifiedShrinkBytes: Int64
    public var unexplainedDeltaBytes: Int64?
    public var topGrowing: [StorageChangeItem]
    public var topShrinking: [StorageChangeItem]
    public var newLargeItems: [StorageChangeItem]
    public var removedLargeItems: [StorageChangeItem]
    public var categoryDeltas: [StorageCategoryDelta]
    public var relatedVerifiedActions: [StorageVerifiedActionCorrelation]
    public var regeneratedItems: [StorageRegenerationCorrelation]
    public var coverageNotes: [String]
    public var explanation: StorageChangeExplanation
    public var allChanges: [StorageChangeItem]
    public var falseGREEN: Int
    public var duplicateEvaluations: Int
    public var generatedAt: Date
    public var diffMs: Int?
    public var snapshotSerializationMs: Int?
    public var historyLoadMs: Int?
    public var changeReportBuildMs: Int?

    public init(
        currentSnapshotID: String,
        comparisonSnapshotID: String? = nil,
        comparisonWindow: String,
        comparisonQuality: StorageComparisonQuality,
        diskUsedPrevious: Int64? = nil,
        diskUsedCurrent: Int64,
        diskUsedDelta: Int64? = nil,
        diskFreePrevious: Int64? = nil,
        diskFreeCurrent: Int64,
        diskFreeDelta: Int64? = nil,
        mappedPrevious: Int64? = nil,
        mappedCurrent: Int64? = nil,
        mappedDelta: Int64? = nil,
        identifiedGrowthBytes: Int64 = 0,
        identifiedShrinkBytes: Int64 = 0,
        unexplainedDeltaBytes: Int64? = nil,
        topGrowing: [StorageChangeItem] = [],
        topShrinking: [StorageChangeItem] = [],
        newLargeItems: [StorageChangeItem] = [],
        removedLargeItems: [StorageChangeItem] = [],
        categoryDeltas: [StorageCategoryDelta] = [],
        relatedVerifiedActions: [StorageVerifiedActionCorrelation] = [],
        regeneratedItems: [StorageRegenerationCorrelation] = [],
        coverageNotes: [String] = [],
        explanation: StorageChangeExplanation,
        allChanges: [StorageChangeItem] = [],
        falseGREEN: Int = 0,
        duplicateEvaluations: Int = 0,
        generatedAt: Date = Date(),
        diffMs: Int? = nil,
        snapshotSerializationMs: Int? = nil,
        historyLoadMs: Int? = nil,
        changeReportBuildMs: Int? = nil
    ) {
        self.currentSnapshotID = currentSnapshotID
        self.comparisonSnapshotID = comparisonSnapshotID
        self.comparisonWindow = comparisonWindow
        self.comparisonQuality = comparisonQuality
        self.diskUsedPrevious = diskUsedPrevious
        self.diskUsedCurrent = diskUsedCurrent
        self.diskUsedDelta = diskUsedDelta
        self.diskFreePrevious = diskFreePrevious
        self.diskFreeCurrent = diskFreeCurrent
        self.diskFreeDelta = diskFreeDelta
        self.mappedPrevious = mappedPrevious
        self.mappedCurrent = mappedCurrent
        self.mappedDelta = mappedDelta
        self.identifiedGrowthBytes = identifiedGrowthBytes
        self.identifiedShrinkBytes = identifiedShrinkBytes
        self.unexplainedDeltaBytes = unexplainedDeltaBytes
        self.topGrowing = topGrowing
        self.topShrinking = topShrinking
        self.newLargeItems = newLargeItems
        self.removedLargeItems = removedLargeItems
        self.categoryDeltas = categoryDeltas
        self.relatedVerifiedActions = relatedVerifiedActions
        self.regeneratedItems = regeneratedItems
        self.coverageNotes = coverageNotes
        self.explanation = explanation
        self.allChanges = allChanges
        self.falseGREEN = falseGREEN
        self.duplicateEvaluations = duplicateEvaluations
        self.generatedAt = generatedAt
        self.diffMs = diffMs
        self.snapshotSerializationMs = snapshotSerializationMs
        self.historyLoadMs = historyLoadMs
        self.changeReportBuildMs = changeReportBuildMs
    }
}

public struct P302StorageChangeExport: Codable, Sendable, Equatable {
    public var currentSnapshotID: String
    public var comparisonSnapshotID: String?
    public var comparisonWindow: String
    public var comparisonQuality: String
    public var diskUsedPrevious: Int64?
    public var diskUsedCurrent: Int64
    public var diskUsedDelta: Int64?
    public var diskFreePrevious: Int64?
    public var diskFreeCurrent: Int64
    public var diskFreeDelta: Int64?
    public var mappedPrevious: Int64?
    public var mappedCurrent: Int64?
    public var mappedDelta: Int64?
    public var identifiedGrowthBytes: Int64
    public var identifiedShrinkBytes: Int64
    public var unexplainedDeltaBytes: Int64?
    public var topGrowing: [StorageChangeItem]
    public var topShrinking: [StorageChangeItem]
    public var newLargeItems: [StorageChangeItem]
    public var removedLargeItems: [StorageChangeItem]
    public var categoryDeltas: [StorageCategoryDelta]
    public var relatedVerifiedActions: [StorageVerifiedActionCorrelation]
    public var regeneratedItems: [StorageRegenerationCorrelation]
    public var coverageNotes: [String]
    public var falseGREEN: Int
    public var duplicateEvaluations: Int
    public var generatedAt: Date

    public init(from report: StorageChangeReport) {
        self.currentSnapshotID = report.currentSnapshotID
        self.comparisonSnapshotID = report.comparisonSnapshotID
        self.comparisonWindow = report.comparisonWindow
        self.comparisonQuality = report.comparisonQuality.rawValue
        self.diskUsedPrevious = report.diskUsedPrevious
        self.diskUsedCurrent = report.diskUsedCurrent
        self.diskUsedDelta = report.diskUsedDelta
        self.diskFreePrevious = report.diskFreePrevious
        self.diskFreeCurrent = report.diskFreeCurrent
        self.diskFreeDelta = report.diskFreeDelta
        self.mappedPrevious = report.mappedPrevious
        self.mappedCurrent = report.mappedCurrent
        self.mappedDelta = report.mappedDelta
        self.identifiedGrowthBytes = report.identifiedGrowthBytes
        self.identifiedShrinkBytes = report.identifiedShrinkBytes
        self.unexplainedDeltaBytes = report.unexplainedDeltaBytes
        self.topGrowing = report.topGrowing
        self.topShrinking = report.topShrinking
        self.newLargeItems = report.newLargeItems
        self.removedLargeItems = report.removedLargeItems
        self.categoryDeltas = report.categoryDeltas
        self.relatedVerifiedActions = report.relatedVerifiedActions
        self.regeneratedItems = report.regeneratedItems
        self.coverageNotes = report.coverageNotes
        self.falseGREEN = report.falseGREEN
        self.duplicateEvaluations = report.duplicateEvaluations
        self.generatedAt = report.generatedAt
    }
}

public struct P302HistoryStatusReport: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var historySnapshotCount: Int
    public var oldestSnapshotAt: Date?
    public var newestSnapshotAt: Date?
    public var retentionLimit: Int
    public var historyStoreLocationType: String
    public var snapshotWriteSuccess: Bool
    public var secondCrawlerAdded: Bool
    public var privacyFieldsStored: [String]
    public var generatedAt: Date

    public init(
        schemaVersion: Int = storageHistorySchemaVersion,
        historySnapshotCount: Int,
        oldestSnapshotAt: Date?,
        newestSnapshotAt: Date?,
        retentionLimit: Int = storageHistoryRetentionLimit,
        historyStoreLocationType: String,
        snapshotWriteSuccess: Bool,
        secondCrawlerAdded: Bool = false,
        privacyFieldsStored: [String],
        generatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.historySnapshotCount = historySnapshotCount
        self.oldestSnapshotAt = oldestSnapshotAt
        self.newestSnapshotAt = newestSnapshotAt
        self.retentionLimit = retentionLimit
        self.historyStoreLocationType = historyStoreLocationType
        self.snapshotWriteSuccess = snapshotWriteSuccess
        self.secondCrawlerAdded = secondCrawlerAdded
        self.privacyFieldsStored = privacyFieldsStored
        self.generatedAt = generatedAt
    }
}
