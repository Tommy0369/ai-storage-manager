import Foundation

/// Builds an exact HF CLI install proposal. Never installs. Never authorizes cleanup.
public enum HuggingFaceCLIInstallationPlanner {
    public static let product = "HUGGING_FACE_CLI"
    public static let purpose = "RESTORE_VENDOR_NATIVE_CACHE_MANAGEMENT"

    public static func plan(
        environment: HFCLIEnvironmentSnapshot,
        relatedEntityID: String? = "ai.hf.snapshot.mlx-community.whisper-large-v3-mlx.49e6aa286ad6",
        now: Date = Date()
    ) -> HFCLIInstallationProposal {
        let rejected = [
            "STANDALONE_PIPE_INSTALLER(curl|bash)",
            "STANDALONE_PIPE_INSTALLER(curl|sh)",
            "TRANSIENT_UVX_AS_LONG_TERM_EXECUTOR",
            "ARBITRARY_GITHUB_RELEASE_BINARY",
            "UNVERIFIED_TAP_OR_MIRROR",
        ]

        // Path A: already present — no install.
        if environment.trustedHFCLIAlreadyPresent,
           environment.presenceClass == .trustedCLIPresent {
            return make(
                environment: environment,
                installationRequired: false,
                selectedMethod: .unresolved,
                packageManager: nil,
                packageIdentity: "existing-trusted-hf",
                desiredVersionPolicy: "EXISTING_CONTRACT_PROVEN",
                sourceTrust: .officialVerified,
                executableExpectedAt: environment.hfBrewExecutableURL
                    ?? environment.uvHFExecutableURL
                    ?? environment.existingHFEntryPoints.first,
                mutationsExpected: [],
                unrelatedDependencyChanges: [],
                expectedDependencyChanges: [],
                rollbackMethod: "N/A_ALREADY_PRESENT",
                rejected: rejected,
                requiresHumanAuthorization: false,
                selectionReason: "Trusted HF CLI already present — fix/use resolver; do not install.",
                readyForInstallAuthorization: false,
                verdict: "CLI_ALREADY_PRESENT_UNRESOLVED_OR_RESOLVED",
                relatedEntityID: relatedEntityID,
                now: now
            )
        }

        if environment.presenceClass == .installedButNotResolvable {
            return make(
                environment: environment,
                installationRequired: false,
                selectedMethod: .unresolved,
                packageManager: environment.brewPresent ? "homebrew" : nil,
                packageIdentity: "hf",
                desiredVersionPolicy: "EXISTING_FORMULA_LINK_SEPARATE_MUTATION",
                sourceTrust: .officialVerified,
                executableExpectedAt: environment.hfBrewExecutableURL
                    ?? environment.brewPrefix.map { HomebrewArchitectureResolver.expectedHFExecutable(prefix: $0) },
                mutationsExpected: ["possible future brew link (separate authorization)"],
                unrelatedDependencyChanges: [],
                expectedDependencyChanges: [],
                rollbackMethod: "brew uninstall hf (if applicable)",
                rejected: rejected,
                requiresHumanAuthorization: true,
                selectionReason: "Formula/tool installed but executable not resolvable. Linking is a separate system mutation — not auto-performed.",
                readyForInstallAuthorization: false,
                verdict: "CLI_INSTALLED_BUT_NOT_RESOLVABLE",
                relatedEntityID: relatedEntityID,
                now: now
            )
        }

        // Path B: Homebrew preferred — only when host-native brew is selected.
        let brewOK = environment.brewPresent
            && environment.hfBrewFormulaRecognized
            && !environment.hfBrewFormulaInstalled
            && environment.brewExecutableURL != nil
            && environment.brewArchitectureMatchesHost
            && (environment.brewPrefix != nil)

        if brewOK {
            let prefix = environment.brewPrefix!
            let expected = HomebrewArchitectureResolver.expectedHFExecutable(prefix: prefix)
            let version = environment.hfBrewFormulaVersion ?? "stable"
            return make(
                environment: environment,
                installationRequired: true,
                selectedMethod: .homebrew,
                packageManager: "homebrew",
                packageIdentity: "hf",
                desiredVersionPolicy: "homebrew-stable (\(version)) — must support hf cache ls/verify/rm --dry-run --cache-dir",
                sourceTrust: .officialVerified,
                executableExpectedAt: expected,
                mutationsExpected: [
                    "brew install hf via exact brew executable \(environment.brewExecutableURL ?? "")",
                    "new \(expected) executable",
                    "Homebrew Cellar package files for formula hf",
                    "possible dependency installs if missing: \(environment.brewDeclaredDependencies.joined(separator: ", "))",
                ],
                unrelatedDependencyChanges: environment.brewDeclaredDependencies.map { "may install/upgrade \($0) if not satisfied" },
                expectedDependencyChanges: environment.brewDeclaredDependencies,
                rollbackMethod: "brew uninstall hf",
                rejected: rejected,
                requiresHumanAuthorization: true,
                selectionReason: "Host-native Homebrew selected; official core formula `hf` recognized; deterministic prefix binary; PATH order did not decide.",
                readyForInstallAuthorization: true,
                verdict: "READY_FOR_HF_CLI_INSTALL_AUTHORIZATION",
                relatedEntityID: relatedEntityID,
                now: now
            )
        }

        // Brew present but architecture mismatch — do not prefer foreign brew as native install.
        if environment.brewPresent,
           environment.hfBrewFormulaRecognized,
           !environment.hfBrewFormulaInstalled,
           !environment.brewArchitectureMatchesHost {
            // Fall through to UV / python / unresolved — record mismatch in reason if no fallback.
            if environment.uvPresent, !environment.existingUVHFTool {
                // continue to Path C below
            } else if !environment.pythonRuntimesInspected.isEmpty, !environment.uvPresent {
                // continue
            } else {
                return make(
                    environment: environment,
                    installationRequired: true,
                    selectedMethod: .unresolved,
                    packageManager: "homebrew",
                    packageIdentity: "hf",
                    desiredVersionPolicy: "NONE_UNTIL_HOST_NATIVE_BREW",
                    sourceTrust: .officialVerified,
                    executableExpectedAt: nil,
                    mutationsExpected: [],
                    unrelatedDependencyChanges: [],
                    expectedDependencyChanges: [],
                    rollbackMethod: "N/A",
                    rejected: rejected + ["FOREIGN_ARCHITECTURE_HOMEBREW_NOT_AUTO_SELECTED"],
                    requiresHumanAuthorization: false,
                    selectionReason: environment.brewSelectionReason
                        ?? "Foreign-architecture Homebrew present; refuse auto-select as native install.",
                    readyForInstallAuthorization: false,
                    verdict: "HOMEBREW_ARCHITECTURE_MISMATCH",
                    relatedEntityID: relatedEntityID,
                    now: now
                )
            }
        }

        // Path C: UV tool when brew absent/unsuitable.
        if (!environment.brewPresent
            || !environment.hfBrewFormulaRecognized
            || !environment.brewArchitectureMatchesHost),
           environment.uvPresent,
           !environment.existingUVHFTool {
            let expected = "\(NSHomeDirectory())/.local/share/uv/tools/hf/bin/hf"
            return make(
                environment: environment,
                installationRequired: true,
                selectedMethod: .uvTool,
                packageManager: "uv",
                packageIdentity: "hf",
                desiredVersionPolicy: "uv tool install hf — fixed tool env (not transient uvx)",
                sourceTrust: .officialVerified,
                executableExpectedAt: expected,
                mutationsExpected: [
                    "uv tool install hf",
                    "new isolated uv tool environment",
                    "executable at \(expected)",
                ],
                unrelatedDependencyChanges: ["uv-managed dependencies inside tool env"],
                expectedDependencyChanges: ["uv tool environment packages"],
                rollbackMethod: "uv tool uninstall hf",
                rejected: rejected + (environment.brewPresent && !environment.brewArchitectureMatchesHost
                    ? ["FOREIGN_ARCHITECTURE_HOMEBREW_SKIPPED"] : []),
                requiresHumanAuthorization: true,
                selectionReason: "Host-native Homebrew unsuitable or absent; uv present — prefer isolated fixed tool install over transient uvx.",
                readyForInstallAuthorization: true,
                verdict: "READY_FOR_HF_CLI_INSTALL_AUTHORIZATION",
                relatedEntityID: relatedEntityID,
                now: now
            )
        }

        // Path D: dedicated Python — only if neither brew nor uv works and a python exists.
        if !environment.pythonRuntimesInspected.isEmpty,
           (!environment.brewPresent || !environment.hfBrewFormulaRecognized || !environment.brewArchitectureMatchesHost),
           !environment.uvPresent {
            return make(
                environment: environment,
                installationRequired: true,
                selectedMethod: .dedicatedPythonEnv,
                packageManager: "python-venv",
                packageIdentity: "huggingface_hub[cli] / hf console entry point",
                desiredVersionPolicy: "dedicated tool venv; pin huggingface_hub with cache CLI contract",
                sourceTrust: .officialVerified,
                executableExpectedAt: "dedicated-tool-env/bin/hf",
                mutationsExpected: [
                    "create dedicated tool virtualenv (not project/system pollution)",
                    "pip install huggingface_hub into that env",
                ],
                unrelatedDependencyChanges: ["venv-local packages only"],
                expectedDependencyChanges: ["huggingface_hub and declared extras"],
                rollbackMethod: "remove dedicated tool environment directory",
                rejected: rejected,
                requiresHumanAuthorization: true,
                selectionReason: "Neither host-native Homebrew nor uv suitable; dedicated Python tool env is last inspectable option.",
                readyForInstallAuthorization: true,
                verdict: "READY_FOR_HF_CLI_INSTALL_AUTHORIZATION",
                relatedEntityID: relatedEntityID,
                now: now
            )
        }

        _ = HFCLIInstallMethod.standalonePipeInstaller

        return make(
            environment: environment,
            installationRequired: true,
            selectedMethod: .unresolved,
            packageManager: nil,
            packageIdentity: "unresolved",
            desiredVersionPolicy: "NONE",
            sourceTrust: .unresolved,
            executableExpectedAt: nil,
            mutationsExpected: [],
            unrelatedDependencyChanges: [],
            expectedDependencyChanges: [],
            rollbackMethod: "N/A",
            rejected: rejected + ["NO_FALLBACK_TO_CURL_BASH"],
            requiresHumanAuthorization: false,
            selectionReason: "No safe deterministic install method on this Mac. Do not invent curl|bash.",
            readyForInstallAuthorization: false,
            verdict: "INSTALL_METHOD_UNRESOLVED",
            relatedEntityID: relatedEntityID,
            now: now
        )
    }

