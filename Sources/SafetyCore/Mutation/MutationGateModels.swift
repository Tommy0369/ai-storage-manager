import Foundation

// P2.0 — Mutation gate types. Read-only. No execution authority.

public enum MutationReadiness: String, Codable, Sendable {
    case blocked = "BLOCKED"
    case verifyMore = "VERIFY_MORE"
    case preflightRequired = "PREFLIGHT_REQUIRED"
    case approvalRequired = "APPROVAL_REQUIRED"
    case contractSatisfiedReadOnly = "CONTRACT_SATISFIED_READ_ONLY"
}

public enum HardProductBlock: String, Codable, Sendable {
    case permanentDelete = "PERMANENT_DELETE"
    case rawRm = "RAW_RM"
    case unsafeBulkCleanup = "UNSAFE_BULK_CLEANUP"
    case autoCleanup = "AUTO_CLEANUP"
    case backgroundDelete = "BACKGROUND_DELETE"
    case llmOverride = "LLM_OVERRIDE"
    case genericLibraryRelocation = "GENERIC_LIBRARY_RELOCATION"
}

public struct ApprovalState: Codable, Sendable, Equatable {
    public var approval: UserActionApproval?

    public static let scanDefault = ApprovalState(approval: nil)

    public var isApproved: Bool { approval != nil }
}

public struct UserActionApproval: Codable, Sendable, Equatable {
    public var approvalID: String
    public var entityID: String
    public var action: StorageAction
    public var bindingFingerprint: ActionBindingFingerprint
    public var consequenceSummaryVersion: String
    public var expectedRecoveryBytes: Int64?
    public var approvedAt: Date
    public var expiryPolicy: String
    public var scope: String
    /// Provenance only — UI / CLI_EXPLICIT_HUMAN_CONFIRMATION / API.
    /// All origins mint the same canonical approval model; CLI is not weaker.
    public var approvalOrigin: String?

    public init(
        approvalID: String,
        entityID: String,
        action: StorageAction,
        bindingFingerprint: ActionBindingFingerprint,
        consequenceSummaryVersion: String,
        expectedRecoveryBytes: Int64?,
        approvedAt: Date,
        expiryPolicy: String,
        scope: String,
        approvalOrigin: String? = nil
    ) {
        self.approvalID = approvalID
        self.entityID = entityID
        self.action = action
        self.bindingFingerprint = bindingFingerprint
        self.consequenceSummaryVersion = consequenceSummaryVersion
        self.expectedRecoveryBytes = expectedRecoveryBytes
        self.approvedAt = approvedAt
        self.expiryPolicy = expiryPolicy
        self.scope = scope
        self.approvalOrigin = approvalOrigin
    }
}

public struct ActionBindingFingerprint: Codable, Sendable, Hashable, Equatable {
    public var entityID: String
    public var action: StorageAction
    public var canonicalPath: String
    public var evidenceGeneration: Int
    public var verificationGeneration: Int
    public var runtimeGeneration: Int
    public var ruleVersion: String
    public var transactionContractVersion: String
    /// Optional digest of vendor-native bound facts (model/manifest/remote/refGraph). Empty for trash.
    public var semanticBindingDigest: String

    public func matches(_ other: ActionBindingFingerprint) -> Bool {
        self == other
    }

    public init(
        entityID: String,
        action: StorageAction,
        canonicalPath: String,
        evidenceGeneration: Int,
        verificationGeneration: Int,
        runtimeGeneration: Int,
        ruleVersion: String,
        transactionContractVersion: String,
        semanticBindingDigest: String = ""
    ) {
        self.entityID = entityID
        self.action = action
        self.canonicalPath = canonicalPath
        self.evidenceGeneration = evidenceGeneration
        self.verificationGeneration = verificationGeneration
        self.runtimeGeneration = runtimeGeneration
        self.ruleVersion = ruleVersion
        self.transactionContractVersion = transactionContractVersion
        self.semanticBindingDigest = semanticBindingDigest
    }
}

public struct PreflightReceipt: Codable, Sendable, Equatable {
    public var receiptID: String
    public var entityID: String
    public var action: StorageAction
    public var bindingFingerprint: ActionBindingFingerprint
    public var requiredClaims: [ClaimType]
    public var satisfiedClaims: [ClaimType]
    public var missingClaims: [ClaimType]
    public var staleClaims: [ClaimType]
    public var conflictedClaims: [ClaimType]
    public var observedAt: Date
    public var freshnessValidity: [FreshnessRequirement]
    public var evidenceGeneration: Int
    public var verificationGeneration: Int
    public var runtimeGeneration: Int
    public var result: String

