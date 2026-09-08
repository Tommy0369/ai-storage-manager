import Foundation

// MARK: - Semantic binding vs freshness (P3.2A.6)

/// What exactly is being authorized — material identity only.
/// Ephemeral timestamps / latency / request IDs are excluded.
public struct ActionSemanticBinding: Codable, Sendable, Equatable, Hashable {
    public var entityID: String
    public var action: StorageAction
    public var canonicalModelID: String?
    public var canonicalPath: String
    public var manifestIdentity: String
    public var remoteExactIdentity: String
    public var referenceGraphIdentity: String
    public var executorContractVersion: String
    public var nativeExecutableIdentity: String
    public var transactionContractVersion: String
    public var postVerifyContractVersion: String
    public var uniqueBytesProven: Int64?
    public var sharedBytesProven: Int64?
    public var customOrUserOriginalSuspect: Bool
    public var digest: String

    public init(
        entityID: String,
        action: StorageAction,
        canonicalModelID: String?,
        canonicalPath: String,
        manifestIdentity: String,
        remoteExactIdentity: String,
        referenceGraphIdentity: String,
        executorContractVersion: String,
        nativeExecutableIdentity: String,
        transactionContractVersion: String,
        postVerifyContractVersion: String,
        uniqueBytesProven: Int64?,
        sharedBytesProven: Int64?,
        customOrUserOriginalSuspect: Bool,
        digest: String
    ) {
        self.entityID = entityID
        self.action = action
        self.canonicalModelID = canonicalModelID
        self.canonicalPath = canonicalPath
        self.manifestIdentity = manifestIdentity
        self.remoteExactIdentity = remoteExactIdentity
        self.referenceGraphIdentity = referenceGraphIdentity
        self.executorContractVersion = executorContractVersion
        self.nativeExecutableIdentity = nativeExecutableIdentity
        self.transactionContractVersion = transactionContractVersion
        self.postVerifyContractVersion = postVerifyContractVersion
        self.uniqueBytesProven = uniqueBytesProven
        self.sharedBytesProven = sharedBytesProven
        self.customOrUserOriginalSuspect = customOrUserOriginalSuspect
        self.digest = digest
    }
}

/// Whether proofs are still valid right now — separate from identity.
public struct FreshnessEnvelope: Codable, Sendable, Equatable {
    public var runtimeFreshClass: String
    public var remoteFreshClass: String
    public var runtimeObservedAt: Date?
    public var runtimeFreshUntil: Date?
    public var remoteVerifiedAt: Date?
    public var remoteFreshUntil: Date?
    public var runtimeValidNow: Bool
    public var remoteValidNow: Bool
    public var overallValidNow: Bool

    public init(
        runtimeFreshClass: String,
        remoteFreshClass: String,
        runtimeObservedAt: Date? = nil,
        runtimeFreshUntil: Date? = nil,
        remoteVerifiedAt: Date? = nil,
        remoteFreshUntil: Date? = nil,
        runtimeValidNow: Bool,
        remoteValidNow: Bool
    ) {
        self.runtimeFreshClass = runtimeFreshClass
        self.remoteFreshClass = remoteFreshClass
        self.runtimeObservedAt = runtimeObservedAt
        self.runtimeFreshUntil = runtimeFreshUntil
        self.remoteVerifiedAt = remoteVerifiedAt
        self.remoteFreshUntil = remoteFreshUntil
        self.runtimeValidNow = runtimeValidNow
        self.remoteValidNow = remoteValidNow
        self.overallValidNow = runtimeValidNow && remoteValidNow
    }
}

public enum ActionSemanticBindingBuilder {
    /// Fields intentionally excluded from semantic identity (ephemeral / non-consented).
    public static let ephemeralFieldsExcluded: [String] = [
        "verifiedAt_epoch",
        "freshUntil_epoch",
        "traceIDs",
        "reportGenerationTimestamps",
        "latencyValues",
        "temporaryRequestIDs",
        "scanTimingIDs",
        "preflightSessionIDs",
    ]

    public static let semanticBindingFields: [String] = [
        "entityID",
        "action",
        "canonicalModelID",
        "canonicalPath",
        "manifestIdentity",
        "remoteExactIdentity",
        "referenceGraphIdentity",
        "executorContractVersion",
        "nativeExecutableIdentity",
        "transactionContractVersion",
        "postVerifyContractVersion",
        "uniqueBytesProven",
        "sharedBytesProven",
        "customOrUserOriginalSuspect",
    ]

