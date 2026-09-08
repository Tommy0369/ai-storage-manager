import Foundation
import SafetyCore

public enum OptimizationGoalKind: String, Codable, Sendable, Equatable {
    case freeLocalSpace = "FREE_LOCAL_SPACE"
}

public enum OptimizationGoalError: Error, Equatable, Sendable {
    case nonPositive
    case overflow
}

public struct OptimizationGoal: Codable, Sendable, Equatable {
    public var kind: OptimizationGoalKind
    public var targetBytes: Int64
    public var excludeEntityIDs: Set<String>
    public var excludeCategories: Set<String>
    public var allowedActions: Set<String>
    public var maxActionCount: Int?
    public var preferReversible: Bool

    public static let maxReasonableBytes: Int64 = 10_000_000_000_000 // 10 TB

    public init(
        kind: OptimizationGoalKind = .freeLocalSpace,
        targetBytes: Int64,
        excludeEntityIDs: Set<String> = [],
        excludeCategories: Set<String> = [],
        allowedActions: Set<String> = [],
        maxActionCount: Int? = nil,
        preferReversible: Bool = true
    ) throws {
        guard targetBytes > 0 else { throw OptimizationGoalError.nonPositive }
        guard targetBytes <= Self.maxReasonableBytes else { throw OptimizationGoalError.overflow }
        self.kind = kind
        self.targetBytes = targetBytes
        self.excludeEntityIDs = excludeEntityIDs
        self.excludeCategories = excludeCategories
        self.allowedActions = allowedActions
        self.maxActionCount = maxActionCount
        self.preferReversible = preferReversible
    }

    public static func gigabytes(_ value: Int) throws -> OptimizationGoal {
        guard value > 0 else { throw OptimizationGoalError.nonPositive }
        let (bytes, overflow) = Int64(value).multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflow else { throw OptimizationGoalError.overflow }
        return try OptimizationGoal(targetBytes: bytes)
    }
}

public enum OptimizationEligibilityTier: String, Codable, Sendable, Equatable {
    case executableNow = "EXECUTABLE_NOW"
    case verifiedButExecutorUnavailable = "VERIFIED_BUT_EXECUTOR_UNAVAILABLE"
    case requiresVendorRestoration = "REQUIRES_VENDOR_RESTORATION"
    case preflightRequired = "PREFLIGHT_REQUIRED"
    case approvalRequired = "APPROVAL_REQUIRED"
    case verifyMore = "VERIFY_MORE"
    case blocked = "BLOCKED"
    case protectedTier = "PROTECTED"
}

public enum OptimizationGoalStatus: String, Codable, Sendable, Equatable {
    case achievableNow = "ACHIEVABLE_NOW"
    case partiallyAchievable = "PARTIALLY_ACHIEVABLE"
    case achievableWithFutureCapabilities = "ACHIEVABLE_WITH_FUTURE_CAPABILITIES"
    case needsMoreVerification = "NEEDS_MORE_VERIFICATION"
    case noSafeOptions = "NO_SAFE_OPTIONS"
}

public enum OptimizationPlanFreshness: String, Codable, Sendable, Equatable {
    case current = "CURRENT"
    case stale = "STALE"
}

public struct OptimizationActionFact: Codable, Sendable, Equatable {
    public var entityID: String
    public var displayName: String
    public var canonicalPath: String
    public var action: StorageAction
    public var eligible: Bool
    public var safetyClass: SafetyClass
    public var expectedLogicalBytes: Int64
    public var blockedReasons: [String]
    public var explanation: String

    public init(
        entityID: String,
        displayName: String,
        canonicalPath: String,
        action: StorageAction,
        eligible: Bool,
        safetyClass: SafetyClass,
        expectedLogicalBytes: Int64,
        blockedReasons: [String] = [],
        explanation: String = ""
    ) {
        self.entityID = entityID
        self.displayName = displayName
        self.canonicalPath = canonicalPath
        self.action = action
        self.eligible = eligible
        self.safetyClass = safetyClass
        self.expectedLogicalBytes = expectedLogicalBytes
        self.blockedReasons = blockedReasons
        self.explanation = explanation
    }
}

public struct OptimizationCandidate: Codable, Sendable, Equatable, Identifiable {
    public var id: String { candidateID }
    public var candidateID: String
    public var entityID: String
    public var displayName: String
    public var canonicalPath: String
    public var action: StorageAction
    public var readiness: UIReadinessState
    public var executionSupport: ActionExecutionSupport
    public var logicalBytes: Int64
    public var potentialRecoveryBytes: Int64
    public var immediateExpectedRecoveryBytes: Int64
    public var verifiedRecoveredBytes: Int64
    public var recoveryState: String
    public var safetyClass: SafetyClass
    public var blastRadius: BlastRadiusClass
    public var reversibility: String
    public var transactionComplexity: TransactionComplexityClass
    public var independenceGroup: String
    public var blockers: [String]
    public var explanation: String
    public var whyIncluded: [String]
    public var whyExcluded: String?
    public var tier: OptimizationEligibilityTier
    public var category: String

