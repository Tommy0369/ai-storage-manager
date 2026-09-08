import Foundation

/// P3.4B — Voice Memos preservation / local residency proof (read-only).
/// PRESERVATION ≠ DELETION.
/// DELETE_RECORDING (sync-propagating) must never alias REMOVE_LOCAL_DOWNLOAD.

public enum VoiceMemoCloudSyncState: String, Codable, Sendable, Equatable {
    case localOnlyVerified = "LOCAL_ONLY_VERIFIED"
    case remotePresentVerified = "REMOTE_PRESENT_VERIFIED"
    case remoteCurrentVerified = "REMOTE_CURRENT_VERIFIED"
    case syncPending = "SYNC_PENDING"
    case syncConflicted = "SYNC_CONFLICTED"
    case remoteUnknown = "REMOTE_UNKNOWN"
    case localMissingRemoteUnknown = "LOCAL_MISSING_REMOTE_UNKNOWN"
    case unknown = "UNKNOWN"
}

public enum VoiceMemoLocalResidencyState: String, Codable, Sendable, Equatable {
    case resident = "RESIDENT"
    case nonresidentNative = "NONRESIDENT_NATIVE"
    case partiallyResident = "PARTIALLY_RESIDENT"
    case downloadPending = "DOWNLOAD_PENDING"
    case evictionPending = "EVICTION_PENDING"
    case unknown = "UNKNOWN"
}

public enum VoiceMemoSourceOfTruthState: String, Codable, Sendable, Equatable {
    case localSourceOnly = "LOCAL_SOURCE_ONLY"
    case remoteSourceVerified = "REMOTE_SOURCE_VERIFIED"
    case localAndRemoteVerified = "LOCAL_AND_REMOTE_VERIFIED"
    case sourceOfTruthUnknown = "SOURCE_OF_TRUTH_UNKNOWN"
}

public enum DeletionPropagationSemantics: String, Codable, Sendable, Equatable {
    case localOnlyVerified = "LOCAL_ONLY_VERIFIED"
    case syncPropagatesDelete = "SYNC_PROPAGATES_DELETE"
    case remoteDelete = "REMOTE_DELETE"
    case unknown = "UNKNOWN"
}

public enum VoiceMemosSyncArchitecture: String, Codable, Sendable, Equatable {
    case cloudKitCoreDataMirroring = "CLOUDKIT_COREDATA_MIRRORING"
    case cloudDocs = "CLOUDDOCS"
    case fileProvider = "FILE_PROVIDER"
    case appPrivateICloudContainer = "APP_PRIVATE_ICLOUD_CONTAINER"
    case unknown = "UNKNOWN"
}

public enum VoiceMemosICloudSettingState: String, Codable, Sendable, Equatable {
    case enabledVerified = "ENABLED_VERIFIED"
    case disabledVerified = "DISABLED_VERIFIED"
    case enabledInferred = "ENABLED_INFERRED"
    case unknown = "UNKNOWN"
}

public enum VoiceMemosFutureActionUnit: String, Codable, Sendable, Equatable {
    case exactRecording = "EXACT_RECORDING"
    case nativeAsset = "NATIVE_ASSET"
    case vendorManagedSet = "VENDOR_MANAGED_SET"
    case none = "NONE"
    case unknown = "UNKNOWN"
}

public struct VoiceMemosLocalEvictionContract: Codable, Sendable, Equatable {
    public var vendor: String
    public var storageClass: String
    public var targetUnit: VoiceMemosFutureActionUnit
    public var nativeOperation: String
    public var remoteProofRequirement: String
    public var currentnessRequirement: String
    public var localResidencyRequirement: String
    public var deletePropagationSemantics: DeletionPropagationSemantics
    public var runtimeRequirements: String
    public var blastRadius: String
    public var postVerifyContract: String
    public var evidence: [String]
    public var confidence: String
    public var contractFound: Bool
    public var contractReady: Bool
    public var currentExecutable: Bool
    public var candidateBytes: Int64
}