    public static let freshnessFields: [String] = [
        "runtimeFreshClass",
        "remoteFreshClass",
        "runtimeObservedAt",
        "runtimeFreshUntil",
        "remoteVerifiedAt",
        "remoteFreshUntil",
        "runtimeValidNow",
        "remoteValidNow",
    ]

    public static func build(from input: MutationGateInput) -> ActionSemanticBinding {
        let path = (input.snapshot?.evidence.canonicalPath.isEmpty == false
            ? input.snapshot!.evidence.canonicalPath
            : input.item.detected.entity.path)
        let canonical = (path as NSString).standardizingPath
        let v = input.item.verification ?? input.snapshot?.verification
        let isHF = ActionPolicy.isHuggingFaceSnapshotEntity(input.item)
        let model: String?
        if isHF {
            let repo = ActionPolicy.huggingFaceRepoID(from: input.item) ?? ""
            let rev = ActionPolicy.huggingFaceRevision(from: input.item) ?? ""
            model = "\(repo)@\(rev)"
        } else {
            model = ActionPolicy.ollamaCanonicalModelName(from: input.item)
                ?? (input.action == .vendorNativeCleanup ? input.item.detected.entity.displayName : nil)
        }
        let manifest = isHF
            ? (v?.vendorProofNotes.first(where: { $0.hasPrefix("HF_DRY_RUN_FP=") })
                ?? v?.vendorProofNotes.first(where: { $0.hasPrefix("HF_CACHE_ROOT=") })
                ?? "")
            : (v?.vendorProofNotes.first(where: { $0.hasPrefix("LOCAL_MANIFEST=") })
                ?? v?.reconstructionMechanism
                ?? "")
        let remote = v?.remoteReacquisitionProof
        let remoteExact = [remote?.remoteIdentity, remote?.remoteRevisionOrDigest, remote?.status.rawValue]
            .compactMap { $0 }.joined(separator: "|")
        let ref = v?.referenceGraphConfidence.rawValue ?? ""
        let binary = v?.vendorProofNotes.first(where: {
            $0.hasPrefix(isHF ? "HF_BINARY_FP=" : "OLLAMA_BINARY_FP=")
        }) ?? ""
        let cli = v?.vendorProofNotes.first(where: {
            $0.hasPrefix(isHF ? "HF_CLI_RESOLVED=" : "OLLAMA_CLI_RESOLVED=")
        }) ?? ""
        let native = [binary, cli].filter { !$0.isEmpty }.joined(separator: "|")
        let tx = input.transactionContract?.version ?? "NONE"
        let pv = input.postVerifyContract?.version ?? "NONE"
        let custom = v?.vendorProofNotes.contains(where: {
            $0.contains("USER_ORIGINAL") || $0.contains("CUSTOM_MODEL") || $0.contains("CUSTOM")
        }) == true
        let digest = ActionBindingFingerprintBuilder.semanticDigest(input: input)
        let contract: String
        if input.action == .vendorNativeCleanup {
            contract = isHF
                ? HuggingFaceNativeCleanupExecutor.contractVersion
                : OllamaNativeCleanupExecutor.contractVersion
        } else {
            contract = "MOVE_TO_TRASH"
        }
        return ActionSemanticBinding(
            entityID: input.item.detected.entity.id,
            action: input.action,
            canonicalModelID: model,
            canonicalPath: canonical,
            manifestIdentity: manifest,
            remoteExactIdentity: remoteExact,
            referenceGraphIdentity: ref,
            executorContractVersion: contract,
            nativeExecutableIdentity: native,
            transactionContractVersion: tx,
            postVerifyContractVersion: pv,
            uniqueBytesProven: v?.uniqueBytesProven,
            sharedBytesProven: v?.sharedBytesProven,
            customOrUserOriginalSuspect: custom,
            digest: digest
        )
    }

