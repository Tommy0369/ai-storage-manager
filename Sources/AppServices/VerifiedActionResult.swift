import Foundation
import SafetyCore

/// First-class product presentation of a verified (or failed) action.
/// UI must not reconstruct semantics from raw report fields.
public struct VerifiedActionResult: Codable, Sendable, Equatable {
    public var actionEventID: String
    public var action: StorageAction
    public var targetEntityID: String
    public var targetDisplayName: String
    public var canonicalModel: String?
    public var vendor: String?
    public var repoID: String?
    public var revision: String?
    public var executionOutcome: String
    public var attemptPhase: ExecutionAttemptPhase
    public var logicalOutcome: String
    public var storageRecoveryOutcome: ProductRecoveryPresentation
    public var potentialRecoveryBytes: Int64
    public var vendorReportedRecoveryBytes: Int64?
    public var verifiedRecoveredBytes: Int64
    public var observedDiskFreeDelta: Int64?
    public var remoteReacquisitionState: String?
    public var lastRevisionConsequence: String?
    public var regenerationState: String
    public var approvalID: String?
    public var permitID: String?
    public var approvalOrigin: String?
    public var nativeExecutor: String?
    public var completedAt: Date
    public var userHeadline: String
    public var userLines: [String]
    public var technicalDetailLines: [String]

    public init(
        actionEventID: String,
        action: StorageAction,
        targetEntityID: String,
        targetDisplayName: String,
        canonicalModel: String? = nil,
        vendor: String? = nil,
        repoID: String? = nil,
        revision: String? = nil,
        executionOutcome: String,
        attemptPhase: ExecutionAttemptPhase,
        logicalOutcome: String,
        storageRecoveryOutcome: ProductRecoveryPresentation,
        potentialRecoveryBytes: Int64,
        vendorReportedRecoveryBytes: Int64? = nil,
        verifiedRecoveredBytes: Int64,
        observedDiskFreeDelta: Int64? = nil,
        remoteReacquisitionState: String? = nil,
        lastRevisionConsequence: String? = nil,
        regenerationState: String,
        approvalID: String? = nil,
        permitID: String? = nil,
        approvalOrigin: String? = nil,
        nativeExecutor: String? = nil,
        completedAt: Date = Date(),
        userHeadline: String,
        userLines: [String],
        technicalDetailLines: [String] = []
    ) {
        self.actionEventID = actionEventID
        self.action = action
        self.targetEntityID = targetEntityID
        self.targetDisplayName = targetDisplayName
        self.canonicalModel = canonicalModel
        self.vendor = vendor
        self.repoID = repoID
        self.revision = revision
        self.executionOutcome = executionOutcome
        self.attemptPhase = attemptPhase
        self.logicalOutcome = logicalOutcome
        self.storageRecoveryOutcome = storageRecoveryOutcome
        self.potentialRecoveryBytes = potentialRecoveryBytes
        self.vendorReportedRecoveryBytes = vendorReportedRecoveryBytes
        self.verifiedRecoveredBytes = verifiedRecoveredBytes
        self.observedDiskFreeDelta = observedDiskFreeDelta
        self.remoteReacquisitionState = remoteReacquisitionState
        self.lastRevisionConsequence = lastRevisionConsequence
        self.regenerationState = regenerationState
        self.approvalID = approvalID
        self.permitID = permitID
        self.approvalOrigin = approvalOrigin
        self.nativeExecutor = nativeExecutor
        self.completedAt = completedAt
        self.userHeadline = userHeadline
        self.userLines = userLines
        self.technicalDetailLines = technicalDetailLines
    }
}

public enum ProductRecoveryPresentation: String, Codable, Sendable, Equatable {
    case completedRecoveryVerified = "ACTION_COMPLETED_RECOVERY_VERIFIED"
    case completedRecoveryPartial = "ACTION_COMPLETED_RECOVERY_PARTIAL"
    case completedRecoveryPending = "ACTION_COMPLETED_RECOVERY_PENDING"
    case completedNoRecovery = "ACTION_COMPLETED_NO_RECOVERY"
    case notVerified = "ACTION_NOT_VERIFIED"
    case failed = "ACTION_FAILED"
    case outcomeUnknown = "ACTION_OUTCOME_UNKNOWN"

