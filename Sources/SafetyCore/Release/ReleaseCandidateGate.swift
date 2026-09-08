import Foundation

/// Authoritative product identity for the current shipping line.
public enum ProductReleaseIdentity {
    public static let productName = "AI Storage Manager"
    public static let releaseVersion = "0.2.0"
    public static let buildNumber = "51"
    public static let bundleIdentifier = "com.tomystudio.aistoragemanager"
    public static let minimumMacOSVersion = "13.0"
    public static let supportedArchitectures: [String] = ["arm64"]
    public static let distributionModel = "DIRECT_MACOS_DISTRIBUTION"
    public static let researchStatus = "COMPLETE_FROZEN"
    public static let verifiedRecoveredBytesCanonical: Int64 = 5_580_814_899

    public static let existingExecutors: [String] = [
        "MOVE_TO_TRASH",
        "OLLAMA_MODEL_VENDOR_NATIVE_CLEANUP",
        "HF_SNAPSHOT_VENDOR_NATIVE_CLEANUP",
    ]

    public static var marketingVersionDisplay: String {
        "\(releaseVersion) (\(buildNumber))"
    }
}

public enum ReleaseGateDimensionStatus: String, Codable, Sendable, Equatable {
    case pass = "PASS"
    case blocked = "BLOCKED"
    case manualRequired = "MANUAL_REQUIRED"
    case notApplicable = "NOT_APPLICABLE"
}

public enum ReleaseCandidateOverallStatus: String, Codable, Sendable, Equatable {
    case rcPassExternalDistributionReady = "RC_PASS_EXTERNAL_DISTRIBUTION_READY"
    case rcPassLocalBetaReady = "RC_PASS_LOCAL_BETA_READY"
    case rcPassPendingNotarization = "RC_PASS_PENDING_NOTARIZATION"
    case rcBlocked = "RC_BLOCKED"
}

public struct ReleaseGateDimension: Codable, Sendable, Equatable {
    public var name: String
    public var status: ReleaseGateDimensionStatus
    public var note: String
}

public struct ReleaseCandidateGateInput: Codable, Sendable, Equatable {
    public var buildPass: Bool
    public var testsPass: Bool
    public var falseGreen: Int
    public var duplicateEvaluations: Int
    public var secondCrawlerAdded: Bool
    public var unknownAuthorizationCount: Int
    public var contractBypassCount: Int
    public var approvalBypassCount: Int
    public var unverifiedRecoveryPresentationCount: Int
    public var fakeRecoverableByteCount: Int
    public var mutationAutoRetryCount: Int
    public var privacyPass: Bool
    public var secretsShipped: Bool
    public var permissionsDegradeSafely: Bool
    public var performanceBlocker: Bool
    public var packagingPass: Bool
    public var signed: Bool
    public var notarized: Bool
    public var notarizationCredentialsAvailable: Bool
    public var gatekeeperReady: Bool
    public var firstLaunchPass: Bool
    public var cleanStatePass: Bool
    public var failureRecoveryPass: Bool
    public var actionFlowPass: Bool
    public var documentationPass: Bool
    public var researchFrozen: Bool
    public var realMutationPerformed: Bool
    public var newExecutorAdded: Bool