    public static func freshnessEnvelope(
        from input: MutationGateInput,
        now: Date = Date()
    ) -> FreshnessEnvelope {
        let v = input.item.verification ?? input.snapshot?.verification
        let remote = v?.remoteReacquisitionProof
        let remoteClass: String
        let remoteValid: Bool
        if let remote, remote.isStrictVerified {
            remoteClass = "STRICT_FRESH"
            remoteValid = true
        } else if let remote, remote.isFresh {
            remoteClass = "FRESH"
            remoteValid = true
        } else if remote != nil {
            remoteClass = "STALE"
            remoteValid = false
        } else if input.action != .vendorNativeCleanup {
            remoteClass = "NOT_REQUIRED"
            remoteValid = true
        } else {
            remoteClass = "MISSING"
            remoteValid = false
        }

        let runtime = input.runtimeResolution
        let runtimeClass: String
        let runtimeValid: Bool
        if let runtime, runtime.activeStateConfidence == .verified {
            runtimeClass = "VERIFIED"
            runtimeValid = true
        } else if let runtime, runtime.activeStateConfidence == .inferred {
            runtimeClass = "INFERRED"
            runtimeValid = input.action != .vendorNativeCleanup
        } else {
            runtimeClass = "UNKNOWN"
            runtimeValid = input.action != .vendorNativeCleanup
        }
        _ = now
        return FreshnessEnvelope(
            runtimeFreshClass: runtimeClass,
            remoteFreshClass: remoteClass,
            runtimeObservedAt: nil,
            runtimeFreshUntil: nil,
            remoteVerifiedAt: remote?.verifiedAt,
            remoteFreshUntil: remote?.freshUntil,
            runtimeValidNow: runtimeValid,
            remoteValidNow: remoteValid
        )
    }

    public static func materialDifferenceReasons(
        _ a: ActionSemanticBinding,
        _ b: ActionSemanticBinding
    ) -> [String] {
        var reasons: [String] = []
        if a.entityID != b.entityID { reasons.append("ENTITY_CHANGED") }
        if a.action != b.action { reasons.append("ACTION_CHANGED") }
        if a.canonicalModelID != b.canonicalModelID { reasons.append("MODEL_CHANGED") }
        if a.manifestIdentity != b.manifestIdentity { reasons.append("MANIFEST_CHANGED") }
        if a.remoteExactIdentity != b.remoteExactIdentity { reasons.append("REMOTE_IDENTITY_CHANGED") }
        if a.referenceGraphIdentity != b.referenceGraphIdentity { reasons.append("REFERENCE_GRAPH_CHANGED") }
        if a.nativeExecutableIdentity != b.nativeExecutableIdentity { reasons.append("EXECUTABLE_CHANGED") }
        if a.transactionContractVersion != b.transactionContractVersion { reasons.append("TRANSACTION_CONTRACT_CHANGED") }
        if a.postVerifyContractVersion != b.postVerifyContractVersion { reasons.append("POSTVERIFY_CONTRACT_CHANGED") }
        if a.customOrUserOriginalSuspect != b.customOrUserOriginalSuspect { reasons.append("CUSTOM_STATUS_CHANGED") }
        if a.digest != b.digest { reasons.append("SEMANTIC_DIGEST_CHANGED") }
        return reasons
    }
}

// MARK: - Approval lifecycle

public enum UserActionApprovalLifecycle: String, Codable, Sendable, Equatable {
    case created = "CREATED"
    case valid = "VALID"
    case consumed = "CONSUMED"
    case invalidated = "INVALIDATED"
    case expired = "EXPIRED"
}

public struct UserActionApprovalRecord: Codable, Sendable, Equatable {
    public var approval: UserActionApproval
    public var semanticBindingDigest: String
    public var lifecycle: UserActionApprovalLifecycle
    public var authorizationTextFingerprint: String?
    public var invalidatedReasons: [String]
    public var consumedAt: Date?
    public var invalidatedAt: Date?

    public init(
        approval: UserActionApproval,
        semanticBindingDigest: String,
        lifecycle: UserActionApprovalLifecycle = .created,
        authorizationTextFingerprint: String? = nil,
        invalidatedReasons: [String] = [],
        consumedAt: Date? = nil,
        invalidatedAt: Date? = nil
    ) {
        self.approval = approval
        self.semanticBindingDigest = semanticBindingDigest
        self.lifecycle = lifecycle
        self.authorizationTextFingerprint = authorizationTextFingerprint
        self.invalidatedReasons = invalidatedReasons
        self.consumedAt = consumedAt
        self.invalidatedAt = invalidatedAt
    }

    public mutating func markValid() {
        guard lifecycle == .created || lifecycle == .valid else { return }
        lifecycle = .valid
    }

