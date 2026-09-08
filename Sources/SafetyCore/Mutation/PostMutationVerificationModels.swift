import Foundation

// P2.2 — Post-mutation verification canonical model. Read-only observation only.

public enum PostMutationVerificationState: String, Codable, Sendable, CaseIterable {
    case notVerified = "NOT_VERIFIED"
    case verifying = "VERIFYING"
    case actionConfirmed = "ACTION_CONFIRMED"
    case actionPartiallyConfirmed = "ACTION_PARTIALLY_CONFIRMED"
    case actionFailed = "ACTION_FAILED"
    case stateChanged = "STATE_CHANGED"
    case regenerated = "REGENERATED"
    case storageRecoveryPending = "STORAGE_RECOVERY_PENDING"
    case storageRecoveryVerified = "STORAGE_RECOVERY_VERIFIED"
    case unknown = "UNKNOWN"
}

public enum StorageRecoveryState: String, Codable, Sendable {
    case notMeasured = "NOT_MEASURED"
    case recoveryPending = "STORAGE_RECOVERY_PENDING"
    case recoveryVerified = "STORAGE_RECOVERY_VERIFIED"
    case recoveryUnknown = "RECOVERY_UNKNOWN"
}

public enum RecoveryConfidence: String, Codable, Sendable {
    case exact = "EXACT"
    case estimated = "ESTIMATED"
    case unknown = "UNKNOWN"
}

public enum SourcePathState: String, Codable, Sendable {
    case absent = "ABSENT"
    case present = "PRESENT"
    case changed = "CHANGED"
    case unknown = "UNKNOWN"
}

public enum DestinationState: String, Codable, Sendable {
    case trashObserved = "TRASH_OBSERVED"
    case trashNotObserved = "TRASH_NOT_OBSERVED"
    case notApplicable = "NOT_APPLICABLE"
    case unknown = "UNKNOWN"
}

public enum AuditLifecycleStatus: String, Codable, Sendable, CaseIterable {
    case planned = "PLANNED"
    case preflighted = "PREFLIGHTED"
    case approved = "APPROVED"
    case executed = "EXECUTED"
    case postVerifyPending = "POST_VERIFY_PENDING"
    case postVerified = "POST_VERIFIED"
    case failed = "FAILED"
    case unknown = "UNKNOWN"
}

public enum SemanticSuccessorRelationship: String, Codable, Sendable {
    case regeneratedAs = "REGENERATED_AS"
    case semanticSuccessor = "SEMANTIC_SUCCESSOR"
    case none = "NONE"
}

public struct PostMutationObservation: Codable, Sendable, Equatable {
    public var sourcePathState: SourcePathState
    public var sourceIdentityMatch: Bool
    public var trashEntityObserved: Bool
    public var trashIdentityMatch: Bool
    public var trashPath: String?
    public var siblingUnchanged: Bool
    public var bindingMatches: Bool
    public var auditRecordMatches: Bool

    public init(
        sourcePathState: SourcePathState,
        sourceIdentityMatch: Bool,
        trashEntityObserved: Bool,
        trashIdentityMatch: Bool,
        trashPath: String?,
        siblingUnchanged: Bool,
        bindingMatches: Bool,
        auditRecordMatches: Bool
    ) {
        self.sourcePathState = sourcePathState
        self.sourceIdentityMatch = sourceIdentityMatch
        self.trashEntityObserved = trashEntityObserved
        self.trashIdentityMatch = trashIdentityMatch
        self.trashPath = trashPath
        self.siblingUnchanged = siblingUnchanged
        self.bindingMatches = bindingMatches
        self.auditRecordMatches = auditRecordMatches
    }
}

public struct PostMutationVerificationResult: Codable, Sendable, Equatable {
    public var actionID: String
    public var entityID: String
    public var action: StorageAction
    public var preMutationBindingFingerprint: ActionBindingFingerprint
    public var postMutationObservation: PostMutationObservation
    public var verificationState: PostMutationVerificationState
    public var logicalActionCompleted: Bool
    public var storageRecoveryState: StorageRecoveryState
    public var expectedBytes: Int64?
    public var measuredBytesBefore: Int64?
    public var measuredBytesAfter: Int64?
    public var freeBytesBeforeAction: Int64?
    public var freeBytesAfterAction: Int64?
    public var freeBytesAfterPostVerifyScan: Int64?
    public var actualRecoveredBytes: Int64?
    public var recoveryConfidence: RecoveryConfidence
    public var trashStillHoldingData: Bool
    public var entityRegenerated: Bool
    public var regeneratedEntityID: String?
    public var semanticRelationship: SemanticSuccessorRelationship
    public var auditStatus: AuditLifecycleStatus
    public var verificationTimestamp: Date
    public var executedAt: Date?
    public var preflightObservedAt: Date?
    public var regeneratedEntityObservedAt: Date?
    public var contractVersion: String
    public var contractSteps: [PostActionVerifyStepResult]
    public var errors: [String]
    public var unknownReasons: [String]

