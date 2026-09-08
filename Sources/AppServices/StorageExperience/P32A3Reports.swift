import Foundation
import SafetyCore

public struct P32A3InstallReport: Codable, Sendable {
    public var authorizationPresent: Bool
    public var authorizationScope: String
    public var installAttempted: Bool
    public var installMethod: String
    public var sourceClass: String
    public var sourceVerified: Bool
    public var artifactIdentity: String?
    public var installedVersion: String?
    public var bundleIdentifier: String?
    public var installSucceeded: Bool
    public var managementServiceStarted: Bool
    public var modelRunPerformed: Bool
    public var modelPullPerformed: Bool
    public var cleanupPerformed: Bool
    public var preInstallModelDataPresent: Bool
    public var postInstallModelDataPresent: Bool
    public var unexpectedDataMutation: Bool
    public var failureReason: String?
    public var generatedAt: Date
}

public struct P32A3NativeInterfaceReport: Codable, Sendable {
    public var appFound: Bool
    public var cliResolved: Bool
    public var cliVersion: String?
    public var supportsPS: Bool
    public var supportsRM: Bool
    public var localAPIReachable: Bool
    public var interfaceKind: String
    public var binaryFingerprint: String?
    public var resolutionMethod: String
    public var bundleIdentifier: String?
    public var status: String
}

public struct P32A3ModelRecognitionReport: Codable, Sendable {
    public var targetModel: String
    public var recognizedByVendorInventory: Bool
    public var canonicalIdentity: String?
    public var manifestStatus: String
    public var referenceGraphStatus: String
    public var logicalBytes: Int64?
    public var uniqueBytes: Int64?
    public var sharedBytes: Int64?
    public var modelRecognitionStatus: String
    public var inventoryModels: [String]
}

public struct P32A3RuntimeProofReport: Codable, Sendable {
    public var target: String
    public var source: String
    public var snapshotCompleteness: String
    public var runningModels: [String]
    public var targetRuntimeState: String
    public var observedAt: Date?
    public var freshUntil: Date?
}

public struct P32A3CleanupPreflightReport: Codable, Sendable {
    public var targetEntity: String
    public var targetModel: String
    public var nativeInterface: String
    public var supportsRM: Bool
    public var modelRecognized: Bool
    public var manifestStatus: String
    public var referenceGraphStatus: String
    public var runtimeStatus: String
    public var runtimeFresh: Bool?
    public var remoteReacquisition: String
    public var remoteProofFresh: Bool?
    public var cleanupCapability: String
    public var preflightStatus: String
    public var remainingBlockers: [String]
    public var humanModelRemovalAuthorizationRequired: Bool
    public var modelRemovalApprovalCreated: Bool
    public var cleanupExecutionPermitCreated: Bool
    public var modelRemovalExecuted: Bool
    public var phaseOutcome: String
}

public struct P32A3PlanAfterRestoreReport: Codable, Sendable {
    public var goal20GB: Int64
    public var readyNow: Int64
    public var approvalRequired: Int64
    public var verifiedFuture: Int64
    public var requiresVendorRestoration: Int64
    public var verifyMore: Int64
    public var protectedBytes: Int64
    public var ollamaCurrentTier: String
    public var ollamaPotentialBytes: Int64
    public var hfCurrentTier: String
}

public enum P32A3ReportBuilder {
    public static func install(
        authorization: SoftwareInstallationAuthorization?,
        attempted: Bool,
        restore: VendorManagementRestoreResult,
        preInstallPresent: Bool,
        postInstallPresent: Bool
    ) -> P32A3InstallReport {
        P32A3InstallReport(
            authorizationPresent: authorization != nil,
            authorizationScope: authorization?.scope.rawValue
                ?? SoftwareInstallationAuthorizationScope.ollamaSoftwareReinstallationOnly.rawValue,
            installAttempted: attempted,
            installMethod: restore.installMethod.rawValue,
            sourceClass: restore.sourceClass.rawValue,
            sourceVerified: restore.sourceVerified,
            artifactIdentity: restore.artifactIdentity,
            installedVersion: restore.installedVersion,
            bundleIdentifier: restore.bundleIdentifier,
            installSucceeded: restore.installationSucceeded,
            managementServiceStarted: restore.startedManagementService,
            modelRunPerformed: restore.modelRunPerformed,
            modelPullPerformed: restore.modelPullPerformed,
            cleanupPerformed: restore.cleanupPerformed,
            preInstallModelDataPresent: preInstallPresent,
            postInstallModelDataPresent: postInstallPresent,
            unexpectedDataMutation: restore.unexpectedDataMutation,
            failureReason: restore.failureReason,
            generatedAt: restore.completedAt
        )
    }

