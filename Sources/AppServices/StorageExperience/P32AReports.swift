import Foundation
import SafetyCore

/// P3.2A report payloads (no credentials, no mutation).
public struct P32AExecutorContractReport: Codable, Sendable {
    public var executorImplemented: Bool
    public var supportedVendor: String
    public var supportedEntityType: String
    public var supportedAction: String
    public var commandContract: String
    public var shellUsed: Bool
    public var rawDeleteFallback: Bool
    public var permitRequired: Bool
    public var approvalRequired: Bool
    public var freshPreflightRequired: Bool
    public var runtimePredicate: String
    public var remoteFreshnessRequired: Bool
    public var referenceGraphRequired: Bool
    public var postVerifyRequired: Bool
    public var HFSupported: Bool
    public var rawBlobSupported: Bool
}

public struct P32ARealPreflightReport: Codable, Sendable {
    public var entityID: String
    public var modelIdentity: String
    public var localManifestFingerprint: String?
    public var observedBytes: Int64
    public var uniqueBytes: Int64?
    public var sharedBytes: Int64?
    public var referenceGraphStatus: String
    public var runtimeStatus: String
    public var runtimeProofFresh: Bool?
    public var remoteReacquisitionStatus: String
    public var remoteProofFreshUntil: Date?
    public var remoteProofFresh: Bool?
    public var executorCapability: String
    public var executionCapability: String?
    public var supportsRM: Bool?
    public var preflightStatus: String
    public var remainingBlockers: [String]
    public var humanAuthorizationRequired: Bool
    public var realApprovalCreated: Bool
    public var ExecutionPermitCreated: Bool
    public var realMutationExecuted: Bool
    public var exactCandidateReadyForHumanAuthorization: Bool
    public var firstMapMs: Int?
    public var ollamaPsCompleteness: String?
    public var nativeInterfaceStatus: String?
    public var executableResolved: Bool?
    public var remoteProofStatus: String?
    public var localManifestStatus: String?
    public var note: String
}

public struct P32A1NativeInterfaceReport: Codable, Sendable {
    public var generatedAt: Date
    public var ollamaAppFound: Bool
    public var bundleIdentifier: String?
    public var bundleVersion: String?
    public var bundleLocationClass: String?
    public var interfaceKind: String
    public var installReality: String
    public var cliResolved: Bool
    public var cliExecutableLocationClass: String?
    public var cliVersion: String?
    public var binaryFingerprint: String?
    public var supportsPS: Bool
    public var supportsRM: Bool
    public var guiExecutableRejectedAsCLI: Bool
    public var localAPIReachable: Bool
    public var localAPIIdentityVerified: Bool
    public var resolutionMethod: String
    public var resolutionDurationMs: Int
    public var resolutionEvidence: [String]
    public var failureReason: String?
}

public struct P32A1RuntimeProofReport: Codable, Sendable {
    public var targetEntity: String
    public var targetModel: String
    public var observationSource: String
    public var snapshotCompleteness: String
    public var runningModelCount: Int
    public var targetStatus: String
    public var observedAt: Date
    public var freshUntil: Date
    public var failureReason: String?
    public var serviceRunning: Bool
    public var serviceRunningUsedAsTargetProof: Bool
}

public struct P32A1PerformanceReport: Codable, Sendable {
    public var timeToFirstUsefulMapMs: Int?
    public var nativeInterfaceResolutionMs: Int?
    public var runtimeObservationMs: Int?
    public var referenceGraphRefreshMs: Int?
    public var remoteRefreshMs: Int?
    public var freshPreflightMs: Int?
    public var networkOnFirstMapPath: Bool
    public var nativeDiscoveryOnFirstMapPath: Bool
    public var runtimeObservationOnFirstMapPath: Bool
}

public struct P32APlanBeforeAfter: Codable, Sendable {
    public var beforeReadyNow: Int64
    public var beforeVerifiedFuture: Int64
    public var beforeVerifyMore: Int64
    public var beforeOllamaCapability: String
    public var afterReadyNow: Int64
    public var afterApprovalRequired: Int64
    public var afterVerifiedFuture: Int64
    public var afterVerifyMore: Int64
    public var afterProtected: Int64?
    public var afterOllamaCapability: String
    public var ollamaExecutionCapability: String?
    public var ollamaRuntimeStatus: String?
    public var ollamaPreflightStatus: String?
    public var ollamaReadinessTier: String
    public var ollamaPotentialBytes: Int64
    public var ollamaRemainingBlockers: [String]
    public var hfVerifiedFutureBytes: Int64?
    public var hfRemainsNonExecutable: Bool
    public var hfExecutable: Bool
    public var goal20GBStatus: String?
}