    public init(
        receiptID: String,
        entityID: String,
        action: StorageAction,
        bindingFingerprint: ActionBindingFingerprint,
        requiredClaims: [ClaimType],
        satisfiedClaims: [ClaimType],
        missingClaims: [ClaimType],
        staleClaims: [ClaimType],
        conflictedClaims: [ClaimType],
        observedAt: Date,
        freshnessValidity: [FreshnessRequirement],
        evidenceGeneration: Int,
        verificationGeneration: Int,
        runtimeGeneration: Int,
        result: String
    ) {
        self.receiptID = receiptID
        self.entityID = entityID
        self.action = action
        self.bindingFingerprint = bindingFingerprint
        self.requiredClaims = requiredClaims
        self.satisfiedClaims = satisfiedClaims
        self.missingClaims = missingClaims
        self.staleClaims = staleClaims
        self.conflictedClaims = conflictedClaims
        self.observedAt = observedAt
        self.freshnessValidity = freshnessValidity
        self.evidenceGeneration = evidenceGeneration
        self.verificationGeneration = verificationGeneration
        self.runtimeGeneration = runtimeGeneration
        self.result = result
    }
}

/// P2.1: trash (GREEN). P3.2A: Ollama vendor-native (eligible; SafetyClass may remain UNKNOWN).
public struct ExecutionPermit: Codable, Sendable, Equatable {
    public var permitID: String
    public var entityID: String
    public var action: StorageAction
    public var bindingFingerprint: ActionBindingFingerprint
    public var preflightReceiptID: String
    public var approvalID: String
    public var issuedAt: Date

    public init(
        permitID: String,
        entityID: String,
        action: StorageAction,
        bindingFingerprint: ActionBindingFingerprint,
        preflightReceiptID: String,
        approvalID: String,
        issuedAt: Date
    ) {
        self.permitID = permitID
        self.entityID = entityID
        self.action = action
        self.bindingFingerprint = bindingFingerprint
        self.preflightReceiptID = preflightReceiptID
        self.approvalID = approvalID
        self.issuedAt = issuedAt
    }

    public static func generate(
        receipt: PreflightReceipt,
        approval: UserActionApproval,
        decision: ActionDecision
    ) -> ExecutionPermit? {
        guard receipt.result == PreflightResultCode.satisfiedReadOnly.rawValue else { return nil }
        guard receipt.missingClaims.isEmpty, receipt.staleClaims.isEmpty, receipt.conflictedClaims.isEmpty else { return nil }
        guard decision.eligible else { return nil }
        guard approval.entityID == receipt.entityID, approval.action == receipt.action else { return nil }
        guard ActionBindingFingerprintBuilder.isApprovalValid(
            approval: approval,
            fingerprint: receipt.bindingFingerprint
        ) else { return nil }
        guard approval.bindingFingerprint.matches(receipt.bindingFingerprint) else { return nil }

        switch receipt.action {
        case .moveToTrash:
            guard decision.safetyClass == .green else { return nil }
            guard ActionExecutionPolicy.authorizedActions.contains(receipt.action) else { return nil }
            guard ActionExecutionPolicy.allowsFirstMutationTrash(
                entityID: receipt.entityID,
                path: receipt.bindingFingerprint.canonicalPath
            ) else { return nil }
        case .vendorNativeCleanup:
            // Action eligibility is canonical; SafetyClass may stay UNKNOWN for vendor storage.
            // UNKNOWN class is NOT a bypass — missing strict claims still reject the permit.
            guard decision.missingClaimTypes.isEmpty else { return nil }
            guard decision.blockedReasons.isEmpty else { return nil }
            guard !decision.blockedReasons.contains(.reacquisitionNotStrictVerified) else { return nil }
            guard !decision.blockedReasons.contains(.regenerabilityUnknown) else { return nil }
            let path = receipt.bindingFingerprint.canonicalPath
            let ollamaOK = ActionPolicy.isOllamaModelEntity(
                entityID: receipt.entityID,
                path: path
            )
            let hfOK = ActionPolicy.isHuggingFaceSnapshotEntity(
                entityID: receipt.entityID,
                path: path
            )
            guard ollamaOK || hfOK else { return nil }
            guard !ActionPolicy.isRawAIVendorBlob(
                entityID: receipt.entityID,
                path: path
            ) else { return nil }
        default:
            return nil
        }

        return ExecutionPermit(
            permitID: "permit-\(receipt.entityID)-\(receipt.action.rawValue)-\(UUID().uuidString.prefix(8))",
            entityID: receipt.entityID,
            action: receipt.action,
            bindingFingerprint: receipt.bindingFingerprint,
            preflightReceiptID: receipt.receiptID,
            approvalID: approval.approvalID,
            issuedAt: Date()
        )
    }
}

