import Foundation

/// P3.3C.2 — dual agent-cli store lifecycle & remediation proof (read-only).
/// Start state: UNRESOLVED_SECONDARY_AGENT_CLI_STORE.
/// Promote to LEGACY_STORE_VERIFIED only with evidence (never age/path alone).
/// potentialRecoveryBytes stays 0 without an aligned GS remediation contract.

public enum CursorAgentCLIStoreLifecycleState: String, Codable, Sendable, Equatable {
    case currentPrimaryStore = "CURRENT_PRIMARY_STORE"
    case currentSecondaryStore = "CURRENT_SECONDARY_STORE"
    case rollbackStore = "ROLLBACK_STORE"
    case fallbackStore = "FALLBACK_STORE"
    case migrationSource = "MIGRATION_SOURCE"
    case migrationDestination = "MIGRATION_DESTINATION"
    case migrationSourceRemains = "MIGRATION_SOURCE_REMAINS"
    case legacyStoreVerified = "LEGACY_STORE_VERIFIED"
    case unreferencedVerified = "UNREFERENCED_VERIFIED"
    case vendorAbsentManagedStore = "VENDOR_ABSENT_MANAGED_STORE"
    case staleInstallStore = "STALE_INSTALL_STORE"
    case unknownSecondaryStore = "UNKNOWN_SECONDARY_STORE"
    case unresolvedSecondaryAgentCLIStore = "UNRESOLVED_SECONDARY_AGENT_CLI_STORE"
}

public enum CursorAgentCLIVersionOverlapClass: String, Codable, Sendable, Equatable {
    case duplicatedVersion = "DUPLICATED_VERSION"
    case gsOnlyVersion = "GS_ONLY_VERSION"
    case homeOnlyVersion = "HOME_ONLY_VERSION"
    case sameLabelDifferentArtifact = "SAME_LABEL_DIFFERENT_ARTIFACT"
    case unknown = "UNKNOWN"
}

public enum CursorAgentCLIVersionReferenceState: String, Codable, Sendable, Equatable {
    case selected = "SELECTED"
    case active = "ACTIVE"
    case fallbackReferenced = "FALLBACK_REFERENCED"
    case migrationReferenced = "MIGRATION_REFERENCED"
    case unreferencedVerified = "UNREFERENCED_VERIFIED"
    case unknown = "UNKNOWN"
}

public enum VendorStoreRemediationKind: String, Codable, Sendable, Equatable {
    case none = "NONE"
    case nativeLegacyCleanup = "NATIVE_LEGACY_CLEANUP"
    case migrationFinalization = "MIGRATION_FINALIZATION"
    case storeReconciliation = "STORE_RECONCILIATION"
    case managerRestoration = "MANAGER_RESTORATION"
    case exactVersionEviction = "EXACT_VERSION_EVICTION"
    case atomicStaleStoreEviction = "ATOMIC_STALE_STORE_EVICTION"
    case unknown = "UNKNOWN"
}

public enum CursorAgentCLIFutureActionUnit: String, Codable, Sendable, Equatable {
    case exactVersion = "EXACT_VERSION"
    case staleVersionSet = "STALE_VERSION_SET"
    case legacyStore = "LEGACY_STORE"
    case migrationSourceSet = "MIGRATION_SOURCE_SET"
    case none = "NONE"
    case unknown = "UNKNOWN"
}

public struct CursorAgentCLIStore: Codable, Sendable, Equatable {
    public var storeID: String
    public var canonicalRoot: String
    public var storageClass: CursorAgentCLIStorageClass
    public var observedBytes: Int64
    public var uniqueBytes: Int64
    public var versionEntities: [String]
    public var selectedVersion: String?
    public var creationEvidence: String
    public var readEvidence: String
    public var writeEvidence: String
    public var launchEvidence: String
    public var cleanupEvidence: String
    public var migrationEvidence: String
    public var selectionState: String
    public var runtimeState: String
    public var lifecycleState: CursorAgentCLIStoreLifecycleState
    public var confidence: String
    public var owner: String
    public var managerClass: String
}