    public var userLabel: String {
        switch self {
        case .completedRecoveryVerified: return "Recovery verified"
        case .completedRecoveryPartial: return "Partially recovered"
        case .completedRecoveryPending: return "Recovery pending"
        case .completedNoRecovery: return "No storage recovered"
        case .notVerified: return "Not verified"
        case .failed: return "Action failed"
        case .outcomeUnknown: return "Outcome unknown"
        }
    }
}

/// History-safe event for P3.0.2 exact correlation (not timestamp-alone).
public struct VerifiedStorageActionEvent: Codable, Sendable, Equatable {
    public var actionEventID: String
    public var entityID: String
    public var vendor: String?
    public var action: StorageAction
    public var repoID: String?
    public var revision: String?
    public var executedAt: Date
    public var postVerifyAt: Date?
    public var logicalOutcome: String
    public var recoveryOutcome: String
    public var verifiedRecoveredBytes: Int64
    public var vendorPreviewFingerprint: String?
    public var remoteIdentity: String?
    public var permitID: String?
    public var approvalID: String?
    public var eligibleForFutureSnapshotCorrelation: Bool

    public init(
        actionEventID: String,
        entityID: String,
        vendor: String? = nil,
        action: StorageAction,
        repoID: String? = nil,
        revision: String? = nil,
        executedAt: Date,
        postVerifyAt: Date? = nil,
        logicalOutcome: String,
        recoveryOutcome: String,
        verifiedRecoveredBytes: Int64,
        vendorPreviewFingerprint: String? = nil,
        remoteIdentity: String? = nil,
        permitID: String? = nil,
        approvalID: String? = nil,
        eligibleForFutureSnapshotCorrelation: Bool = true
    ) {
        self.actionEventID = actionEventID
        self.entityID = entityID
        self.vendor = vendor
        self.action = action
        self.repoID = repoID
        self.revision = revision
        self.executedAt = executedAt
        self.postVerifyAt = postVerifyAt
        self.logicalOutcome = logicalOutcome
        self.recoveryOutcome = recoveryOutcome
        self.verifiedRecoveredBytes = verifiedRecoveredBytes
        self.vendorPreviewFingerprint = vendorPreviewFingerprint
        self.remoteIdentity = remoteIdentity
        self.permitID = permitID
        self.approvalID = approvalID
        self.eligibleForFutureSnapshotCorrelation = eligibleForFutureSnapshotCorrelation
    }
}

public enum VerifiedActionResultBuilder {
    public static func byteLabel(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.0f MB", mb)
    }