public struct TransactionContract: Codable, Sendable, Equatable {
    public var action: StorageAction
    public var version: String
    public var supportedEntitySemantics: [String]
    public var requiredPreflightPredicates: [String]
    public var orderedPhases: [String]
    public var failureBehavior: String
    public var sourcePreservationBehavior: String
    public var freshnessRequirements: [FreshnessRequirement]
}

public struct PostActionVerificationContract: Codable, Sendable, Equatable {
    public var action: StorageAction
    public var version: String
    public var verificationSteps: [String]
}

public struct ActionAuditContract: Codable, Sendable, Equatable {
    public var action: StorageAction
    public var version: String
    public var requiredFields: [String]
    public var auditBeginsBeforeMutation: Bool
}

public struct MutationGateInput: Sendable {
    public var item: ClassifiedItem
    public var action: StorageAction
    public var actionDecision: ActionDecision
    public var snapshot: EntitySafetySnapshot?
    public var recommendation: ActionRecommendationResult?
    public var preflight: ActionPreflightResult?
    public var runtimeResolution: RuntimeStateResolution?
    public var transactionContract: TransactionContract?
    public var postVerifyContract: PostActionVerificationContract?
    public var auditContract: ActionAuditContract?
    public var approvalState: ApprovalState
    public var evidenceGeneration: Int
    public var verificationGeneration: Int
    public var runtimeGeneration: Int
    public var ruleVersion: String
    /// P2.0.6: real read-only fresh preflight receipt — satisfies fresh_runtime_preflight when valid.
    public var freshPreflightReceipt: PreflightReceipt? = nil

    public init(
        item: ClassifiedItem,
        action: StorageAction,
        actionDecision: ActionDecision,
        snapshot: EntitySafetySnapshot? = nil,
        recommendation: ActionRecommendationResult? = nil,
        preflight: ActionPreflightResult? = nil,
        runtimeResolution: RuntimeStateResolution? = nil,
        transactionContract: TransactionContract? = nil,
        postVerifyContract: PostActionVerificationContract? = nil,
        auditContract: ActionAuditContract? = nil,
        approvalState: ApprovalState = .scanDefault,
        evidenceGeneration: Int = 0,
        verificationGeneration: Int = 0,
        runtimeGeneration: Int = 0,
        ruleVersion: String,
        freshPreflightReceipt: PreflightReceipt? = nil
    ) {
        self.item = item
        self.action = action
        self.actionDecision = actionDecision
        self.snapshot = snapshot
        self.recommendation = recommendation
        self.preflight = preflight
        self.runtimeResolution = runtimeResolution
        self.transactionContract = transactionContract
        self.postVerifyContract = postVerifyContract
        self.auditContract = auditContract
        self.approvalState = approvalState
        self.evidenceGeneration = evidenceGeneration
        self.verificationGeneration = verificationGeneration
        self.runtimeGeneration = runtimeGeneration
        self.ruleVersion = ruleVersion
        self.freshPreflightReceipt = freshPreflightReceipt
    }
}

public enum PreflightResultCode: String, Codable, Sendable {
    case satisfiedReadOnly = "SATISFIED_READ_ONLY"
    case missingProof = "MISSING_PROOF"
    case staleEvidence = "STALE_EVIDENCE"
    case conflicted = "CONFLICTED"
    case realStateBlock = "REAL_STATE_BLOCK"
    case unsupportedObservation = "UNSUPPORTED_OBSERVATION"
    case candidateChanged = "CANDIDATE_CHANGED"
}

public struct FreshPreflightSession: Codable, Sendable, Equatable {
    public var preflightSessionID: String
    public var startedAt: Date
    public var completedAt: Date?
    public var entityID: String
    public var action: String
    public var originalBindingFingerprint: ActionBindingFingerprint?
    public var freshRuntimeGeneration: Int
    public var runtimeObservationMs: Int
    public var claimEvaluationMs: Int
    public var safetyReEvalMs: Int
    public var gateEvalMs: Int
    public var totalMs: Int
}

