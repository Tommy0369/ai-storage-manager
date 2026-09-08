import Foundation

/// P3.3C.1 — cleanup contract path alignment (read-only).
/// Principle: cleanup capability exists ≠ this exact store is covered.

public enum CleanupTargetRelationship: String, Codable, Sendable, Equatable {
    case exactRootMatch = "EXACT_ROOT_MATCH"
    case targetIsParent = "TARGET_IS_PARENT"
    case targetIsChild = "TARGET_IS_CHILD"
    case siblingStore = "SIBLING_STORE"
    case legacyRoot = "LEGACY_ROOT"
    case stagingRoot = "STAGING_ROOT"
    case downloadCacheRoot = "DOWNLOAD_CACHE_ROOT"
    case migrationSourceRoot = "MIGRATION_SOURCE_ROOT"
    case migrationDestinationRoot = "MIGRATION_DESTINATION_ROOT"
    case unrelated = "UNRELATED"
    case unknown = "UNKNOWN"
}

public enum CursorAgentCLIStorageClass: String, Codable, Sendable, Equatable {
    case installedVersions = "INSTALLED_VERSIONS"
    case downloadCache = "DOWNLOAD_CACHE"
    case staging = "STAGING"
    case rollback = "ROLLBACK"
    case temp = "TEMP"
    case legacyInstall = "LEGACY_INSTALL"
    case unknown = "UNKNOWN"
}

public enum CleanupContractCoverage: String, Codable, Sendable, Equatable {
    case covered = "COVERED"
    case notCovered = "NOT_COVERED"
    case unknown = "UNKNOWN"
}

public struct CursorAgentCLICleanupContract: Codable, Sendable, Equatable {
    public var contractID: String
    public var sourceLocation: String
    public var confidence: String
    public var trigger: String
    public var commandID: String
    public var functionNameClass: String
    public var targetRootExpression: String
    public var targetRootResolved: String
    public var targetSelectionSemantics: String
    public var versionSelectorSemantics: String
    public var currentVersionProtection: Bool
    public var fallbackProtection: Bool
    public var blastRadius: String
    public var runtimeRequirements: String
    public var dryRunAvailable: Bool
    public var executionMechanism: String
    public var targetStorageClass: CursorAgentCLIStorageClass
    public var reachability: String

    public static let knownHomeInstallContract = CursorAgentCLICleanupContract(
        contractID: "cursor.agent_cli.cleanup_install_versions.home",
        sourceLocation: "agent-cli install-core-posix.ts (bundled chunk)",
        confidence: "VERIFIED_CALL_PATH",
        trigger: "after successful installCursorAgent / agent update (detached spawn); manual hidden CLI",
        commandID: "cleanup-install-versions",
        functionNameClass: "cleanupInstalledAgentVersions → cleanupOldInstallVersions",
        targetRootExpression: "join(homedir(), \".local\", \"share\", \"cursor-agent\", \"versions\")",
        targetRootResolved: "", // filled at runtime
        targetSelectionSemantics: "readdir versionsDir; skip currentVersion, 'dev', dotdirs, active-bin realpaths",
        versionSelectorSemantics: "sort remaining by mtime desc; keep first 2; rm rest unless in-use marker",
        currentVersionProtection: true,
        fallbackProtection: true,
        blastRadius: "HOME versions directories only (recursive rm of selected version dirs)",
        runtimeRequirements: "CLI binary available; versionsDir exists; no dry-run flag",
        dryRunAvailable: false,
        executionMechanism: "hidden CLI command; also spawned detached after install",
        targetStorageClass: .installedVersions,
        reachability: "LIVE — command registered; help reachable; post-install spawn present"
    )
}

public struct CursorAgentCLIRetentionContract: Codable, Sendable, Equatable {
    public var currentProtected: Bool
    public var previousProtected: Bool
    public var retainedVersionCount: String
    public var ageRule: String?
    public var sizeRule: String?
    public var cleanupTrigger: String
    public var cleanupTargetRoot: String
    public var cleanupTargetVersionPredicate: String
    public var rollbackSemantics: String
    public var evidence: [String]
}

public struct VendorCleanupContract: Codable, Sendable, Equatable {
    public var vendor: String
    public var storageClass: String
    public var actionClass: String
    public var canonicalTargetRoot: String
    public var targetSelector: String
    public var exclusions: [String]
    public var previewCapability: Bool
    public var runtimeRequirements: String
    public var postVerifyContract: String
    public var confidence: String
}

public enum CursorAgentCLIPathAlignment {
    public static func canonicalize(_ path: String) -> String {
        (path as NSString).standardizingPath
            .replacingOccurrences(of: "//", with: "/")
    }

    public static func resolveSymlinks(_ path: String) -> String {
        (path as NSString).resolvingSymlinksInPath
    }

    /// Classify relationship between actual installed store and cleanup resolved target.
    public static func relationship(
        actualCanonical: String,
        cleanupCanonical: String
    ) -> CleanupTargetRelationship {
        let a = resolveSymlinks(canonicalize(actualCanonical))
        let c = resolveSymlinks(canonicalize(cleanupCanonical))
        if a == c { return .exactRootMatch }
        if a.hasPrefix(c + "/") { return .targetIsParent }
        if c.hasPrefix(a + "/") { return .targetIsChild }
        // Sibling: same leaf name pattern under different parents
        let aLeaf = (a as NSString).lastPathComponent
        let cLeaf = (c as NSString).lastPathComponent
        if aLeaf == cLeaf && aLeaf == "versions" {
            let aParent = (a as NSString).deletingLastPathComponent
            let cParent = (c as NSString).deletingLastPathComponent
            if aParent != cParent { return .siblingStore }
        }
        return .unrelated
    }

    public static func cleanupCoversActualStore(
        relationship: CleanupTargetRelationship,
        semanticClassMatch: Bool
    ) -> Bool {
        relationship == .exactRootMatch && semanticClassMatch
    }

    /// Coverage for a version living in the ACTUAL (GS) store given HOME-targeted cleanup.
    public static func coverageForActualStoreVersion(
        relationship: CleanupTargetRelationship,
        isCurrent: Bool,
        isFallbackWindow: Bool
    ) -> CleanupContractCoverage {
        // HOME cleanup does not cover GS versions at all when sibling/unrelated.
        switch relationship {
        case .exactRootMatch:
            if isCurrent || isFallbackWindow { return .notCovered } // protected, not removable
            return .covered
        case .siblingStore, .unrelated, .legacyRoot, .stagingRoot, .downloadCacheRoot,
             .migrationSourceRoot, .migrationDestinationRoot, .targetIsParent, .targetIsChild:
            return .notCovered
        case .unknown:
            return .unknown
        }
    }

    public static func potentialRecoveryBytes(
        versions: [(id: String, bytes: Int64, coverage: CleanupContractCoverage)],
        onlyCoveredInactive: Bool = true
    ) -> Int64 {
        versions
            .filter { onlyCoveredInactive ? $0.coverage == .covered : true }
            .reduce(Int64(0)) { $0 + $1.bytes }
    }
}
