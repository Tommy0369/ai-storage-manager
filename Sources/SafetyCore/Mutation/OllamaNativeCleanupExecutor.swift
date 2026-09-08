import Foundation

public enum OllamaNativeCleanupPhase: String, Codable, Sendable, Equatable {
    case notStarted = "NOT_STARTED"
    case preflight = "PREFLIGHT"
    case approvalRequired = "APPROVAL_REQUIRED"
    case ready = "READY"
    case invokingNativeRm = "INVOKING_NATIVE_RM"
    case verifyingModelAbsent = "VERIFYING_MODEL_ABSENT"
    case measuringStorage = "MEASURING_STORAGE"
    case postVerify = "POST_VERIFY"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
    case unknown = "UNKNOWN"
}

/// P3.2A — Exact Ollama MODEL × VENDOR_NATIVE_CLEANUP via `ollama rm <canonical>`.
/// No shell. No raw blob delete. Requires ExecutionPermit + single-use ledger.
public struct OllamaNativeCleanupExecutor: Sendable {
    public static let contractVersion = "OLLAMA_MODEL_NATIVE_CLEANUP_v0.1"
    public static let executorVersion = "P3.2A"

    public var processRunner: any BoundedProcessRunner
    public var resolveExecutable: () -> URL?

    public init(
        processRunner: any BoundedProcessRunner = FoundationProcessRunner(),
        resolveExecutable: @escaping () -> URL? = { OllamaModelIdentity.resolveExecutableURL() }
    ) {
        self.processRunner = processRunner
        self.resolveExecutable = resolveExecutable
    }

    public func execute(
        plan: DryRunActionPlan,
        permit: ExecutionPermit,
        canonicalModel: String,
        timeoutSeconds: TimeInterval = 60
    ) throws -> ActionAuditRecord {
        try ActionExecutionPolicy.validateOllamaNativePermit(permit, plan: plan, canonicalModel: canonicalModel)
        guard ExecutionPermitLedger.consume(permit.permitID) else {
            throw ActionExecutionError.permitAlreadyConsumed(permit.permitID)
        }
        try OllamaModelIdentity.validateOrThrow(canonicalModel)
        guard let exe = resolveExecutable() else {
            throw ActionExecutionError.executableUnresolved("ollama")
        }
        let args = try OllamaModelIdentity.rmArguments(canonicalModel: canonicalModel)
        let started = Date()
        let result = processRunner.run(BoundedProcessRequest(
            executableURL: exe,
            arguments: args,
            timeoutSeconds: timeoutSeconds
        ))

        var failure: String?
        switch result.outcome {
        case .commandAccepted:
            failure = nil
        case .nonzeroExit:
            failure = "NONZERO_EXIT:\(result.exitCode ?? -1)"
        case .timedOut:
            failure = "TIMED_OUT"
        case .startFailed:
            failure = "START_FAILED"
        case .terminated:
            failure = "TERMINATED"
        case .unknownOutcome:
            failure = "UNKNOWN_OUTCOME"
        }

        var audit = ActionAuditRecord(
            actionID: permit.permitID,
            entityID: plan.entityID,
            action: .vendorNativeCleanup,
            sourcePath: plan.path,
            destinationPath: nil,
            preflightClaims: [],
            transactionPhase: OllamaNativeCleanupPhase.invokingNativeRm.rawValue,
            logicalBytesAffected: nil,
            measuredRecoveryBytes: nil,
            failureReason: failure,
            startedAt: started
        )
        audit.bindingFingerprint = permit.bindingFingerprint
        audit.approvalID = permit.approvalID
        audit.preflightReceiptID = permit.preflightReceiptID
        audit.executedAt = Date()
        // Command outcome is NOT postcondition truth.
        if failure != nil {
            audit.auditStatus = AuditLifecycleStatus.failed.rawValue
            audit.transactionPhase = OllamaNativeCleanupPhase.failed.rawValue
        } else {
            audit.auditStatus = AuditLifecycleStatus.postVerifyPending.rawValue
            audit.transactionPhase = OllamaNativeCleanupPhase.verifyingModelAbsent.rawValue
        }
        audit.notes.append("NATIVE_ARGV=ollama \(args.joined(separator: " "))")
        audit.notes.append("PROCESS_OUTCOME=\(result.outcome.rawValue)")
        if !result.stderr.isEmpty {
            audit.notes.append("STDERR_SUMMARY=\(String(result.stderr.prefix(200)))")
        }
        return audit
    }
}