public enum VoiceMemosPreservationRules {
    public static let preservationIsNotDeletion = true
    public static let userOriginalDefault = true
    public static let userOriginalBlocksDelete = true
    public static let userOriginalAllowsPreservationAnalysis = true

    public static let vendorDocsCrossDeviceSync = true
    public static let vendorDocsPermanentDeletePropagates = true
    public static let genericMacOptimizeStorageInsufficient = true
    public static let rawDeleteIsNotNativeEviction = true
    public static let genericMoveToICloudBlocked = true
    public static let fileProviderNotAssumed = true

    /// Distinct action IDs — must never alias.
    public static let distinctActions: [String] = [
        "KEEP",
        "DELETE_RECORDING",
        "MOVE_TO_TRASH",
        "SYNC_TO_CLOUD",
        "REMOVE_LOCAL_DOWNLOAD",
        "EXPORT_ARCHIVE",
        "MOVE_TO_ICLOUD",
    ]

    public static func deleteRecordingAliasesRemoveLocalDownload() -> Bool { false }

    public static func eligibleLocalEvictionBytes(
        remoteIdentityVerified: Bool,
        remoteCurrentVerified: Bool,
        reacquisitionVerified: Bool,
        nativeLocalOnlyEvictionVerified: Bool,
        deletePropagation: DeletionPropagationSemantics,
        blastRadiusBound: Bool,
        exactLocalMediaTargetVerified: Bool,
        stateCompatible: Bool,
        bytes: Int64
    ) -> Int64 {
        guard remoteIdentityVerified,
              remoteCurrentVerified,
              reacquisitionVerified,
              nativeLocalOnlyEvictionVerified,
              deletePropagation == .localOnlyVerified,
              blastRadiusBound,
              exactLocalMediaTargetVerified,
              stateCompatible
        else {
            return 0
        }
        return bytes
    }

    public static func missingLocalFileImpliesCloudOnly() -> Bool { false }

    public static func iCloudEnabledAloneProvesRemoteObject() -> Bool { false }

    public static func remoteCopyAloneCreatesActionability() -> Bool { false }

    /// Evidence-backed live Mac conclusion template (fixtures use same gates).
    public static func knownNoNativeLocalEvictionContract() -> VoiceMemosLocalEvictionContract {
        VoiceMemosLocalEvictionContract(
            vendor: "APPLE_VOICE_MEMOS",
            storageClass: "USER_ORIGINAL_RECORDINGS",
            targetUnit: .none,
            nativeOperation: "NONE_PROVEN",
            remoteProofRequirement: "REMOTE_CURRENT_VERIFIED per recording",
            currentnessRequirement: "REQUIRED",
            localResidencyRequirement: "RESIDENT media exact target",
            deletePropagationSemantics: .unknown,
            runtimeRequirements: "N/A — no eviction operation",
            blastRadius: "UNBOUNDED_WITHOUT_OPERATION",
            postVerifyContract: "N/A",
            evidence: [
                "App links CloudKit + VoiceMemos.framework; no FileProvider",
                "CloudRecordings.db uses NSCloudKitMirroring (ANSCK*)",
                "UI/localizable: Delete Recording / iCloud Syncing — no Remove Download",
                "voicememod has CloudRecordingsMarkedPlayableAndEvicted literal but no product call path for REMOVE_LOCAL_DOWNLOAD",
                "ZEVICTIONDATE column exists; does not prove safe local-only eviction API",
                "Vendor docs: sync across devices; permanent delete propagates",
            ],
            confidence: "VERIFIED_ABSENCE_BOUNDED_SEARCH",
            contractFound: false,
            contractReady: false,
            currentExecutable: false,
            candidateBytes: 0
        )
    }

    public static func classifySyncArchitecture(
        cloudKitLinked: Bool,
        fileProviderLinked: Bool,
        coreDataMirroringPresent: Bool
    ) -> VoiceMemosSyncArchitecture {
        if fileProviderLinked { return .fileProvider }
        if cloudKitLinked && coreDataMirroringPresent { return .cloudKitCoreDataMirroring }
        if cloudKitLinked { return .cloudKitCoreDataMirroring }
        return .unknown
    }
}
