import Foundation

public enum HuggingFaceNativeInterfaceStatus: String, Codable, Sendable, Equatable {
    case resolvedCLI = "RESOLVED_CLI"
    case unresolved = "UNRESOLVED"
    case contractIncomplete = "CONTRACT_INCOMPLETE"
    case unknown = "UNKNOWN"
}

/// Deterministic HF `hf` CLI resolution result. No PATH shell search in production.
public struct HuggingFaceNativeInterfaceResolution: Codable, Sendable, Equatable {
    public var status: HuggingFaceNativeInterfaceStatus
    public var cliResolved: Bool
    public var cliExecutableURL: String?
    public var cliVersion: String?
    public var supportsCacheLS: Bool
    public var supportsCacheVerify: Bool
    public var supportsCacheRM: Bool
    public var supportsDryRun: Bool
    public var supportsCacheDir: Bool
    public var supportsYes: Bool
    public var binaryFingerprint: String?
    public var resolutionMethod: String
    public var resolvedAt: Date
    public var failureReason: String?
    public var evidence: [String]

    public var executionTransportAvailable: Bool {
        cliResolved && supportsCacheRM && supportsDryRun && supportsCacheDir
    }
}

public enum HuggingFaceNativeCleanupPhase: String, Codable, Sendable, Equatable, CaseIterable {
    case notStarted = "NOT_STARTED"
    case preflight = "PREFLIGHT"
    case dryRunPreview = "DRY_RUN_PREVIEW"
    case approvalRequired = "APPROVAL_REQUIRED"
    case ready = "READY"
    case invokingNativeRm = "INVOKING_NATIVE_RM"
    case verifyingRevisionAbsent = "VERIFYING_REVISION_ABSENT"
    case measuringStorage = "MEASURING_STORAGE"
    case postVerify = "POST_VERIFY"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
    case unknown = "UNKNOWN"
}

/// Vendor dry-run consequence proof — part of approval binding.
public struct HuggingFaceCacheRemovalPreview: Codable, Sendable, Equatable {
    public var repoID: String
    public var repoType: String
    public var revision: String
    public var cacheRoot: String
    public var revisionFound: Bool
    public var revisionCountBefore: Int
    public var targetedRevisionCount: Int
    public var targetedSnapshotPaths: [String]
    public var refEffects: [String]
    public var exclusiveBlobCount: Int
    public var sharedBlobCount: Int
    public var expectedFreedBytesVendor: Int64?
    public var expectedRepoDirectoryRemoval: Bool
    public var warnings: [String]
    public var previewComplete: Bool
    public var rawOutputDigest: String
    public var observedAt: Date
    public var dryRunMutationDetected: Bool
    public var durationMs: Int

    public var consequenceFingerprint: String {
        ActionBindingFingerprintBuilder.stablePublicHash([
            repoID,
            revision,
            cacheRoot,
            "found=\(revisionFound)",
            "targeted=\(targetedRevisionCount)",
            "revCount=\(revisionCountBefore)",
            "repoRemoval=\(expectedRepoDirectoryRemoval)",
            "exclusive=\(exclusiveBlobCount)",
            "shared=\(sharedBlobCount)",
            "freed=\(expectedFreedBytesVendor.map(String.init) ?? "nil")",
            "complete=\(previewComplete)",
        ].joined(separator: "#"))
    }
}

public enum HuggingFaceRevisionIdentity {
    /// Full immutable commit hash (40 hex) preferred.
    public static func isValidFullRevision(_ revision: String) -> Bool {
        guard revision.count == 40 else { return false }
        return revision.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }

    public static func validateOrThrow(_ revision: String) throws {
        guard isValidFullRevision(revision) else {
            throw ActionExecutionError.invalidModelIdentity(revision)
        }
        if revision.hasPrefix("-") {
            throw ActionExecutionError.invalidModelIdentity(revision)
        }
        let forbidden = CharacterSet(charactersIn: ";|&`$()<>*?!\\\n\r\0 ")
        if revision.unicodeScalars.contains(where: { forbidden.contains($0) }) {
            throw ActionExecutionError.invalidModelIdentity(revision)
        }
    }

    public static func rmArguments(
        revision: String,
        cacheRoot: String,
        dryRun: Bool,
        yes: Bool
    ) throws -> [String] {
        try validateOrThrow(revision)
        let root = (cacheRoot as NSString).standardizingPath
        guard !root.isEmpty, root.hasPrefix("/") else {
            throw ActionExecutionError.invalidModelIdentity("cacheRoot")
        }
        var args = ["cache", "rm", revision]
        if dryRun { args.append("--dry-run") }
        if yes, !dryRun { args.append("--yes") }
        args.append(contentsOf: ["--cache-dir", root])
        return args
    }
}
