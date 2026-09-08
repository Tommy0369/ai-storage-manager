import Foundation

/// ACT-phase design types only. No execution in PROVE phase.
/// See `docs/ACTION_ARCHITECTURE_v0.1.md`.

public enum StorageAction: String, Codable, Sendable, CaseIterable {
    case keep = "KEEP"
    case moveToTrash = "MOVE_TO_TRASH"
    case moveToICloud = "MOVE_TO_ICLOUD"
    case removeLocalDownload = "REMOVE_LOCAL_DOWNLOAD"
    case vendorNativeCleanup = "VENDOR_NATIVE_CLEANUP"
}

public enum ICloudTransactionPhase: String, Codable, Sendable {
    case notStarted = "NOT_STARTED"
    case preflight = "PREFLIGHT"
    case approvalRequired = "APPROVAL_REQUIRED"
    case copying = "COPYING"
    case localCopyVerified = "LOCAL_COPY_VERIFIED"
    case uploadPending = "UPLOAD_PENDING"
    case verifyingRemote = "VERIFYING_REMOTE"
    case remoteVerified = "REMOTE_VERIFIED"
    case localReleaseEligible = "LOCAL_RELEASE_ELIGIBLE"
    case releasingLocalCopy = "RELEASING_LOCAL_COPY"
    case postVerify = "POST_VERIFY"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case unknown = "UNKNOWN"
    case cancelled = "CANCELLED"
}

public enum TrashTransactionPhase: String, Codable, Sendable {
    case notStarted = "NOT_STARTED"
    case preflight = "PREFLIGHT"
    case approvalRequired = "APPROVAL_REQUIRED"
    case ready = "READY"
    case movingToTrash = "MOVING_TO_TRASH"
    case verifyingTrashResult = "VERIFYING_TRASH_RESULT"
    case postVerify = "POST_VERIFY"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
    case unknown = "UNKNOWN"
}

public enum RemoveLocalDownloadTransactionPhase: String, Codable, Sendable {
    case notStarted = "NOT_STARTED"
    case preflight = "PREFLIGHT"
    case approvalRequired = "APPROVAL_REQUIRED"
    case ready = "READY"
    case requestingNativeEviction = "REQUESTING_NATIVE_EVICTION"
    case verifyingLocalRelease = "VERIFYING_LOCAL_RELEASE"
    case verifyingRemotePreservation = "VERIFYING_REMOTE_PRESERVATION"
    case postVerify = "POST_VERIFY"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case unknown = "UNKNOWN"
    case cancelled = "CANCELLED"
}

public struct ICloudTransferAuditRecord: Codable, Sendable, Equatable {
    public var entityID: String
    public var sourcePath: String
    public var destinationPath: String?
    public var action: StorageAction
    public var phase: ICloudTransactionPhase
    public var bytesExpected: Int64?
    public var bytesReclaimed: Int64?
    public var sourceVerified: Bool
    public var remoteVerified: Bool
    public var uploadState: String?
    public var localReleaseApproved: Bool
    public var localReleaseSucceeded: Bool?
    public var errors: [String]
    public var startedAt: Date
    public var completedAt: Date?
    public var userApproved: Bool
}

public enum ActionArchitecture {
    /// Maps legacy SafetyRuleEngine action to first-class storage action (design aid).
    public static func storageAction(from mode: ActionMode) -> StorageAction? {
        switch mode {
        case .noAction, .userReview:
            return .keep
        case .hardBlock:
            return nil
        case .moveToTrash, .osAPIOnly:
            return .moveToTrash
        case .cloudEvictOnly:
            return .removeLocalDownload
        case .toolCLIOnly, .packageManagerCommand, .appAPIOnly, .appUninstall:
            return .vendorNativeCleanup
        case .permanentDelete:
            return nil
        }
    }

    public static func evidenceBundle(from item: ClassifiedItem, snapshot: EntitySafetySnapshot? = nil) -> EvidenceBundle {
        if let snapshot {
            return snapshot.evidence
        }
        var bundle = EvidenceBundle(canonicalPath: item.detected.entity.path, confidence: 0.5)
        if let v = item.verification {
            bundle.sourceOfTruth = v.sourceOfTruth.value
            bundle.regenerable = v.regenerable.value
            bundle.predicateConfidence["not_source_of_truth"] = v.sourceOfTruth.confidence
            bundle.predicateConfidence["regenerable"] = v.regenerable.confidence
            if v.activeState == .active { bundle.owningProcessRunning = .true }
            if v.activeState == .inactive, v.activeStateConfidence == .verified {
                bundle.owningProcessRunning = .false
            }
        }
        if item.detected.bucket == .cloud {
            bundle.cloudFileProvider = .true
        }
        return bundle
    }

    /// Entity classes that must NOT auto-offer MOVE_TO_ICLOUD without relocation contract.
    public static let iCloudRelocationBlockedPathPatterns: [String] = [
        "/Library/Application Support",
        "/Library/Containers",
        "/Library/Group Containers",
        "/Library/Caches",
        "/Library/Developer/Xcode/DerivedData",
        "node_modules",
        "globalStorage",
        "snapshots",
        ".vm",
        "rootfs.img",
    ]

    public static func mayOfferMoveToICloud(path: String, userOwnedVerified: Bool, relocationContractVerified: Bool) -> Bool {
        if relocationContractVerified { return true }
        guard userOwnedVerified else { return false }
        let lower = path.lowercased()
        return !iCloudRelocationBlockedPathPatterns.contains { lower.contains($0.lowercased()) }
    }
}
