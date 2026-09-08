import Foundation
import SafetyCore

public struct P32A2VendorAbsentDataReport: Codable, Sendable {
    public var vendor: String
    public var entity: String
    public var canonicalModel: String
    public var observedBytes: Int64
    public var uniqueBytes: Int64?
    public var sharedBytes: Int64?
    public var vendorApplicationPresent: Bool
    public var nativeInterfacePresent: Bool
    public var semanticOwnershipStatus: String
    public var remoteReacquisitionStatus: String
    public var localFormatCompatibility: String
    public var managedDataAvailabilityState: String
    public var recommendedRemediation: String
    public var rawDeleteAllowed: Bool
    public var cleanupCurrentlyExecutable: Bool
    public var softwareInstallRequired: Bool
    public var cleanupRequiresSeparateApproval: Bool
    public var readyForOllamaInstallAuthorization: Bool
    public var generatedAt: Date
}

public struct P32A2RemediationPlanReport: Codable, Sendable {
    public var vendor: String
    public var entityID: String
    public var steps: [VendorRemediationPlanStep]
    public var installDoesNotAuthorizeCleanup: Bool
    public var postInstallRequiredChecks: [String]
    public var generatedAt: Date
}

public enum P32A2ReportBuilder {
    public static func vendorAbsent(
        remediation: VendorManagedDataRemediation,
        observedBytes: Int64,
        uniqueBytes: Int64?,
        sharedBytes: Int64?,
        remoteStatus: String
    ) -> P32A2VendorAbsentDataReport {
        P32A2VendorAbsentDataReport(
            vendor: remediation.vendor.rawValue,
            entity: remediation.entityID,
            canonicalModel: remediation.canonicalModel ?? "",
            observedBytes: observedBytes,
            uniqueBytes: uniqueBytes,
            sharedBytes: sharedBytes,
            vendorApplicationPresent: {
                switch remediation.managedDataAvailability {
                case .vendorPresentNativeInterfaceAvailable, .vendorPresentNativeInterfaceUnavailable:
                    return true
                case .vendorAbsentManagedDataRemains, .vendorInstallStateUnknown, .notApplicable:
                    return false
                }
            }(),
            nativeInterfacePresent: remediation.nativeCleanupAvailable,
            semanticOwnershipStatus: remediation.semanticOwnershipVerified ? "VERIFIED" : "NOT_VERIFIED",
            remoteReacquisitionStatus: remoteStatus,
            localFormatCompatibility: remediation.localFormatCompatibility.rawValue,
            managedDataAvailabilityState: remediation.managedDataAvailability.rawValue,
            recommendedRemediation: remediation.recommendedRemediation.rawValue,
            rawDeleteAllowed: remediation.rawDeleteAllowed,
            cleanupCurrentlyExecutable: remediation.nativeCleanupAvailable,
            softwareInstallRequired: remediation.requiresSoftwareInstall,
            cleanupRequiresSeparateApproval: remediation.cleanupRequiresSeparateApproval,
            readyForOllamaInstallAuthorization: remediation.readyForInstallAuthorization,
            generatedAt: remediation.observedAt
        )
    }

    public static func remediationPlan(
        entityID: String,
        vendor: VendorStorageKind = .ollama
    ) -> P32A2RemediationPlanReport {
        P32A2RemediationPlanReport(
            vendor: vendor.rawValue,
            entityID: entityID,
            steps: VendorAbsentManagedDataAnalyzer.remediationPlanSteps(),
            installDoesNotAuthorizeCleanup: true,
            postInstallRequiredChecks: VendorPostInstallVerificationRequirements.requiredLabels,
            generatedAt: Date()
        )
    }
}