    public static func nativeInterface(_ iface: OllamaNativeInterfaceResolution) -> P32A3NativeInterfaceReport {
        P32A3NativeInterfaceReport(
            appFound: iface.ollamaAppFound,
            cliResolved: iface.cliResolved,
            cliVersion: iface.cliVersion,
            supportsPS: iface.supportsPS,
            supportsRM: iface.supportsRM,
            localAPIReachable: iface.localAPIReachable,
            interfaceKind: iface.interfaceKind.rawValue,
            binaryFingerprint: iface.binaryFingerprint,
            resolutionMethod: iface.resolutionMethod,
            bundleIdentifier: iface.bundleIdentifier,
            status: iface.status.rawValue
        )
    }

    public static func modelRecognition(
        target: String,
        status: InstalledModelRecognitionStatus,
        inventory: OllamaInstalledModelInventory.Snapshot?,
        manifestStatus: String,
        referenceGraphStatus: String,
        logicalBytes: Int64?,
        uniqueBytes: Int64?,
        sharedBytes: Int64?
    ) -> P32A3ModelRecognitionReport {
        P32A3ModelRecognitionReport(
            targetModel: target,
            recognizedByVendorInventory: status == .recognizedExact,
            canonicalIdentity: status == .recognizedExact ? target : nil,
            manifestStatus: manifestStatus,
            referenceGraphStatus: referenceGraphStatus,
            logicalBytes: logicalBytes,
            uniqueBytes: uniqueBytes,
            sharedBytes: sharedBytes,
            modelRecognitionStatus: status.rawValue,
            inventoryModels: inventory?.models ?? []
        )
    }

    public static func runtime(_ proof: OllamaExactRuntimeProof?) -> P32A3RuntimeProofReport {
        P32A3RuntimeProofReport(
            target: proof?.targetModel ?? "",
            source: proof?.observationSource ?? "NONE",
            snapshotCompleteness: proof?.snapshotCompleteness.rawValue ?? "UNKNOWN",
            runningModels: proof?.runningModelIdentities ?? [],
            targetRuntimeState: proof.map {
                "\($0.targetStatus.rawValue)/\($0.targetConfidence.rawValue)"
            } ?? "UNKNOWN",
            observedAt: proof?.observedAt,
            freshUntil: proof?.freshUntil
        )
    }

    public static func cleanupPreflight(
        entityID: String,
        model: String,
        reverify: OllamaPostInstallReverification.Result,
        manifestStatus: String,
        referenceGraphStatus: String,
        remoteStatus: String,
        remoteFresh: Bool?,
        cleanupCapability: String
    ) -> P32A3CleanupPreflightReport {
        let pf = reverify.preflight
        let readiness = pf?.freshGateResult.readiness
            ?? reverify.outcome.rawValue
        let humanRequired = reverify.outcome == .readyForModelRemovalAuthorization
            || reverify.outcome == .approvalRequired
        let runtimeFresh = reverify.runtimeProof.map { Date() < $0.freshUntil }
        return P32A3CleanupPreflightReport(
            targetEntity: entityID,
            targetModel: model,
            nativeInterface: reverify.interface?.status.rawValue ?? "UNRESOLVED",
            supportsRM: reverify.interface?.supportsRM ?? false,
            modelRecognized: reverify.recognitionStatus == .recognizedExact,
            manifestStatus: manifestStatus,
            referenceGraphStatus: referenceGraphStatus,
            runtimeStatus: reverify.runtimeProof.map {
                "\($0.targetStatus.rawValue)/\($0.targetConfidence.rawValue)"
            } ?? "UNKNOWN",
            runtimeFresh: runtimeFresh,
            remoteReacquisition: remoteStatus,
            remoteProofFresh: remoteFresh,
            cleanupCapability: cleanupCapability,
            preflightStatus: readiness,
            remainingBlockers: reverify.remainingBlockers,
            humanModelRemovalAuthorizationRequired: humanRequired,
            modelRemovalApprovalCreated: reverify.modelRemovalApprovalCreated,
            cleanupExecutionPermitCreated: reverify.cleanupExecutionPermitCreated,
            modelRemovalExecuted: reverify.ollamaRmExecuted,
            phaseOutcome: reverify.outcome.rawValue
        )
    }

    public static func planAfterRestore(
        plan: OptimizationPlan?,
        ollamaTier: String,
        ollamaBytes: Int64,
        hfTier: String
    ) -> P32A3PlanAfterRestoreReport {
        func sum(_ tier: OptimizationEligibilityTier) -> Int64 {
            plan?.entries
                .filter { $0.candidate.tier == tier }
                .map(\.candidate.potentialRecoveryBytes)
                .reduce(0, +) ?? 0
        }
        return P32A3PlanAfterRestoreReport(
            goal20GB: 20_000_000_000,
            readyNow: plan?.availableNowPotentialBytes ?? 0,
            approvalRequired: sum(.approvalRequired),
            verifiedFuture: plan?.verifiedFuturePotentialBytes ?? 0,
            requiresVendorRestoration: plan?.requiresVendorRestorationPotentialBytes ?? 0,
            verifyMore: sum(.verifyMore),
            protectedBytes: sum(.protectedTier),
            ollamaCurrentTier: ollamaTier,
            ollamaPotentialBytes: ollamaBytes,
            hfCurrentTier: hfTier
        )
    }
}