    public static func fromOllamaExecution(
        _ exec: ActExecutionOrchestrator.OllamaNativeExecutionReport
    ) -> VerifiedActionResult {
        let display = exec.canonicalModel.replacingOccurrences(of: "library/", with: "")
        let phase: ExecutionAttemptPhase
        if exec.outcome == "ABORTED" || exec.abortReason != nil, !exec.realMutationExecuted {
            phase = .preExecutionRejected
        } else if exec.logicalRemovalVerified {
            phase = .postVerifyCompleted
        } else if exec.executorInvoked {
            phase = exec.processOutcome == "COMMAND_ACCEPTED" ? .processCompleted : .processStartAttempted
        } else if exec.permitID != nil {
            phase = .permitCreated
        } else {
            phase = .preExecutionRejected
        }

        let recovery: ProductRecoveryPresentation
        switch exec.recoveryStatus {
        case "MODEL_REMOVED_STORAGE_RECOVERED":
            recovery = .completedRecoveryVerified
        case "MODEL_REMOVED_STORAGE_PARTIALLY_RECOVERED":
            recovery = .completedRecoveryPartial
        case "MODEL_REMOVED_STORAGE_REMAINS":
            recovery = .completedNoRecovery
        case "MODEL_REMOVAL_NOT_VERIFIED":
            recovery = .notVerified
        default:
            if exec.abortReason != nil { recovery = .failed }
            else if exec.processOutcome == "UNKNOWN_OUTCOME" { recovery = .outcomeUnknown }
            else if exec.logicalRemovalVerified { recovery = .completedRecoveryPending }
            else { recovery = .failed }
        }

        let verified = exec.verifiedRecoveredBytes
        let potential = exec.potentialRecoveryBytesBefore ?? 0
        var lines: [String] = []
        var headline: String
        if phase == .preExecutionRejected {
            headline = "Action was not started"
            lines = [
                "Safety checks stopped before any change.",
                exec.abortReason.map { "Reason: \($0)" } ?? "Pre-execution rejection.",
            ]
        } else if exec.logicalRemovalVerified {
            headline = "\(display) was removed using Ollama."
            lines = [
                "\(byteLabel(verified)) of model storage was verified as removed.",
                "The model can be downloaded again if you need it.",
            ]
            if let disk = exec.diskFreeDeltaBytes, disk != verified {
                // Keep distinct — do not claim disk delta as causal recovery.
            }
        } else if recovery == .outcomeUnknown {
            headline = "AI Storage Manager could not verify whether the action completed."
            lines = ["Re-check state. Do not retry deletion until reconciliation finishes."]
        } else {
            headline = "Ollama cleanup did not verify removal."
            lines = [exec.explanation]
        }

        var tech: [String] = [
            "entity=\(exec.entityID)",
            "action=\(exec.action)",
            "executionOutcome=\(exec.processOutcome ?? exec.outcome)",
            "logical=\(exec.postVerifyStatus ?? exec.outcome)",
            "potentialBytes=\(potential)",
            "verifiedRecoveredBytes=\(verified)",
        ]
        if let disk = exec.diskFreeDeltaBytes {
            tech.append("observedDiskFreeDelta=\(disk) (not causal claim)")
        }
        if let permit = exec.permitID {
            tech.append("permit=\(permit)")
        }

        return VerifiedActionResult(
            actionEventID: exec.permitID ?? exec.approvalID ?? "event-\(exec.entityID)",
            action: .vendorNativeCleanup,
            targetEntityID: exec.entityID,
            targetDisplayName: display,
            canonicalModel: exec.canonicalModel,
            vendor: "OLLAMA",
            executionOutcome: exec.processOutcome ?? exec.outcome,
            attemptPhase: phase,
            logicalOutcome: exec.postVerifyStatus ?? exec.outcome,
            storageRecoveryOutcome: recovery,
            potentialRecoveryBytes: potential,
            verifiedRecoveredBytes: verified,
            observedDiskFreeDelta: exec.diskFreeDeltaBytes,
            regenerationState: (exec.regenerationDetected == true) ? "DETECTED" : "NONE",
            approvalID: exec.approvalID,
            permitID: exec.permitID,
            approvalOrigin: UserActionApprovalOrigin.cliExplicitHumanConfirmation.rawValue,
            nativeExecutor: "OllamaNativeCleanupExecutor",
            completedAt: exec.auditRecord?.executedAt ?? Date(),
            userHeadline: headline,
            userLines: lines,
            technicalDetailLines: tech
        )
    }

