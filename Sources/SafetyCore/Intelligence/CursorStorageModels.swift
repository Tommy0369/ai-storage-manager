import Foundation

/// P3.3A — Cursor globalStorage semantic component (read-only intelligence).
public enum CursorStorageComponentKind: String, Codable, Sendable, Equatable {
    case cursorCoreGlobalState = "CURSOR_CORE_GLOBAL_STATE"
    case extensionGlobalStorage = "EXTENSION_GLOBAL_STORAGE"
    case extensionAbsentStorage = "EXTENSION_ABSENT_STORAGE"
    case database = "DATABASE"
    case databaseWAL = "DATABASE_WAL"
    case databaseSHM = "DATABASE_SHM"
    case indexedDBOrKVStore = "INDEXED_DB_OR_KV_STORE"
    case blobStore = "BLOB_STORE"
    case cacheVerified = "CACHE_VERIFIED"
    case cacheSuspect = "CACHE_SUSPECT"
    case sessionOrHistoryState = "SESSION_OR_HISTORY_STATE"
    case aiConversationOrContextState = "AI_CONVERSATION_OR_CONTEXT_STATE"
    case checkpointOrRecoveryState = "CHECKPOINT_OR_RECOVERY_STATE"
    case logOrTelemetry = "LOG_OR_TELEMETRY"
    case unknownAppManaged = "UNKNOWN_APP_MANAGED"
    case otherVerified = "OTHER_VERIFIED"
    case vendorToolchainVersions = "VENDOR_TOOLCHAIN_VERSIONS"
}

public enum CursorEvidenceLevel: String, Codable, Sendable, Equatable {
    case verified = "VERIFIED"
    case inferred = "INFERRED"
    case unknown = "UNKNOWN"
}

public enum CursorPotentialAction: String, Codable, Sendable, Equatable {
    case keep = "KEEP"
    case verifyMore = "VERIFY_MORE"
    case nativeCleanupCandidate = "NATIVE_CLEANUP_CANDIDATE"
    case moveToICloudCandidate = "MOVE_TO_ICLOUD_CANDIDATE"
    case exportThenRemoveCandidate = "EXPORT_THEN_REMOVE_CANDIDATE"
    case none = "NONE"
}

public struct CursorStorageComponent: Codable, Sendable, Equatable {
    public var entityID: String
    public var rootEntityID: String
    public var componentKind: CursorStorageComponentKind
    public var path: String
    public var relativePath: String
    public var owner: String
    public var extensionID: String?
    public var extensionPresent: Bool?
    public var storageRole: String
    public var observedBytes: Int64
    public var uniqueBytes: Int64
    public var sharedBytes: Int64
    public var fileCount: Int?
    public var databaseLike: Bool
    public var runtimeState: String
    public var sourceOfTruthState: String
    public var userOriginalState: String
    public var reacquisitionState: String
    public var regenerabilityState: String
    public var syncState: String
    public var evidence: [String]
    public var classificationConfidence: CursorEvidenceLevel
    public var recommendedAction: CursorPotentialAction
    public var actionability: String
    public var percentOfRoot: Double

    public init(
        entityID: String,
        rootEntityID: String,
        componentKind: CursorStorageComponentKind,
        path: String,
        relativePath: String,
        owner: String,
        extensionID: String? = nil,
        extensionPresent: Bool? = nil,
        storageRole: String,
        observedBytes: Int64,
        uniqueBytes: Int64,
        sharedBytes: Int64 = 0,
        fileCount: Int? = nil,
        databaseLike: Bool = false,
        runtimeState: String,
        sourceOfTruthState: String,
        userOriginalState: String,
        reacquisitionState: String,
        regenerabilityState: String,
        syncState: String = "UNKNOWN",
        evidence: [String],
        classificationConfidence: CursorEvidenceLevel,
        recommendedAction: CursorPotentialAction,
        actionability: String,
        percentOfRoot: Double
    ) {
        self.entityID = entityID
        self.rootEntityID = rootEntityID
        self.componentKind = componentKind
        self.path = path
        self.relativePath = relativePath
        self.owner = owner
        self.extensionID = extensionID
        self.extensionPresent = extensionPresent
        self.storageRole = storageRole
        self.observedBytes = observedBytes
        self.uniqueBytes = uniqueBytes
        self.sharedBytes = sharedBytes
        self.fileCount = fileCount
        self.databaseLike = databaseLike
        self.runtimeState = runtimeState
        self.sourceOfTruthState = sourceOfTruthState
        self.userOriginalState = userOriginalState
        self.reacquisitionState = reacquisitionState
        self.regenerabilityState = regenerabilityState
        self.syncState = syncState
        self.evidence = evidence
        self.classificationConfidence = classificationConfidence
        self.recommendedAction = recommendedAction
        self.actionability = actionability
        self.percentOfRoot = percentOfRoot
    }
}

