import Foundation

/// Exact scope for software-install human authorization. Never covers model cleanup.
public enum SoftwareInstallationAuthorizationScope: String, Codable, Sendable, Equatable {
    case ollamaSoftwareReinstallationOnly = "OLLAMA_SOFTWARE_REINSTALLATION_ONLY"
    case huggingFaceCLIInstallationOnly = "HUGGING_FACE_CLI_INSTALLATION_ONLY"
}

/// Single-purpose install authorization. Consumed once for Ollama restore.
/// Cannot mint cleanup ExecutionPermit or UserActionApproval for model removal.
public struct SoftwareInstallationAuthorization: Codable, Sendable, Equatable {
    public var authorizationID: String
    public var scope: SoftwareInstallationAuthorizationScope
    public var vendor: VendorStorageKind
    public var relatedEntityID: String
    public var purpose: String
    public var authorizedAt: Date
    public var consumedAt: Date?
    public var doesNotAuthorizeCleanup: Bool
    public var doesNotAuthorizeModelRemoval: Bool
    public var doesNotAuthorizePullRunCreate: Bool
    public var doesNotAuthorizeRawDelete: Bool

    public var isConsumed: Bool { consumedAt != nil }

    public var allowsOllamaInstall: Bool {
        !isConsumed
            && scope == .ollamaSoftwareReinstallationOnly
            && vendor == .ollama
    }

    public var allowsHuggingFaceCLIInstall: Bool {
        !isConsumed
            && scope == .huggingFaceCLIInstallationOnly
            && vendor == .huggingFace
    }

    public static func authorizeOllamaRestore(
        entityID: String,
        authorizedAt: Date = Date()
    ) -> SoftwareInstallationAuthorization {
        SoftwareInstallationAuthorization(
            authorizationID: "install-auth-ollama-\(UUID().uuidString.prefix(8))",
            scope: .ollamaSoftwareReinstallationOnly,
            vendor: .ollama,
            relatedEntityID: entityID,
            purpose: "Restore Ollama native management only. Does not authorize model removal.",
            authorizedAt: authorizedAt,
            consumedAt: nil,
            doesNotAuthorizeCleanup: true,
            doesNotAuthorizeModelRemoval: true,
            doesNotAuthorizePullRunCreate: true,
            doesNotAuthorizeRawDelete: true
        )
    }

    public static func authorizeHuggingFaceCLIInstall(
        entityID: String,
        authorizedAt: Date = Date()
    ) -> SoftwareInstallationAuthorization {
        SoftwareInstallationAuthorization(
            authorizationID: "install-auth-hf-cli-\(UUID().uuidString.prefix(8))",
            scope: .huggingFaceCLIInstallationOnly,
            vendor: .huggingFace,
            relatedEntityID: entityID,
            purpose: "Install Hugging Face hf CLI only. Does not authorize cache revision removal.",
            authorizedAt: authorizedAt,
            consumedAt: nil,
            doesNotAuthorizeCleanup: true,
            doesNotAuthorizeModelRemoval: true,
            doesNotAuthorizePullRunCreate: true,
            doesNotAuthorizeRawDelete: true
        )
    }

    public mutating func consume(at date: Date = Date()) -> Bool {
        guard allowsOllamaInstall || allowsHuggingFaceCLIInstall else { return false }
        consumedAt = date
        return true
    }

    /// Install authorization must never become cleanup approval.
    public func asModelRemovalApproval() -> UserActionApproval? { nil }

    public func asCleanupExecutionPermit() -> ExecutionPermit? { nil }
}

public enum SoftwareInstallMethod: String, Codable, Sendable, Equatable {
    case officialAppInstall = "OFFICIAL_APP_INSTALL"
    case packageManagerInstall = "PACKAGE_MANAGER_INSTALL"
    case existingOfficialInstaller = "EXISTING_OFFICIAL_INSTALLER"
    case unresolved = "UNRESOLVED"
}

public enum SoftwareInstallSourceClass: String, Codable, Sendable, Equatable {
    case officialLocalArtifact = "OFFICIAL_LOCAL_ARTIFACT"
    case officialRemoteDistribution = "OFFICIAL_REMOTE_DISTRIBUTION"
    case establishedPackageManager = "ESTABLISHED_PACKAGE_MANAGER"
    case unresolved = "UNRESOLVED"
}

/// Read-only pre-install evidence. Not reusable as cleanup authorization.
public struct PreInstallManagedDataReceipt: Codable, Sendable, Equatable {
    public var vendorAbsent: Bool
    public var entityID: String
    public var canonicalModel: String
    public var manifestFingerprint: String?
    public var referenceGraphFingerprint: String?
    public var uniqueBytes: Int64?
    public var sharedBytes: Int64?
    public var remoteProofStatus: String?
    public var managedDataRootPath: String
    public var managedDataRootExists: Bool
    public var manifestPresentOnDisk: Bool
    public var capturedAt: Date
}

