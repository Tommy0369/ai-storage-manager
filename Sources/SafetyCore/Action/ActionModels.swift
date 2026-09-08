import Foundation

// P2.0 — Canonical action model. Execution NOT STARTED. See docs/ACTION_ARCHITECTURE_v0.1.md

public enum ActionBlockReason: String, Codable, Sendable, CaseIterable {
    case sourceOfTruthProtected = "SOURCE_OF_TRUTH_PROTECTED"
    case applicationManagedData = "APPLICATION_MANAGED_DATA"
    case userOriginalRequiresPreservation = "USER_ORIGINAL_REQUIRES_PRESERVATION"
    case sourceActive = "SOURCE_ACTIVE"
    case sourceOpen = "SOURCE_OPEN"
    case sourceChanged = "SOURCE_CHANGED"
    case iCloudUnavailable = "ICLOUD_UNAVAILABLE"
    case iCloudQuotaUnknown = "ICLOUD_QUOTA_UNKNOWN"
    case destinationConflict = "DESTINATION_CONFLICT"
    case remoteCopyUnknown = "REMOTE_COPY_UNKNOWN"
    case syncStateUnknown = "SYNC_STATE_UNKNOWN"
    case fileProviderRequired = "FILE_PROVIDER_REQUIRED"
    case nativeEvictionUnavailable = "NATIVE_EVICTION_UNAVAILABLE"
    case voiceMemoNativeSyncRequired = "VOICE_MEMO_NATIVE_SYNC_REQUIRED"
    case iosBackupRequiresDeviceAwareMigration = "IOS_BACKUP_REQUIRES_DEVICE_AWARE_MIGRATION"
    case relocationContractMissing = "RELOCATION_CONTRACT_MISSING"
    case evidenceStale = "EVIDENCE_STALE"
    case evidenceConflict = "EVIDENCE_CONFLICT"
    case verificationIncomplete = "VERIFICATION_INCOMPLETE"
    case safetyClassRed = "SAFETY_CLASS_RED"
    case safetyClassUnknown = "SAFETY_CLASS_UNKNOWN"
    case regenerabilityUnknown = "REGENERABILITY_UNKNOWN"
    /// Vendor-native exact remote reacquisition missing/stale — NOT regenerability.
    case reacquisitionNotStrictVerified = "REACQUISITION_NOT_STRICT_VERIFIED"
    case sourceOfTruthUnknown = "SOURCE_OF_TRUTH_UNKNOWN"
    case notApplicable = "NOT_APPLICABLE"
    case permanentDeleteForbidden = "PERMANENT_DELETE_FORBIDDEN"
}

public enum ClaimType: String, Codable, Sendable {
    case canonicalPath = "CANONICAL_PATH"
    case entityIdentity = "ENTITY_IDENTITY"
    case userOwned = "USER_OWNED"
    case sourceOfTruth = "SOURCE_OF_TRUTH"
    case regenerability = "REGENERABILITY"
    case referenceGraph = "REFERENCE_GRAPH"
    case reacquisition = "REACQUISITION"
    case vendorOwnership = "VENDOR_OWNERSHIP"
    case activeState = "ACTIVE_STATE"
    case openFileState = "OPEN_FILE_STATE"
    case fileProviderBacked = "FILE_PROVIDER_BACKED"
    case remoteBacking = "REMOTE_BACKING"
    case syncSafe = "SYNC_SAFE"
    case iCloudAvailable = "ICLOUD_AVAILABLE"
    case preservationContract = "PRESERVATION_CONTRACT"
    case relocationSupported = "RELOCATION_SUPPORTED"
}

public enum FreshnessRequirement: String, Codable, Sendable {
    case staticClaim = "STATIC"
    case sessionStable = "SESSION_STABLE"
    case runtimeFresh = "RUNTIME_FRESH"
    case cloudFresh = "CLOUD_FRESH"
    case remoteStateFresh = "REMOTE_STATE_FRESH"
}

