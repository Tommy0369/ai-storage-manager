import Foundation

public enum RuntimeObservationSource: String, Codable, Sendable {
    case processArg = "PROCESS_ARG"
    case processExecutable = "PROCESS_EXECUTABLE"
    case openFile = "OPEN_FILE"
    case lockReference = "LOCK_REFERENCE"
}

public enum PathObservationRelation: String, Codable, Sendable {
    case exactEntityPath = "EXACT_ENTITY_PATH"
    case observationInsideEntity = "OBSERVATION_INSIDE_ENTITY"
    case entityInsideObservedParent = "ENTITY_INSIDE_OBSERVED_PARENT"
    case siblingObservation = "SIBLING_OBSERVATION"
    case unrelated = "UNRELATED"
}

public enum RuntimeResolutionNeed: String, Codable, Sendable {
    case requiredNow = "REQUIRED_NOW"
    case requiredForPotentialAction = "REQUIRED_FOR_POTENTIAL_ACTION"
    case notRequiredForCurrentDecision = "NOT_REQUIRED_FOR_CURRENT_DECISION"
}

public enum RuntimeDeferReason: String, Codable, Sendable {
    case staticHardBlock = "STATIC_HARD_BLOCK"
    case actionNotApplicable = "ACTION_NOT_APPLICABLE"
    case relocationContractMissing = "RELOCATION_CONTRACT_MISSING"
    case nativeSyncRequired = "NATIVE_SYNC_REQUIRED"
    case deviceAwareMigrationRequired = "DEVICE_AWARE_MIGRATION_REQUIRED"
    case noRuntimePredicateInCandidateRule = "NO_RUNTIME_PREDICATE_IN_CANDIDATE_RULE"
    case noPotentiallyActionableAction = "NO_POTENTIALLY_ACTIONABLE_ACTION"
}

public enum RuntimeResolutionDisposition: String, Codable, Sendable {
    case resolved = "RESOLVED"
    case deferred = "DEFERRED_NOT_DECISION_RELEVANT"
}

public struct RuntimeObservation: Sendable, Equatable {
    public var source: RuntimeObservationSource
    public var observedPath: String?
    public var processID: Int32?
    public var argumentIndex: Int?
    public var observedAt: Date
    public var confidence: EvidenceConfidence
    public var completeness: ObservationCompleteness
    public var reasonCodes: [String]
}

public struct RuntimeRequirementPlan: Sendable, Equatable {
    public var needsActive: Bool
    public var needsOpenFile: Bool
    public var need: RuntimeResolutionNeed
    public var deferReason: RuntimeDeferReason?
    public var deferReasons: [RuntimeDeferReason]
}

public struct RuntimeStateResolution: Sendable, Equatable {
    public var entityID: String
    public var disposition: RuntimeResolutionDisposition
    public var deferReason: RuntimeDeferReason?
    public var activeState: ObservedActiveState
    public var activeStateConfidence: EvidenceConfidence
    public var activeStateCompleteness: ObservationCompleteness
    public var openFileHandle: PredicateValue
    public var openFileConfidence: EvidenceConfidence
    public var unknownReasons: [String]
    public var lookupMs: Int
}

public struct RuntimeObservationIndexReport: Codable, Sendable, Equatable {
    public var processObservationsIndexed: Int
    public var openFileObservationsIndexed: Int
    public var exactPathKeys: Int
    public var commandPathKeys: Int
    public var buildRuntimeMs: Int
    public var parseFailures: Int
    public var processCompleteness: String
    public var openFileCompleteness: String
    public var runtimeGeneration: Int
}

public struct RuntimeBatchResolutionReport: Codable, Sendable, Equatable {
    public var totalEntities: Int
    public var runtimeResolutionRequired: Int
    public var runtimeResolutionDeferred: Int
    public var activeResolved: Int
    public var openResolved: Int
    public var positiveExactMatches: Int
    public var verifiedInactive: Int
    public var unknownIncompleteObservation: Int
    public var conflicts: Int
    public var indexEntries: Int
    public var indexBuildRuntimeMs: Int
    public var batchLookupRuntimeMs: Int
    public var totalRuntimeResolutionMs: Int
    public var deferPlannerMs: Int
}

public struct RuntimeResolutionNeedEntry: Codable, Sendable, Equatable {
    public var entityID: String
    public var need: String
    public var needsActive: Bool
    public var needsOpenFile: Bool
    public var reasons: [String]
}

public struct RuntimeResolutionNeedReport: Codable, Sendable, Equatable {
    public var requiredNow: Int
    public var requiredForPotentialAction: Int
    public var notRequiredForCurrentDecision: Int
    public var entries: [RuntimeResolutionNeedEntry]
}

public enum ActionReadinessState: String, Codable, Sendable {
    case blocked = "BLOCKED"
    case verifyMore = "VERIFY_MORE"
    case recommendable = "RECOMMENDABLE"
    case preflightRequired = "PREFLIGHT_REQUIRED"
    case preflightSatisfiedReadOnly = "PREFLIGHT_SATISFIED_READ_ONLY"
}

public struct ActionReadinessEntry: Codable, Sendable, Equatable {
    public var entityID: String
    public var path: String
    public var recommendedAction: String
    public var safetyClass: String
    public var readiness: String
    public var mutationReadiness: String?
    public var staticPredicatesSatisfied: Bool
    public var runtimePredicatesRequired: [String]
    public var runtimePredicatesSatisfied: [String]
    public var freshPreflightRequirements: [String]
    public var transactionContractAvailable: Bool
    public var postVerifyContractAvailable: Bool
    public var executorImplemented: Bool
}

public struct ActionReadinessReport: Codable, Sendable, Equatable {
    public var entries: [ActionReadinessEntry]
    public var recommendableCount: Int
    public var preflightRequiredCount: Int
    public var preflightSatisfiedReadOnlyCount: Int
    public var executorImplemented: Bool
}

public struct P113RuntimeComparison: Codable, Sendable, Equatable {
    public var p112TotalSeconds: Double
    public var p113TotalSeconds: Double
    public var safetyEvalP112Ms: Int
    public var safetyEvalP113Ms: Int
    public var snapshotFinalizationP112Ms: Int
    public var snapshotFinalizationP113Ms: Int
    public var activeStateP112Ms: Int
    public var runtimeBatchP113Ms: Int
    public var runtimeIndexBuildP113Ms: Int
    public var runtimeBatchLookupP113Ms: Int
    public var deferPlannerP113Ms: Int
    public var entitiesRuntimeRequiredP113: Int
    public var entitiesDeferredP113: Int
}

extension P113RuntimeComparison {
    public static let p112Baseline = P113RuntimeComparison(
        p112TotalSeconds: 81.6,
        p113TotalSeconds: 0,
        safetyEvalP112Ms: 26_152,
        safetyEvalP113Ms: 0,
        snapshotFinalizationP112Ms: 17_042,
        snapshotFinalizationP113Ms: 0,
        activeStateP112Ms: 11_256,
        runtimeBatchP113Ms: 0,
        runtimeIndexBuildP113Ms: 0,
        runtimeBatchLookupP113Ms: 0,
        deferPlannerP113Ms: 0,
        entitiesRuntimeRequiredP113: 0,
        entitiesDeferredP113: 0
    )
}
