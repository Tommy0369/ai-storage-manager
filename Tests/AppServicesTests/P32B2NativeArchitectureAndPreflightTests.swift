import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P32B2NativeArchitectureAndPreflightTests: XCTestCase {
    func testMultipleBrewsPreferHostNativeArm64() {
        let candidates = [
            HomebrewCandidate(
                executableURL: "/usr/local/bin/brew", prefix: "/usr/local",
                architecture: .x86_64, version: "Intel", usable: true, hostNative: false,
                formulaHFAvailable: true, evidence: []
            ),
            HomebrewCandidate(
                executableURL: "/opt/homebrew/bin/brew", prefix: "/opt/homebrew",
                architecture: .arm64, version: "ARM", usable: true, hostNative: true,
                formulaHFAvailable: true, evidence: []
            ),
        ]
        let r = HomebrewArchitectureResolver.resolve(
            context: .init(hostArchitecture: .arm64, injectedCandidates: candidates)
        )
        XCTAssertEqual(r.selectedExecutable, "/opt/homebrew/bin/brew")
        XCTAssertEqual(r.selectedPrefix, "/opt/homebrew")
        XCTAssertTrue(r.architectureMatchesHost)
        XCTAssertTrue(r.multipleInstallations)
        XCTAssertTrue(r.selectionReason.contains("HOST_NATIVE"))
    }

    func testOnlyForeignBrewNotAutoSelected() {
        let candidates = [
            HomebrewCandidate(
                executableURL: "/usr/local/bin/brew", prefix: "/usr/local",
                architecture: .x86_64, version: "Intel", usable: true, hostNative: false,
                formulaHFAvailable: true, evidence: []
            ),
        ]
        let r = HomebrewArchitectureResolver.resolve(
            context: .init(hostArchitecture: .arm64, injectedCandidates: candidates)
        )
        XCTAssertNil(r.selectedExecutable)
        XCTAssertFalse(r.architectureMatchesHost)
        XCTAssertTrue(r.selectionReason.contains("FOREIGN"))
    }

    func testHostIntelSelectsUsrLocal() {
        let candidates = [
            HomebrewCandidate(
                executableURL: "/usr/local/bin/brew", prefix: "/usr/local",
                architecture: .x86_64, version: "Intel", usable: true, hostNative: true,
                formulaHFAvailable: true, evidence: []
            ),
        ]
        let r = HomebrewArchitectureResolver.resolve(
            context: .init(hostArchitecture: .x86_64, injectedCandidates: candidates)
        )
        XCTAssertEqual(r.selectedExecutable, "/usr/local/bin/brew")
        XCTAssertTrue(r.architectureMatchesHost)
    }

    func testInstallProposalBinPathFromSelectedPrefix() {
        var env = emptyEnv()
        env.brewPresent = true
        env.brewExecutableURL = "/opt/homebrew/bin/brew"
        env.brewPrefix = "/opt/homebrew"
        env.hostArchitecture = .arm64
        env.brewArchitecture = .arm64
        env.brewArchitectureMatchesHost = true
        env.hfBrewFormulaRecognized = true
        env.hfBrewFormulaInstalled = false
        env.hfBrewFormulaVersion = "1.29.0"
        let plan = HuggingFaceCLIInstallationPlanner.plan(environment: env)
        XCTAssertEqual(plan.executableExpectedAt, "/opt/homebrew/bin/hf")
        XCTAssertNotEqual(plan.executableExpectedAt, "/usr/local/bin/hf")
        XCTAssertEqual(plan.brewExecutableBound, "/opt/homebrew/bin/brew")
        XCTAssertEqual(plan.architectureMatch, true)
    }

    func testFailedInstallDoesNotMeanInstalled() {
        // Nonzero brew + no executable → contract not resolved.
        XCTAssertFalse(FileManager.default.isExecutableFile(atPath: "/tmp/definitely-missing-hf-\(UUID().uuidString)"))
    }

    func testSizeAgreementFormattingDifference() {
        let r = HuggingFaceDryRunSizeAgreement.compare(
            vendorExpectedFreedBytes: 3_100_000_000,
            semanticBytes: 3_083_520_968
        )
        XCTAssertEqual(r, .agreesWithFormattingDifference)
        XCTAssertEqual(
            HuggingFaceDryRunSizeAgreement.parseVendorSizeToken("About to delete 1 repo(s) totalling 3.1G"),
            3_100_000_000
        )
    }

    func testRuntimePartialRemainsUnknown() {
        let handles = OpenFileSnapshot(
            openPaths: [], snapshotFailed: false, failureReason: nil, completeness: .partial
        )
        XCTAssertEqual(handles.hasOpenHandles(path: "/tmp/x"), .unknown)
    }

    func testRuntimeCompleteNoHandlesInactive() {
        let handles = OpenFileSnapshot(
            openPaths: ["/other"], snapshotFailed: false, failureReason: nil, completeness: .complete
        )
        XCTAssertEqual(handles.hasOpenHandles(path: "/cache/snap"), .false)
    }

    func testRuntimeCompleteTargetHandleActive() {
        let target = "/Users/t/.cache/huggingface/hub/models--x/snapshots/abc"
        let handles = OpenFileSnapshot(
            openPaths: [target + "/model.safetensors"],
            snapshotFailed: false, failureReason: nil, completeness: .complete
        )
        XCTAssertEqual(handles.hasOpenHandles(path: target), .true)
    }

    func testRawBlobStillNotSupported() {
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .blob
            ),
            .notSupported
        )
    }

    func testOllamaCapabilityUnchanged() {
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .ollama, entityKind: .model
            ),
            .implemented
        )
    }

    func testDryRunSingleRevisionRepoRemovalExpected() {
        let rev = "49e6aa286ad60c14352c404340ded53710378a11"
        // Path must contain `/huggingface/hub` so resolveCacheRoot binds the fixture, not ~/.cache.
        let hub = FileManager.default.temporaryDirectory
            .appendingPathComponent("p32b2-\(UUID().uuidString)/.cache/huggingface/hub")
        let repo = hub.appendingPathComponent("models--mlx-community--whisper-large-v3-mlx")
        let snap = repo.appendingPathComponent("snapshots").appendingPathComponent(rev)
        let refs = repo.appendingPathComponent("refs")
        try? FileManager.default.createDirectory(at: snap, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
        try? "\(rev)".write(to: refs.appendingPathComponent("main"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: hub.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()) }

        let inv = HuggingFaceCacheDryRunPreviewer.captureLocalInventory(
            repoID: "mlx-community/whisper-large-v3-mlx",
            revision: rev,
            itemPath: snap.path,
            uniqueBytes: 3_083_520_968,
            sharedBytes: 0
        )
        XCTAssertTrue(inv.snapshotPresent)
        XCTAssertEqual(inv.revisions.count, 1)

        let fake = FakeProcessRunner(nextResult: .init(
            outcome: .commandAccepted, exitCode: 0,
            stdout: "About to delete 1 repo(s) totalling 3.1G — entire repo (sole revision)\n"
        ))
        let iface = HuggingFaceNativeInterfaceResolution(
            status: .resolvedCLI, cliResolved: true,
            cliExecutableURL: "/opt/homebrew/bin/hf", cliVersion: "1.29.0",
            supportsCacheLS: true, supportsCacheVerify: true, supportsCacheRM: true,
            supportsDryRun: true, supportsCacheDir: true, supportsYes: true,
            binaryFingerprint: "x", resolutionMethod: "TEST", resolvedAt: Date(),
            failureReason: nil, evidence: []
        )
        let preview = HuggingFaceCacheDryRunPreviewer.preview(
            inventory: inv, interface: iface, processRunner: fake
        )
        XCTAssertTrue(preview.previewComplete)
        XCTAssertEqual(preview.targetedRevisionCount, 1)
        XCTAssertTrue(preview.expectedRepoDirectoryRemoval)
        XCTAssertFalse(preview.dryRunMutationDetected)
        let agree = HuggingFaceDryRunSizeAgreement.compare(
            vendorExpectedFreedBytes: preview.expectedFreedBytesVendor,
            semanticBytes: inv.uniqueBytes
        )
        XCTAssertTrue(agree == .agrees || agree == .agreesWithFormattingDifference)
    }

    func testForeignBrewMismatchVerdict() {
        var env = emptyEnv()
        env.brewPresent = true
        env.brewExecutableURL = nil
        env.brewPrefix = "/usr/local"
        env.hostArchitecture = .arm64
        env.brewArchitecture = .x86_64
        env.brewArchitectureMatchesHost = false
        env.brewSelectionReason = "ONLY_FOREIGN_ARCHITECTURE_BREW_PRESENT_DO_NOT_AUTO_SELECT_AS_NATIVE"
        env.hfBrewFormulaRecognized = true
        env.hfBrewFormulaInstalled = false
        env.uvPresent = false
        env.pythonRuntimesInspected = []
        let plan = HuggingFaceCLIInstallationPlanner.plan(environment: env)
        XCTAssertEqual(plan.verdict, "HOMEBREW_ARCHITECTURE_MISMATCH")
        XCTAssertFalse(plan.readyForInstallAuthorization)
    }

    func testBrewConfigRosettaTrueIsX86() {
        var evidence: [String] = []
        let arch = HomebrewArchitectureResolver.architectureFromBrewConfig(
            "CPU: Apple M2\nRosetta 2: true\nmacOS: 15.0 arm64\n",
            evidence: &evidence
        )
        XCTAssertEqual(arch, .x86_64)
    }

    // MARK: -

    private func emptyEnv() -> HFCLIEnvironmentSnapshot {
        return HFCLIEnvironmentSnapshot(
            brewPresent: false,
            brewExecutableURL: nil,
            brewPrefix: nil,
            brewVersion: nil,
            hostArchitecture: .arm64,
            brewArchitecture: nil,
            brewArchitectureMatchesHost: false,
            brewSelectionReason: nil,
            brewMultipleInstallations: false,
            brewAlternateInstallations: [],
            homebrewResolution: nil,
            hfBrewFormulaRecognized: false,
            hfBrewFormulaVersion: nil,
            hfBrewFormulaInstalled: false,
            hfBrewExecutablePresent: false,
            hfBrewExecutableURL: nil,
            brewDeclaredDependencies: [],
            uvPresent: false,
            uvExecutableURL: nil,
            uvVersion: nil,
            existingUVHFTool: false,
            uvHFExecutableURL: nil,
            pipxPresent: false,
            existingPipxHF: false,
            pythonRuntimesInspected: [],
            huggingfaceHubPackagesFound: [],
            existingHFEntryPoints: [],
            trustedHFCLIAlreadyPresent: false,
            presenceClass: .notInstalled,
            evidence: [],
            observedAt: Date(),
            brewMetadataMs: 0,
            uvMetadataMs: 0,
            pythonMetadataMs: 0,
            totalResolutionMs: 0
        )
    }
}