public struct ClaimRequirement: Codable, Sendable, Equatable {
    public var claimType: ClaimType
    public var requiredPredicate: PredicateValue?
    public var minimumConfidence: EvidenceConfidence
    public var freshness: FreshnessRequirement

    public init(
        claimType: ClaimType,
        requiredPredicate: PredicateValue? = .true,
        minimumConfidence: EvidenceConfidence = .verified,
        freshness: FreshnessRequirement = .staticClaim
    ) {
        self.claimType = claimType
        self.requiredPredicate = requiredPredicate
        self.minimumConfidence = minimumConfidence
        self.freshness = freshness
    }
}

public struct ActionDecision: Codable, Sendable, Equatable {
    public var entityID: String
    public var action: StorageAction
    public var safetyClass: SafetyClass
    public var eligible: Bool
    public var requiredClaims: [ClaimRequirement]
    public var satisfiedClaimTypes: [ClaimType]
    public var missingClaimTypes: [ClaimType]
    public var blockedReasons: [ActionBlockReason]
    public var expectedLocalRecoveryBytes: Int64?
    public var expectedLogicalBytesMoved: Int64?
    public var recoveryConfidence: EvidenceConfidence
    public var explanationCodes: [String]

    public init(
        entityID: String,
        action: StorageAction,
        safetyClass: SafetyClass,
        eligible: Bool,
        requiredClaims: [ClaimRequirement] = [],
        satisfiedClaimTypes: [ClaimType] = [],
        missingClaimTypes: [ClaimType] = [],
        blockedReasons: [ActionBlockReason] = [],
        expectedLocalRecoveryBytes: Int64? = nil,
        expectedLogicalBytesMoved: Int64? = nil,
        recoveryConfidence: EvidenceConfidence = .unknown,
        explanationCodes: [String] = []
    ) {
        self.entityID = entityID
        self.action = action
        self.safetyClass = safetyClass
        self.eligible = eligible
        self.requiredClaims = requiredClaims
        self.satisfiedClaimTypes = satisfiedClaimTypes
        self.missingClaimTypes = missingClaimTypes
        self.blockedReasons = blockedReasons
        self.expectedLocalRecoveryBytes = expectedLocalRecoveryBytes
        self.expectedLogicalBytesMoved = expectedLogicalBytesMoved
        self.recoveryConfidence = recoveryConfidence
        self.explanationCodes = explanationCodes
    }
}

public struct BlockedAction: Codable, Sendable, Equatable {
    public var action: StorageAction
    public var reasons: [ActionBlockReason]
}

public enum RecommendationDisposition: Codable, Sendable, Equatable {
    case actionable(StorageAction)
    case keep
    case verifyMore([ClaimType])

    enum CodingKeys: String, CodingKey { case kind, action, claims }
    enum Kind: String, Codable { case actionable, keep, verifyMore }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .actionable:
            self = .actionable(try c.decode(StorageAction.self, forKey: .action))
        case .keep:
            self = .keep
        case .verifyMore:
            self = .verifyMore(try c.decode([ClaimType].self, forKey: .claims))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .actionable(let a):
            try c.encode(Kind.actionable, forKey: .kind)
            try c.encode(a, forKey: .action)
        case .keep:
            try c.encode(Kind.keep, forKey: .kind)
        case .verifyMore(let claims):
            try c.encode(Kind.verifyMore, forKey: .kind)
            try c.encode(claims, forKey: .claims)
        }
    }
}

public struct ActionRecommendationResult: Codable, Sendable, Equatable {
    public var entityID: String
    public var path: String
    public var disposition: RecommendationDisposition
    public var recommendedAction: StorageAction
    public var alternatives: [StorageAction]
    public var recommendationReasons: [String]
    public var blockedActions: [BlockedAction]
    public var confidence: EvidenceConfidence
    public var expectedLocalRecoveryBytes: Int64?
    public var recoveryConfidence: EvidenceConfidence
    public var missingProof: [ClaimType]
}

