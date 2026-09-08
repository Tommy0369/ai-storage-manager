import Foundation

/// P3.3C — Cursor agent-cli version retention & native cleanup proof (read-only).
/// No version deletion, no update, no ExecutionPermit.

public enum CursorAgentCLIVersionState: String, Codable, Sendable, Equatable {
    case currentActive = "CURRENT_ACTIVE"
    case currentInactive = "CURRENT_INACTIVE"
    case rollbackRequired = "ROLLBACK_REQUIRED"
    case fallbackCandidate = "FALLBACK_CANDIDATE"
    case inactiveVerified = "INACTIVE_VERIFIED"
    case inactiveButReacquisitionUnknown = "INACTIVE_BUT_REACQUISITION_UNKNOWN"
    case staleInstallIncomplete = "STALE_INSTALL_INCOMPLETE"
    case unreferencedVerified = "UNREFERENCED_VERIFIED"
    case unknown = "UNKNOWN"
}

public struct CursorAgentCLIVersionOpportunity: Codable, Sendable, Equatable {
    public var versionEntityID: String
    public var version: String
    public var uniqueBytes: Int64
    public var selectionState: String
    public var runtimeState: String
    public var reacquisitionState: String
    public var vendorRetentionState: String
    public var nativeCleanupState: String
    public var userOriginalState: String
    public var requiredMissingProof: [String]
    public var potentialRecoveryBytes: Int64
    public var currentExecutable: Bool

    public init(
        versionEntityID: String,
        version: String,
        uniqueBytes: Int64,
        selectionState: String,
        runtimeState: String,
        reacquisitionState: String,
        vendorRetentionState: String,
        nativeCleanupState: String,
        userOriginalState: String,
        requiredMissingProof: [String],
        potentialRecoveryBytes: Int64,
        currentExecutable: Bool = false
    ) {
        self.versionEntityID = versionEntityID
        self.version = version
        self.uniqueBytes = uniqueBytes
        self.selectionState = selectionState
        self.runtimeState = runtimeState
        self.reacquisitionState = reacquisitionState
        self.vendorRetentionState = vendorRetentionState
        self.nativeCleanupState = nativeCleanupState
        self.userOriginalState = userOriginalState
        self.requiredMissingProof = requiredMissingProof
        self.potentialRecoveryBytes = potentialRecoveryBytes
        self.currentExecutable = currentExecutable
    }
}

/// Vendor retention decoded from agent-cli `cleanupOldInstallVersions` (install-core-posix).
/// Keeps: currentVersion + up to 2 newest other non-active directories (+ in-use markers).
public enum CursorAgentCLIVendorRetentionPolicy {
    public static let keepAdditionalNonCurrentVersions = 2
    public static let hiddenCommand = "cleanup-install-versions"
    public static let commandDescription = "Remove stale Cursor Agent install versions"
    /// Hardcoded by cleanupInstalledAgentVersions → ~/.local/share/cursor-agent/versions
    public static let defaultVersionsDirClass = "HOME/.local/share/cursor-agent/versions"
    /// Worker installs into globalStorage/.../agent-cli/.local/share/cursor-agent/versions
    public static let workerVersionsDirClass =
        "globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions"

    /// Apply vendor keep rule to a sorted-by-mtime-desc list of non-current version IDs.
    public static func versionsEligibleForCleanup(
        nonCurrentNewestFirst: [String],
        protectedFallbackCount: Int = keepAdditionalNonCurrentVersions
    ) -> [String] {
        guard nonCurrentNewestFirst.count > protectedFallbackCount else { return [] }
        return Array(nonCurrentNewestFirst.dropFirst(protectedFallbackCount))
    }

    public static func estimateRecoverableBytes(
        versions: [(id: String, bytes: Int64)],
        currentID: String?
    ) -> (protectedBytes: Int64, candidateBytes: Int64, keptNonCurrent: [String], candidates: [String]) {
        let currentBytes = versions.first(where: { $0.id == currentID })?.bytes ?? 0
        let nonCurrent = versions
            .filter { $0.id != currentID }
            .sorted { $0.id > $1.id } // version IDs are date-prefixed; lexical ≈ newest first
        let kept = Array(nonCurrent.prefix(keepAdditionalNonCurrentVersions))
        let cand = Array(nonCurrent.dropFirst(keepAdditionalNonCurrentVersions))
        let keptBytes = kept.reduce(Int64(0)) { $0 + $1.bytes }
        let candBytes = cand.reduce(Int64(0)) { $0 + $1.bytes }
        return (
            protectedBytes: currentBytes + keptBytes,
            candidateBytes: candBytes,
            keptNonCurrent: kept.map(\.id),
            candidates: cand.map(\.id)
        )
    }
}

public enum CursorAgentCLIPathResolver {
    public static func workerRoot(home: String) -> String {
        "\(home)/Library/Application Support/Cursor/User/globalStorage/anysphere.cursor-agent-worker"
    }

    public static func agentCLIRoot(home: String) -> String {
        workerRoot(home: home) + "/agent-cli"
    }

    public static func versionsRoot(home: String) -> String {
        agentCLIRoot(home: home) + "/.local/share/cursor-agent/versions"
    }

    public static func selectionBin(home: String) -> String {
        agentCLIRoot(home: home) + "/.local/bin/cursor-agent"
    }

    public static func homeVersionsRoot(home: String) -> String {
        "\(home)/.local/share/cursor-agent/versions"
    }

    public static func resolveSelectedVersion(home: String) -> String? {
        let bin = selectionBin(home: home)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: bin),
              attrs[.type] as? FileAttributeType == .typeSymbolicLink,
              let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: bin)
        else {
            // try resolving even if not reported as symlink
            let resolved = (bin as NSString).resolvingSymlinksInPath
            return versionID(fromResolvedPath: resolved)
        }
        let absolute: String
        if dest.hasPrefix("/") {
            absolute = dest
        } else {
            absolute = (URL(fileURLWithPath: bin).deletingLastPathComponent().path as NSString)
                .appendingPathComponent(dest)
        }
        let resolved = (absolute as NSString).resolvingSymlinksInPath
        return versionID(fromResolvedPath: resolved)
    }

    public static func versionID(fromResolvedPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let idx = parts.firstIndex(of: "versions"), idx + 1 < parts.count else { return nil }
        return parts[idx + 1]
    }
}

public enum CursorAgentCLISafetyRules {
    public static func rootExecutable() -> Bool { false }

    public static func versionExecutable(
        isCurrent: Bool,
        isActive: Bool,
        nativeCleanupContractApplies: Bool
    ) -> Bool {
        // P3.3C never makes versions executable.
        _ = isCurrent; _ = isActive; _ = nativeCleanupContractApplies
        return false
    }

    public static func isNativeCleanupCandidate(
        isCurrent: Bool,
        isActive: Bool,
        isRequiredFallback: Bool,
        vendorToolchainVerified: Bool,
        userOriginalFalseVerified: Bool,
        nativeCleanupContractFound: Bool,
        blastRadiusKnown: Bool,
        reacquisitionKnown: Bool
    ) -> Bool {
        guard !isCurrent, !isActive, !isRequiredFallback else { return false }
        guard vendorToolchainVerified, userOriginalFalseVerified else { return false }
        guard nativeCleanupContractFound, blastRadiusKnown else { return false }
        // Reacquisition need not be TRUE; must be "sufficiently known" (including UNKNOWN documented).
        _ = reacquisitionKnown
        return true
    }

    public static func oldMtimeDoesNotPromoteSafety() -> Bool { true }

    public static func softwareUpdateDoesNotProveOldArtifactReacquire() -> Bool { true }
}
