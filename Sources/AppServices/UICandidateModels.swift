import Foundation
import SafetyCore

// P2.3 — Presentation models. UI displays canonical SafetyCore truth; does not infer it.

public enum UICandidateGroup: String, Codable, Sendable, CaseIterable {
    case safeActions = "SAFE_ACTIONS"
    case reviewNeeded = "REVIEW_NEEDED"
    case protected = "PROTECTED"
}

public enum UIReadinessState: String, Codable, Sendable, CaseIterable {
    case verifyMore = "VERIFY_MORE"
    case preflightRequired = "PREFLIGHT_REQUIRED"
    case approvalRequired = "APPROVAL_REQUIRED"
    case executing = "EXECUTING"
    case postVerifyPending = "POST_VERIFY_PENDING"
    case completed = "COMPLETED"
    case storageRecoveryPending = "STORAGE_RECOVERY_PENDING"
    case regenerated = "REGENERATED"
    case failed = "FAILED"
    case unknown = "UNKNOWN"

    public var userLabel: String {
        switch self {
        case .verifyMore: return "More verification needed"
        case .preflightRequired: return "Safety check required"
        case .approvalRequired: return "Ready for your approval"
        case .executing: return "Moving to Trash…"
        case .postVerifyPending: return "Moved. Verifying…"
        case .completed: return "Action verified"
        case .storageRecoveryPending: return "Disk recovery pending"
        case .regenerated: return "Xcode regenerated this data"
        case .failed: return "Action stopped"
        case .unknown: return "Status unknown"
        }
    }
}

public struct StorageOverviewState: Codable, Sendable, Equatable {
    public var observedBytes: Int64
    public var observedBytesLabel: String
    public var safeActionCount: Int
    public var reviewCount: Int
    public var protectedCount: Int
    public var lastScanAt: Date?
    public var scanRuntimeSeconds: Double?

    public static let empty = StorageOverviewState(
        observedBytes: 0,
        observedBytesLabel: "0 B",
        safeActionCount: 0,
        reviewCount: 0,
        protectedCount: 0
    )

    public init(
        observedBytes: Int64,
        observedBytesLabel: String,
        safeActionCount: Int,
        reviewCount: Int,
        protectedCount: Int,
        lastScanAt: Date? = nil,
        scanRuntimeSeconds: Double? = nil
    ) {
        self.observedBytes = observedBytes
        self.observedBytesLabel = observedBytesLabel
        self.safeActionCount = safeActionCount
        self.reviewCount = reviewCount
        self.protectedCount = protectedCount
        self.lastScanAt = lastScanAt
        self.scanRuntimeSeconds = scanRuntimeSeconds
    }
}

public struct UIEvidenceLine: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var satisfied: Bool
    public var userText: String
    public var technicalDetail: String?
}

public struct UICandidateItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var entityID: String
    public var displayName: String
    public var category: String
    public var pathSummary: String
    public var fullPath: String
    public var byteLabel: String
    public var expectedBytes: Int64?
    public var recommendedAction: StorageAction?
    public var recommendedActionLabel: String
    public var reasonSummary: String
    public var readiness: UIReadinessState
    public var group: UICandidateGroup
    public var safetyClass: SafetyClass
    public var evidenceLines: [UIEvidenceLine]
    public var executorAvailable: Bool
}

public struct UICandidateDetail: Codable, Sendable, Equatable {
    public var item: UICandidateItem
    public var consequenceCopy: String
    public var recoverySemantics: String
    public var reversibilityCopy: String
    public var technicalDetails: UITechnicalDetails
}

public struct UITechnicalDetails: Codable, Sendable, Equatable {
    public var entityID: String
    public var canonicalPath: String
    public var safetyClass: String
    public var readiness: String
    public var gateReadiness: String?
    public var bindingFingerprintSummary: String?
    public var auditID: String?
    public var postVerificationState: String?
}

public struct UIPreflightResult: Codable, Sendable, Equatable {
    public var entityID: String
    public var action: StorageAction
    public var readiness: UIReadinessState
    public var satisfiedLines: [UIEvidenceLine]
    public var blockingLines: [UIEvidenceLine]
    public var bindingFingerprint: ActionBindingFingerprint?
    public var receipt: PreflightReceipt?
    public var canApprove: Bool
    public var userMessage: String
}

public struct UIApprovalState: Codable, Sendable, Equatable {
    public var approval: UserActionApproval
    public var receipt: PreflightReceipt
    public var entityID: String
    public var action: StorageAction
    public var boundAt: Date
}

public struct UIExecutionOutcome: Codable, Sendable, Equatable {
    public var entityID: String
    public var action: StorageAction
    public var readiness: UIReadinessState
    public var logicalActionCompleted: Bool
    public var storageRecoveryState: StorageRecoveryState
    public var recoveryLabel: String
    public var potentialRecoveryLabel: String?
    public var movedBytesLabel: String?
    public var trashWarning: String?
    public var userLines: [String]
    public var executionReport: ActFirstMutationExecutionReport?
    public var postVerification: PostMutationVerificationResult?
    public var errorMessage: String?
}

public struct UIActionHistoryItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var timestamp: Date
    public var entityID: String
    public var displayName: String
    public var action: StorageAction
    public var actionLabel: String
    public var logicalVerified: Bool
    public var storageRecoveryPending: Bool
    public var readiness: UIReadinessState
    public var summaryLines: [String]
    public var permitID: String?
    public var verifiedRecoveredBytes: Int64?
    public var recoveryPresentation: String?

    public init(
        id: String,
        timestamp: Date,
        entityID: String,
        displayName: String,
        action: StorageAction,
        actionLabel: String,
        logicalVerified: Bool,
        storageRecoveryPending: Bool,
        readiness: UIReadinessState,
        summaryLines: [String],
        permitID: String? = nil,
        verifiedRecoveredBytes: Int64? = nil,
        recoveryPresentation: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.entityID = entityID
        self.displayName = displayName
        self.action = action
        self.actionLabel = actionLabel
        self.logicalVerified = logicalVerified
        self.storageRecoveryPending = storageRecoveryPending
        self.readiness = readiness
        self.summaryLines = summaryLines
        self.permitID = permitID
        self.verifiedRecoveredBytes = verifiedRecoveredBytes
        self.recoveryPresentation = recoveryPresentation
    }
}

public struct UIActionSurfaceReport: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var candidateCount: Int
    public var safeActionCount: Int
    public var reviewCount: Int
    public var protectedCount: Int
    public var selectedCandidateID: String?
    public var preflightState: String?
    public var approvalState: String?
    public var executionState: String?
    public var postVerificationState: String?
    public var recoveryState: String?
}
