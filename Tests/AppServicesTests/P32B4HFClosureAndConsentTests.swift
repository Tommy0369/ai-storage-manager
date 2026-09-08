import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P32B4HFClosureAndConsentTests: XCTestCase {
    private let repo = "mlx-community/whisper-large-v3-mlx"
    private let revision = "49e6aa286ad60c14352c404340ded53710378a11"
    private let entityID = "ai.hf.snapshot.mlx-community.whisper-large-v3-mlx.49e6aa286ad6"
    private let verified: Int64 = 3_083_520_968
    private let diskFree: Int64 = 3_083_640_832
    private let vendorApprox: Int64 = 3_100_000_000

    override func setUp() {
        super.setUp()
        ExecutionPermitLedger.reset()
    }

    // MARK: - CLI consent contract

    func testConfirmWithoutExactFlagsRejected() {
        XCTAssertEqual(
            HuggingFaceCLIConsentContract.validateExecuteArguments(
                ["execute-hf", "--confirm"],
                authorizedRepo: repo,
                authorizedRevision: revision
            ),
            .failure(.missingRepo)
        )
        XCTAssertEqual(
            HuggingFaceCLIConsentContract.validateExecuteArguments(
                ["execute-hf", "--confirm", "--repo", repo],
                authorizedRepo: repo,
                authorizedRevision: revision
            ),
            .failure(.repoOnly)
        )
    }

    func testConfirmWithoutConfirmRejected() {
        XCTAssertEqual(
            HuggingFaceCLIConsentContract.validateExecuteArguments(
                ["execute-hf", "--repo", repo, "--revision", revision],
                authorizedRepo: repo,
                authorizedRevision: revision
            ),
            .failure(.missingConfirm)
        )
    }

    func testConfirmAllRejected() {
        XCTAssertEqual(
            HuggingFaceCLIConsentContract.validateExecuteArguments(
                ["execute-hf", "--confirm", "--all", "--repo", repo, "--revision", revision],
                authorizedRepo: repo,
                authorizedRevision: revision
            ),
            .failure(.wildcardAll)
        )
    }

    func testConfirmCannotPrune() {
        XCTAssertEqual(
            HuggingFaceCLIConsentContract.validateExecuteArguments(
                ["execute-hf", "--confirm", "--repo", repo, "--revision", revision, "prune"],
                authorizedRepo: repo,
                authorizedRevision: revision
            ),
            .failure(.pruneFlag)
        )
        XCTAssertFalse(HuggingFaceCLIConsentContract.pruneAllowed)
    }

    func testConfirmCannotHubDelete() {
        XCTAssertEqual(
            HuggingFaceCLIConsentContract.validateExecuteArguments(
                ["execute-hf", "--confirm", "--repo", repo, "--revision", revision, "--hub-delete"],
                authorizedRepo: repo,
                authorizedRevision: revision
            ),
            .failure(.hubDeleteFlag)
        )
        XCTAssertFalse(HuggingFaceCLIConsentContract.hubDeleteAllowed)
    }

    func testConfirmWrongRevisionRejected() {
        XCTAssertEqual(
            HuggingFaceCLIConsentContract.validateExecuteArguments(
                ["execute-hf", "--confirm", "--repo", repo, "--revision", String(repeating: "a", count: 40)],
                authorizedRepo: repo,
                authorizedRevision: revision
            ),
            .failure(.targetMismatch)
        )
    }

    func testConfirmValidExactTargetAcceptedAsArgvOnly() {
        let r = HuggingFaceCLIConsentContract.validateExecuteArguments(
            ["execute-hf", "--confirm", "--repo", repo, "--revision", revision],
            authorizedRepo: repo,
            authorizedRevision: revision
        )
        guard case .success(let t) = r else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(t.repo, repo)
        XCTAssertEqual(t.revision, revision)
        // Argv success ≠ approval bypass
        XCTAssertTrue(HuggingFaceCLIConsentContract.canonicalApprovalRequired)
        XCTAssertTrue(HuggingFaceCLIConsentContract.freshPreflightRequired)
        XCTAssertFalse(HuggingFaceCLIConsentContract.executorDirectBypassPossible)
        XCTAssertFalse(HuggingFaceCLIConsentContract.strictUnknownCanBeOverridden)
    }

    func testStrictUnknownCannotBeOverriddenByConfirm() {
        XCTAssertFalse(HuggingFaceCLIConsentContract.strictUnknownCanBeOverridden)
    }

    // MARK: - Remote ≠ local candidate

    func testRemoteAvailableDoesNotCreateLocalCandidate() {
        XCTAssertFalse(
            HuggingFaceLocalCandidatePolicy.mayCreateVendorNativeCleanupCandidate(
                localSnapshotPresent: false,
                remoteExactRevisionAvailable: true
            )
        )
        XCTAssertTrue(
            HuggingFaceLocalCandidatePolicy.mayCreateVendorNativeCleanupCandidate(
                localSnapshotPresent: true,
                remoteExactRevisionAvailable: false
            )
        )
    }

    func testCompletedEntityNotActionableWhenAbsent() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let snap = "\(home)/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-mlx/snapshots/\(revision)"
        let present = FileManager.default.fileExists(atPath: snap)
        XCTAssertFalse(present, "live post-B3 state must keep removed revision absent")
        XCTAssertFalse(
            HuggingFaceLocalCandidatePolicy.mayCreateVendorNativeCleanupCandidate(
                localSnapshotPresent: present,
                remoteExactRevisionAvailable: true
            )
        )
    }

    // MARK: - Verified recovery presentation

    func testVerifiedRecoveryPrimaryNotDiskDelta() {
        let exec = sampleSuccessReport(diskDelta: diskFree)
        let result = VerifiedActionResultBuilder.fromHuggingFaceExecution(exec, remoteStillAvailable: true)
        XCTAssertEqual(result.verifiedRecoveredBytes, verified)
        XCTAssertEqual(result.observedDiskFreeDelta, diskFree)
        XCTAssertNotEqual(result.verifiedRecoveredBytes, result.observedDiskFreeDelta)
        XCTAssertTrue(result.userLines.contains(where: { $0.contains("3.08 GB") }))
        XCTAssertFalse(result.userHeadline.lowercased().contains("deleted model from hugging face"))
    }

    func testLargerDiskDeltaDoesNotBecomeCanonical() {
        let exec = sampleSuccessReport(diskDelta: 4_000_000_000)
        let result = VerifiedActionResultBuilder.fromHuggingFaceExecution(exec)
        XCTAssertEqual(result.verifiedRecoveredBytes, verified)
        XCTAssertEqual(result.observedDiskFreeDelta, 4_000_000_000)
        XCTAssertTrue(result.userLines.contains(where: { $0.contains("3.08 GB verified") }))
    }

    func testVendorTelemetryFormattingNotConflict() {
        XCTAssertTrue(
            VendorPreviewOutcomeComparison.sizeSemanticsCompatible(
                vendorReportedApprox: vendorApprox,
                verifiedRecovered: verified
            )
        )
        let cmp = VendorPreviewOutcomeComparison.forP32B3RealAction()
        XCTAssertTrue(cmp.sizeSemanticsCompatible)
        XCTAssertTrue(cmp.logicalConsequenceMatched)
        XCTAssertFalse(cmp.unexpectedEffects)
    }

    func testLastRevisionConsequenceMatched() {
        let exec = sampleSuccessReport(diskDelta: diskFree)
        let result = VerifiedActionResultBuilder.fromHuggingFaceExecution(exec)
        XCTAssertEqual(result.lastRevisionConsequence, "SOLE_REVISION_EMPTIED_LOCAL_REPO_CACHE")
        let cmp = VendorPreviewOutcomeComparison.forP32B3RealAction()
        XCTAssertTrue(cmp.repoRemovalConsequenceMatch)
        XCTAssertTrue(cmp.actualRepoRemoved)
    }

    func testMultiRevisionFixtureDoesNotRequireRepoAbsence() {
        let cmp = VendorPreviewOutcomeComparison.forMultiRevisionFixture(verifiedRecovered: 1_000)
        XCTAssertTrue(cmp.logicalConsequenceMatched)
        XCTAssertFalse(cmp.actualRepoRemoved)
        XCTAssertFalse(cmp.previewRepoRemovalExpected)
    }

    // MARK: - History survives entity disappearance

    func testHistoryEventSurvivesEntityAbsence() {
        let exec = sampleSuccessReport(diskDelta: diskFree)
        let result = VerifiedActionResultBuilder.fromHuggingFaceExecution(exec)
        let event = VerifiedActionResultBuilder.toHistoryEvent(result)
        XCTAssertEqual(event.entityID, entityID)
        XCTAssertTrue(event.eligibleForFutureSnapshotCorrelation)
        XCTAssertTrue(
            VerifiedActionResultBuilder.canCorrelate(
                event: event,
                entityID: entityID,
                action: .vendorNativeCleanup,
                permitID: event.permitID
            )
        )
        XCTAssertFalse(VerifiedActionResultBuilder.timestampOnlyCorrelationAllowed)
    }

    func testTimestampOnlyCorrelationBlocked() {
        let event = VerifiedStorageActionEvent(
            actionEventID: "other",
            entityID: "different.entity",
            action: .vendorNativeCleanup,
            executedAt: Date(),
            logicalOutcome: "SNAPSHOT_REMOVED",
            recoveryOutcome: "ACTION_COMPLETED_RECOVERY_VERIFIED",
            verifiedRecoveredBytes: verified,
            permitID: "permit-x",
            eligibleForFutureSnapshotCorrelation: true
        )
        XCTAssertFalse(
            VerifiedActionResultBuilder.canCorrelate(
                event: event,
                entityID: entityID,
                action: .vendorNativeCleanup,
                permitID: "permit-x"
            )
        )
    }

    func testUnknownOutcomeUXNoRetry() {
        var exec = sampleSuccessReport(diskDelta: nil)
        exec.logicalRemovalVerified = false
        exec.outcome = "UNKNOWN"
        exec.processOutcome = "UNKNOWN_OUTCOME"
        exec.recoveryStatus = nil
        exec.postVerifyStatus = nil
        exec.repoPresentAfter = nil
        let result = VerifiedActionResultBuilder.fromHuggingFaceExecution(exec)
        XCTAssertEqual(result.storageRecoveryOutcome, .outcomeUnknown)
        XCTAssertTrue(result.userHeadline.contains("Could not verify"))
        XCTAssertTrue(result.userLines.contains(where: { $0.contains("Re-check") }))
        XCTAssertFalse(result.userLines.contains(where: { $0.lowercased().contains("try again") }))
    }

    func testCompletedRecoveryTotalArithmetic() {
        XCTAssertEqual(
            VerifiedActionResultBuilder.completedVerifiedRecoveryTotal(),
            5_580_814_899
        )
    }

    func testHFBlobAndRepoWideStillBlocked() {
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .blob
            ),
            .notSupported
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .repository
            ),
            .notImplemented
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .snapshot
            ),
            .implemented
        )
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToTrash), .implemented)
    }

    func testHostNativeBrewPathRegression() {
        let path = "/opt/homebrew/bin/hf"
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
        XCTAssertNotEqual(path, "/usr/local/bin/hf")
    }

    func testQwen3StillAbsent() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testReceiptChecklistHF() {
        let exec = sampleSuccessReport(diskDelta: diskFree)
        let result = VerifiedActionResultBuilder.fromHuggingFaceExecution(exec)
        let list = VerifiedActionResultBuilder.receiptChecklist(from: result)
        XCTAssertTrue(list.contains(where: { $0.contains("Native Hugging Face") }))
        XCTAssertTrue(list.contains(where: { $0.contains("3.08 GB") }))
        XCTAssertTrue(list.contains(where: { $0.contains("Hub revision remains") }))
    }

    func testApprovalOriginModelShared() {
        XCTAssertEqual(UserActionApprovalOrigin.cliExplicitHumanConfirmation.rawValue, "CLI_EXPLICIT_HUMAN_CONFIRMATION")
        XCTAssertEqual(UserActionApprovalOrigin.ui.rawValue, "UI")
        XCTAssertEqual(UserActionApprovalOrigin.api.rawValue, "API")
    }

    func testConfirmWithoutPreflightAbortsViaOrchestratorWhenSnapshotGone() throws {
        // Live post-B3: snapshot absent → product path aborts before executor mutation.
        // Proves --confirm alone cannot force execution without valid present-state preflight/before.
        let kb = try loadKB()
        let engine = SafetyRuleEngine(knowledge: kb)
        let report = try ActExecutionOrchestrator.executeHuggingFaceRevisionCleanup(
            .init(
                authorizationText: HuggingFaceNativePostMutationProbe.authorizationText,
                humanConfirmed: true,
                expectedRecoveryBytes: verified,
                engine: engine,
                processRunner: FakeProcessRunner()
            )
        )
        XCTAssertEqual(report.outcome, "ABORTED")
        XCTAssertFalse(report.executorInvoked || report.realMutationExecuted)
        XCTAssertTrue(
            report.abortReason == "SNAPSHOT_NOT_PRESENT_BEFORE"
                || (report.abortReason?.contains("FINAL_PREFLIGHT") == true)
                || (report.abortReason?.contains("STRICT") == true)
                || (report.abortReason?.contains("PERMIT") == true)
                || (report.abortReason?.contains("EXECUTABLE") == true)
                || (report.abortReason?.contains("AUTHORIZATION") == true)
        )
        // No second real mutation
        XCTAssertEqual(report.verifiedRecoveredBytes, 0)
    }

    // MARK: - Fixtures

    private func sampleSuccessReport(diskDelta: Int64?) -> ActExecutionOrchestrator.HuggingFaceNativeExecutionReport {
        ActExecutionOrchestrator.HuggingFaceNativeExecutionReport(
            phase: "P3.2B.3",
            outcome: "SNAPSHOT_REMOVED_STORAGE_RECOVERED",
            entityID: entityID,
            repoID: repo,
            revision: revision,
            action: StorageAction.vendorNativeCleanup.rawValue,
            authorizationTextFingerprint: "fp",
            approvalID: "human-approval-hf-TEST",
            approvalConsumed: true,
            approvalBindingValid: true,
            finalPreflightReceiptID: "fresh-preflight-test",
            finalPreflightReadiness: "APPROVAL_REQUIRED",
            canonicalActionDecisionEligible: true,
            strictUnknownCount: 0,
            strictConflictCount: 0,
            permitID: "permit-hf-test",
            permitConsumed: true,
            executorInvoked: true,
            argvContract: ["cache", "rm", revision, "--yes", "--cache-dir", "/tmp/hf"],
            shellUsed: false,
            rawDeleteFallback: false,
            hubRemoteDeletion: false,
            pruneUsed: false,
            processOutcome: "COMMAND_ACCEPTED",
            realMutationExecuted: true,
            snapshotPresentBefore: true,
            snapshotPresentAfter: false,
            repoPresentAfter: false,
            logicalRemovalVerified: true,
            potentialRecoveryBytesBefore: verified,
            verifiedRecoveredBytes: verified,
            diskFreeDeltaBytes: diskDelta,
            recoveryStatus: "SNAPSHOT_REMOVED_STORAGE_RECOVERED",
            postVerifyStatus: "SNAPSHOT_REMOVED",
            binaryFingerprint: "path=/opt/homebrew/bin/hf",
            cliExecutablePath: "/opt/homebrew/bin/hf",
            auditRecord: nil,
            postVerify: HuggingFacePostMutationVerifier.Result(
                logical: .snapshotRemoved,
                storage: .recovered,
                verifiedRecoveredBytes: verified,
                vendorReportedFreedBytes: vendorApprox,
                diskFreeDelta: diskDelta,
                revisionStillPresent: false,
                repoDirectoryStillPresent: false,
                notes: []
            ),
            executionMs: 1,
            abortReason: nil,
            humanConfirmed: true,
            explanation: "Exact local HF cached revision removed; Hub untouched",
            dryRunPreviewFingerprint: "preview-fp",
            scope: "LOCAL_HF_HUB_CACHE_REVISION_ONLY"
        )
    }

    private func loadKB() throws -> KnowledgeBaseDocument {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = cwd.appendingPathComponent("knowledge/compiled/compiled_rules_v0.1.json")
        return try KnowledgeBaseLoader().load(from: url)
    }
}
