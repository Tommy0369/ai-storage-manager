import Foundation

public enum VerificationClaimType: String, Codable, Sendable, CaseIterable {
    case provenance = "PROVENANCE"
    case belongsToWorkspace = "BELONGS_TO_WORKSPACE"
    case derivedFrom = "DERIVED_FROM"
    case generatedBy = "GENERATED_BY"
    case sourceExists = "SOURCE_EXISTS"
    case sourceOfTruth = "SOURCE_OF_TRUTH"
    case regenerability = "REGENERABILITY"
    case activeState = "ACTIVE_STATE"
    case openFileState = "OPEN_FILE_STATE"
    case belongsToVersion = "BELONGS_TO_VERSION"
    case backupOf = "BACKUP_OF"
    case belongsToDevice = "BELONGS_TO_DEVICE"
    case remoteCopyExists = "REMOTE_COPY_EXISTS"
    case syncState = "SYNC_STATE"
    case owningProduct = "OWNING_PRODUCT"
    case referenceGraph = "REFERENCE_GRAPH"
    case sharedByteStatus = "SHARED_BYTE_STATUS"
    case reacquisition = "REACQUISITION"

    public var tier: Int {
        switch self {
        case .sourceOfTruth, .regenerability, .activeState, .openFileState, .remoteCopyExists, .syncState, .reacquisition:
            return 1
        case .belongsToWorkspace, .derivedFrom, .generatedBy, .belongsToVersion, .backupOf, .belongsToDevice, .referenceGraph, .sharedByteStatus:
            return 2
        case .provenance, .sourceExists, .owningProduct:
            return 3
        }
    }
}

public enum VerificationAttemptState: String, Codable, Sendable {
    case notAttempted = "NOT_ATTEMPTED"
    case verified = "VERIFIED"
    case unknownNoEvidence = "UNKNOWN_NO_EVIDENCE"
    case unknownBudget = "UNKNOWN_BUDGET"
    case unknownConflict = "UNKNOWN_CONFLICT"
    case blocked = "BLOCKED"
    case notApplicable = "NOT_APPLICABLE"
}

public enum VerificationStrategyID: String, Codable, Sendable, CaseIterable {
    case cursorMetadata = "CursorMetadataProofStrategy"
    case claudeVMActive = "ClaudeVMActiveProofStrategy"
    case derivedData = "DerivedDataProofStrategy"
    case nodeModules = "NodeModulesProofStrategy"
    case fileProvider = "FileProviderProofStrategy"
    case workspaceRelationship = "WorkspaceRelationshipProofStrategy"
    case resolverSourceOfTruth = "SourceOfTruthResolver"
    case resolverRegenerability = "RegenerabilityResolver"
    case resolverActiveState = "ActiveStateResolver"
    case ollamaStorage = "OllamaStorageProofStrategy"
    case huggingFaceStorage = "HuggingFaceStorageProofStrategy"
}

public enum VerificationStrategyOutcome: String, Codable, Sendable {
    case verified = "VERIFIED"
    case inferred = "INFERRED"
    case unknown = "UNKNOWN"
    case conflicted = "CONFLICTED"
    case blocked = "BLOCKED"
}

public enum VerificationProofTier: String, Codable, Sendable {
    case core = "CORE"
    case boundedDefault = "BOUNDED_DEFAULT_PROOF"
    case optIn = "OPT_IN_PROOF"
}

public struct VerificationCandidate: Codable, Sendable, Equatable {
    public var entityID: String
    public var canonicalPath: String
    public var domain: String
    public var semanticLevel: Int
    public var uniqueBytes: Int64
    public var measurementKnown: Bool
    public var unresolvedClaims: [VerificationClaimType]
    public var strategiesAvailable: [VerificationStrategyID]
    public var priority: Double
    public var estimatedCostMs: Int
    public var blockingReasons: [String]
    public var attemptState: VerificationAttemptState
    public var proofTier: VerificationProofTier
}

public struct VerificationStrategyResult: Codable, Sendable, Equatable {
    public var strategyID: VerificationStrategyID
    public var entityID: String
    public var claim: VerificationClaimType
    public var outcome: VerificationStrategyOutcome
    public var runtimeMs: Int
    public var budgetUsedMs: Int
    public var reasonCodes: [String]
    public var supportingEvidence: [String]
    public var failedRequirements: [String]
    public var unknownRequirements: [String]
}