    public init(
        candidateID: String,
        entityID: String,
        displayName: String,
        canonicalPath: String,
        action: StorageAction,
        readiness: UIReadinessState,
        executionSupport: ActionExecutionSupport,
        logicalBytes: Int64,
        potentialRecoveryBytes: Int64,
        immediateExpectedRecoveryBytes: Int64,
        verifiedRecoveredBytes: Int64 = 0,
        recoveryState: String,
        safetyClass: SafetyClass,
        blastRadius: BlastRadiusClass,
        reversibility: String,
        transactionComplexity: TransactionComplexityClass,
        independenceGroup: String,
        blockers: [String],
        explanation: String,
        whyIncluded: [String] = [],
        whyExcluded: String? = nil,
        tier: OptimizationEligibilityTier,
        category: String = ""
    ) {
        self.candidateID = candidateID
        self.entityID = entityID
        self.displayName = displayName
        self.canonicalPath = canonicalPath
        self.action = action
        self.readiness = readiness
        self.executionSupport = executionSupport
        self.logicalBytes = logicalBytes
        self.potentialRecoveryBytes = potentialRecoveryBytes
        self.immediateExpectedRecoveryBytes = immediateExpectedRecoveryBytes
        self.verifiedRecoveredBytes = verifiedRecoveredBytes
        self.recoveryState = recoveryState
        self.safetyClass = safetyClass
        self.blastRadius = blastRadius
        self.reversibility = reversibility
        self.transactionComplexity = transactionComplexity
        self.independenceGroup = independenceGroup
        self.blockers = blockers
        self.explanation = explanation
        self.whyIncluded = whyIncluded
        self.whyExcluded = whyExcluded
        self.tier = tier
        self.category = category
    }
}

public struct OptimizationPlanEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { candidate.candidateID }
    public var candidate: OptimizationCandidate
    public var selected: Bool
    public var stale: Bool
    public var completionState: String?

    public init(
        candidate: OptimizationCandidate,
        selected: Bool,
        stale: Bool = false,
        completionState: String? = nil
    ) {
        self.candidate = candidate
        self.selected = selected
        self.stale = stale
        self.completionState = completionState
    }
}

public struct OptimizationExcludedReason: Codable, Sendable, Equatable {
    public var entityID: String
    public var displayName: String
    public var reason: String
    public var bytes: Int64
}

public struct OptimizationCandidateConflict: Codable, Sendable, Equatable {
    public var leftID: String
    public var rightID: String
    public var kind: String
}

public struct OptimizationPlan: Codable, Sendable, Equatable {
    public var planID: String
    public var createdAt: Date
    public var goal: OptimizationGoal
    public var planningSnapshotID: String
    public var freshness: OptimizationPlanFreshness
    public var entries: [OptimizationPlanEntry]
    public var availableNowPotentialBytes: Int64
    public var verifiedFuturePotentialBytes: Int64
    public var requiresVendorRestorationPotentialBytes: Int64
    public var preflightPossibleBytes: Int64
    public var requestedBytes: Int64
    public var shortfallBytes: Int64
    public var goalStatus: OptimizationGoalStatus
    public var excludedSummary: [OptimizationExcludedReason]
    public var conflicts: [OptimizationCandidateConflict]
    public var overlapBytesPrevented: Int64
    public var warnings: [String]
    public var contextNotes: [String]
    public var funnel: OptimizationCandidateFunnel
    public var candidateBuildMs: Int
    public var conflictResolutionMs: Int
    public var planSelectionMs: Int
    public var planTotalMs: Int
    public var falseGREEN: Int
    public var duplicateEvaluations: Int
    public var approvalCreated: Bool
    public var executionPermitCreated: Bool
    public var executorCalled: Bool
    public var bulkActionPresent: Bool

    public var selectedEntries: [OptimizationPlanEntry] {
        entries.filter(\.selected)
    }

