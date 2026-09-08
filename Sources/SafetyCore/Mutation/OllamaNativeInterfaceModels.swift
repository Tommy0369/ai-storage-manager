import Foundation

public enum OllamaNativeInterfaceKind: String, Codable, Sendable, Equatable {
    case cli = "CLI"
    case localAPI = "LOCAL_API"
    case guiOnly = "GUI_ONLY"
    case none = "NONE"
    case unknown = "UNKNOWN"
}

public enum OllamaInstallReality: String, Codable, Sendable, Equatable {
    case cliNotInstalled = "CLI_NOT_INSTALLED"
    case cliInstalledNonstandardLocation = "CLI_INSTALLED_NONSTANDARD_LOCATION"
    case ollamaAppWithEmbeddedCLI = "OLLAMA_APP_INSTALLED_WITH_EMBEDDED_CLI"
    case guiAppOnly = "GUI_APP_ONLY"
    case runningProcessExposesExecutable = "RUNNING_PROCESS_EXPOSES_EXECUTABLE_PATH"
    case localAPIAvailableWithoutCLI = "LOCAL_API_AVAILABLE_WITHOUT_CLI"
    case staleModelDataWithNoInstall = "STALE_MODEL_DATA_WITH_NO_OLLAMA_INSTALL"
    case other = "OTHER"
}

public enum OllamaNativeInterfaceStatus: String, Codable, Sendable, Equatable {
    case resolvedCLI = "RESOLVED_CLI"
    case resolvedLocalAPIOnly = "RESOLVED_LOCAL_API_ONLY"
    case guiOnly = "GUI_ONLY"
    case unresolved = "UNRESOLVED"
    case unknown = "UNKNOWN"
}

/// Exact discovered Ollama native interface. Read-only evidence only.
public struct OllamaNativeInterfaceResolution: Codable, Sendable, Equatable {
    public var interfaceKind: OllamaNativeInterfaceKind
    public var status: OllamaNativeInterfaceStatus
    public var installReality: OllamaInstallReality
    public var ollamaAppFound: Bool
    public var bundleIdentifier: String?
    public var bundleVersion: String?
    public var bundleLocationClass: String?
    public var cliResolved: Bool
    public var cliExecutableURL: String?
    public var cliExecutableLocationClass: String?
    public var cliVersion: String?
    public var supportsPS: Bool
    public var supportsRM: Bool
    public var guiExecutableRejectedAsCLI: Bool
    public var localAPIReachable: Bool
    public var localAPIIdentityVerified: Bool
    public var localAPIVersion: String?
    public var resolutionMethod: String
    public var resolutionEvidence: [String]
    public var resolutionDurationMs: Int
    public var binaryFingerprint: String?
    public var observedAt: Date

    public var executionTransportAvailable: Bool {
        cliResolved && supportsRM
    }
}

public struct OllamaExactRuntimeProof: Codable, Sendable, Equatable {
    public var targetEntityID: String
    public var targetModel: String
    public var observationSource: String
    public var snapshotCompleteness: ObservationCompleteness
    public var runningModelCount: Int
    public var runningModelIdentities: [String]
    public var targetStatus: ObservedActiveState
    public var targetConfidence: EvidenceConfidence
    public var observedAt: Date
    public var freshUntil: Date
    public var failureReason: String?
    public var serviceRunning: Bool
    public var serviceRunningUsedAsTargetProof: Bool

    public var isStrictInactive: Bool {
        snapshotCompleteness == .complete
            && targetStatus == .inactive
            && targetConfidence == .verified
    }

    public var isStrictActive: Bool {
        snapshotCompleteness == .complete
            && targetStatus == .active
            && targetConfidence == .verified
    }
}

public enum OllamaModelIdentityNormalization {
    /// Exact known equivalents only. No fuzzy matching.
    public static func equivalents(of canonical: String) -> Set<String> {
        var out: Set<String> = [canonical]
        let lower = canonical.lowercased()
        out.insert(lower)
        if lower.hasPrefix("library/") {
            out.insert(String(lower.dropFirst("library/".count)))
        } else if !lower.contains("/") {
            out.insert("library/\(lower)")
        }
        return out
    }

    public static func matches(_ observed: String, canonical: String) -> Bool {
        let o = observed.lowercased()
        let cSet = equivalents(of: canonical)
        if cSet.contains(o) { return true }
        // Digest-qualified: name:tag@sha256:... — compare prefix before @
        if let at = o.firstIndex(of: "@") {
            let base = String(o[..<at])
            if cSet.contains(base) { return true }
        }
        return false
    }
}