public struct VerificationBudgetConfig: Codable, Sendable, Equatable {
    public var totalBudgetMs: Int
    public var maxCandidates: Int
    public var maxAttemptsPerEntity: Int
    public var perStrategyBudgetMs: Int

    public static let `default` = VerificationBudgetConfig(
        totalBudgetMs: 45_000,
        maxCandidates: 120,
        maxAttemptsPerEntity: 4,
        perStrategyBudgetMs: 500
    )
}

public struct EntityVerificationBacklogEntry: Codable, Sendable, Equatable {
    public var entityID: String
    public var path: String
    public var uniqueBytes: Int64
    public var measurementKnown: Bool
    public var semanticLevel: Int
    public var unresolvedClaim: String
    public var priority: Double
    public var estimatedProofCostMs: Int
    public var availableStrategy: String?
    public var attempted: Bool
    public var result: String
    public var blockingReason: String?
}

public struct EntityVerificationBacklogReport: Codable, Sendable, Equatable {
    public var entries: [EntityVerificationBacklogEntry]
    public var totalCandidates: Int
    public var attemptedCount: Int
    public var blockedCount: Int
}

public struct EntityVerificationLoopReport: Codable, Sendable, Equatable {
    public var candidatesDiscovered: Int
    public var candidatesAttempted: Int
    public var candidatesSkipped: Int
    public var candidatesBlocked: Int
    public var claimsVerified: Int
    public var claimsInferred: Int
    public var claimsUnknown: Int
    public var claimsConflicted: Int
    public var budgetExhausted: Bool
    public var totalRuntimeMs: Int
    public var candidateBuildingMs: Int
    public var strategySelectionMs: Int
    public var proofExecutionMs: Int
    public var claimUpdateMs: Int
    public var safetyEvaluationMs: Int
    public var proofStrategyCounts: [String: Int]
    public var topSuccessfulProofs: [String]
    public var topUnresolvedProofs: [String]
    public var verificationYield: Double
    public var verifiedBytesImpacted: Int64
    public var runtimePerVerifiedClaimMs: Double
}

public struct VerificationStrategyRuntimeStat: Codable, Sendable, Equatable {
    public var strategyID: String
    public var attempts: Int
    public var totalRuntimeMs: Int
    public var medianRuntimeMs: Int
    public var verifiedResults: Int
    public var unknownResults: Int
    public var conflictResults: Int
    public var budgetFailures: Int
}

public struct VerificationStrategyRuntimeReport: Codable, Sendable, Equatable {
    public var strategies: [VerificationStrategyRuntimeStat]
}

public struct EvidenceConflictRecord: Codable, Sendable, Equatable {
    public var entityID: String
    public var path: String
    public var claim: String
    public var conflictDescription: String
    public var reasonCode: String
}

public struct VerificationLoopCoverageReport: Codable, Sendable, Equatable {
    public var measurementCoveragePercent: Double
    public var semanticL3PlusPercent: Double
    public var provenanceVerifiedPercent: Double
    public var verifiedRelationshipPercent: Double
    public var sourceOfTruthKnownPercent: Double
    public var regenerabilityKnownPercent: Double
    public var runtimeStateKnownPercent: Double
    public var verificationLoopCoveragePercent: Double
    public var entitiesWithAttemptedProof: Int
    public var entitiesWithVerifiedClaim: Int
}

public struct P110RuntimeComparison: Codable, Sendable, Equatable {
    public var p19TotalSeconds: Double
    public var p110TotalSeconds: Double
    public var entityVerificationLoopP19Ms: Int
    public var entityVerificationLoopP110Ms: Int
    public var scannerFilesystemWalkP110Ms: Int
    public var detectorCatalogP110Ms: Int
}

extension EntityVerificationLoopReport {
    public static let p19Baseline = P110RuntimeComparison(
        p19TotalSeconds: 100.8,
        p110TotalSeconds: 0,
        entityVerificationLoopP19Ms: 40_146,
        entityVerificationLoopP110Ms: 0,
        scannerFilesystemWalkP110Ms: 0,
        detectorCatalogP110Ms: 0
    )
}