public enum P32AReportBuilder {
    public static func nativeInterface(_ iface: OllamaNativeInterfaceResolution) -> P32A1NativeInterfaceReport {
        let failure: String?
        if iface.cliResolved {
            failure = nil
        } else if iface.installReality == .staleModelDataWithNoInstall {
            failure = "STALE_MODEL_DATA_ONLY"
        } else if !iface.ollamaAppFound && !iface.localAPIReachable {
            failure = "NO_CURRENT_OLLAMA_INSTALL"
        } else {
            failure = iface.status.rawValue
        }
        return P32A1NativeInterfaceReport(
            generatedAt: iface.observedAt,
            ollamaAppFound: iface.ollamaAppFound,
            bundleIdentifier: iface.bundleIdentifier,
            bundleVersion: iface.bundleVersion,
            bundleLocationClass: iface.bundleLocationClass,
            interfaceKind: iface.interfaceKind.rawValue,
            installReality: iface.installReality.rawValue,
            cliResolved: iface.cliResolved,
            cliExecutableLocationClass: iface.cliExecutableLocationClass,
            cliVersion: iface.cliVersion,
            binaryFingerprint: iface.binaryFingerprint,
            supportsPS: iface.supportsPS,
            supportsRM: iface.supportsRM,
            guiExecutableRejectedAsCLI: iface.guiExecutableRejectedAsCLI,
            localAPIReachable: iface.localAPIReachable,
            localAPIIdentityVerified: iface.localAPIIdentityVerified,
            resolutionMethod: iface.resolutionMethod,
            resolutionDurationMs: iface.resolutionDurationMs,
            resolutionEvidence: iface.resolutionEvidence,
            failureReason: failure
        )
    }

    public static func runtimeProof(
        _ proof: OllamaExactRuntimeProof,
        fallbackEntityID: String
    ) -> P32A1RuntimeProofReport {
        P32A1RuntimeProofReport(
            targetEntity: proof.targetEntityID.isEmpty ? fallbackEntityID : proof.targetEntityID,
            targetModel: proof.targetModel,
            observationSource: proof.observationSource,
            snapshotCompleteness: proof.snapshotCompleteness.rawValue,
            runningModelCount: proof.runningModelCount,
            targetStatus: "\(proof.targetStatus.rawValue)/\(proof.targetConfidence.rawValue)",
            observedAt: proof.observedAt,
            freshUntil: proof.freshUntil,
            failureReason: proof.failureReason,
            serviceRunning: proof.serviceRunning,
            serviceRunningUsedAsTargetProof: proof.serviceRunningUsedAsTargetProof
        )
    }

    public static func performance(
        timeToFirstUsefulMapMs: Int?,
        nativeInterfaceResolutionMs: Int?,
        runtimeObservationMs: Int?,
        referenceGraphRefreshMs: Int?,
        remoteRefreshMs: Int?,
        freshPreflightMs: Int?
    ) -> P32A1PerformanceReport {
        P32A1PerformanceReport(
            timeToFirstUsefulMapMs: timeToFirstUsefulMapMs,
            nativeInterfaceResolutionMs: nativeInterfaceResolutionMs,
            runtimeObservationMs: runtimeObservationMs,
            referenceGraphRefreshMs: referenceGraphRefreshMs,
            remoteRefreshMs: remoteRefreshMs,
            freshPreflightMs: freshPreflightMs,
            networkOnFirstMapPath: false,
            nativeDiscoveryOnFirstMapPath: false,
            runtimeObservationOnFirstMapPath: false
        )
    }

    public static func contractReport() -> P32AExecutorContractReport {
        P32AExecutorContractReport(
            executorImplemented: true,
            supportedVendor: "OLLAMA",
            supportedEntityType: "MODEL",
            supportedAction: StorageAction.vendorNativeCleanup.rawValue,
            commandContract: "argv: <resolved-ollama-bin> rm <canonical-model>",
            shellUsed: false,
            rawDeleteFallback: false,
            permitRequired: true,
            approvalRequired: true,
            freshPreflightRequired: true,
            runtimePredicate: "exact_model_INACTIVE_VERIFIED via bounded ollama ps",
            remoteFreshnessRequired: true,
            referenceGraphRequired: true,
            postVerifyRequired: true,
            HFSupported: false,
            rawBlobSupported: false
        )
    }

