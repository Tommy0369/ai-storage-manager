import Foundation

/// P3.2B — Exact HF SNAPSHOT/REVISION × VENDOR_NATIVE_CLEANUP via `hf cache rm <revision>`.
/// No shell. No raw delete. No prune. No repo-wide target. Requires ExecutionPermit + single-use ledger.
public struct HuggingFaceNativeCleanupExecutor: Sendable {
    public static let contractVersion = "HF_SNAPSHOT_NATIVE_CLEANUP_v0.1"
    public static let executorVersion = "P3.2B"

    public var processRunner: any BoundedProcessRunner
    public var resolveExecutable: () -> URL?

    public init(
        processRunner: any BoundedProcessRunner = FoundationProcessRunner(),
        resolveExecutable: @escaping () -> URL? = {
            HuggingFaceNativeInterfaceResolver.resolve().cliExecutableURL.map { URL(fileURLWithPath: $0) }
        }
    ) {
        self.processRunner = processRunner
        self.resolveExecutable = resolveExecutable
    }

    public func execute(
        plan: DryRunActionPlan,
        permit: ExecutionPermit,
        revision: String,
        cacheRoot: String,
        timeoutSeconds: TimeInterval = 120
    ) throws -> ActionAuditRecord {
        try ActionExecutionPolicy.validateHuggingFaceNativePermit(
            permit,
            plan: plan,
            revision: revision,
            cacheRoot: cacheRoot
        )
        guard ExecutionPermitLedger.consume(permit.permitID) else {
            throw ActionExecutionError.permitAlreadyConsumed(permit.permitID)
        }
        try HuggingFaceRevisionIdentity.validateOrThrow(revision)
        // Reject repo-wide / prune / multi-target injection.
        guard !revision.contains("/"), !revision.lowercased().hasPrefix("model/") else {
            throw ActionExecutionError.invalidModelIdentity(revision)
        }
        guard let exe = resolveExecutable() else {
            throw ActionExecutionError.executableUnresolved("hf")
        }
        let args = try HuggingFaceRevisionIdentity.rmArguments(
            revision: revision,
            cacheRoot: cacheRoot,
            dryRun: false,
            yes: true
        )
        // Hard invariant: never allow prune argv.
        guard !args.contains("prune") else {
            throw ActionExecutionError.unauthorizedAction(.vendorNativeCleanup)
        }
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
            transactionPhase: HuggingFaceNativeCleanupPhase.invokingNativeRm.rawValue,
            logicalBytesAffected: nil,
            measuredRecoveryBytes: nil,
            failureReason: failure,
            startedAt: started
        )
        audit.bindingFingerprint = permit.bindingFingerprint
        audit.approvalID = permit.approvalID
        audit.preflightReceiptID = permit.preflightReceiptID
        audit.executedAt = Date()
        if failure != nil {
            audit.auditStatus = AuditLifecycleStatus.failed.rawValue
            audit.transactionPhase = HuggingFaceNativeCleanupPhase.failed.rawValue
        } else {
            audit.auditStatus = AuditLifecycleStatus.postVerifyPending.rawValue
            audit.transactionPhase = HuggingFaceNativeCleanupPhase.verifyingRevisionAbsent.rawValue
        }
        audit.notes.append("NATIVE_ARGV=hf \(args.joined(separator: " "))")
        audit.notes.append("PROCESS_OUTCOME=\(result.outcome.rawValue)")
        audit.notes.append("HF_REVISION=\(revision)")
        if !result.stderr.isEmpty {
            audit.notes.append("STDERR_SUMMARY=\(String(result.stderr.prefix(200)))")
        }
        return audit
    }
}

/// Post-mutation verification for HF exact revision removal.
public enum HuggingFacePostMutationVerifier {
    public enum LogicalOutcome: String, Codable, Sendable {
        case snapshotRemoved = "SNAPSHOT_REMOVED"
        case snapshotRemains = "SNAPSHOT_REMOVAL_NOT_VERIFIED"
        case snapshotReappeared = "SNAPSHOT_REAPPEARED"
        case unknown = "UNKNOWN"
    }

    public enum StorageOutcome: String, Codable, Sendable {
        case recovered = "SNAPSHOT_REMOVED_STORAGE_RECOVERED"
        case partial = "SNAPSHOT_REMOVED_STORAGE_PARTIALLY_RECOVERED"
        case remains = "SNAPSHOT_REMOVED_STORAGE_REMAINS"
        case notVerified = "SNAPSHOT_REMOVAL_NOT_VERIFIED"
        case reappeared = "SNAPSHOT_REAPPEARED"
        case unknown = "UNKNOWN"
    }

    public struct Result: Codable, Sendable, Equatable {
        public var logical: LogicalOutcome
        public var storage: StorageOutcome
        public var verifiedRecoveredBytes: Int64?
        public var vendorReportedFreedBytes: Int64?
        public var diskFreeDelta: Int64?
        public var revisionStillPresent: Bool
        public var repoDirectoryStillPresent: Bool
        public var notes: [String]
    }

    public static func verify(
        revision: String,
        snapshotPath: String,
        repoPath: String,
        beforeUniqueBytes: Int64?,
        afterUniqueBytes: Int64?,
        vendorReportedFreed: Int64?,
        diskFreeDelta: Int64?,
        fm: FileManager = .default
    ) -> Result {
        let snapPresent = fm.fileExists(atPath: snapshotPath)
        let repoPresent = fm.fileExists(atPath: repoPath)
        var notes: [String] = []
        notes.append("REVISION=\(revision)")
        notes.append("SNAPSHOT_PRESENT=\(snapPresent)")
        notes.append("REPO_PRESENT=\(repoPresent)")

        let logical: LogicalOutcome
        if !snapPresent {
            logical = .snapshotRemoved
        } else {
            logical = .snapshotRemains
        }

        var verified: Int64?
        let storage: StorageOutcome
        if logical == .snapshotRemoved {
            if let before = beforeUniqueBytes, let after = afterUniqueBytes {
                let delta = max(0, before - after)
                verified = delta
                if after == 0 { storage = .recovered }
                else if delta > 0 { storage = .partial }
                else { storage = .remains }
            } else if let before = beforeUniqueBytes, !snapPresent {
                verified = before
                storage = .recovered
            } else {
                storage = .notVerified
            }
        } else {
            storage = .notVerified
        }
        _ = vendorReportedFreed
        _ = diskFreeDelta
        return Result(
            logical: logical,
            storage: storage,
            verifiedRecoveredBytes: verified,
            vendorReportedFreedBytes: vendorReportedFreed,
            diskFreeDelta: diskFreeDelta,
            revisionStillPresent: snapPresent,
            repoDirectoryStillPresent: repoPresent,
            notes: notes
        )
    }
}
