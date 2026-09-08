import Foundation

/// P3.4A — preservation-first opportunity ranking (proof category, not permission).

public enum PreservationOpportunity: String, Codable, Sendable, Equatable {
    case none = "NONE"
    case remoteBackedLocalEvictionCandidate = "REMOTE_BACKED_LOCAL_EVICTION_CANDIDATE"
    case appNativeSyncOffloadCandidate = "APP_NATIVE_SYNC_OFFLOAD_CANDIDATE"
    case exportArchiveCandidate = "EXPORT_ARCHIVE_CANDIDATE"
    case moveToICloudCandidate = "MOVE_TO_ICLOUD_CANDIDATE"
    case vendorNativeRelocationCandidate = "VENDOR_NATIVE_RELOCATION_CANDIDATE"
    case unknown = "UNKNOWN"
}

public enum PreservationActionClass: String, Codable, Sendable, Equatable {
    case removeLocalDownload = "REMOVE_LOCAL_DOWNLOAD"
    case appNativeSyncOffload = "APP_NATIVE_SYNC_OFFLOAD"
    case exportArchive = "EXPORT_ARCHIVE"
    case vendorNativeRelocation = "VENDOR_NATIVE_RELOCATION"
    case none = "NONE"
    case unknown = "UNKNOWN"
}

public struct PreservationContract: Codable, Sendable, Equatable {
    public var vendor: String
    public var storageClass: String
    public var exactTarget: String
    public var preservationAction: PreservationActionClass
    public var remoteIdentity: String
    public var sourceOfTruthState: String
    public var localResidencyState: String
    public var cloudState: String
    public var deletionPropagationSemantics: String
    public var nativeOperation: String
    public var blastRadius: String
    public var postVerifyContract: String
    public var evidence: [String]
    public var confidence: String
    public var contractReady: Bool
    public var currentExecutable: Bool
    public var candidateBytes: Int64
}

public struct NextCenterpinScore: Codable, Sendable, Equatable {
    public var entityID: String
    public var uniqueBytes: Int64
    public var userValue: Double
    public var sourceOfTruthRisk: Double
    public var proofFeasibility: Double
    public var nativeContractAvailability: Double
    public var preservationPotential: Double
    public var expectedLocalRecovery: Double
    public var implementationEffort: Double
    public var runtimeRisk: Double
    public var score: Double
    public var preservationOpportunity: PreservationOpportunity
    public var currentActionabilityBytes: Int64
    public var reasoning: String
}

public enum PreservationFirstRanking {
    public static let completedVerifiedRecoveryBytes: Int64 = 5_580_814_899
    public static let twentyGBGoal: Int64 = 20_000_000_000

    public static var remainingTwentyGBGoal: Int64 {
        max(0, twentyGBGoal - completedVerifiedRecoveryBytes)
    }

    /// Score for NEXT PROOF WORK — does not authorize action / SafetyClass.
    public static func score(
        uniqueBytes: Int64,
        userValue: Double,
        sourceOfTruthRisk: Double,
        proofFeasibility: Double,
        nativeContractAvailability: Double,
        preservationPotential: Double,
        expectedLocalRecovery: Double,
        implementationEffort: Double,
        runtimeRisk: Double,
        closedProtectedInvestigation: Bool,
        currentActionabilityBytes: Int64
    ) -> Double {
        if closedProtectedInvestigation {
            // Size cannot reopen Cursor-class closed investigations.
            return 0
        }
        let gb = Double(uniqueBytes) / 1_000_000_000.0
        let sizeSignal = min(gb / 20.0, 1.0)
        let effortPenalty = implementationEffort
        let riskPenalty = runtimeRisk + sourceOfTruthRisk * 0.25
        let raw =
            sizeSignal * 0.15
            + userValue * 0.15
            + proofFeasibility * 0.20
            + nativeContractAvailability * 0.15
            + preservationPotential * 0.20
            + expectedLocalRecovery * 0.15
            - effortPenalty * 0.10
            - riskPenalty * 0.10
        // Actionability is informational; zero actionable does not zero proof score.
        _ = currentActionabilityBytes
        return max(0, raw)
    }

    public static func cursorClosureActionableBytes() -> Int64 { 0 }

    public static func genericICloudRelocationAllowed(
        forPathClass pathClass: String
    ) -> Bool {
        let blocked = [
            "Application Support",
            "Containers",
            "Group Containers",
            "Cursor",
            "Claude",
            "DerivedData",
            "Caches",
            "node_modules",
            "runtime_database",
            "VoiceMemos",
        ]
        return !blocked.contains(where: { pathClass.localizedCaseInsensitiveContains($0) })
    }

    public static func userOriginalBlocksDestructiveDeletion() -> Bool { true }
    public static func userOriginalDoesNotBlockPreservationAnalysis() -> Bool { true }

    public static func remoteVerifiedButDeletePropagatesBlocksEviction() -> Bool { true }

    public static func iCloudAccountAloneIsNotRemoteProof() -> Bool { true }

    public static func preservationIsNotDelete() -> Bool { true }

    public static func rawDeleteIsNotLocalOffloadFallback() -> Bool { true }
}

public enum CursorInvestigationClosure {
    public static let stateDBDecision = "KEEP"
    public static let agentCLIDecision = "KEEP"
    public static let backupDecision = "KEEP"
    public static let backupLifecycle = "CURRENT_RECOVERY_BACKUP"
    public static let actionableBytes: Int64 = 0
    public static let investigationClosed = true

    public static func backupKeepReason() -> String {
        "Cursor-generated recovery copy; backup()/restore path verified; not superseded; no aligned cleanup contract"
    }

    public static func agentCLIKeepReason() -> String {
        "CURRENT_PRIMARY for cursor-agent-worker; alternate route still uses GS store"
    }

    public static func stateDBKeepReason() -> String {
        "LIVE_USER_AGENT_STATE_DOMINANT; bubbleId/agentKv protected"
    }
}