public struct ActionPreflightResult: Codable, Sendable, Equatable {
    public var action: StorageAction
    public var entityID: String
    public var path: String
    public var allowed: Bool
    public var satisfied: [ClaimType]
    public var missing: [ClaimType]
    public var stale: [ClaimType]
    public var conflicted: [ClaimType]
    public var blockedReasons: [ActionBlockReason]
    public var wouldExecuteNow: Bool
}

public struct ActionUserContext: Codable, Sendable, Equatable {
    public var wantsMoreFreeSpace: Bool
    public var iCloudEnabled: Bool?
    public var allowManualReview: Bool

    public static let `default` = ActionUserContext(wantsMoreFreeSpace: true, iCloudEnabled: nil, allowManualReview: true)
}

public struct RelocationContract: Codable, Sendable, Equatable {
    public var semanticType: String
    public var action: StorageAction
    public var supported: Bool
    public var requiredClaims: [ClaimRequirement]
}

public struct ActionAuditRecord: Codable, Sendable, Equatable {
    public var actionID: String
    public var entityID: String
    public var action: StorageAction
    public var sourcePath: String
    public var destinationPath: String?
    public var preflightClaims: [ClaimType]
    public var transactionPhase: String?
    public var logicalBytesAffected: Int64?
    public var measuredRecoveryBytes: Int64?
    public var failureReason: String?
    public var startedAt: Date
    public var auditStatus: String?
    public var bindingFingerprint: ActionBindingFingerprint?
    public var approvalID: String?
    public var preflightReceiptID: String?
    public var executedAt: Date?
    public var freeBytesBeforeAction: Int64?
    public var freeBytesAfterAction: Int64?
    public var notes: [String]

    public init(
        actionID: String,
        entityID: String,
        action: StorageAction,
        sourcePath: String,
        destinationPath: String? = nil,
        preflightClaims: [ClaimType] = [],
        transactionPhase: String? = nil,
        logicalBytesAffected: Int64? = nil,
        measuredRecoveryBytes: Int64? = nil,
        failureReason: String? = nil,
        startedAt: Date,
        auditStatus: String? = nil,
        bindingFingerprint: ActionBindingFingerprint? = nil,
        approvalID: String? = nil,
        preflightReceiptID: String? = nil,
        executedAt: Date? = nil,
        freeBytesBeforeAction: Int64? = nil,
        freeBytesAfterAction: Int64? = nil,
        notes: [String] = []
    ) {
        self.actionID = actionID
        self.entityID = entityID
        self.action = action
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.preflightClaims = preflightClaims
        self.transactionPhase = transactionPhase
        self.logicalBytesAffected = logicalBytesAffected
        self.measuredRecoveryBytes = measuredRecoveryBytes
        self.failureReason = failureReason
        self.startedAt = startedAt
        self.auditStatus = auditStatus
        self.bindingFingerprint = bindingFingerprint
        self.approvalID = approvalID
        self.preflightReceiptID = preflightReceiptID
        self.executedAt = executedAt
        self.freeBytesBeforeAction = freeBytesBeforeAction
        self.freeBytesAfterAction = freeBytesAfterAction
        self.notes = notes
    }
}

public struct ActionArchitectureReport: Codable, Sendable, Equatable {
    public var recommendations: [ActionRecommendationResult]
    public var preflightPreviews: [ActionPreflightResult]
    public var blockedSummaries: [ActionBlockedSummary]
    public var iCloudMoveCandidates: [ActionRecommendationResult]
    public var removeLocalDownloadCandidates: [ActionRecommendationResult]
    public var previewExecutable: Bool
    public var destructiveActionsExecuted: Bool
}

public struct ActionBlockedSummary: Codable, Sendable, Equatable {
    public var entityID: String
    public var path: String
    public var action: StorageAction
    public var reasons: [ActionBlockReason]
}
