import Foundation

public enum PredicateValue: String, Codable, Sendable {
    case `true`
    case `false`
    case unknown
}

public struct EvidenceBundle: Codable, Sendable, Equatable {
    public var canonicalPath: String
    public var ownerIsCurrentUser: PredicateValue
    public var isSymlink: PredicateValue
    public var isHardLink: PredicateValue
    public var isAPFSClone: PredicateValue
    public var isPackage: PredicateValue
    public var cloudFileProvider: PredicateValue
    public var iCloudEvictable: PredicateValue
    public var openFileHandle: PredicateValue
    public var owningProcessRunning: PredicateValue
    public var sourceOfTruth: PredicateValue
    public var regenerable: PredicateValue
    public var sourceProjectExists: PredicateValue
    public var manifestExists: PredicateValue
    public var lockfileExists: PredicateValue
    public var backupExists: PredicateValue
    public var syncWouldDeleteRemote: PredicateValue
    public var sipProtected: PredicateValue
    public var extra: [String: PredicateValue]
    public var confidence: Double
    /// Confidence for strict Safety predicates. Missing key ⇒ UNKNOWN (cannot satisfy GREEN).
    public var predicateConfidence: [String: EvidenceConfidence]
    public var observationCompleteness: [String: ObservationCompleteness]

    public init(
        canonicalPath: String,
        ownerIsCurrentUser: PredicateValue = .unknown,
        isSymlink: PredicateValue = .false,
        isHardLink: PredicateValue = .unknown,
        isAPFSClone: PredicateValue = .unknown,
        isPackage: PredicateValue = .unknown,
        cloudFileProvider: PredicateValue = .unknown,
        iCloudEvictable: PredicateValue = .unknown,
        openFileHandle: PredicateValue = .unknown,
        owningProcessRunning: PredicateValue = .unknown,
        sourceOfTruth: PredicateValue = .unknown,
        regenerable: PredicateValue = .unknown,
        sourceProjectExists: PredicateValue = .unknown,
        manifestExists: PredicateValue = .unknown,
        lockfileExists: PredicateValue = .unknown,
        backupExists: PredicateValue = .unknown,
        syncWouldDeleteRemote: PredicateValue = .unknown,
        sipProtected: PredicateValue = .unknown,
        extra: [String: PredicateValue] = [:],
        confidence: Double = 0.5,
        predicateConfidence: [String: EvidenceConfidence] = [:],
        observationCompleteness: [String: ObservationCompleteness] = [:]
    ) {
        self.canonicalPath = canonicalPath
        self.ownerIsCurrentUser = ownerIsCurrentUser
        self.isSymlink = isSymlink
        self.isHardLink = isHardLink
        self.isAPFSClone = isAPFSClone
        self.isPackage = isPackage
        self.cloudFileProvider = cloudFileProvider
        self.iCloudEvictable = iCloudEvictable
        self.openFileHandle = openFileHandle
        self.owningProcessRunning = owningProcessRunning
        self.sourceOfTruth = sourceOfTruth
        self.regenerable = regenerable
        self.sourceProjectExists = sourceProjectExists
        self.manifestExists = manifestExists
        self.lockfileExists = lockfileExists
        self.backupExists = backupExists
        self.syncWouldDeleteRemote = syncWouldDeleteRemote
        self.sipProtected = sipProtected
        self.extra = extra
        self.confidence = confidence
        self.predicateConfidence = predicateConfidence
        self.observationCompleteness = observationCompleteness
    }

    public func value(for key: String) -> PredicateValue {
        switch key {
        case "canonical_path": return canonicalPath.isEmpty ? .unknown : .true
        case "owner_current_user": return ownerIsCurrentUser
        case "not_symlink": return isSymlink == .true ? .false : (isSymlink == .false ? .true : .unknown)
        case "no_open_file_handle": return inverted(openFileHandle)
        case "owning_process_not_running": return inverted(owningProcessRunning)
        case "not_source_of_truth": return inverted(sourceOfTruth)
        case "regenerable": return regenerable
        case "source_project_exists": return sourceProjectExists
        case "manifest_exists": return manifestExists
        case "lockfile_exists": return lockfileExists
        case "backup_exists": return backupExists
        case "sync_would_not_delete_remote": return inverted(syncWouldDeleteRemote)
        case "not_sip_protected": return inverted(sipProtected)
        case "icloud_evictable": return iCloudEvictable
        default:
            return extra[key] ?? .unknown
        }
    }

    /// Strict Safety gate: value must be true AND confidence VERIFIED.
    public func satisfiesStrictPredicate(_ key: String) -> Bool {
        guard value(for: key) == .true else { return false }
        let conf = confidence(for: key)
        return conf == .verified
    }

    public func confidence(for key: String) -> EvidenceConfidence {
        if let hit = predicateConfidence[key] { return hit }
        // Explicit filesystem facts default to VERIFIED when value is known true/false
        switch key {
        case "canonical_path":
            return canonicalPath.isEmpty ? .unknown : .verified
        case "not_symlink":
            return isSymlink == .unknown ? .unknown : .verified
        default:
            return .unknown
        }
    }

    private func inverted(_ value: PredicateValue) -> PredicateValue {
        switch value {
        case .true: return .false
        case .false: return .true
        case .unknown: return .unknown
        }
    }
}