    public init(
        actionID: String,
        entityID: String,
        action: StorageAction,
        preMutationBindingFingerprint: ActionBindingFingerprint,
        postMutationObservation: PostMutationObservation,
        verificationState: PostMutationVerificationState,
        logicalActionCompleted: Bool,
        storageRecoveryState: StorageRecoveryState,
        expectedBytes: Int64?,
        measuredBytesBefore: Int64?,
        measuredBytesAfter: Int64?,
        freeBytesBeforeAction: Int64?,
        freeBytesAfterAction: Int64?,
        freeBytesAfterPostVerifyScan: Int64?,
        actualRecoveredBytes: Int64?,
        recoveryConfidence: RecoveryConfidence,
        trashStillHoldingData: Bool,
        entityRegenerated: Bool,
        regeneratedEntityID: String?,
        semanticRelationship: SemanticSuccessorRelationship,
        auditStatus: AuditLifecycleStatus,
        verificationTimestamp: Date,
        executedAt: Date?,
        preflightObservedAt: Date?,
        regeneratedEntityObservedAt: Date?,
        contractVersion: String,
        contractSteps: [PostActionVerifyStepResult],
        errors: [String],
        unknownReasons: [String]
    ) {
        self.actionID = actionID
        self.entityID = entityID
        self.action = action
        self.preMutationBindingFingerprint = preMutationBindingFingerprint
        self.postMutationObservation = postMutationObservation
        self.verificationState = verificationState
        self.logicalActionCompleted = logicalActionCompleted
        self.storageRecoveryState = storageRecoveryState
        self.expectedBytes = expectedBytes
        self.measuredBytesBefore = measuredBytesBefore
        self.measuredBytesAfter = measuredBytesAfter
        self.freeBytesBeforeAction = freeBytesBeforeAction
        self.freeBytesAfterAction = freeBytesAfterAction
        self.freeBytesAfterPostVerifyScan = freeBytesAfterPostVerifyScan
        self.actualRecoveredBytes = actualRecoveredBytes
        self.recoveryConfidence = recoveryConfidence
        self.trashStillHoldingData = trashStillHoldingData
        self.entityRegenerated = entityRegenerated
        self.regeneratedEntityID = regeneratedEntityID
        self.semanticRelationship = semanticRelationship
        self.auditStatus = auditStatus
        self.verificationTimestamp = verificationTimestamp
        self.executedAt = executedAt
        self.preflightObservedAt = preflightObservedAt
        self.regeneratedEntityObservedAt = regeneratedEntityObservedAt
        self.contractVersion = contractVersion
        self.contractSteps = contractSteps
        self.errors = errors
        self.unknownReasons = unknownReasons
    }
}

public struct StorageRecoveryResult: Codable, Sendable, Equatable {
    public var actionID: String
    public var entityID: String
    public var expectedPotentialRecoveryBytes: Int64?
    public var freeBytesBefore: Int64?
    public var freeBytesImmediatelyAfterAction: Int64?
    public var freeBytesPostVerify: Int64?
    public var actualObservedDelta: Int64?
    public var confidence: RecoveryConfidence
    public var trashStillHoldingData: Bool
    public var regenerationOccurred: Bool
    public var reasonCodes: [String]
    public var notes: String?
}

public struct PendingPostMutationVerification: Codable, Sendable, Equatable, Identifiable {
    public var id: String { actionID }
    public var actionID: String
    public var entityID: String
    public var action: StorageAction
    public var bindingFingerprint: ActionBindingFingerprint
    public var sourcePath: String
    public var expectedDestinationSemantics: String
    public var trashDestinationPath: String?
    public var expectedBytes: Int64?
    public var executedAt: Date
    public var approvalID: String?
    public var preflightReceiptID: String?
    public var preflightObservedAt: Date?
    public var auditStatus: AuditLifecycleStatus
    public var freeBytesBeforeAction: Int64?
    public var freeBytesAfterAction: Int64?
    public var verificationDeadline: Date?
}

public struct PendingPostMutationRegistryDocument: Codable, Sendable, Equatable {
    public var pending: [PendingPostMutationVerification]
    public var closed: [PostMutationVerificationResult]

    public static let empty = PendingPostMutationRegistryDocument(pending: [], closed: [])

    public init(pending: [PendingPostMutationVerification], closed: [PostMutationVerificationResult]) {
        self.pending = pending
        self.closed = closed
    }
}

public struct ActionHistoryItem: Codable, Sendable, Equatable {
    public var actionID: String
    public var entityID: String
    public var action: StorageAction
    public var sourcePath: String
    public var plannedAt: Date?
    public var preflightedAt: Date?
    public var approvedAt: Date?
    public var executedAt: Date?
    public var postVerifiedAt: Date?
    public var auditStatus: AuditLifecycleStatus
    public var verificationState: PostMutationVerificationState?
    public var logicalActionCompleted: Bool?
    public var storageRecoveryState: StorageRecoveryState?
    public var approvalID: String?
    public var permitID: String?
}

public struct ActionHistoryReport: Codable, Sendable, Equatable {
    public var items: [ActionHistoryItem]
    public var generatedAt: Date
}

public struct PostMutationVerificationReport: Codable, Sendable, Equatable {
    public var results: [PostMutationVerificationResult]
    public var pendingCount: Int
    public var closedCount: Int
    public var generatedAt: Date
}

public struct PostMutationScanSummary: Codable, Sendable, Equatable {
    public var lines: [String]
    public var hasPendingVerification: Bool
}