public enum InstalledModelRecognitionStatus: String, Codable, Sendable, Equatable {
    case recognizedExact = "RECOGNIZED_EXACT"
    case dataRemainsUnrecognized = "DATA_REMAINS_UNRECOGNIZED"
    case identityAmbiguous = "IDENTITY_AMBIGUOUS"
    case dataUnexpectedlyAltered = "DATA_UNEXPECTEDLY_ALTERED"
    case inventoryUnavailable = "INVENTORY_UNAVAILABLE"
}

/// Result of restoring vendor management. Locks forbid pull/run/cleanup in this phase.
public struct VendorManagementRestoreResult: Codable, Sendable, Equatable {
    public var vendor: VendorStorageKind
    public var installMethod: SoftwareInstallMethod
    public var sourceClass: SoftwareInstallSourceClass
    public var sourceVerified: Bool
    public var installedVersion: String?
    public var bundleIdentifier: String?
    public var installationSucceeded: Bool
    public var nativeInterfaceDetected: Bool
    public var modelDataPreserved: Bool
    public var startedManagementService: Bool
    public var modelRunPerformed: Bool
    public var modelPullPerformed: Bool
    public var cleanupPerformed: Bool
    public var completedAt: Date
    public var failureReason: String?
    public var artifactIdentity: String?
    public var unexpectedDataMutation: Bool

    public init(
        vendor: VendorStorageKind = .ollama,
        installMethod: SoftwareInstallMethod,
        sourceClass: SoftwareInstallSourceClass,
        sourceVerified: Bool,
        installedVersion: String? = nil,
        bundleIdentifier: String? = nil,
        installationSucceeded: Bool,
        nativeInterfaceDetected: Bool,
        modelDataPreserved: Bool,
        startedManagementService: Bool,
        modelRunPerformed: Bool = false,
        modelPullPerformed: Bool = false,
        cleanupPerformed: Bool = false,
        completedAt: Date = Date(),
        failureReason: String? = nil,
        artifactIdentity: String? = nil,
        unexpectedDataMutation: Bool = false
    ) {
        self.vendor = vendor
        self.installMethod = installMethod
        self.sourceClass = sourceClass
        self.sourceVerified = sourceVerified
        self.installedVersion = installedVersion
        self.bundleIdentifier = bundleIdentifier
        self.installationSucceeded = installationSucceeded
        self.nativeInterfaceDetected = nativeInterfaceDetected
        self.modelDataPreserved = modelDataPreserved
        self.startedManagementService = startedManagementService
        self.modelRunPerformed = modelRunPerformed
        self.modelPullPerformed = modelPullPerformed
        self.cleanupPerformed = cleanupPerformed
        self.completedAt = completedAt
        self.failureReason = failureReason
        self.artifactIdentity = artifactIdentity
        self.unexpectedDataMutation = unexpectedDataMutation
    }

    public static func failure(
        method: SoftwareInstallMethod,
        sourceClass: SoftwareInstallSourceClass,
        sourceVerified: Bool,
        reason: String,
        modelDataPreserved: Bool,
        unexpectedMutation: Bool = false,
        artifactIdentity: String? = nil
    ) -> VendorManagementRestoreResult {
        VendorManagementRestoreResult(
            vendor: .ollama,
            installMethod: method,
            sourceClass: sourceClass,
            sourceVerified: sourceVerified,
            installedVersion: nil,
            bundleIdentifier: nil,
            installationSucceeded: false,
            nativeInterfaceDetected: false,
            modelDataPreserved: modelDataPreserved,
            startedManagementService: false,
            modelRunPerformed: false,
            modelPullPerformed: false,
            cleanupPerformed: false,
            completedAt: Date(),
            failureReason: reason,
            artifactIdentity: artifactIdentity,
            unexpectedDataMutation: unexpectedMutation
        )
    }
}

public enum PostInstallRestorePhaseOutcome: String, Codable, Sendable, Equatable {
    case readyForModelRemovalAuthorization = "READY_FOR_MODEL_REMOVAL_AUTHORIZATION"
    case approvalRequired = "APPROVAL_REQUIRED"
    case vendorRestoredModelUnrecognized = "VENDOR_RESTORED_MODEL_UNRECOGNIZED"
    case blockedActive = "BLOCKED_ACTIVE"
    case verifyMore = "VERIFY_MORE"
    case installFailed = "INSTALL_FAILED"
    case dataDamageStop = "DATA_DAMAGE_STOP"
}

/// Soft product UX labels after restore (presentation only).
public enum OllamaRestoreUXLabel {
    public static let managementRestored = "Ollama management restored"
    public static let checkingSafety = "Checking model safety…"
    public static let readyForReview = "Ready for review"
    public static let modelCurrentlyActive = "Model currently active"
    public static let moreVerificationRequired = "More verification required"
    public static let removeOllamaModel = "Remove Ollama Model"
}