public struct CursorStorageOpportunity: Codable, Sendable, Equatable {
    public var candidateID: String
    public var component: String
    public var uniqueBytes: Int64
    public var currentSafety: String
    public var potentialAction: CursorPotentialAction
    public var proofFeasibility: String
    public var requiredEvidence: [String]
    public var expectedValue: String
    public var risk: String
    public var nativeContractAvailability: String
    public var preservationPotential: String
    public var currentExecutable: Bool
    public var rankingScore: Double
    public var rankingExplanation: String

    public init(
        candidateID: String,
        component: String,
        uniqueBytes: Int64,
        currentSafety: String,
        potentialAction: CursorPotentialAction,
        proofFeasibility: String,
        requiredEvidence: [String],
        expectedValue: String,
        risk: String,
        nativeContractAvailability: String,
        preservationPotential: String,
        currentExecutable: Bool = false,
        rankingScore: Double,
        rankingExplanation: String
    ) {
        self.candidateID = candidateID
        self.component = component
        self.uniqueBytes = uniqueBytes
        self.currentSafety = currentSafety
        self.potentialAction = potentialAction
        self.proofFeasibility = proofFeasibility
        self.requiredEvidence = requiredEvidence
        self.expectedValue = expectedValue
        self.risk = risk
        self.nativeContractAvailability = nativeContractAvailability
        self.preservationPotential = preservationPotential
        self.currentExecutable = currentExecutable
        self.rankingScore = rankingScore
        self.rankingExplanation = rankingExplanation
    }
}

public struct CursorExtensionOwnership: Codable, Sendable, Equatable {
    public var namespace: String
    public var extensionID: String?
    public var extensionInstalled: Bool
    public var version: String?
    public var ownershipEvidence: String
    public var storageBytes: Int64
    public var availabilityState: String
    public var recommendedNextProof: String
}

public struct CursorKVNamespaceSummary: Codable, Sendable, Equatable {
    public var keyClass: String
    public var keyCount: Int
    public var approxValueBytes: Int64
    /// Never includes key UUIDs or value contents.
    public var semanticRole: String
}

public struct CursorGlobalStorageIntelligenceReport: Codable, Sendable, Equatable {
    public var rootEntityID: String
    public var rootPath: String
    public var owner: String
    public var semanticRole: String
    public var observedBytes: Int64
    public var uniqueBytes: Int64
    public var mappedChildBytes: Int64
    public var unknownBytes: Int64
    public var classificationCoveragePercent: Double
    public var accountingValid: Bool
    public var appInstalled: Bool
    public var appVersion: String?
    public var appBundleID: String?
    public var appRunning: Bool
    public var rootSafety: String
    public var rootActionability: String
    public var rootExecutable: Bool
    public var components: [CursorStorageComponent]
    public var extensionOwnership: [CursorExtensionOwnership]
    public var kvNamespaceSummaries: [CursorKVNamespaceSummary]
    public var opportunities: [CursorStorageOpportunity]
    public var openComponentPaths: [String]
    public var runtimeCompleteness: String
    public var privacyNote: String
    public var generatedAt: Date
}