/// Post-mutation verification for Ollama native model removal.
public enum OllamaPostMutationVerifier {
    public enum LogicalOutcome: String, Codable, Sendable {
        case modelRemoved = "MODEL_REMOVED"
        case modelRemains = "MODEL_REMOVAL_NOT_VERIFIED"
        case modelReappeared = "MODEL_REAPPEARED"
        case unknown = "UNKNOWN"
    }

    public enum StorageOutcome: String, Codable, Sendable {
        case recovered = "MODEL_REMOVED_STORAGE_RECOVERED"
        case partial = "MODEL_REMOVED_STORAGE_PARTIALLY_RECOVERED"
        case remains = "MODEL_REMOVED_STORAGE_REMAINS"
        case notVerified = "MODEL_REMOVAL_NOT_VERIFIED"
        case unknown = "UNKNOWN"
    }

    public struct Result: Sendable, Equatable {
        public var logical: LogicalOutcome
        public var storage: StorageOutcome
        public var modelStillInstalled: Bool
        public var verifiedRecoveredBytes: Int64
        public var remainingBlobBytes: Int64
        public var steps: [PostActionVerifyStepResult]
    }

    /// Inventory probe: returns whether exact model still appears installed.
    public static func verify(
        canonicalModel: String,
        modelStillInstalled: Bool,
        removedExclusiveBlobBytes: Int64?,
        remainingUnreferencedBlobBytes: Int64?,
        sharedRetainedBytes: Int64?,
        contract: PostActionVerificationContract?
    ) -> Result {
        var steps: [PostActionVerifyStepResult] = []
        let removed = !modelStillInstalled
        steps.append(PostActionVerifyStepResult(
            step: "verify_exact_model_absent",
            satisfied: removed,
            detail: removed ? "absent" : "still_installed"
        ))
        let logical: LogicalOutcome = removed ? .modelRemoved : .modelRemains

        let remaining = remainingUnreferencedBlobBytes ?? 0
        let shared = sharedRetainedBytes ?? 0
        let recovered = removedExclusiveBlobBytes ?? 0

        let storage: StorageOutcome
        if !removed {
            storage = .notVerified
        } else if remaining > 0 && recovered == 0 {
            storage = .remains
        } else if remaining > 0 || shared > 0 {
            storage = .partial
        } else if recovered > 0 {
            storage = .recovered
        } else {
            storage = .unknown
        }

        steps.append(PostActionVerifyStepResult(
            step: "record_actual_recovered_bytes",
            satisfied: removed,
            detail: "\(recovered)"
        ))
        steps.append(PostActionVerifyStepResult(
            step: "record_remaining_blob_bytes",
            satisfied: true,
            detail: "remaining=\(remaining);shared=\(shared)"
        ))
        if let contract {
            for step in contract.verificationSteps where !steps.contains(where: { $0.step == step }) {
                steps.append(PostActionVerifyStepResult(step: step, satisfied: removed, detail: nil))
            }
        }
        steps.append(PostActionVerifyStepResult(step: "complete_audit", satisfied: removed, detail: storage.rawValue))

        return Result(
            logical: logical,
            storage: storage,
            modelStillInstalled: modelStillInstalled,
            // Never use pre-action estimate as actual.
            verifiedRecoveredBytes: removed ? max(0, recovered) : 0,
            remainingBlobBytes: remaining,
            steps: steps
        )
    }
}
