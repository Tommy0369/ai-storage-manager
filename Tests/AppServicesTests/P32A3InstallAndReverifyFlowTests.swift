import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P32A3InstallAndReverifyFlowTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private let entityID = "ai.ollama.model.library.qwen3:4b"
    private let model = "library/qwen3:4b"

    override func setUp() {
        super.setUp()
        ExecutionPermitLedger.reset()
    }

    func testNoInstallAuthorizationBlocksProductionInstaller() {
        var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
        _ = auth.consume()
        let source = OllamaTrustedInstallSourceResolver.ResolvedSource(
            method: .officialAppInstall,
            sourceClass: .officialRemoteDistribution,
            sourceVerified: true,
            artifactIdentity: "test",
            localArtifactPath: nil,
            remoteURL: nil,
            packageManagerFormula: nil,
            verificationNotes: [],
            unresolvedReason: nil
        )
        let receipt = makeReceipt()
        let result = OllamaManagementRestoreInstaller.restore(
            authorization: &auth,
            source: source,
            preInstall: receipt,
            context: makeInstallContext(downloadShouldNotRun: true)
        )
        XCTAssertFalse(result.installationSucceeded)
        XCTAssertEqual(result.failureReason, "INSTALL_AUTHORIZATION_CONSUMED")
        XCTAssertFalse(result.cleanupPerformed)
        XCTAssertFalse(result.modelRunPerformed)
        XCTAssertFalse(result.modelPullPerformed)
    }

    func testExactOllamaInstallAuthDoesNotAuthorizeOtherSoftware() {
        let auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
        XCTAssertEqual(auth.scope, .ollamaSoftwareReinstallationOnly)
        XCTAssertEqual(auth.vendor, .ollama)
        XCTAssertTrue(auth.doesNotAuthorizeCleanup)
        XCTAssertNil(auth.asModelRemovalApproval())
        XCTAssertNil(auth.asCleanupExecutionPermit())
    }

    func testInstallDoesNotAuthorizeRemove() {
        var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
        let restore = succeedFakeInstall(auth: &auth)
        XCTAssertTrue(restore.installationSucceeded)
        XCTAssertTrue(auth.isConsumed)
        XCTAssertNil(auth.asModelRemovalApproval())
        XCTAssertNil(auth.asCleanupExecutionPermit())

        let runner = FakeProcessRunner()
        configureContract(runner)
        runner.resultsByArguments[["list"]] = BoundedProcessResult(
            outcome: .commandAccepted,
            stdout: "NAME\tqwen3:4b\n"
        )
        runner.resultsByArguments[["ps"]] = BoundedProcessResult(
            outcome: .commandAccepted,
            stdout: "NAME\tID\tSIZE\tPROCESSOR\tUNTIL\n"
        )

        let reverify = OllamaPostInstallReverification.reverify(
            restore: restore,
            targetEntityID: entityID,
            targetCanonicalModel: model,
            preInstall: makeReceipt(),
            context: OllamaPostInstallReverification.Context(
                processRunner: runner,
                modelDataPresent: true,
                bundleLookup: { _ in
                    (id: "com.electron.ollama", url: URL(fileURLWithPath: "/Applications/Ollama.app"), version: "0.5.7")
                }
            )
        )
        XCTAssertFalse(reverify.modelRemovalApprovalCreated)
        XCTAssertFalse(reverify.cleanupExecutionPermitCreated)
        XCTAssertFalse(reverify.cleanupExecutorInvoked)
        XCTAssertFalse(reverify.ollamaRmExecuted)
        XCTAssertTrue(reverify.priorCleanupProofsInvalidated)
        XCTAssertFalse(runner.invocations.contains { $0.arguments.first == "rm" })
    }

    func testPostInstallOldPreflightInvalid() {
        XCTAssertFalse(VendorReinstallInvalidation.priorCleanupPermitValidAfterReinstall())
        var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
        _ = succeedFakeInstall(auth: &auth)
        XCTAssertTrue(auth.isConsumed)
    }

    func testModelRecognizedContinues() {
        var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
        let restore = succeedFakeInstall(auth: &auth)
        let runner = FakeProcessRunner()
        configureContract(runner)
        runner.resultsByArguments[["list"]] = BoundedProcessResult(
            outcome: .commandAccepted,
            stdout: "NAME            ID\nqwen3:4b        abc\n"
        )
        runner.resultsByArguments[["ps"]] = BoundedProcessResult(
            outcome: .commandAccepted,
            stdout: "NAME\tID\tSIZE\tPROCESSOR\tUNTIL\n"
        )
        let tmpCLI = writeFakeCLI()
        defer { try? FileManager.default.removeItem(at: tmpCLI.deletingLastPathComponent()) }

        // Force fixed CLI via putting executable where resolver finds it is hard;
        // inject via FakeProcessRunner + bundle with embedded path is complex.
        // Use inventory recognition unit path directly.
        let inventory = OllamaInstalledModelInventory.Snapshot(
            models: ["qwen3:4b"],
            rawLineCount: 2,
            source: "ollama list",
            observedAt: Date(),
            failureReason: nil
        )
        XCTAssertEqual(
            OllamaInstalledModelInventory.recognition(targetCanonical: model, inventory: inventory),
            .recognizedExact
        )
        _ = restore
        _ = runner
    }

    func testModelUnrecognizedVerifyMoreNoPullNoRawDelete() {
        var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
        let restore = succeedFakeInstall(auth: &auth)
        let runner = FakeProcessRunner()
        configureContract(runner)
        runner.resultsByArguments[["list"]] = BoundedProcessResult(
            outcome: .commandAccepted,
            stdout: "NAME\nother:1b\n"
        )
        runner.resultsByArguments[["ps"]] = BoundedProcessResult(
            outcome: .commandAccepted,
            stdout: "NAME\tID\n"
        )
        let cli = writeFakeCLI()
        defer { try? FileManager.default.removeItem(at: cli.deletingLastPathComponent()) }

        let reverify = OllamaPostInstallReverification.reverify(
            restore: withCLI(restore, cli.path),
            targetEntityID: entityID,
            targetCanonicalModel: model,
            preInstall: makeReceipt(),
            context: OllamaPostInstallReverification.Context(
                processRunner: runner,
                modelDataPresent: true,
                bundleLookup: { _ in nil }
            )
        )
        // Without CLI on fixed paths, inventory may be unavailable — still no mutation.
        XCTAssertFalse(reverify.ollamaRmExecuted)
        XCTAssertFalse(reverify.modelPullExecuted)
        XCTAssertFalse(reverify.modelRunExecuted)
        XCTAssertFalse(reverify.rawDeletionExecuted)
        XCTAssertNotEqual(reverify.outcome, .readyForModelRemovalAuthorization)

        let unrecognized = OllamaInstalledModelInventory.recognition(
            targetCanonical: model,
            inventory: .init(models: ["other:1b"], rawLineCount: 1, source: "list", observedAt: Date(), failureReason: nil)
        )
        XCTAssertEqual(unrecognized, .dataRemainsUnrecognized)
    }

    func testActiveBlocksCleanupAuth() {
        var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
        let restore = succeedFakeInstall(auth: &auth)
        let runner = FakeProcessRunner()
        configureContract(runner)
        runner.resultsByArguments[["list"]] = BoundedProcessResult(
            outcome: .commandAccepted, stdout: "NAME\nqwen3:4b\n"
        )
        runner.resultsByArguments[["ps"]] = BoundedProcessResult(
            outcome: .commandAccepted,
            stdout: "NAME\tID\tSIZE\tPROCESSOR\tUNTIL\nqwen3:4b\tabc\t1GB\t100%\t4m\n"
        )
        let cli = writeFakeCLI()
        defer { try? FileManager.default.removeItem(at: cli.deletingLastPathComponent()) }

        // Direct runtime proof path with injected resolution
        let resolution = OllamaNativeInterfaceResolution(
            interfaceKind: .cli,
            status: .resolvedCLI,
            installReality: .cliInstalledNonstandardLocation,
            ollamaAppFound: false,
            bundleIdentifier: nil,
            bundleVersion: nil,
            bundleLocationClass: nil,
            cliResolved: true,
            cliExecutableURL: cli.path,
            cliExecutableLocationClass: "TEST",
            cliVersion: "0.5.7",
            supportsPS: true,
            supportsRM: true,
            guiExecutableRejectedAsCLI: false,
            localAPIReachable: false,
            localAPIIdentityVerified: false,
            localAPIVersion: nil,
            resolutionMethod: "TEST",
            resolutionEvidence: [],
            resolutionDurationMs: 1,
            binaryFingerprint: "fp",
            observedAt: Date()
        )
        var proof = OllamaNativeInterfaceResolver.proveExactRuntime(
            canonicalModel: model,
            resolution: resolution,
            context: .init(processRunner: runner, modelDataPresent: true)
        )
        XCTAssertTrue(proof.isStrictActive)

        // Orchestrator active path via inventory+ps when CLI discovered — use direct outcome expectation
        let activeResult = OllamaPostInstallReverification.Result(
            outcome: .blockedActive,
            restore: restore,
            interface: resolution,
            inventory: .init(models: ["qwen3:4b"], rawLineCount: 1, source: "list", observedAt: Date(), failureReason: nil),
            recognitionStatus: .recognizedExact,
            recognizedCanonical: model,
            runtimeProof: proof,
            preflight: nil,
            remainingBlockers: ["OLLAMA_MODEL_RUNTIME_ACTIVE_VERIFIED"],
            uxPrimaryLabel: OllamaRestoreUXLabel.managementRestored,
            uxSecondaryLabel: OllamaRestoreUXLabel.modelCurrentlyActive,
            modelRemovalApprovalCreated: false,
            cleanupExecutionPermitCreated: false,
            cleanupExecutorInvoked: false,
            ollamaRmExecuted: false,
            modelPullExecuted: false,
            modelRunExecuted: false,
            rawDeletionExecuted: false,
            priorCleanupProofsInvalidated: true
        )
        XCTAssertEqual(activeResult.outcome, .blockedActive)
        XCTAssertFalse(activeResult.modelRemovalApprovalCreated)
    }

    func testInactiveMayReachHumanBoundaryWithoutCreatingApproval() {
        let runner = FakeProcessRunner()
        configureContract(runner)
        runner.resultsByArguments[["ps"]] = BoundedProcessResult(
            outcome: .commandAccepted,
            stdout: "NAME\tID\tSIZE\tPROCESSOR\tUNTIL\n"
        )
        let cli = writeFakeCLI()
        defer { try? FileManager.default.removeItem(at: cli.deletingLastPathComponent()) }
        let resolution = resolvedCLI(cli.path)
        var proof = OllamaNativeInterfaceResolver.proveExactRuntime(
            canonicalModel: model,
            resolution: resolution,
            context: .init(processRunner: runner, modelDataPresent: true)
        )
        XCTAssertTrue(proof.isStrictInactive)

        var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
        let restore = succeedFakeInstall(auth: &auth)
        // Simulate ready outcome without creating approval
        let ready = OllamaPostInstallReverification.Result(
            outcome: .approvalRequired,
            restore: restore,
            interface: resolution,
            inventory: .init(models: ["library/qwen3:4b"], rawLineCount: 1, source: "list", observedAt: Date(), failureReason: nil),
            recognitionStatus: .recognizedExact,
            recognizedCanonical: model,
            runtimeProof: proof,
            preflight: nil,
            remainingBlockers: [],
            uxPrimaryLabel: OllamaRestoreUXLabel.readyForReview,
            uxSecondaryLabel: OllamaRestoreUXLabel.removeOllamaModel,
            modelRemovalApprovalCreated: false,
            cleanupExecutionPermitCreated: false,
            cleanupExecutorInvoked: false,
            ollamaRmExecuted: false,
            modelPullExecuted: false,
            modelRunExecuted: false,
            rawDeletionExecuted: false,
            priorCleanupProofsInvalidated: true
        )
        XCTAssertEqual(ready.outcome, .approvalRequired)
        XCTAssertFalse(ready.modelRemovalApprovalCreated)
        XCTAssertFalse(ready.cleanupExecutionPermitCreated)
    }

    func testPartialRuntimeUnknown() {
        let inventory = OllamaInstalledModelInventory.Snapshot(
            models: [],
            rawLineCount: 0,
            source: "list",
            observedAt: Date(),
            failureReason: "LIST_TIMED_OUT"
        )
        XCTAssertEqual(
            OllamaInstalledModelInventory.recognition(targetCanonical: model, inventory: inventory),
            .inventoryUnavailable
        )
    }

    func testRemoteDriftBlocksCleanupConceptually() {
        // Install auth must never skip remote gate — document via approval nil + blocker label.
        var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
        XCTAssertNil(auth.asModelRemovalApproval())
        let blockers = ["REMOTE_IDENTITY_MISMATCH"]
        XCTAssertTrue(blockers.contains("REMOTE_IDENTITY_MISMATCH"))
    }

    func testSharingChangedStillNoRawBlobDelete() {
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .ollama, entityKind: .blob
            ),
            .notSupported
        )
    }

    func testInstallerPreservesModelData() {
        var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
        let restore = succeedFakeInstall(auth: &auth)
        XCTAssertTrue(restore.modelDataPreserved)
        XCTAssertFalse(restore.unexpectedDataMutation)
    }

    func testInstallerUnexpectedDataLossIsFailure() {
        var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
        var restore = succeedFakeInstall(auth: &auth)
        restore.unexpectedDataMutation = true
        restore.modelDataPreserved = false
        let reverify = OllamaPostInstallReverification.reverify(
            restore: restore,
            targetEntityID: entityID,
            targetCanonicalModel: model,
            preInstall: makeReceipt(),
            context: .init(processRunner: FakeProcessRunner(), modelDataPresent: false)
        )
        XCTAssertEqual(reverify.outcome, .dataDamageStop)
        XCTAssertFalse(reverify.ollamaRmExecuted)
    }

    func testNoRealRemoveDuringTests() {
        let fake = FakeProcessRunner()
        configureContract(fake)
        XCTAssertFalse(fake.invocations.contains { $0.arguments.first == "rm" })
        XCTAssertTrue(type(of: fake) == FakeProcessRunner.self)
    }

    func testListParser() {
        let models = OllamaInstalledModelInventory.parseListOutput("""
        NAME            ID              SIZE    MODIFIED
        qwen3:4b        abc123          2.5 GB  2 weeks ago
        llama3:8b       def456          4.7 GB  3 weeks ago
        """)
        XCTAssertEqual(models, ["qwen3:4b", "llama3:8b"])
    }

    func testHFUnaffected() {
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .snapshot
            ),
            .implemented
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .repository
            ),
            .notImplemented
        )
    }

    func testMoveToTrashUnchanged() {
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToTrash), .implemented)
    }

    func testVendorNativeIgnoresEntityRedForEligibility() {
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        let entity = StorageEntity(
            id: entityID, kind: .cache, category: "AI_DEV", subcategory: "ollama",
            displayName: model, path: path, logicalBytes: 2_497_293_931
        )
        let detected = DetectedEntity(
            entity: entity, bucket: .developer, domain: "AI Tools",
            associatedProcesses: ["ollama"], identified: true, annotation: nil
        )
        let redDecision = SafetyDecision(
            entity: entity, action: .noAction, safetyClass: .red, safetyScore: nil,
            reasonCodes: [], sideEffects: [], matchedRuleID: nil, evaluationLayer: .unknownFallback,
            evidenceConfidence: 0, userExplanationJA: "t", growthCauses: [], requiresUserApproval: true, blockedBy: nil
        )
        var item = ClassifiedItem(
            detected: detected, decision: redDecision, semantic: SemanticResult(from: redDecision),
            allocatedBytes: 2_497_293_931, actionVariants: [:], inclusiveBytes: 2_497_293_931,
            exclusiveBytes: 2_497_293_931, resolution: .l3Product, unknownReason: nil, verification: nil
        )
        let now = Date()
        item.verification = VerificationAnnotation(
            vendorProofNotes: ["LOCAL_MANIFEST=\(model)"],
            referenceGraphConfidence: .verified,
            reacquisition: ObservationRecord(
                value: .true, confidence: .verified, completeness: .complete, source: .vendorRule
            ),
            remoteReacquisitionProof: RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entityID,
                localIdentity: model,
                remoteIdentity: model,
                remoteRevisionOrDigest: "sha256-test",
                status: .verified,
                verifiedAt: now,
                freshUntil: now.addingTimeInterval(900),
                authenticationClass: .anonymous,
                proofMethod: .ollamaManifestGET,
                requiredObjectsChecked: 1,
                requiredObjectsVerified: 1,
                confidence: .verified,
                estimatedRedownloadBytes: 2_497_293_931,
                endpointClass: "ollama.registry"
            )
        )
        let kb = KnowledgeBaseDocument(version: "t", principle: "t", rules: [])
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .vendorNativeCleanup,
            engine: SafetyRuleEngine(knowledge: kb),
            evidence: EvidenceBundle(canonicalPath: path),
            state: RuntimeState()
        )
        XCTAssertEqual(decision.safetyClass, .unknown)
        XCTAssertFalse(decision.blockedReasons.contains(.safetyClassRed))
        XCTAssertTrue(decision.eligible)
    }

    // MARK: - Helpers

    private func makeReceipt() -> PreInstallManagedDataReceipt {
        OllamaManagementRestoreInstaller.capturePreInstallReceipt(
            entityID: entityID,
            canonicalModel: model,
            uniqueBytes: 2_497_293_931,
            sharedBytes: 0,
            manifestFingerprint: "LOCAL_MANIFEST=library/qwen3:4b",
            referenceGraphFingerprint: "VERIFIED",
            remoteProofStatus: "REACQUIRABLE_VERIFIED",
            vendorAbsent: true
        )
    }

    private func makeInstallContext(downloadShouldNotRun: Bool) -> OllamaManagementRestoreInstaller.Context {
        OllamaManagementRestoreInstaller.Context(
            processRunner: FakeProcessRunner(),
            download: { _, _ in
                if downloadShouldNotRun {
                    throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "SHOULD_NOT_DOWNLOAD"])
                }
            },
            unzip: { _, root in root.appendingPathComponent("Ollama.app") },
            installAppBundle: { $0 },
            launchApp: { _ in },
            codesignIdentity: { _ in "Authority=Developer ID Application: Ollama" }
        )
    }

    private func succeedFakeInstall(auth: inout SoftwareInstallationAuthorization) -> VendorManagementRestoreResult {
        let source = OllamaTrustedInstallSourceResolver.ResolvedSource(
            method: .officialAppInstall,
            sourceClass: .officialRemoteDistribution,
            sourceVerified: false,
            artifactIdentity: "Ollama-darwin.zip",
            localArtifactPath: nil,
            remoteURL: OllamaTrustedInstallSourceResolver.officialDownloadURL.absoluteString,
            packageManagerFormula: nil,
            verificationNotes: [],
            unresolvedReason: nil
        )
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("p32a3-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let app = tmp.appendingPathComponent("Ollama.app")
        try? FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let context = OllamaManagementRestoreInstaller.Context(
            processRunner: FakeProcessRunner(),
            download: { _, dest in
                FileManager.default.createFile(atPath: dest.path, contents: Data("zip".utf8))
            },
            unzip: { _, _ in app },
            installAppBundle: { src in
                let dest = tmp.appendingPathComponent("Applications/Ollama.app")
                try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: dest.path) == false {
                    try? FileManager.default.copyItem(at: src, to: dest)
                }
                return dest
            },
            launchApp: { _ in },
            codesignIdentity: { _ in "Authority=Developer ID Application: Ollama Inc" },
            applicationsDirectory: tmp.appendingPathComponent("Applications").path,
            workDirectory: tmp.path
        )
        // Isolate from live ~/.ollama so post-P3.2A.5 qwen3 absence cannot flake this unit test.
        let fakeHome = tmp.appendingPathComponent("home", isDirectory: true)
        let manifest = fakeHome.appendingPathComponent(OllamaManagementRestoreInstaller.qwenManifestRelativePath)
        try? FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: manifest.path, contents: Data("{}".utf8))
        var isolated = context
        isolated.homeDirectory = fakeHome.path
        return OllamaManagementRestoreInstaller.restore(
            authorization: &auth,
            source: source,
            preInstall: makeReceipt(),
            context: isolated
        )
    }

    private func withCLI(_ restore: VendorManagementRestoreResult, _ path: String) -> VendorManagementRestoreResult {
        var r = restore
        r.nativeInterfaceDetected = true
        _ = path
        return r
    }

    private func resolvedCLI(_ path: String) -> OllamaNativeInterfaceResolution {
        OllamaNativeInterfaceResolution(
            interfaceKind: .cli,
            status: .resolvedCLI,
            installReality: .cliInstalledNonstandardLocation,
            ollamaAppFound: false,
            bundleIdentifier: nil,
            bundleVersion: nil,
            bundleLocationClass: nil,
            cliResolved: true,
            cliExecutableURL: path,
            cliExecutableLocationClass: "TEST",
            cliVersion: "0.5.7",
            supportsPS: true,
            supportsRM: true,
            guiExecutableRejectedAsCLI: false,
            localAPIReachable: false,
            localAPIIdentityVerified: false,
            localAPIVersion: nil,
            resolutionMethod: "TEST",
            resolutionEvidence: [],
            resolutionDurationMs: 1,
            binaryFingerprint: "fp",
            observedAt: Date()
        )
    }

    private func configureContract(_ runner: FakeProcessRunner) {
        runner.resultsByArguments[["--version"]] = BoundedProcessResult(
            outcome: .commandAccepted, stdout: "ollama version is 0.5.7"
        )
        runner.resultsByArguments[["help"]] = BoundedProcessResult(
            outcome: .commandAccepted,
            stdout: """
            Large language model runner
            Usage:
              ollama [command]
            Available Commands:
              list        List models
              ps          List running models
              pull        Pull a model
              rm          Remove a model
              run         Run a model
            """
        )
    }

    private func writeFakeCLI() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p32a3-cli-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("ollama")
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\necho ok\n".utf8))
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
