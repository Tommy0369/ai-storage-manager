import Foundation

/// Vendor-managed storage availability relative to the vendor application/interface.
public enum VendorManagedDataAvailability: String, Codable, Sendable, Equatable {
    case vendorPresentNativeInterfaceAvailable = "VENDOR_PRESENT_NATIVE_INTERFACE_AVAILABLE"
    case vendorPresentNativeInterfaceUnavailable = "VENDOR_PRESENT_NATIVE_INTERFACE_UNAVAILABLE"
    case vendorAbsentManagedDataRemains = "VENDOR_ABSENT_MANAGED_DATA_REMAINS"
    case vendorInstallStateUnknown = "VENDOR_INSTALL_STATE_UNKNOWN"
    case notApplicable = "NOT_APPLICABLE"
}

public enum VendorLocalFormatCompatibility: String, Codable, Sendable, Equatable {
    case compatibleVerified = "COMPATIBLE_VERIFIED"
    case likelyCompatibleInferred = "LIKELY_COMPATIBLE_INFERRED"
    case unknown = "UNKNOWN"
    case incompatibleVerified = "INCOMPATIBLE_VERIFIED"
}

public enum VendorManagedDataRemediationKind: String, Codable, Sendable, Equatable {
    case reinstallVendorToRestoreNativeManagement = "REINSTALL_VENDOR_TO_RESTORE_NATIVE_MANAGEMENT"
    case keep = "KEEP"
    case verifyMore = "VERIFY_MORE"
}

public enum VendorRemediationFlowState: String, Codable, Sendable, Equatable {
    case staleVendorDataDetected = "STALE_VENDOR_DATA_DETECTED"
    case installRequired = "INSTALL_REQUIRED"
    case installAuthorizationRequired = "INSTALL_AUTHORIZATION_REQUIRED"
    // Future (post-install) — not entered in P3.2A.2 live path:
    case vendorInstalled = "VENDOR_INSTALLED"
    case nativeInterfaceVerifying = "NATIVE_INTERFACE_VERIFYING"
    case modelRecognitionVerifying = "MODEL_RECOGNITION_VERIFYING"
    case runtimeVerifying = "RUNTIME_VERIFYING"
    case cleanupPreflight = "CLEANUP_PREFLIGHT"
    case cleanupAuthorizationRequired = "CLEANUP_AUTHORIZATION_REQUIRED"
    case execution = "EXECUTION"
}

public enum SoftwareInstallationSource: String, Codable, Sendable, Equatable {
    case officialApp = "OFFICIAL_APP"
    case packageManager = "PACKAGE_MANAGER"
    case userManagedInstall = "USER_MANAGED_INSTALL"
    case unknown = "UNKNOWN"
}

/// Remediation for vendor-managed data when native cleanup is unavailable.
/// Does NOT assign SafetyClass. Does NOT authorize deletion.
public struct VendorManagedDataRemediation: Codable, Sendable, Equatable {
    public var vendor: VendorStorageKind
    public var entityID: String
    public var canonicalModel: String?
    public var managedDataAvailability: VendorManagedDataAvailability
    public var nativeCleanupAvailable: Bool
    public var recommendedRemediation: VendorManagedDataRemediationKind
    public var flowState: VendorRemediationFlowState
    public var requiresSoftwareInstall: Bool
    public var softwareInstallAuthorized: Bool
    public var cleanupRequiresNewPreflight: Bool
    public var cleanupRequiresSeparateApproval: Bool
    public var rawDeleteAllowed: Bool
    public var localFormatCompatibility: VendorLocalFormatCompatibility
    public var semanticOwnershipVerified: Bool
    public var remoteReacquisitionVerified: Bool
    public var installationSource: SoftwareInstallationSource
    public var explanation: String
    public var observedAt: Date

    public var readyForInstallAuthorization: Bool {
        managedDataAvailability == .vendorAbsentManagedDataRemains
            && recommendedRemediation == .reinstallVendorToRestoreNativeManagement
            && requiresSoftwareInstall
            && !softwareInstallAuthorized
            && semanticOwnershipVerified
            && !rawDeleteAllowed
    }
}