    public init(
        buildPass: Bool,
        testsPass: Bool,
        falseGreen: Int = 0,
        duplicateEvaluations: Int = 0,
        secondCrawlerAdded: Bool = false,
        unknownAuthorizationCount: Int = 0,
        contractBypassCount: Int = 0,
        approvalBypassCount: Int = 0,
        unverifiedRecoveryPresentationCount: Int = 0,
        fakeRecoverableByteCount: Int = 0,
        mutationAutoRetryCount: Int = 0,
        privacyPass: Bool = true,
        secretsShipped: Bool = false,
        permissionsDegradeSafely: Bool = true,
        performanceBlocker: Bool = false,
        packagingPass: Bool = true,
        signed: Bool = false,
        notarized: Bool = false,
        notarizationCredentialsAvailable: Bool = false,
        gatekeeperReady: Bool = false,
        firstLaunchPass: Bool = true,
        cleanStatePass: Bool = true,
        failureRecoveryPass: Bool = true,
        actionFlowPass: Bool = true,
        documentationPass: Bool = true,
        researchFrozen: Bool = true,
        realMutationPerformed: Bool = false,
        newExecutorAdded: Bool = false
    ) {
        self.buildPass = buildPass
        self.testsPass = testsPass
        self.falseGreen = falseGreen
        self.duplicateEvaluations = duplicateEvaluations
        self.secondCrawlerAdded = secondCrawlerAdded
        self.unknownAuthorizationCount = unknownAuthorizationCount
        self.contractBypassCount = contractBypassCount
        self.approvalBypassCount = approvalBypassCount
        self.unverifiedRecoveryPresentationCount = unverifiedRecoveryPresentationCount
        self.fakeRecoverableByteCount = fakeRecoverableByteCount
        self.mutationAutoRetryCount = mutationAutoRetryCount
        self.privacyPass = privacyPass
        self.secretsShipped = secretsShipped
        self.permissionsDegradeSafely = permissionsDegradeSafely
        self.performanceBlocker = performanceBlocker
        self.packagingPass = packagingPass
        self.signed = signed
        self.notarized = notarized
        self.notarizationCredentialsAvailable = notarizationCredentialsAvailable
        self.gatekeeperReady = gatekeeperReady
        self.firstLaunchPass = firstLaunchPass
        self.cleanStatePass = cleanStatePass
        self.failureRecoveryPass = failureRecoveryPass
        self.actionFlowPass = actionFlowPass
        self.documentationPass = documentationPass
        self.researchFrozen = researchFrozen
        self.realMutationPerformed = realMutationPerformed
        self.newExecutorAdded = newExecutorAdded
    }
}

public struct ReleaseCandidateGateResult: Codable, Sendable, Equatable {
    public var overallStatus: ReleaseCandidateOverallStatus
    public var dimensions: [ReleaseGateDimension]
    public var hardBlockers: [String]
    public var manualRequired: [String]
    public var nonBlockingLimitations: [String]
    public var liveMutationValidationRequired: Bool
    public var recommendedNextPhase: String
}

public enum ReleaseCandidateGate {
    public static let mutationAutoRetryAllowed = false
    public static let approvalSurvivesRestart = false
    public static let liveMutationRequiredByDefault = false