    private static func make(
        environment: HFCLIEnvironmentSnapshot,
        installationRequired: Bool,
        selectedMethod: HFCLIInstallMethod,
        packageManager: String?,
        packageIdentity: String,
        desiredVersionPolicy: String,
        sourceTrust: HFCLISourceTrustStatus,
        executableExpectedAt: String?,
        mutationsExpected: [String],
        unrelatedDependencyChanges: [String],
        expectedDependencyChanges: [String],
        rollbackMethod: String,
        rejected: [String],
        requiresHumanAuthorization: Bool,
        selectionReason: String,
        readyForInstallAuthorization: Bool,
        verdict: String,
        relatedEntityID: String?,
        now: Date
    ) -> HFCLIInstallationProposal {
        let bindBrew = selectedMethod == .homebrew && environment.brewArchitectureMatchesHost
        return HFCLIInstallationProposal(
            product: product,
            purpose: purpose,
            installationRequired: installationRequired,
            selectedMethod: selectedMethod,
            packageManager: packageManager,
            packageIdentity: packageIdentity,
            desiredVersionPolicy: desiredVersionPolicy,
            sourceTrust: sourceTrust,
            executableExpectedAt: executableExpectedAt,
            brewExecutableBound: bindBrew ? environment.brewExecutableURL : nil,
            brewPrefixBound: bindBrew ? environment.brewPrefix : nil,
            brewArchitectureBound: bindBrew ? environment.brewArchitecture : nil,
            hostArchitectureBound: environment.hostArchitecture,
            architectureMatch: bindBrew ? environment.brewArchitectureMatchesHost : nil,
            mutationsExpected: mutationsExpected,
            unrelatedDependencyChanges: unrelatedDependencyChanges,
            expectedDependencyChanges: expectedDependencyChanges,
            credentialChangesExpected: false,
            hfSkillsInstallExpected: false,
            rollbackMethod: rollbackMethod,
            policyRejectedMethods: rejected,
            requiresHumanAuthorization: requiresHumanAuthorization,
            doesNotAuthorizeCacheCleanup: true,
            doesNotAuthorizeHubRemoteDeletion: true,
            recoveryBytesFromInstall: 0,
            selectionReason: selectionReason,
            readyForInstallAuthorization: readyForInstallAuthorization,
            verdict: verdict,
            relatedEntityID: relatedEntityID,
            createdAt: now
        )
    }

    /// Install proposal must never mint cleanup approval/permit.
    public static func cleanupAuthorizationFromInstallProposal(_: HFCLIInstallationProposal) -> UserActionApproval? {
        nil
    }

    public static func cleanupPermitFromInstallProposal(_: HFCLIInstallationProposal) -> ExecutionPermit? {
        nil
    }

    /// Cleanup approval must never authorize CLI installation.
    public static func installAuthorizedByCleanupApproval(_: UserActionApproval) -> Bool {
        false
    }
}