    public static func realPreflight(
        entityID: String,
        modelIdentity: String,
        localManifestFingerprint: String?,
        observedBytes: Int64,
        uniqueBytes: Int64?,
        sharedBytes: Int64?,
        referenceGraphStatus: String,
        runtimeStatus: String,
        remoteReacquisitionStatus: String,
        remoteProofFreshUntil: Date?,
        remoteProofFresh: Bool?,
        executorCapability: String,
        preflightStatus: String,
        remainingBlockers: [String],
        humanAuthorizationRequired: Bool,
        exactCandidateReadyForHumanAuthorization: Bool,
        firstMapMs: Int?,
        ollamaPsCompleteness: String?,
        nativeInterfaceStatus: String? = nil,
        executableResolved: Bool? = nil,
        remoteProofStatus: String? = nil,
        localManifestStatus: String? = nil,
        supportsRM: Bool? = nil,
        runtimeProofFresh: Bool? = nil
    ) -> P32ARealPreflightReport {
        P32ARealPreflightReport(
            entityID: entityID,
            modelIdentity: modelIdentity,
            localManifestFingerprint: localManifestFingerprint,
            observedBytes: observedBytes,
            uniqueBytes: uniqueBytes,
            sharedBytes: sharedBytes,
            referenceGraphStatus: referenceGraphStatus,
            runtimeStatus: runtimeStatus,
            runtimeProofFresh: runtimeProofFresh,
            remoteReacquisitionStatus: remoteReacquisitionStatus,
            remoteProofFreshUntil: remoteProofFreshUntil,
            remoteProofFresh: remoteProofFresh,
            executorCapability: executorCapability,
            executionCapability: executorCapability,
            supportsRM: supportsRM,
            preflightStatus: preflightStatus,
            remainingBlockers: remainingBlockers,
            humanAuthorizationRequired: humanAuthorizationRequired,
            realApprovalCreated: false,
            ExecutionPermitCreated: false,
            realMutationExecuted: false,
            exactCandidateReadyForHumanAuthorization: exactCandidateReadyForHumanAuthorization,
            firstMapMs: firstMapMs,
            ollamaPsCompleteness: ollamaPsCompleteness,
            nativeInterfaceStatus: nativeInterfaceStatus,
            executableResolved: executableResolved,
            remoteProofStatus: remoteProofStatus,
            localManifestStatus: localManifestStatus,
            note: "P3.2A.1 read-only. No ollama rm / API DELETE / real mutation. No real approval/permit."
        )
    }

    public static func planBeforeAfter(
        afterReadyNow: Int64,
        afterVerifiedFuture: Int64,
        afterVerifyMore: Int64,
        ollamaReadinessTier: String,
        ollamaPotentialBytes: Int64,
        ollamaRemainingBlockers: [String],
        ollamaExecutionCapability: String = "IMPLEMENTED",
        ollamaRuntimeStatus: String? = nil,
        ollamaPreflightStatus: String? = nil,
        goal20GBStatus: String? = nil,
        afterApprovalRequired: Int64 = 0,
        afterProtected: Int64? = nil,
        hfVerifiedFutureBytes: Int64? = nil
    ) -> P32APlanBeforeAfter {
        P32APlanBeforeAfter(
            beforeReadyNow: 0,
            beforeVerifiedFuture: 5_684_664_883,
            beforeVerifyMore: 0,
            beforeOllamaCapability: "NOT_IMPLEMENTED",
            afterReadyNow: afterReadyNow,
            afterApprovalRequired: afterApprovalRequired,
            afterVerifiedFuture: afterVerifiedFuture,
            afterVerifyMore: afterVerifyMore,
            afterProtected: afterProtected,
            afterOllamaCapability: ollamaExecutionCapability,
            ollamaExecutionCapability: ollamaExecutionCapability,
            ollamaRuntimeStatus: ollamaRuntimeStatus,
            ollamaPreflightStatus: ollamaPreflightStatus,
            ollamaReadinessTier: ollamaReadinessTier,
            ollamaPotentialBytes: ollamaPotentialBytes,
            ollamaRemainingBlockers: ollamaRemainingBlockers,
            hfVerifiedFutureBytes: hfVerifiedFutureBytes,
            hfRemainsNonExecutable: true,
            hfExecutable: false,
            goal20GBStatus: goal20GBStatus
        )
    }
}