    public static func evaluate(_ input: ReleaseCandidateGateInput) -> ReleaseCandidateGateResult {
        var dimensions: [ReleaseGateDimension] = []
        var hard: [String] = []
        var manual: [String] = []
        var nonBlocking: [String] = []

        func dim(_ name: String, _ status: ReleaseGateDimensionStatus, _ note: String) {
            dimensions.append(ReleaseGateDimension(name: name, status: status, note: note))
            if status == .blocked { hard.append("\(name): \(note)") }
            if status == .manualRequired { manual.append("\(name): \(note)") }
        }

        dim("BUILD", input.buildPass ? .pass : .blocked, input.buildPass ? "Release build succeeded" : "Release build failed")
        dim("TESTS", input.testsPass && input.falseGreen == 0 && input.duplicateEvaluations == 0 && !input.secondCrawlerAdded ? .pass : .blocked,
            "failures/falseGreen/dup/secondCrawler checked")
        let safetyOK = input.unknownAuthorizationCount == 0
            && input.contractBypassCount == 0
            && input.approvalBypassCount == 0
            && input.unverifiedRecoveryPresentationCount == 0
            && input.fakeRecoverableByteCount == 0
            && input.mutationAutoRetryCount == 0
            && input.researchFrozen
            && !input.newExecutorAdded
        dim("SAFETY", safetyOK ? .pass : .blocked, safetyOK ? "Release Safety invariants hold" : "Safety counter non-zero or research unfrozen")
        dim("PRIVACY", input.privacyPass && !input.secretsShipped ? .pass : .blocked,
            input.secretsShipped ? "Secrets must not ship" : "Privacy audit")
        dim("PERMISSIONS", input.permissionsDegradeSafely ? .pass : .blocked, "Partial visibility must remain non-authorizing")
        dim("PERFORMANCE", input.performanceBlocker ? .blocked : .pass, input.performanceBlocker ? "Material regression" : "No material release blocker")
        dim("PACKAGING", input.packagingPass ? .pass : .blocked, "Release artifact packaging")
        if input.signed {
            dim("SIGNING", .pass, "Signed")
        } else if input.notarizationCredentialsAvailable {
            dim("SIGNING", .manualRequired, "Signing identity/credentials present but not applied")
        } else {
            dim("SIGNING", .manualRequired, "NOTARIZATION_CREDENTIALS_REQUIRED / no Developer ID identity on this Mac")
        }
        if input.notarized {
            dim("NOTARIZATION", .pass, "Notarized")
        } else if input.signed {
            dim("NOTARIZATION", .manualRequired, "Signed but not notarized")
        } else {
            dim("NOTARIZATION", .manualRequired, "NOTARIZATION_CREDENTIALS_REQUIRED")
        }
        dim("FIRST_LAUNCH", input.firstLaunchPass ? .pass : .blocked, "Clean first launch")
        dim("CLEAN_STATE", input.cleanStatePass ? .pass : .blocked, "Empty history / defaults")
        dim("FAILURE_RECOVERY", input.failureRecoveryPass ? .pass : .blocked, "Degraded states safe")
        dim("ACTION_FLOW", input.actionFlowPass ? .pass : .blocked, "Canonical mutation chain without live mutation")
        dim("DOCUMENTATION", input.documentationPass ? .pass : .blocked, "README/INSTALL/SAFETY/PRIVACY/LIMITATIONS/RELEASE_NOTES")

        nonBlocking.append(contentsOf: [
            "Vendor-specific UNKNOWN remains non-authorizing",
            "Voice Memos native local-only eviction unavailable",
            "Many large entities remain KEEP / actionable=0",
            "arm64-only build on this development Mac",
            "Interactive release-mode performance timings partially fixture-bounded",
        ])

        let liveMutationRequired = false // historical Ollama/HF + unchanged executor semantics

        if !hard.isEmpty {
            return ReleaseCandidateGateResult(
                overallStatus: .rcBlocked,
                dimensions: dimensions,
                hardBlockers: hard,
                manualRequired: manual,
                nonBlockingLimitations: nonBlocking,
                liveMutationValidationRequired: liveMutationRequired,
                recommendedNextPhase: "P5.1_FIX_HIGHEST_RELEASE_BLOCKER"
            )
        }

        if input.gatekeeperReady && input.notarized && input.signed {
            return ReleaseCandidateGateResult(
                overallStatus: .rcPassExternalDistributionReady,
                dimensions: dimensions,
                hardBlockers: [],
                manualRequired: manual,
                nonBlockingLimitations: nonBlocking,
                liveMutationValidationRequired: liveMutationRequired,
                recommendedNextPhase: "P5.1_RELEASE_FREEZE_AND_V0_1"
            )
        }

        if input.signed && !input.notarized {
            return ReleaseCandidateGateResult(
                overallStatus: .rcPassPendingNotarization,
                dimensions: dimensions,
                hardBlockers: [],
                manualRequired: manual,
                nonBlockingLimitations: nonBlocking,
                liveMutationValidationRequired: liveMutationRequired,
                recommendedNextPhase: "P5.1_SIGN_NOTARIZE_PACKAGE"
            )
        }

        return ReleaseCandidateGateResult(
            overallStatus: .rcPassLocalBetaReady,
            dimensions: dimensions,
            hardBlockers: [],
            manualRequired: manual,
            nonBlockingLimitations: nonBlocking,
            liveMutationValidationRequired: liveMutationRequired,
            recommendedNextPhase: "P5.1_SIGN_NOTARIZE_PACKAGE"
        )
    }
}
