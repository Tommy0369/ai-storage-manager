import Foundation

/// Install transport for Hugging Face `hf` CLI. Standalone pipe is always policy-rejected.
public enum HFCLIInstallMethod: String, Codable, Sendable, Equatable {
    case homebrew = "HOMEBREW"
    case uvTool = "UV_TOOL"
    case dedicatedPythonEnv = "DEDICATED_PYTHON_ENV"
    case standalonePipeInstaller = "STANDALONE_PIPE_INSTALLER"
    case unresolved = "UNRESOLVED"
}

public enum HFCLIPresenceClass: String, Codable, Sendable, Equatable {
    case trustedCLIPresent = "TRUSTED_CLI_PRESENT"
    case installedButNotResolvable = "CLI_INSTALLED_BUT_NOT_RESOLVABLE"
    case notInstalled = "HF_CLI_NOT_INSTALLED"
    case unknown = "UNKNOWN"
}

public enum HFCLISourceTrustStatus: String, Codable, Sendable, Equatable {
    case officialVerified = "OFFICIAL_VERIFIED"
    case policyRejected = "POLICY_REJECTED"
    case unresolved = "UNRESOLVED"
}

/// Read-only Mac environment for HF CLI resolution / install planning.
public struct HFCLIEnvironmentSnapshot: Codable, Sendable, Equatable {
    public var brewPresent: Bool
    public var brewExecutableURL: String?
    public var brewPrefix: String?
    public var brewVersion: String?
    public var hostArchitecture: CPUArchitectureClass
    public var brewArchitecture: CPUArchitectureClass?
    public var brewArchitectureMatchesHost: Bool
    public var brewSelectionReason: String?
    public var brewMultipleInstallations: Bool
    public var brewAlternateInstallations: [String]
    public var homebrewResolution: HomebrewInstallationResolution?
    public var hfBrewFormulaRecognized: Bool
    public var hfBrewFormulaVersion: String?
    public var hfBrewFormulaInstalled: Bool
    public var hfBrewExecutablePresent: Bool
    public var hfBrewExecutableURL: String?
    public var brewDeclaredDependencies: [String]
    public var uvPresent: Bool
    public var uvExecutableURL: String?
    public var uvVersion: String?
    public var existingUVHFTool: Bool
    public var uvHFExecutableURL: String?
    public var pipxPresent: Bool
    public var existingPipxHF: Bool
    public var pythonRuntimesInspected: [String]
    public var huggingfaceHubPackagesFound: [String]
    public var existingHFEntryPoints: [String]
    public var trustedHFCLIAlreadyPresent: Bool
    public var presenceClass: HFCLIPresenceClass
    public var evidence: [String]
    public var observedAt: Date
    public var brewMetadataMs: Int
    public var uvMetadataMs: Int
    public var pythonMetadataMs: Int
    public var totalResolutionMs: Int
}

/// Exact install plan. Approving it does NOT authorize HF cache removal.
public struct HFCLIInstallationProposal: Codable, Sendable, Equatable {
    public var product: String
    public var purpose: String
    public var installationRequired: Bool
    public var selectedMethod: HFCLIInstallMethod
    public var packageManager: String?
    public var packageIdentity: String
    public var desiredVersionPolicy: String
    public var sourceTrust: HFCLISourceTrustStatus
    public var executableExpectedAt: String?
    public var brewExecutableBound: String?
    public var brewPrefixBound: String?
    public var brewArchitectureBound: CPUArchitectureClass?
    public var hostArchitectureBound: CPUArchitectureClass?
    public var architectureMatch: Bool?
    public var mutationsExpected: [String]
    public var unrelatedDependencyChanges: [String]
    public var expectedDependencyChanges: [String]
    public var credentialChangesExpected: Bool
    public var hfSkillsInstallExpected: Bool
    public var rollbackMethod: String
    public var policyRejectedMethods: [String]
    public var requiresHumanAuthorization: Bool
    public var doesNotAuthorizeCacheCleanup: Bool
    public var doesNotAuthorizeHubRemoteDeletion: Bool
    public var recoveryBytesFromInstall: Int64
    public var selectionReason: String
    public var readyForInstallAuthorization: Bool
    public var verdict: String
    public var relatedEntityID: String?
    public var createdAt: Date

    public var asCleanupPermitStub: ExecutionPermit? { nil }
    public var asCleanupApprovalStub: UserActionApproval? { nil }
}

public enum HFCLIInstallUXCopy {
    public static let title = "Restore Hugging Face Cache Management"
    public static let why = """
    3.08 GB of verified Hugging Face cache cannot be safely previewed because the official HF CLI is not installed.
    """
    public static let does = "Installs the Hugging Face `hf` command-line tool."
    public static let doesNot = """
    Does not remove the cached model revision. Does not delete anything from Hugging Face Hub. Does not delete local cache files yet.
    """
    public static let after = """
    AI Storage Manager will run a read-only vendor dry-run and ask separately before any local cache removal.
    """
}