    public mutating func consume(at date: Date = Date()) {
        lifecycle = .consumed
        consumedAt = date
    }

    public mutating func invalidate(reasons: [String], at date: Date = Date()) {
        lifecycle = .invalidated
        invalidatedReasons = reasons
        invalidatedAt = date
    }
}

// MARK: - Execution attempt lifecycle

public enum ExecutionAttemptPhase: String, Codable, Sendable, Equatable {
    case preExecutionRejected = "PRE_EXECUTION_REJECTED"
    case permitCreated = "PERMIT_CREATED"
    case processStartAttempted = "PROCESS_START_ATTEMPTED"
    case processStarted = "PROCESS_STARTED"
    case processCompleted = "PROCESS_COMPLETED"
    case postVerifyCompleted = "POSTVERIFY_COMPLETED"
}

/// Distinguishes binding/preflight rejection from an actual mutation attempt.
public struct ExecutionAttemptRecord: Codable, Sendable, Equatable {
    public var attemptID: String
    public var entityID: String
    public var action: StorageAction
    public var phase: ExecutionAttemptPhase
    public var approvalID: String?
    public var permitID: String?
    public var executorInvoked: Bool
    public var processStarted: Bool
    public var nativeMutationAttempted: Bool
    public var abortReason: String?
    public var recordedAt: Date

    public init(
        attemptID: String = "attempt-\(UUID().uuidString.prefix(8))",
        entityID: String,
        action: StorageAction,
        phase: ExecutionAttemptPhase,
        approvalID: String? = nil,
        permitID: String? = nil,
        executorInvoked: Bool = false,
        processStarted: Bool = false,
        nativeMutationAttempted: Bool = false,
        abortReason: String? = nil,
        recordedAt: Date = Date()
    ) {
        self.attemptID = attemptID
        self.entityID = entityID
        self.action = action
        self.phase = phase
        self.approvalID = approvalID
        self.permitID = permitID
        self.executorInvoked = executorInvoked
        self.processStarted = processStarted
        self.nativeMutationAttempted = nativeMutationAttempted
        self.abortReason = abortReason
        self.recordedAt = recordedAt
    }

    public static func preExecutionRejected(
        entityID: String,
        action: StorageAction,
        approvalID: String?,
        reason: String
    ) -> ExecutionAttemptRecord {
        ExecutionAttemptRecord(
            entityID: entityID,
            action: action,
            phase: .preExecutionRejected,
            approvalID: approvalID,
            permitID: nil,
            executorInvoked: false,
            processStarted: false,
            nativeMutationAttempted: false,
            abortReason: reason
        )
    }
}

public struct ExecutionAttemptCounters: Codable, Sendable, Equatable {
    public var authorizationAttempts: Int
    public var preflightAttempts: Int
    public var permitIssuanceCount: Int
    public var executorInvocationCount: Int
    public var nativeProcessStartCount: Int
    public var successfulNativeMutationCount: Int

    public static let zero = ExecutionAttemptCounters(
        authorizationAttempts: 0,
        preflightAttempts: 0,
        permitIssuanceCount: 0,
        executorInvocationCount: 0,
        nativeProcessStartCount: 0,
        successfulNativeMutationCount: 0
    )
}

/// Retry / reconciliation policy — explicit, not automatic.
public enum ActionRetryPolicy {
    /// Binding mismatch before permit/executor: not a mutation attempt.
    /// Approval may remain usable only if semantic target unchanged and new Fresh Preflight passes.
    public static let preExecutionRejectionAllowsReuseIfSemanticUnchanged = true

    /// After permit issued/consumed or process start attempted: no automatic retry.
    public static let automaticRetryAfterPermitOrProcess = false

    /// Unknown outcome: re-check state (read-only) only.
    public static let unknownOutcomeAllowsReplay = false

    public static func mayReuseApprovalAfterPreExecutionRejection(
        approvalLifecycle: UserActionApprovalLifecycle,
        semanticUnchanged: Bool,
        freshPreflightEligible: Bool
    ) -> Bool {
        guard preExecutionRejectionAllowsReuseIfSemanticUnchanged else { return false }
        guard approvalLifecycle == .created || approvalLifecycle == .valid else { return false }
        return semanticUnchanged && freshPreflightEligible
    }
}