public struct PreflightClaimDelta: Codable, Sendable, Equatable {
    public var requirement: String
    public var freshnessClass: String
    public var previousValue: String?
    public var currentValue: String?
    public var changed: Bool
    public var disposition: String
    public var reason: String?
}

public struct PreflightStateDeltaReport: Codable, Sendable, Equatable {
    public var entityID: String
    public var action: String
    public var scanBindingFingerprint: ActionBindingFingerprint?
    public var freshBindingFingerprint: ActionBindingFingerprint?
    public var bindingValid: Bool
    public var sourceUnchanged: Bool
    public var entries: [PreflightClaimDelta]
}

public struct RealPreflightClosureReport: Codable, Sendable, Equatable {
    public var phase: String
    public var outcome: String
    public var preflightSession: FreshPreflightSession?
    public var entityID: String?
    public var action: String?
    public var path: String?
    public var previousMutationReadiness: String?
    public var mutationReadinessAfterPreflight: String?
    public var bindingValid: Bool
    public var sourceUnchanged: Bool
    public var safetyClassBefore: String?
    public var safetyClassAfter: String?
    public var staticClaimsReused: [String]
    public var dynamicClaimsRefreshed: [String]
    public var processCompleteness: String?
    public var handleCompleteness: String?
    public var satisfiedClaims: [String]
    public var missingClaims: [String]
    public var staleClaims: [String]
    public var conflictedClaims: [String]
    public var firstBlocker: String?
    public var causalBlockerChain: [String]
    public var preflightReceipt: PreflightReceipt?
    public var preflightReceiptResult: String?
    public var mutationGateReadiness: String?
    public var humanApprovalRequired: Bool
    public var userActionApprovalGenerated: Bool
    public var executionPermitGenerated: Bool
    public var executorImplemented: Bool
    public var previewExecutable: Bool
    public var destructiveActionsExecuted: Bool
    public var firstRealMutationGateStatus: String
    public var selectedCandidate: String?
    public var selectedAction: String?
    public var explanation: String
}

public struct MutationGateResult: Codable, Sendable, Equatable {
    public var entityID: String
    public var path: String
    public var action: String
    public var safetyClass: String
    public var recommendation: String?
    public var readiness: String
    public var satisfiedRequirements: [String]
    public var missingRequirements: [String]
    public var staleRequirements: [String]
    public var conflictedRequirements: [String]
    public var blockingReasons: [String]
    public var requiredFreshChecks: [String]
    public var actionBindingFingerprint: ActionBindingFingerprint?
    public var transactionContractAvailable: Bool
    public var postVerifyContractAvailable: Bool
    public var auditContractAvailable: Bool
    public var freshRuntimeCheckRequired: Bool
    public var freshCloudCheckRequired: Bool
    public var approvalRequired: Bool
    public var executorImplemented: Bool
}

public struct MutationGateReport: Codable, Sendable, Equatable {
    public var entries: [MutationGateResult]
    public var executorImplemented: Bool
}

public struct DryRunActionStep: Codable, Sendable, Equatable {
    public var order: Int
    public var step: String
    public var mutates: Bool
}

public struct DryRunActionPlan: Codable, Sendable, Equatable {
    public var entityID: String
    public var path: String
    public var action: String
    public var readiness: String
    public var steps: [DryRunActionStep]
    public var executorImplemented: Bool
}

public struct DryRunActionPlanReport: Codable, Sendable, Equatable {
    public var plans: [DryRunActionPlan]
    public var executorImplemented: Bool
}

public struct MutationSurfaceFinding: Codable, Sendable, Equatable {
    public var file: String
    public var pattern: String
    public var line: Int?
    public var category: String
}

public struct MutationSurfaceAuditReport: Codable, Sendable, Equatable {
    public var scannedFiles: Int
    public var findings: [MutationSurfaceFinding]
    public var actualMutationImplementations: Int
    public var executorImplemented: Bool
    public var auditPassed: Bool
}

public struct ActExecutorReadinessSummary: Codable, Sendable, Equatable {
    public var totalEvaluated: Int
    public var keepCount: Int
    public var moveToTrashCount: Int
    public var moveToICloudCount: Int
    public var removeLocalDownloadCount: Int
    public var blockedCount: Int
    public var verifyMoreCount: Int
    public var preflightRequiredCount: Int
    public var approvalRequiredCount: Int
    public var contractSatisfiedReadOnlyCount: Int
    public var missingActionContracts: Int
    public var missingTransactionContracts: Int
    public var missingPostVerifyContracts: Int
    public var missingAuditContracts: Int
    public var executorImplemented: Bool
}