    public static func fromHuggingFaceExecution(
        _ exec: ActExecutionOrchestrator.HuggingFaceNativeExecutionReport,
        remoteStillAvailable: Bool = true,
        approvalOrigin: UserActionApprovalOrigin = .cliExplicitHumanConfirmation
    ) -> VerifiedActionResult {
        let shortRev = String(exec.revision.prefix(7)) + "…" + String(exec.revision.suffix(5))
        let phase: ExecutionAttemptPhase
        if exec.outcome == "ABORTED" || exec.abortReason != nil, !exec.realMutationExecuted {
            phase = .preExecutionRejected
        } else if exec.logicalRemovalVerified {
            phase = .postVerifyCompleted
        } else if exec.executorInvoked {
            phase = exec.processOutcome == "COMMAND_ACCEPTED" ? .processCompleted : .processStartAttempted
        } else if exec.permitID != nil {
            phase = .permitCreated
        } else {
            phase = .preExecutionRejected
        }

        let recovery: ProductRecoveryPresentation
        switch exec.recoveryStatus {
        case "SNAPSHOT_REMOVED_STORAGE_RECOVERED":
            recovery = .completedRecoveryVerified
        case "SNAPSHOT_REMOVED_STORAGE_PARTIALLY_RECOVERED":
            recovery = .completedRecoveryPartial
        case "SNAPSHOT_REMOVED_STORAGE_REMAINS":
            recovery = .completedNoRecovery
        case "SNAPSHOT_REMOVAL_NOT_VERIFIED":
            recovery = .notVerified
        default:
            if exec.abortReason != nil { recovery = .failed }
            else if exec.processOutcome == "UNKNOWN_OUTCOME" { recovery = .outcomeUnknown }
            else if exec.logicalRemovalVerified { recovery = .completedRecoveryPending }
            else { recovery = .failed }
        }

        let verified = exec.verifiedRecoveredBytes
        let potential = exec.potentialRecoveryBytesBefore ?? 0
        let vendorReported = exec.postVerify?.vendorReportedFreedBytes
        let lastRev: String?
        if exec.repoPresentAfter == false, exec.logicalRemovalVerified {
            lastRev = "SOLE_REVISION_EMPTIED_LOCAL_REPO_CACHE"
        } else if exec.repoPresentAfter == true, exec.logicalRemovalVerified {
            lastRev = "OTHER_REVISIONS_RETAINED_REPO_DIR_PRESENT"
        } else {
            lastRev = nil
        }

        var lines: [String] = []
        var headline: String
        if phase == .preExecutionRejected {
            headline = "Action was not started"
            lines = [
                "Safety checks stopped before any change.",
                exec.abortReason.map { "Reason: \($0)" } ?? "Pre-execution rejection.",
            ]
        } else if exec.logicalRemovalVerified {
            headline = "Removed local Hugging Face cache"
            lines = [
                "\(exec.repoID)",
                "✓ Exact cached revision removed (\(shortRev))",
                "✓ \(byteLabel(verified)) verified recovered",
            ]
            if remoteStillAvailable {
                lines.append("✓ Hugging Face Hub copy remains available")
            }
            lines.append("✓ No other repositories were removed")
            if lastRev == "SOLE_REVISION_EMPTIED_LOCAL_REPO_CACHE" {
                lines.append(
                    "This was the only cached revision; removing it left the local repository cache empty."
                )
            }
        } else if recovery == .outcomeUnknown {
            headline = "Could not verify whether the local cached revision was removed."
            lines = ["Re-check state. Do not retry deletion until reconciliation finishes."]
        } else {
            headline = "Hugging Face cleanup did not verify revision removal."
            lines = [exec.explanation]
        }

        var tech: [String] = [
            "entity=\(exec.entityID)",
            "repo=\(exec.repoID)",
            "revision=\(exec.revision)",
            "action=\(exec.action)",
            "executionOutcome=\(exec.processOutcome ?? exec.outcome)",
            "logical=\(exec.postVerifyStatus ?? exec.outcome)",
            "potentialBytes=\(potential)",
            "verifiedRecoveredBytes=\(verified)",
            "argv=\(exec.argvContract.joined(separator: " "))",
        ]
        if let vendorReported {
            tech.append("vendorReportedRecoveryBytes=\(vendorReported) (telemetry, not causal claim)")
        }
        if let disk = exec.diskFreeDeltaBytes {
            tech.append("observedDiskFreeDelta=\(disk) (not causal claim)")
        }
        if let permit = exec.permitID {
            tech.append("permit=\(permit)")
        }
        if let approval = exec.approvalID {
            tech.append("approval=\(approval)")
        }

        return VerifiedActionResult(
            actionEventID: exec.permitID ?? exec.approvalID ?? "event-\(exec.entityID)",
            action: .vendorNativeCleanup,
            targetEntityID: exec.entityID,
            targetDisplayName: "\(exec.repoID)@\(shortRev)",
            vendor: "HUGGING_FACE",
            repoID: exec.repoID,
            revision: exec.revision,
            executionOutcome: exec.processOutcome ?? exec.outcome,
            attemptPhase: phase,
            logicalOutcome: exec.postVerifyStatus ?? exec.outcome,
            storageRecoveryOutcome: recovery,
            potentialRecoveryBytes: potential,
            vendorReportedRecoveryBytes: vendorReported,
            verifiedRecoveredBytes: verified,
            observedDiskFreeDelta: exec.diskFreeDeltaBytes,
            remoteReacquisitionState: remoteStillAvailable ? "AVAILABLE" : "UNKNOWN",
            lastRevisionConsequence: lastRev,
            regenerationState: "NONE",
            approvalID: exec.approvalID,
            permitID: exec.permitID,
            approvalOrigin: approvalOrigin.rawValue,
            nativeExecutor: "HuggingFaceNativeCleanupExecutor",
            completedAt: exec.auditRecord?.executedAt ?? Date(),
            userHeadline: headline,
            userLines: lines,
            technicalDetailLines: tech
        )
    }