public struct VendorStoreRemediationContract: Codable, Sendable, Equatable {
    public var vendor: String
    public var sourceStore: String
    public var destinationStore: String?
    public var remediationKind: VendorStoreRemediationKind
    public var exactTargetSet: [String]
    public var targetUnit: CursorAgentCLIFutureActionUnit
    public var preconditions: [String]
    public var sourceRetentionSemantics: String
    public var destinationVerification: String
    public var rollbackSemantics: String
    public var blastRadius: String
    public var blastRadiusBound: Bool
    public var nativeOperation: String
    public var previewCapability: Bool
    public var postVerifyContract: String
    public var evidence: [String]
    public var confidence: String
    public var contractFound: Bool
    public var contractAligned: Bool
}

public enum CursorAgentCLIStoreLifecycle {
    /// Formal dual-store model for the live Mac layout (evidence-backed constants).
    public static let homeStoreID = "cursor.agent_cli.store.home"
    public static let gsStoreID = "cursor.agent_cli.store.gs_worker"

    public static func homeVersionsRoot(home: String) -> String {
        CursorAgentCLIPathResolver.homeVersionsRoot(home: home)
    }

    public static func gsVersionsRoot(home: String) -> String {
        CursorAgentCLIPathResolver.versionsRoot(home: home)
    }

    public static func resolveHomeSelectedVersion(home: String) -> String? {
        let bin = "\(home)/.local/bin/cursor-agent"
        return versionIDFromBin(bin)
    }

    public static func resolveGSSelectedVersion(home: String) -> String? {
        CursorAgentCLIPathResolver.resolveSelectedVersion(home: home)
    }

