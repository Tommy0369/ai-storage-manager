import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P32B1HuggingFaceCLIInstallBoundaryTests: XCTestCase {
    func testHomebrewPreferredWhenBrewPresentFormulaAvailable() {
        let env = baseEnv(
            brewPresent: true,
            formulaRecognized: true,
            formulaInstalled: false,
            brewPrefix: "/usr/local",
            deps: ["certifi", "git-lfs", "libyaml", "python@3.14"]
        )
        let plan = HuggingFaceCLIInstallationPlanner.plan(environment: env)
        XCTAssertTrue(plan.installationRequired)
        XCTAssertEqual(plan.selectedMethod, .homebrew)
        XCTAssertEqual(plan.packageIdentity, "hf")
        XCTAssertEqual(plan.sourceTrust, .officialVerified)
        XCTAssertEqual(plan.executableExpectedAt, "/usr/local/bin/hf")
        XCTAssertTrue(plan.readyForInstallAuthorization)
        XCTAssertEqual(plan.verdict, "READY_FOR_HF_CLI_INSTALL_AUTHORIZATION")
        XCTAssertEqual(plan.recoveryBytesFromInstall, 0)
        XCTAssertFalse(plan.credentialChangesExpected)
        XCTAssertFalse(plan.hfSkillsInstallExpected)
        XCTAssertTrue(plan.doesNotAuthorizeCacheCleanup)
        XCTAssertTrue(plan.policyRejectedMethods.contains(where: { $0.contains("curl|bash") }))
    }

    func testUVPreferredWhenBrewAbsent() {
        let env = baseEnv(
            brewPresent: false,
            formulaRecognized: false,
            formulaInstalled: false,
            uvPresent: true
        )
        let plan = HuggingFaceCLIInstallationPlanner.plan(environment: env)
        XCTAssertEqual(plan.selectedMethod, .uvTool)
        XCTAssertTrue(plan.readyForInstallAuthorization)
        XCTAssertFalse(plan.selectedMethod == .standalonePipeInstaller)
    }

    func testStandalonePipeNeverSelected() {
        let env = baseEnv(brewPresent: false, formulaRecognized: false, formulaInstalled: false)
        let plan = HuggingFaceCLIInstallationPlanner.plan(environment: env)
        XCTAssertNotEqual(plan.selectedMethod, .standalonePipeInstaller)
        XCTAssertTrue(plan.policyRejectedMethods.contains(where: { $0.contains("curl|bash") }))
    }

    func testNoPackageManagerUnresolved() {
        let env = baseEnv(
            brewPresent: false,
            formulaRecognized: false,
            formulaInstalled: false,
            uvPresent: false,
            pythons: []
        )
        let plan = HuggingFaceCLIInstallationPlanner.plan(environment: env)
        XCTAssertEqual(plan.selectedMethod, .unresolved)
        XCTAssertEqual(plan.verdict, "INSTALL_METHOD_UNRESOLVED")
        XCTAssertFalse(plan.readyForInstallAuthorization)
    }

    func testExistingTrustedCLINeedsNoInstall() {
        var env = baseEnv(brewPresent: true, formulaRecognized: true, formulaInstalled: true)
        env.trustedHFCLIAlreadyPresent = true
        env.presenceClass = .trustedCLIPresent
        env.hfBrewExecutablePresent = true
        env.hfBrewExecutableURL = "/usr/local/bin/hf"
        let plan = HuggingFaceCLIInstallationPlanner.plan(environment: env)
        XCTAssertFalse(plan.installationRequired)
        XCTAssertFalse(plan.readyForInstallAuthorization)
    }

    func testBrokenBrewLinkDoesNotAutoLink() {
        var env = baseEnv(brewPresent: true, formulaRecognized: true, formulaInstalled: true)
        env.hfBrewExecutablePresent = false
        env.presenceClass = .installedButNotResolvable
        env.trustedHFCLIAlreadyPresent = false
        let plan = HuggingFaceCLIInstallationPlanner.plan(environment: env)
        XCTAssertEqual(plan.verdict, "CLI_INSTALLED_BUT_NOT_RESOLVABLE")
        XCTAssertFalse(plan.installationRequired)
        XCTAssertFalse(plan.mutationsExpected.contains(where: { $0.contains("brew link") && !$0.contains("separate") }))
    }

    func testInstallProposalNeverMintsCleanupAuth() {
        let env = baseEnv(brewPresent: true, formulaRecognized: true, formulaInstalled: false, brewPrefix: "/usr/local")
        let plan = HuggingFaceCLIInstallationPlanner.plan(environment: env)
        XCTAssertNil(HuggingFaceCLIInstallationPlanner.cleanupAuthorizationFromInstallProposal(plan))
        XCTAssertNil(HuggingFaceCLIInstallationPlanner.cleanupPermitFromInstallProposal(plan))
        XCTAssertNil(plan.asCleanupPermitStub)
        XCTAssertNil(SoftwareInstallationProposal.proposeRestoreHuggingFaceCLI(entityID: "x").asCleanupPermitStub())
    }

    func testCleanupApprovalCannotAuthorizeInstall() {
        let fp = ActionBindingFingerprint(
            entityID: "ai.hf.snapshot.x",
            action: .vendorNativeCleanup,
            canonicalPath: "/tmp/x",
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t",
            transactionContractVersion: HuggingFaceNativeCleanupExecutor.contractVersion
        )
        let approval = UserActionApproval(
            approvalID: "a",
            entityID: "ai.hf.snapshot.x",
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            consequenceSummaryVersion: "t",
            expectedRecoveryBytes: 1,
            approvedAt: Date(),
            expiryPolicy: "single_use",
            scope: "cleanup"
        )
        XCTAssertFalse(HuggingFaceCLIInstallationPlanner.installAuthorizedByCleanupApproval(approval))
    }

    func testHFInstallAuthScopeDoesNotAllowOllamaAndViceVersa() {
        let hf = SoftwareInstallationAuthorization.authorizeHuggingFaceCLIInstall(entityID: "e")
        XCTAssertTrue(hf.allowsHuggingFaceCLIInstall)
        XCTAssertFalse(hf.allowsOllamaInstall)
        XCTAssertTrue(hf.doesNotAuthorizeCleanup)
        XCTAssertNil(hf.asModelRemovalApproval())
        XCTAssertNil(hf.asCleanupExecutionPermit())

        let ollama = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: "e")
        XCTAssertTrue(ollama.allowsOllamaInstall)
        XCTAssertFalse(ollama.allowsHuggingFaceCLIInstall)
    }

    func testRandomHFBinaryNotInTrustedCandidatesAlone() {
        // Resolver only trusts fixed/package-manager paths — not /tmp/hf.
        let fake = FakeProcessRunner(nextResult: .init(
            outcome: .commandAccepted, exitCode: 0,
            stdout: "hf version\n"
        ))
        let resolution = HuggingFaceNativeInterfaceResolver.resolve(
            context: .init(
                processRunner: fake,
                fixedCLICandidatePaths: ["/tmp/definitely-not-a-real-hf-\(UUID().uuidString)"]
            )
        )
        XCTAssertFalse(resolution.cliResolved)
    }

    func testExistingUVToolPathInDerivedCandidates() {
        let paths = HuggingFaceNativeInterfaceResolver.packageManagerDerivedCandidates(
            brewPrefixes: ["/usr/local"],
            home: "/Users/test"
        )
        XCTAssertTrue(paths.contains("/Users/test/.local/share/uv/tools/hf/bin/hf"))
        XCTAssertTrue(paths.contains("/usr/local/bin/hf"))
    }

    func testOllamaCapabilityUnchanged() {
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .ollama, entityKind: .model
            ),
            .implemented
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .snapshot
            ),
            .implemented
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .blob
            ),
            .notSupported
        )
    }

    func testEnvironmentResolverWithFakeBrew() {
        let fake = FakeProcessRunner()
        fake.resultsByArguments = [
            ["--prefix"]: .init(outcome: .commandAccepted, exitCode: 0, stdout: "/usr/local\n"),
            ["--version"]: .init(outcome: .commandAccepted, exitCode: 0, stdout: "Homebrew 6.0\n"),
            ["config"]: .init(
                outcome: .commandAccepted, exitCode: 0,
                stdout: "CPU: Intel ...\nRosetta 2: false\nmacOS: ... x86_64\nHOMEBREW_PREFIX: /usr/local\n"
            ),
            ["list", "--formula", "hf"]: .init(
                outcome: .nonzeroExit, exitCode: 1, stderr: "Error: No such keg\n"
            ),
            ["info", "--json=v2", "hf"]: .init(
                outcome: .commandAccepted, exitCode: 0,
                stdout: #"{"formulae":[{"name":"hf","versions":{"stable":"1.29.0"},"dependencies":["certifi","python@3.14"]}]}"#
            ),
        ]
        // Create a temp brew stub path that exists as executable file for isExecutableFile.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("p32b1-brew-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tmp.path, contents: Data("#!/bin/sh\n".utf8), attributes: nil)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let snap = HuggingFaceCLIEnvironmentResolver.inspect(
            context: .init(
                processRunner: fake,
                brewCandidatePaths: [tmp.path],
                uvCandidatePaths: ["/no/uv"],
                pipxCandidatePaths: ["/no/pipx"],
                pythonCandidatePaths: [],
                hostArchitecture: .x86_64,
                hfFixedCLICandidatePaths: ["/tmp/no-hf-\(UUID().uuidString)"]
            )
        )
        XCTAssertTrue(snap.brewPresent)
        XCTAssertEqual(snap.brewPrefix, "/usr/local")
        XCTAssertTrue(snap.brewArchitectureMatchesHost)
        XCTAssertTrue(snap.hfBrewFormulaRecognized)
        XCTAssertEqual(snap.hfBrewFormulaVersion, "1.29.0")
        XCTAssertFalse(snap.hfBrewFormulaInstalled)
        XCTAssertFalse(snap.trustedHFCLIAlreadyPresent)

        let plan = HuggingFaceCLIInstallationPlanner.plan(environment: snap)
        XCTAssertEqual(plan.verdict, "READY_FOR_HF_CLI_INSTALL_AUTHORIZATION")
        XCTAssertEqual(plan.selectedMethod, .homebrew)
        XCTAssertEqual(plan.executableExpectedAt, "/usr/local/bin/hf")
        XCTAssertEqual(plan.brewExecutableBound, tmp.path)
        XCTAssertEqual(plan.architectureMatch, true)
    }

    // MARK: - Helpers

    private func baseEnv(
        brewPresent: Bool,
        formulaRecognized: Bool,
        formulaInstalled: Bool,
        brewPrefix: String? = nil,
        deps: [String] = [],
        uvPresent: Bool = false,
        pythons: [String] = ["/usr/bin/python3"],
        hostArch: CPUArchitectureClass = .x86_64,
        brewArchMatch: Bool = true
    ) -> HFCLIEnvironmentSnapshot {
        let prefix = brewPrefix ?? (brewPresent ? "/usr/local" : nil)
        let brewExe = brewPresent ? "\(prefix!)/bin/brew" : nil
        return HFCLIEnvironmentSnapshot(
            brewPresent: brewPresent,
            brewExecutableURL: (brewPresent && brewArchMatch) ? brewExe : nil,
            brewPrefix: (brewPresent && brewArchMatch) ? prefix : (brewPresent ? prefix : nil),
            brewVersion: brewPresent ? "Homebrew 6.0" : nil,
            hostArchitecture: hostArch,
            brewArchitecture: brewPresent ? (brewArchMatch ? hostArch : (hostArch == .arm64 ? .x86_64 : .arm64)) : nil,
            brewArchitectureMatchesHost: brewPresent && brewArchMatch,
            brewSelectionReason: brewPresent
                ? (brewArchMatch ? "HOST_NATIVE_BREW_SELECTED" : "ONLY_FOREIGN_ARCHITECTURE_BREW_PRESENT_DO_NOT_AUTO_SELECT_AS_NATIVE")
                : nil,
            brewMultipleInstallations: false,
            brewAlternateInstallations: [],
            homebrewResolution: nil,
            hfBrewFormulaRecognized: formulaRecognized,
            hfBrewFormulaVersion: formulaRecognized ? "1.29.0" : nil,
            hfBrewFormulaInstalled: formulaInstalled,
            hfBrewExecutablePresent: false,
            hfBrewExecutableURL: nil,
            brewDeclaredDependencies: deps,
            uvPresent: uvPresent,
            uvExecutableURL: uvPresent ? "/usr/local/bin/uv" : nil,
            uvVersion: uvPresent ? "uv 0.0" : nil,
            existingUVHFTool: false,
            uvHFExecutableURL: nil,
            pipxPresent: false,
            existingPipxHF: false,
            pythonRuntimesInspected: pythons,
            huggingfaceHubPackagesFound: [],
            existingHFEntryPoints: [],
            trustedHFCLIAlreadyPresent: false,
            presenceClass: .notInstalled,
            evidence: [],
            observedAt: Date(),
            brewMetadataMs: 1,
            uvMetadataMs: 1,
            pythonMetadataMs: 1,
            totalResolutionMs: 3
        )
    }
}
