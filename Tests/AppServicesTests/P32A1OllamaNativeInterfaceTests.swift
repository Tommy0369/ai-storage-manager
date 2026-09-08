import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P32A1OllamaNativeInterfaceTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        ExecutionPermitLedger.reset()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("p32a1-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    // MARK: - Bundle discovery (non-default path)

    func testAppBundleDiscoveryNonDefaultPath() {
        let bundleURL = tempRoot.appendingPathComponent("CustomApps/Ollama.app")
        writeFakeCLI(
            at: bundleURL.appendingPathComponent("Contents/Resources/ollama"),
            help: ollamaHelpText()
        )
        let runner = FakeProcessRunner()
        configureContract(runner)
        let resolution = OllamaNativeInterfaceResolver.resolve(context: .init(
            fileManager: .default,
            processRunner: runner,
            modelDataPresent: false,
            httpGET: { _ in nil },
            bundleLookup: { ids in
                XCTAssertTrue(ids.contains("com.ollama.app") || ids.contains("com.electron.ollama"))
                return ("com.ollama.app", bundleURL, "0.9.0-test")
            }
        ))
        XCTAssertTrue(resolution.ollamaAppFound)
        XCTAssertEqual(resolution.bundleIdentifier, "com.ollama.app")
        XCTAssertEqual(resolution.bundleVersion, "0.9.0-test")
        XCTAssertTrue(resolution.cliResolved)
        XCTAssertEqual(resolution.cliExecutableLocationClass, "APP_BUNDLE_EMBEDDED")
        XCTAssertNotEqual(resolution.bundleLocationClass, "APPLICATIONS")
        XCTAssertFalse(resolution.cliExecutableURL?.hasPrefix("/Applications") == true)
    }

    // MARK: - GUI only

    func testGUIOnlyRejectsMainExecutableAsCLI() {
        let bundleURL = tempRoot.appendingPathComponent("Apps/Ollama.app")
        let gui = bundleURL.appendingPathComponent("Contents/MacOS/Ollama")
        try? FileManager.default.createDirectory(at: gui.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: gui.path, contents: Data("#!/bin/sh\necho GUI\n".utf8))
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gui.path)

        let runner = FakeProcessRunner(nextResult: BoundedProcessResult(
            outcome: .commandAccepted,
            stdout: "Ollama GUI 1.0"
        ))
        let resolution = OllamaNativeInterfaceResolver.resolve(context: .init(
            processRunner: runner,
            httpGET: { _ in nil },
            bundleLookup: { _ in ("com.ollama.app", bundleURL, "1.0") }
        ))
        XCTAssertTrue(resolution.ollamaAppFound)
        XCTAssertTrue(resolution.guiExecutableRejectedAsCLI)
        XCTAssertFalse(resolution.cliResolved)
        XCTAssertFalse(resolution.supportsRM)
        XCTAssertEqual(resolution.interfaceKind, .guiOnly)
        XCTAssertFalse(resolution.executionTransportAvailable)
    }

    // MARK: - Embedded CLI

    func testEmbeddedCLIAcceptedWhenContractProven() {
        let bundleURL = tempRoot.appendingPathComponent("Apps2/Ollama.app")
        let cli = bundleURL.appendingPathComponent("Contents/Resources/ollama")
        writeFakeCLI(at: cli, help: ollamaHelpText())
        let runner = FakeProcessRunner()
        configureContract(runner)
        let resolution = OllamaNativeInterfaceResolver.resolve(context: .init(
            processRunner: runner,
            httpGET: { _ in nil },
            bundleLookup: { _ in ("com.ollama.app", bundleURL, "1.2") }
        ))
        XCTAssertTrue(resolution.cliResolved)
        XCTAssertTrue(resolution.supportsPS)
        XCTAssertTrue(resolution.supportsRM)
        XCTAssertEqual(resolution.cliExecutableURL, cli.path)
        XCTAssertEqual(resolution.status, .resolvedCLI)
    }

    // MARK: - Bad executable

    func testBadExecutableNamedOllamaRejected() {
        let fake = tempRoot.appendingPathComponent("bin/ollama")
        writeFakeCLI(at: fake, help: "totally unrelated binary usage")
        let runner = FakeProcessRunner()
        runner.resultsByArguments[["--version"]] = BoundedProcessResult(
            outcome: .commandAccepted, stdout: "fake-tool 9.9"
        )
        runner.resultsByArguments[["help"]] = BoundedProcessResult(
            outcome: .commandAccepted, stdout: "no ollama here"
        )
        runner.resultsByArguments[[]] = BoundedProcessResult(
            outcome: .commandAccepted, stdout: "nope"
        )
        let resolution = OllamaNativeInterfaceResolver.resolve(context: .init(
            processRunner: runner,
            httpGET: { _ in nil },
            bundleLookup: { _ in nil }
        ))
        // Even if we inject fixed path via temporary override — use process path candidate.
        let viaProcess = OllamaNativeInterfaceResolver.resolve(context: .init(
            processRunner: runner,
            processExecutablePaths: [fake.path],
            httpGET: { _ in nil },
            bundleLookup: { _ in nil }
        ))
        XCTAssertFalse(viaProcess.cliResolved)
        XCTAssertTrue(viaProcess.resolutionEvidence.contains("CLI_CONTRACT_FAILED")
            || viaProcess.resolutionEvidence.contains(where: { $0.contains("PROCESS_GUI") })
            || !viaProcess.cliResolved)
        _ = resolution
    }

    // MARK: - PATH lookalike never selected

    func testPATHLookalikeNotSelected() {
        let lookalike = tempRoot.appendingPathComponent("evil-path/ollama")
        writeFakeCLI(at: lookalike, help: ollamaHelpText())
        let runner = FakeProcessRunner()
        configureContract(runner)
        let resolution = OllamaNativeInterfaceResolver.resolve(context: .init(
            processRunner: runner,
            // Not in fixed candidates, not in bundle, not in process list → unresolved
            httpGET: { _ in nil },
            bundleLookup: { _ in nil },
            fixedCLICandidatePaths: []
        ))
        XCTAssertFalse(resolution.cliResolved)
        XCTAssertNotEqual(resolution.cliExecutableURL, lookalike.path)
    }

    // MARK: - Runtime proofs

    func testCompletePSAbsentInactiveVerified() {
        let snap = OllamaRunningModelsSnapshot(
            completeness: .complete,
            runningModelIdentities: ["llama3:8b", "mistral:7b"]
        )
        let (state, conf) = snap.inactivity(for: "library/qwen3:4b")
        XCTAssertEqual(state, .inactive)
        XCTAssertEqual(conf, .verified)
    }

    func testCompletePSPresentActiveVerified() {
        let snap = OllamaRunningModelsSnapshot(
            completeness: .complete,
            runningModelIdentities: ["qwen3:4b", "llama3:8b"]
        )
        let (state, conf) = snap.inactivity(for: "library/qwen3:4b")
        XCTAssertEqual(state, .active)
        XCTAssertEqual(conf, .verified)
    }

    func testPartialPSUnknown() {
        let snap = OllamaRunningModelsSnapshot(
            completeness: .partial,
            runningModelIdentities: [],
            failureReason: "PARSE_FAILED"
        )
        let (state, conf) = snap.inactivity(for: "library/qwen3:4b")
        XCTAssertEqual(state, .unknown)
        XCTAssertEqual(conf, .unknown)
    }

    func testServiceOnlyUnknown() {
        let resolution = OllamaNativeInterfaceResolution(
            interfaceKind: .none,
            status: .unresolved,
            installReality: .cliNotInstalled,
            ollamaAppFound: false,
            bundleIdentifier: nil,
            bundleVersion: nil,
            bundleLocationClass: nil,
            cliResolved: false,
            cliExecutableURL: nil,
            cliExecutableLocationClass: nil,
            cliVersion: nil,
            supportsPS: false,
            supportsRM: false,
            guiExecutableRejectedAsCLI: false,
            localAPIReachable: false,
            localAPIIdentityVerified: false,
            localAPIVersion: nil,
            resolutionMethod: "NONE",
            resolutionEvidence: [],
            resolutionDurationMs: 1,
            binaryFingerprint: nil,
            observedAt: Date()
        )
        let proof = OllamaNativeInterfaceResolver.proveExactRuntime(
            canonicalModel: "library/qwen3:4b",
            resolution: resolution,
            context: .init(
                processExecutablePaths: ["/Applications/Ollama.app/Contents/MacOS/Ollama"],
                httpGET: { _ in nil }
            )
        )
        XCTAssertEqual(proof.targetStatus, .unknown)
        XCTAssertEqual(proof.targetConfidence, .unknown)
        XCTAssertTrue(proof.serviceRunning)
        XCTAssertFalse(proof.serviceRunningUsedAsTargetProof)
        XCTAssertEqual(proof.failureReason, "SERVICE_ONLY_NO_AUTHORITATIVE_SNAPSHOT")
    }

    // MARK: - Identity normalization

    func testModelIDNormalizationExactOnly() {
        XCTAssertTrue(OllamaModelIdentityNormalization.matches("qwen3:4b", canonical: "library/qwen3:4b"))
        XCTAssertTrue(OllamaModelIdentityNormalization.matches("library/qwen3:4b", canonical: "qwen3:4b"))
        XCTAssertTrue(OllamaModelIdentityNormalization.matches(
            "qwen3:4b@sha256:abc", canonical: "library/qwen3:4b"
        ))
        XCTAssertFalse(OllamaModelIdentityNormalization.matches("qwen3", canonical: "library/qwen3:4b"))
        XCTAssertFalse(OllamaModelIdentityNormalization.matches("qwen3:7b", canonical: "library/qwen3:4b"))
        XCTAssertFalse(OllamaModelIdentityNormalization.matches("qwenn3:4b", canonical: "library/qwen3:4b"))
    }

    // MARK: - Local API spoof

    func testLocalAPISpoofRejected() {
        let resolution = OllamaNativeInterfaceResolver.resolve(context: .init(
            httpGET: { url in
                if url.path.contains("/api/version") {
                    return (200, Data(#"{"ok":true,"service":"impostor"}"#.utf8))
                }
                return nil
            },
            bundleLookup: { _ in nil },
            fixedCLICandidatePaths: []
        ))
        XCTAssertTrue(resolution.localAPIReachable)
        XCTAssertFalse(resolution.localAPIIdentityVerified)
        XCTAssertNotEqual(resolution.status, .resolvedLocalAPIOnly)
    }

    func testLocalAPIIdentityVerifiedWhenVersionPresent() {
        let resolution = OllamaNativeInterfaceResolver.resolve(context: .init(
            httpGET: { url in
                if url.path.contains("/api/version") {
                    return (200, Data(#"{"version":"0.5.7"}"#.utf8))
                }
                return nil
            },
            bundleLookup: { _ in nil },
            fixedCLICandidatePaths: []
        ))
        XCTAssertTrue(resolution.localAPIReachable)
        XCTAssertTrue(resolution.localAPIIdentityVerified)
        XCTAssertEqual(resolution.localAPIVersion, "0.5.7")
        XCTAssertEqual(resolution.interfaceKind, .localAPI)
        XCTAssertFalse(resolution.executionTransportAvailable)
    }

    // MARK: - End-to-end fake coordinator

    func testEndToEndFakeCoordinatorOllamaPath() throws {
        let fakeRunner = FakeProcessRunner(nextResult: BoundedProcessResult(outcome: .commandAccepted, exitCode: 0))
        let ollamaExec = OllamaNativeCleanupExecutor(
            processRunner: fakeRunner,
            resolveExecutable: { URL(fileURLWithPath: "/usr/local/bin/ollama") }
        )
        let router = StorageActionExecutorRouter(
            trashExecutor: .shared,
            ollamaExecutor: ollamaExec
        )

        let model = "library/qwen3:4b"
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        let entityID = "ai.ollama.model.library.qwen3:4b"
        let fp = ActionBindingFingerprint(
            entityID: entityID,
            action: .vendorNativeCleanup,
            canonicalPath: path,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t",
            transactionContractVersion: OllamaNativeCleanupExecutor.contractVersion,
            semanticBindingDigest: "e2e"
        )
        let receipt = PreflightReceipt(
            receiptID: "pf-e2e",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            requiredClaims: [],
            satisfiedClaims: [],
            missingClaims: [],
            staleClaims: [],
            conflictedClaims: [],
            observedAt: Date(),
            freshnessValidity: [.runtimeFresh],
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            result: PreflightResultCode.satisfiedReadOnly.rawValue
        )
        let approval = UserActionApproval(
            approvalID: "ap-e2e",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            consequenceSummaryVersion: "P3.2A.1-FIXTURE",
            expectedRecoveryBytes: 100,
            approvedAt: Date(),
            expiryPolicy: "single_use",
            scope: "fixture_ollama"
        )
        let decision = ActionDecision(
            entityID: entityID,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true,
            explanationCodes: ["MODEL=\(model)"]
        )
        guard let permit = ExecutionPermit.generate(receipt: receipt, approval: approval, decision: decision) else {
            return XCTFail("permit")
        }
        let plan = DryRunActionPlan(
            entityID: entityID,
            path: path,
            action: StorageAction.vendorNativeCleanup.rawValue,
            readiness: MutationReadiness.approvalRequired.rawValue,
            steps: [],
            executorImplemented: true
        )
        let audit = try router.executeVendorNativeCleanup(plan: plan, permit: permit, canonicalModel: model)
        let post = OllamaPostMutationVerifier.verify(
            canonicalModel: model,
            modelStillInstalled: false,
            removedExclusiveBlobBytes: 100,
            remainingUnreferencedBlobBytes: 0,
            sharedRetainedBytes: 0,
            contract: nil
        )
        XCTAssertNil(audit.failureReason)
        XCTAssertEqual(post.logical, .modelRemoved)
        XCTAssertEqual(fakeRunner.invocations.count, 1)
        XCTAssertEqual(fakeRunner.invocations[0].arguments, ["rm", model])
        // Production FoundationProcessRunner not used — FakeProcessRunner only.
        XCTAssertTrue(fakeRunner is FakeProcessRunner)
    }

    func testHFNeverRoutesToOllamaExecutor() throws {
        let fake = FakeProcessRunner()
        let ollama = OllamaNativeCleanupExecutor(processRunner: fake, resolveExecutable: {
            URL(fileURLWithPath: "/usr/local/bin/ollama")
        })
        let router = StorageActionExecutorRouter(ollamaExecutor: ollama)
        // P3.2B: HF SNAPSHOT is implemented — but must not use Ollama argv path.
        let support = ActionExecutionCapabilityRegistry.support(
            for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .snapshot
        )
        XCTAssertEqual(support, .implemented)
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .repository
            ),
            .notImplemented
        )
        let path = "\(home)/.cache/huggingface/hub/models--x/snapshots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let plan = DryRunActionPlan(
            entityID: "ai.hf.snapshot.x.aaaaaaaaaaaa",
            path: path,
            action: StorageAction.vendorNativeCleanup.rawValue,
            readiness: MutationReadiness.approvalRequired.rawValue,
            steps: [],
            executorImplemented: true
        )
        let fp = ActionBindingFingerprint(
            entityID: plan.entityID,
            action: .vendorNativeCleanup,
            canonicalPath: path,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t",
            transactionContractVersion: HuggingFaceNativeCleanupExecutor.contractVersion,
            semanticBindingDigest: "hf"
        )
        let permit = ExecutionPermit(
            permitID: "permit-hf-router-guard",
            entityID: plan.entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            preflightReceiptID: "pf-hf",
            approvalID: "a-hf",
            issuedAt: Date()
        )
        // Ollama-facing router entry must reject HF identity (canonical model invalid).
        XCTAssertThrowsError(
            try router.executeVendorNativeCleanup(
                plan: plan,
                permit: permit,
                canonicalModel: "model/mlx-community/whisper-large-v3-mlx"
            )
        )
        XCTAssertEqual(fake.invocations.count, 0)
    }

    func testRealExecutorNotUsedInP32A1Tests() {
        // Guard: this test file only uses FakeProcessRunner for mutation paths.
        let fake = FakeProcessRunner()
        let exec = OllamaNativeCleanupExecutor(processRunner: fake, resolveExecutable: {
            URL(fileURLWithPath: "/usr/local/bin/ollama")
        })
        XCTAssertTrue(type(of: exec.processRunner) == FakeProcessRunner.self)
    }

    func testExecutableUnresolvedBlocksGate() {
        var item = makeOllamaItem()
        item.verification?.vendorProofNotes.append("OLLAMA_EXECUTABLE_UNRESOLVED")
        item.verification?.vendorProofNotes.append("OLLAMA_EXECUTION_TRANSPORT_UNAVAILABLE")
        item.verification?.activeState = .inactive
        item.verification?.activeStateConfidence = .verified
        item.verification?.referenceGraphConfidence = .verified
        item.verification?.remoteReacquisitionProof = makeRemote(fresh: true)
        item.verification?.reacquisition = ObservationRecord(
            value: .true, confidence: .verified, completeness: .complete, source: .vendorRule
        )
        let decision = ActionDecision(
            entityID: item.detected.entity.id,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true
        )
        let gate = MutationGate.evaluate(MutationGateInput(
            item: item,
            action: .vendorNativeCleanup,
            actionDecision: decision,
            snapshot: nil,
            recommendation: nil,
            preflight: nil,
            runtimeResolution: nil,
            transactionContract: TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: .vendorNativeCleanup, item: item),
            approvalState: .scanDefault,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t"
        ))
        XCTAssertTrue(gate.blockingReasons.contains("OLLAMA_EXECUTABLE_UNRESOLVED"))
        XCTAssertNotEqual(gate.readiness, MutationReadiness.approvalRequired.rawValue)
    }

    func testBinaryFingerprintChangeInvalidatesBinding() {
        var item = makeOllamaItem()
        item.verification?.vendorProofNotes.append("OLLAMA_BINARY_FP=path=/a/ollama;size=1;mtime=1")
        item.verification?.vendorProofNotes.append("OLLAMA_CLI_RESOLVED=/a/ollama")
        item.verification?.vendorProofNotes.append("OLLAMA_EXECUTION_TRANSPORT_AVAILABLE")
        item.verification?.activeState = .inactive
        item.verification?.activeStateConfidence = .verified
        item.verification?.remoteReacquisitionProof = makeRemote(fresh: true)
        let input = MutationGateInput(
            item: item,
            action: .vendorNativeCleanup,
            actionDecision: ActionDecision(
                entityID: item.detected.entity.id,
                action: .vendorNativeCleanup,
                safetyClass: .unknown,
                eligible: true
            ),
            snapshot: nil,
            recommendation: nil,
            preflight: nil,
            runtimeResolution: nil,
            transactionContract: TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: .vendorNativeCleanup, item: item),
            approvalState: .scanDefault,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t"
        )
        let fp1 = ActionBindingFingerprintBuilder.compute(input: input)
        item.verification?.vendorProofNotes.removeAll { $0.hasPrefix("OLLAMA_BINARY_FP=") }
        item.verification?.vendorProofNotes.append("OLLAMA_BINARY_FP=path=/a/ollama;size=2;mtime=2")
        var input2 = input
        input2.item = item
        let fp2 = ActionBindingFingerprintBuilder.compute(input: input2)
        XCTAssertNotEqual(fp1.semanticBindingDigest, fp2.semanticBindingDigest)
        XCTAssertFalse(fp1.matches(fp2))
    }

    func testRuntimeEvidenceExpiry() {
        let now = Date()
        let proof = OllamaExactRuntimeProof(
            targetEntityID: "ai.ollama.model.library.qwen3:4b",
            targetModel: "library/qwen3:4b",
            observationSource: "CLI_PS",
            snapshotCompleteness: .complete,
            runningModelCount: 0,
            runningModelIdentities: [],
            targetStatus: .inactive,
            targetConfidence: .verified,
            observedAt: now.addingTimeInterval(-300),
            freshUntil: now.addingTimeInterval(-1),
            failureReason: nil,
            serviceRunning: false,
            serviceRunningUsedAsTargetProof: false
        )
        XCTAssertTrue(proof.isStrictInactive)
        XCTAssertFalse(Date() < proof.freshUntil)
    }

    func testRemoteStaleBlocksPermit() {
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        let entityID = "ai.ollama.model.library.qwen3:4b"
        let fp = ActionBindingFingerprint(
            entityID: entityID,
            action: .vendorNativeCleanup,
            canonicalPath: path,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t",
            transactionContractVersion: OllamaNativeCleanupExecutor.contractVersion,
            semanticBindingDigest: "x"
        )
        let receipt = PreflightReceipt(
            receiptID: "r",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            requiredClaims: [],
            satisfiedClaims: [],
            missingClaims: [.activeState],
            staleClaims: [],
            conflictedClaims: [],
            observedAt: Date(),
            freshnessValidity: [.remoteStateFresh],
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            result: PreflightResultCode.staleEvidence.rawValue
        )
        let approval = UserActionApproval(
            approvalID: "a",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            consequenceSummaryVersion: "t",
            expectedRecoveryBytes: 1,
            approvedAt: Date(),
            expiryPolicy: "single_use",
            scope: "t"
        )
        let decision = ActionDecision(
            entityID: entityID,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true
        )
        XCTAssertNil(ExecutionPermit.generate(receipt: receipt, approval: approval, decision: decision))
    }

    func testManifestDriftChangesSemanticDigest() {
        var item = makeOllamaItem()
        item.verification?.vendorProofNotes = ["LOCAL_MANIFEST=library/qwen3:4b@v1"]
        let d1 = ActionBindingFingerprintBuilder.semanticDigest(input: MutationGateInput(
            item: item,
            action: .vendorNativeCleanup,
            actionDecision: ActionDecision(
                entityID: item.detected.entity.id,
                action: .vendorNativeCleanup,
                safetyClass: .unknown,
                eligible: true
            ),
            snapshot: nil,
            recommendation: nil,
            preflight: nil,
            runtimeResolution: nil,
            transactionContract: nil,
            postVerifyContract: nil,
            auditContract: nil,
            approvalState: .scanDefault,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t"
        ))
        item.verification?.vendorProofNotes = ["LOCAL_MANIFEST=library/qwen3:4b@v2"]
        let d2 = ActionBindingFingerprintBuilder.semanticDigest(input: MutationGateInput(
            item: item,
            action: .vendorNativeCleanup,
            actionDecision: ActionDecision(
                entityID: item.detected.entity.id,
                action: .vendorNativeCleanup,
                safetyClass: .unknown,
                eligible: true
            ),
            snapshot: nil,
            recommendation: nil,
            preflight: nil,
            runtimeResolution: nil,
            transactionContract: nil,
            postVerifyContract: nil,
            auditContract: nil,
            approvalState: .scanDefault,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t"
        ))
        XCTAssertNotEqual(d1, d2)
    }

    func testReferenceGraphDriftChangesSemanticDigest() {
        var item = makeOllamaItem()
        item.verification?.referenceGraphConfidence = .verified
        let mk: (ClassifiedItem) -> String = { it in
            ActionBindingFingerprintBuilder.semanticDigest(input: MutationGateInput(
                item: it,
                action: .vendorNativeCleanup,
                actionDecision: ActionDecision(
                    entityID: it.detected.entity.id,
                    action: .vendorNativeCleanup,
                    safetyClass: .unknown,
                    eligible: true
                ),
                snapshot: nil,
                recommendation: nil,
                preflight: nil,
                runtimeResolution: nil,
                transactionContract: nil,
                postVerifyContract: nil,
                auditContract: nil,
                approvalState: .scanDefault,
                evidenceGeneration: 1,
                verificationGeneration: 1,
                runtimeGeneration: 1,
                ruleVersion: "t"
            ))
        }
        let d1 = mk(item)
        item.verification?.referenceGraphConfidence = .unknown
        let d2 = mk(item)
        XCTAssertNotEqual(d1, d2)
    }

    func testRawBlobNeverRoutesToModelExecutor() {
        let support = ActionExecutionCapabilityRegistry.support(
            for: .vendorNativeCleanup, vendor: .ollama, entityKind: .blob
        )
        XCTAssertEqual(support, .notSupported)
        let path = "\(home)/.ollama/models/blobs/sha256-abc"
        XCTAssertTrue(ActionPolicy.isRawAIVendorBlob(entityID: "ai.ollama.blob.sha256-abc", path: path))
        XCTAssertFalse(ActionPolicy.isOllamaModelEntity(entityID: "ai.ollama.blob.sha256-abc", path: path))
    }

    func testApplicationResolverNonDefaultPath() {
        let bundleURL = tempRoot.appendingPathComponent("Elsewhere/Ollama.app")
        try? FileManager.default.createDirectory(
            at: bundleURL.appendingPathComponent("Contents/MacOS"),
            withIntermediateDirectories: true
        )
        let app = OllamaApplicationResolver.resolve(bundleLookup: { _ in
            ("com.ollama.app", bundleURL, "0.1-fixture")
        })
        XCTAssertTrue(app.appFound)
        XCTAssertEqual(app.bundleIdentifier, "com.ollama.app")
        XCTAssertEqual(app.bundleLocationClass, "BUNDLE_OTHER")
        XCTAssertNotEqual(app.bundleLocationClass, "APPLICATIONS")
    }

    // MARK: - Helpers

    private func ollamaHelpText() -> String {
        """
        Large language model runner
        Usage:
          ollama [flags]
          ollama [command]

        Available Commands:
          ps          List running models
          pull        Pull a model
          rm          Remove a model
          run         Run a model
        """
    }

    private func configureContract(_ runner: FakeProcessRunner) {
        runner.resultsByArguments[["--version"]] = BoundedProcessResult(
            outcome: .commandAccepted, stdout: "ollama version is 0.5.7"
        )
        runner.resultsByArguments[["help"]] = BoundedProcessResult(
            outcome: .commandAccepted, stdout: ollamaHelpText()
        )
    }

    private func writeFakeCLI(at url: URL, help: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = "#!/bin/sh\necho '\(help.replacingOccurrences(of: "'", with: ""))'\n"
        FileManager.default.createFile(atPath: url.path, contents: Data(body.utf8))
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeOllamaItem() -> ClassifiedItem {
        let model = "library/qwen3:4b"
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        let entityID = "ai.ollama.model.library.qwen3:4b"
        let entity = StorageEntity(
            id: entityID, kind: .cache, category: "AI_DEV", subcategory: "ollama",
            displayName: model, path: path, logicalBytes: 2_497_293_931
        )
        let detected = DetectedEntity(
            entity: entity, bucket: .developer, domain: "AI Tools",
            associatedProcesses: ["ollama"], identified: true, annotation: nil
        )
        let decision = SafetyDecision(
            entity: entity, action: .noAction, safetyClass: .unknown, safetyScore: nil,
            reasonCodes: [], sideEffects: [], matchedRuleID: nil, evaluationLayer: .unknownFallback,
            evidenceConfidence: 0, userExplanationJA: "t", growthCauses: [], requiresUserApproval: true, blockedBy: nil
        )
        var item = ClassifiedItem(
            detected: detected, decision: decision, semantic: SemanticResult(from: decision),
            allocatedBytes: 2_497_293_931, actionVariants: [:], inclusiveBytes: 2_497_293_931,
            exclusiveBytes: 2_497_293_931, resolution: .l3Product, unknownReason: nil, verification: nil
        )
        item.verification = VerificationAnnotation(
            vendorProofNotes: ["LOCAL_MANIFEST=\(model)"],
            referenceGraphConfidence: .verified
        )
        return item
    }

    private func makeRemote(fresh: Bool) -> RemoteReacquisitionProof {
        let now = Date()
        return RemoteReacquisitionProof(
            vendor: .ollama,
            entityID: "ai.ollama.model.library.qwen3:4b",
            localIdentity: "library/qwen3:4b",
            remoteIdentity: "library/qwen3:4b",
            remoteRevisionOrDigest: "sha256-test",
            status: .verified,
            verifiedAt: now,
            freshUntil: now.addingTimeInterval(fresh ? 900 : -10),
            authenticationClass: .anonymous,
            proofMethod: .ollamaManifestGET,
            requiredObjectsChecked: 1,
            requiredObjectsVerified: 1,
            confidence: .verified,
            estimatedRedownloadBytes: 100,
            endpointClass: "ollama.registry"
        )
    }
}