/// Separate from StorageAction ExecutionPermit. Install ≠ cleanup.
public struct SoftwareInstallationProposal: Codable, Sendable, Equatable {
    public var proposalID: String
    public var vendor: VendorStorageKind
    public var relatedEntityID: String
    public var installationSource: SoftwareInstallationSource
    public var purpose: String
    public var doesNotAuthorizeCleanup: Bool
    public var invalidatesPriorCleanupProofs: Bool
    public var createdAt: Date
    public var authorizedAt: Date?

    public static func proposeRestoreOllamaManagement(
        entityID: String,
        source: SoftwareInstallationSource = .unknown
    ) -> SoftwareInstallationProposal {
        SoftwareInstallationProposal(
            proposalID: "install-proposal-ollama-\(UUID().uuidString.prefix(8))",
            vendor: .ollama,
            relatedEntityID: entityID,
            installationSource: source,
            purpose: "Restore Ollama native management for existing managed model data. Does not remove any model.",
            doesNotAuthorizeCleanup: true,
            invalidatesPriorCleanupProofs: true,
            createdAt: Date(),
            authorizedAt: nil
        )
    }

    public static func proposeRestoreHuggingFaceCLI(
        entityID: String,
        source: SoftwareInstallationSource = .packageManager
    ) -> SoftwareInstallationProposal {
        SoftwareInstallationProposal(
            proposalID: "install-proposal-hf-cli-\(UUID().uuidString.prefix(8))",
            vendor: .huggingFace,
            relatedEntityID: entityID,
            installationSource: source,
            purpose: "Restore Hugging Face hf CLI for vendor-native cache management. Does not remove any cached revision.",
            doesNotAuthorizeCleanup: true,
            invalidatesPriorCleanupProofs: true,
            createdAt: Date(),
            authorizedAt: nil
        )
    }

    /// Approving install must never mint a cleanup ExecutionPermit.
    public func asCleanupPermitStub() -> ExecutionPermit? { nil }
}

/// Post-install invalidation of prior cleanup bindings.
public enum VendorReinstallInvalidation {
    public static let reason = "VENDOR_REINSTALL_INVALIDATES_PRIOR_CLEANUP_PROOF"

    /// After vendor reinstall, prior cleanup receipts/permits are never reusable.
    public static func priorCleanupPermitValidAfterReinstall() -> Bool { false }
}

/// Explicit post-install checklist before cleanup authorization may be requested.
public struct VendorPostInstallVerificationRequirements: Codable, Sendable, Equatable {
    public var ollamaAppOrCLIPresent: Bool
    public var cliContractProven: Bool
    public var supportsPS: Bool
    public var supportsRM: Bool
    public var exactModelRecognizedByInstalledInventory: Bool
    public var localManifestIdentityMatches: Bool
    public var referenceGraphVerified: Bool
    public var runtimeSnapshotComplete: Bool
    public var targetInactiveVerified: Bool
    public var remoteProofFresh: Bool
    public var scopedExecutorCapable: Bool

    public var allSatisfied: Bool {
        ollamaAppOrCLIPresent
            && cliContractProven
            && supportsPS
            && supportsRM
            && exactModelRecognizedByInstalledInventory
            && localManifestIdentityMatches
            && referenceGraphVerified
            && runtimeSnapshotComplete
            && targetInactiveVerified
            && remoteProofFresh
            && scopedExecutorCapable
    }

    public static let requiredLabels: [String] = [
        "ollama_app_or_cli_present",
        "cli_contract_proven",
        "supports_ps",
        "supports_rm",
        "exact_model_recognized",
        "local_manifest_identity_matches",
        "reference_graph_verified",
        "runtime_snapshot_complete",
        "target_inactive_verified",
        "remote_proof_fresh",
        "scoped_executor_capable",
    ]
}

public struct VendorRemediationPlanStep: Codable, Sendable, Equatable {
    public var order: Int
    public var stepID: String
    public var title: String
    public var readOnly: Bool
    public var requiresHumanAuthorization: Bool
    public var canMutateUserData: Bool
}