    private static func versionIDFromBin(_ bin: String) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: bin) || (try? fm.destinationOfSymbolicLink(atPath: bin)) != nil else {
            return nil
        }
        if let dest = try? fm.destinationOfSymbolicLink(atPath: bin) {
            let absolute: String
            if dest.hasPrefix("/") {
                absolute = dest
            } else {
                absolute = (URL(fileURLWithPath: bin).deletingLastPathComponent().path as NSString)
                    .appendingPathComponent(dest)
            }
            return CursorAgentCLIPathResolver.versionID(
                fromResolvedPath: (absolute as NSString).resolvingSymlinksInPath
            )
        }
        return CursorAgentCLIPathResolver.versionID(
            fromResolvedPath: (bin as NSString).resolvingSymlinksInPath
        )
    }

    /// Classify store lifecycle from evidence flags — never from path age alone.
    public static func classifyStore(
        hasCurrentSelector: Bool,
        hasRuntimeExecutable: Bool,
        hasFallbackReference: Bool?,
        migrationSourceProven: Bool,
        migrationDestProven: Bool,
        previousImplUsedThisStore: Bool,
        currentImplUsesOtherStoreOnly: Bool,
        currentImplStillReadsThisStore: Bool,
        vendorManagerAbsent: Bool,
        completionMarkersAbsent: Bool
    ) -> CursorAgentCLIStoreLifecycleState {
        if hasRuntimeExecutable || hasCurrentSelector {
            return hasCurrentSelector ? .currentPrimaryStore : .currentSecondaryStore
        }
        if hasFallbackReference == true {
            return .fallbackStore
        }
        if migrationSourceProven && currentImplUsesOtherStoreOnly && !currentImplStillReadsThisStore {
            return .migrationSourceRemains
        }
        if migrationDestProven {
            return .migrationDestination
        }
        if migrationSourceProven {
            return .migrationSource
        }
        if vendorManagerAbsent {
            return .vendorAbsentManagedStore
        }
        if completionMarkersAbsent && !hasCurrentSelector {
            return .staleInstallStore
        }
        if previousImplUsedThisStore
            && currentImplUsesOtherStoreOnly
            && !currentImplStillReadsThisStore
            && hasFallbackReference != true
            && !hasRuntimeExecutable
        {
            return .legacyStoreVerified
        }
        if !hasCurrentSelector
            && !hasRuntimeExecutable
            && hasFallbackReference == false
            && !currentImplStillReadsThisStore
            && !migrationSourceProven
        {
            return .unreferencedVerified
        }
        if !hasCurrentSelector && !hasRuntimeExecutable {
            return .unknownSecondaryStore
        }
        return .unresolvedSecondaryAgentCLIStore
    }

    /// Age / path naming alone never yields LEGACY_STORE_VERIFIED.
    public static func oldPathOrMtimeAloneIsNotLegacy() -> Bool { true }

    public static func classifyVersionOverlap(
        presentInHOME: Bool,
        presentInGS: Bool,
        artifactExactMatch: Bool?
    ) -> CursorAgentCLIVersionOverlapClass {
        switch (presentInHOME, presentInGS) {
        case (true, true):
            if artifactExactMatch == true { return .duplicatedVersion }
            if artifactExactMatch == false { return .sameLabelDifferentArtifact }
            return .unknown
        case (false, true):
            return .gsOnlyVersion
        case (true, false):
            return .homeOnlyVersion
        default:
            return .unknown
        }
    }

    public static func classifyVersionReference(
        selected: Bool,
        runtimeActive: Bool,
        fallbackReferenced: Bool?,
        migrationReferenced: Bool,
        implementationMayCacheRead: Bool,
        snapshotComplete: Bool
    ) -> CursorAgentCLIVersionReferenceState {
        if runtimeActive { return .active }
        if selected { return .selected }
        if fallbackReferenced == true { return .fallbackReferenced }
        if migrationReferenced { return .migrationReferenced }
        // Cache-capable manager can re-open any existing version dir → not UNREFERENCED.
        if implementationMayCacheRead { return .unknown }
        if snapshotComplete,
           fallbackReferenced == false,
           !selected,
           !runtimeActive,
           !migrationReferenced,
           !implementationMayCacheRead
        {
            return .unreferencedVerified
        }
        return .unknown
    }

    /// Duplication proves LOCAL_DUPLICATE only — never safe removal.
    public static func localDuplicateDoesNotAuthorizeRemoval() -> Bool { true }

    public static func potentialRecoveryBytes(
        remediationContractFound: Bool,
        contractAligned: Bool,
        exactTargetBytes: Int64
    ) -> Int64 {
        guard remediationContractFound, contractAligned else { return 0 }
        return exactTargetBytes
    }

    public static func unreferencedVerifiedBytes(
        versionRefs: [(bytes: Int64, state: CursorAgentCLIVersionReferenceState)]
    ) -> Int64 {
        versionRefs
            .filter { $0.state == .unreferencedVerified }
            .reduce(Int64(0)) { $0 + $1.bytes }
    }

    /// Built-in evidence for the known Cursor dual-manager architecture (fixture / live constants).
    public static func knownArchitectureEvidence() -> (
        home: CursorAgentCLIStore,
        gs: CursorAgentCLIStore,
        relationship: CleanupTargetRelationship,
        remediation: VendorStoreRemediationContract
    ) {
        let home = CursorAgentCLIStore(
            storeID: homeStoreID,
            canonicalRoot: "~/.local/share/cursor-agent/versions",
            storageClass: .installedVersions,
            observedBytes: 0,
            uniqueBytes: 0,
            versionEntities: [],
            selectedVersion: nil,
            creationEvidence: "install-core-posix / agent install → join(homedir(), .local/share/cursor-agent/versions)",
            readEvidence: "CLI bin ~/.local/bin/cursor-agent → versions/<id>",
            writeEvidence: "CLI install/update writes version dirs under HOME",
            launchEvidence: "Standalone cursor-agent / agent CLI launches from HOME selected bin",
            cleanupEvidence: "LIVE cleanup-install-versions → HOME versions only",
            migrationEvidence: "NONE found GS↔HOME",
            selectionState: "HOME_BIN_SYMLINK",
            runtimeState: "RUNTIME_OBSERVED_NONE_IN_BATCH",
            lifecycleState: .currentPrimaryStore,
            confidence: "VERIFIED_CALL_PATH",
            owner: "CURSOR_CLI_INSTALL_CORE",
            managerClass: "USER_HOME_AGENT_CLI"
        )
        let gs = CursorAgentCLIStore(
            storeID: gsStoreID,
            canonicalRoot: ".../globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions",
            storageClass: .installedVersions,
            observedBytes: 0,
            uniqueBytes: 0,
            versionEntities: [],
            selectedVersion: nil,
            creationEvidence: "cursor-agent-worker: join(globalStorageUri.fsPath, agent-cli, .local/share/cursor-agent/versions); mkdir + download/extract",
            readEvidence: "worker Using cached Cursor Agent <buildId> when version dir present",
            writeEvidence: "worker Downloading Cursor Agent <buildId> into GS versions",
            launchEvidence: "worker Installed CLI at …; spawn from GS agentPath/binDir",
            cleanupEvidence: "NONE — no prune/cleanup of GS versions in worker bundle",
            migrationEvidence: "NONE — no GS→HOME migrate/copy/rename call path",
            selectionState: "GS_BIN_SYMLINK + *.install prod:<version>",
            runtimeState: "RUNTIME_OBSERVED_NONE_IN_BATCH",
            lifecycleState: .currentPrimaryStore,
            confidence: "VERIFIED_CALL_PATH",
            owner: "CURSOR_AGENT_WORKER",
            managerClass: "GLOBALSTORAGE_WORKER_AGENT_CLI"
        )
        let remediation = VendorStoreRemediationContract(
            vendor: "CURSOR",
            sourceStore: gsStoreID,
            destinationStore: nil,
            remediationKind: .none,
            exactTargetSet: [],
            targetUnit: .none,
            preconditions: [
                "Would require vendor-native GS lifecycle operation",
                "HOME cleanup-install-versions MUST NOT be applied to GS"
            ],
            sourceRetentionSemantics: "Worker retains historical version dirs under GS; no eviction found",
            destinationVerification: "N/A",
            rollbackSemantics: "UNKNOWN — no GS rollback metadata graph found",
            blastRadius: "N/A — no remediation contract",
            blastRadiusBound: false,
            nativeOperation: "NONE_FOUND",
            previewCapability: false,
            postVerifyContract: "N/A",
            evidence: [
                "worker main.js: create/download/launch under globalStorage agent-cli",
                "worker: no versions prune/cleanup",
                "workbench: no agent-cli migrate/legacy path",
                "HOME cleanup contract remains SIBLING_STORE vs GS"
            ],
            confidence: "VERIFIED_ABSENCE_BOUNDED_SEARCH",
            contractFound: false,
            contractAligned: false
        )
        return (home, gs, .siblingStore, remediation)
    }

    public static func siblingHomeCleanupAgainstGSStillMismatched(
        homeVersions: String,
        gsVersions: String
    ) -> VendorCleanupAlignmentStatus {
        let rel = CursorAgentCLIPathAlignment.relationship(
            actualCanonical: gsVersions,
            cleanupCanonical: homeVersions
        )
        guard rel == .siblingStore else { return .verifyMore }
        return .storeMismatch
    }

    public static func planTierForGSWithoutRemediation(
        gsLifecycle: CursorAgentCLIStoreLifecycleState
    ) -> String {
        switch gsLifecycle {
        case .currentPrimaryStore, .currentSecondaryStore, .fallbackStore, .rollbackStore:
            return "KEEP"
        case .legacyStoreVerified, .migrationSourceRemains, .unreferencedVerified:
            return "VERIFY_MORE"
        default:
            return "VERIFY_MORE"
        }
    }
}