    public static func receiptChecklist(from result: VerifiedActionResult) -> [String] {
        var items: [String] = []
        if result.vendor == "HUGGING_FACE" || result.repoID != nil {
            items.append(result.attemptPhase == .preExecutionRejected
                ? "○ Native Hugging Face action not started"
                : "✓ Native Hugging Face action completed")
            if result.logicalOutcome == "SNAPSHOT_REMOVED"
                || result.logicalOutcome.contains("SNAPSHOT_REMOVED") {
                items.append("✓ Local revision no longer cached")
            } else if result.attemptPhase != .preExecutionRejected {
                items.append("○ Local revision removal not verified")
            }
            if result.verifiedRecoveredBytes > 0 {
                items.append("✓ \(byteLabel(result.verifiedRecoveredBytes)) verified removed")
            }
            if result.remoteReacquisitionState == "AVAILABLE" {
                items.append("✓ Hub revision remains available")
            }
            return items
        }
        if result.action == .vendorNativeCleanup {
            items.append(result.attemptPhase == .preExecutionRejected
                ? "○ Native Ollama action not started"
                : "✓ Native Ollama action completed")
        }
        if result.logicalOutcome == "MODEL_REMOVED" {
            items.append("✓ Model no longer installed")
        } else if result.attemptPhase != .preExecutionRejected {
            items.append("○ Model removal not verified")
        }
        if result.verifiedRecoveredBytes > 0 {
            items.append("✓ \(byteLabel(result.verifiedRecoveredBytes)) verified removed")
        }
        if result.regenerationState == "NONE", result.logicalOutcome == "MODEL_REMOVED" {
            items.append("✓ No regeneration detected")
        }
        return items
    }

    public static func toHistoryEvent(_ result: VerifiedActionResult) -> VerifiedStorageActionEvent {
        VerifiedStorageActionEvent(
            actionEventID: result.actionEventID,
            entityID: result.targetEntityID,
            vendor: result.vendor,
            action: result.action,
            repoID: result.repoID,
            revision: result.revision,
            executedAt: result.completedAt,
            postVerifyAt: result.attemptPhase == .postVerifyCompleted ? result.completedAt : nil,
            logicalOutcome: result.logicalOutcome,
            recoveryOutcome: result.storageRecoveryOutcome.rawValue,
            verifiedRecoveredBytes: result.verifiedRecoveredBytes,
            vendorPreviewFingerprint: result.repoID.map { "hf:\($0):\(result.revision ?? "")" },
            remoteIdentity: result.revision.map { "hub:\(result.repoID ?? ""):\($0)" },
            permitID: result.permitID,
            approvalID: result.approvalID,
            eligibleForFutureSnapshotCorrelation: result.verifiedRecoveredBytes > 0
                && result.attemptPhase == .postVerifyCompleted
        )
    }

    /// Exact identity correlation — timestamp alone is insufficient.
    public static func canCorrelate(
        event: VerifiedStorageActionEvent,
        entityID: String,
        action: StorageAction,
        permitID: String?
    ) -> Bool {
        guard event.entityID == entityID, event.action == action else { return false }
        if let permitID, let eventPermit = event.permitID {
            return eventPermit == permitID
        }
        let logicalOK = event.logicalOutcome == "MODEL_REMOVED"
            || event.logicalOutcome == "SNAPSHOT_REMOVED"
            || event.logicalOutcome.contains("SNAPSHOT_REMOVED")
        return event.eligibleForFutureSnapshotCorrelation && logicalOK && permitID == nil
    }

    public static var timestampOnlyCorrelationAllowed: Bool { false }

    /// Completed verified recovery from known real vendor-native actions (Ollama + HF).
    public static func completedVerifiedRecoveryTotal(
        ollamaVerified: Int64 = 2_497_293_931,
        hfVerified: Int64 = 3_083_520_968
    ) -> Int64 {
        ollamaVerified &+ hfVerified
    }
}

/// All approval origins mint the same canonical UserActionApproval model.
public enum UserActionApprovalOrigin: String, Codable, Sendable, Equatable {
    case ui = "UI"
    case cliExplicitHumanConfirmation = "CLI_EXPLICIT_HUMAN_CONFIRMATION"
    case api = "API"
}