    public init(
        planID: String,
        createdAt: Date,
        goal: OptimizationGoal,
        planningSnapshotID: String,
        freshness: OptimizationPlanFreshness,
        entries: [OptimizationPlanEntry],
        availableNowPotentialBytes: Int64,
        verifiedFuturePotentialBytes: Int64,
        requiresVendorRestorationPotentialBytes: Int64 = 0,
        preflightPossibleBytes: Int64,
        requestedBytes: Int64,
        shortfallBytes: Int64,
        goalStatus: OptimizationGoalStatus,
        excludedSummary: [OptimizationExcludedReason],
        conflicts: [OptimizationCandidateConflict],
        overlapBytesPrevented: Int64,
        warnings: [String],
        contextNotes: [String],
        funnel: OptimizationCandidateFunnel,
        candidateBuildMs: Int,
        conflictResolutionMs: Int,
        planSelectionMs: Int,
        planTotalMs: Int,
        falseGREEN: Int,
        duplicateEvaluations: Int,
        approvalCreated: Bool,
        executionPermitCreated: Bool,
        executorCalled: Bool,
        bulkActionPresent: Bool
    ) {
        self.planID = planID
        self.createdAt = createdAt
        self.goal = goal
        self.planningSnapshotID = planningSnapshotID
        self.freshness = freshness
        self.entries = entries
        self.availableNowPotentialBytes = availableNowPotentialBytes
        self.verifiedFuturePotentialBytes = verifiedFuturePotentialBytes
        self.requiresVendorRestorationPotentialBytes = requiresVendorRestorationPotentialBytes
        self.preflightPossibleBytes = preflightPossibleBytes
        self.requestedBytes = requestedBytes
        self.shortfallBytes = shortfallBytes
        self.goalStatus = goalStatus
        self.excludedSummary = excludedSummary
        self.conflicts = conflicts
        self.overlapBytesPrevented = overlapBytesPrevented
        self.warnings = warnings
        self.contextNotes = contextNotes
        self.funnel = funnel
        self.candidateBuildMs = candidateBuildMs
        self.conflictResolutionMs = conflictResolutionMs
        self.planSelectionMs = planSelectionMs
        self.planTotalMs = planTotalMs
        self.falseGREEN = falseGREEN
        self.duplicateEvaluations = duplicateEvaluations
        self.approvalCreated = approvalCreated
        self.executionPermitCreated = executionPermitCreated
        self.executorCalled = executorCalled
        self.bulkActionPresent = bulkActionPresent
    }
}

public struct OptimizationCandidateFunnel: Codable, Sendable, Equatable {
    public var allEntityActionPairs: Int
    public var supportedActions: Int
    public var safetyEligible: Int
    public var exactBounded: Int
    public var nonOverlapping: Int
    public var executionSupported: Int
    public var preflightReady: Int
    public var selectedInPlan: Int
    public var dropReasons: [String]
}

public struct P303OptimizationPlanReport: Codable, Sendable, Equatable {
    public var planID: String
    public var goalBytes: Int64
    public var goalStatus: String
    public var planningSnapshotID: String
    public var candidateCount: Int
    public var readyNowCount: Int
    public var verifiedFutureCount: Int
    public var preflightCount: Int
    public var blockedCount: Int
    public var protectedCount: Int
    public var availableNowPotentialBytes: Int64
    public var verifiedFuturePotentialBytes: Int64
    public var preflightPossibleBytes: Int64
    public var shortfallBytes: Int64
    public var selectedEntries: [OptimizationPlanEntry]
    public var excludedReasons: [OptimizationExcludedReason]
    public var conflictCount: Int
    public var overlapBytesPrevented: Int64
    public var executorCapabilities: [String: String]
    public var falseGREEN: Int
    public var duplicateEvaluations: Int
    public var candidateBuildMs: Int
    public var conflictResolutionMs: Int
    public var planSelectionMs: Int
    public var planTotalMs: Int
    public var generatedAt: Date

    public init(from plan: OptimizationPlan) {
        self.planID = plan.planID
        self.goalBytes = plan.requestedBytes
        self.goalStatus = plan.goalStatus.rawValue
        self.planningSnapshotID = plan.planningSnapshotID
        self.candidateCount = plan.entries.count
        self.readyNowCount = plan.entries.filter { $0.candidate.tier == .executableNow || $0.candidate.tier == .approvalRequired }.count
        self.verifiedFutureCount = plan.entries.filter { $0.candidate.tier == .verifiedButExecutorUnavailable }.count
        self.preflightCount = plan.entries.filter { $0.candidate.tier == .preflightRequired }.count
        self.blockedCount = plan.entries.filter { $0.candidate.tier == .blocked }.count
        self.protectedCount = plan.entries.filter { $0.candidate.tier == .protectedTier }.count
        self.availableNowPotentialBytes = plan.availableNowPotentialBytes
        self.verifiedFuturePotentialBytes = plan.verifiedFuturePotentialBytes
        self.preflightPossibleBytes = plan.preflightPossibleBytes
        self.shortfallBytes = plan.shortfallBytes
        self.selectedEntries = plan.selectedEntries
        self.excludedReasons = plan.excludedSummary
        self.conflictCount = plan.conflicts.count
        self.overlapBytesPrevented = plan.overlapBytesPrevented
        self.executorCapabilities = ActionExecutionCapabilityRegistry.reportMap
        self.falseGREEN = plan.falseGREEN
        self.duplicateEvaluations = plan.duplicateEvaluations
        self.candidateBuildMs = plan.candidateBuildMs
        self.conflictResolutionMs = plan.conflictResolutionMs
        self.planSelectionMs = plan.planSelectionMs
        self.planTotalMs = plan.planTotalMs
        self.generatedAt = plan.createdAt
    }
}
