import Foundation
import XCTest
@testable import SafetyCore
@testable import AppServices

final class P32BHuggingFaceNativeCleanupTests: XCTestCase {
    private let revision = "49e6aa286ad60c14352c404340ded53710378a11"
    private let repo = "mlx-community/whisper-large-v3-mlx"
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private var cacheRoot: String { "\(home)/.cache/huggingface/hub" }
    private var snapshotPath: String {
        "\(cacheRoot)/models--mlx-community--whisper-large-v3-mlx/snapshots/\(revision)"
    }
    private let entityID = "ai.hf.snapshot.mlx-community.whisper-large-v3-mlx.49e6aa286ad6"

    override func setUp() {
        super.setUp()
        ExecutionPermitLedger.reset()
    }

    func testCapabilityHFSnapshotImplementedOllamaPreserved() {
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
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .blob
            ),
            .notSupported
        )
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .ollama, entityKind: .model
            ),
            .implemented
        )
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToTrash), .implemented)
    }

    func testRevisionOnlyArgvExactShape() throws {
        let args = try HuggingFaceRevisionIdentity.rmArguments(
            revision: revision,
            cacheRoot: cacheRoot,
            dryRun: false,
            yes: true
        )
        XCTAssertEqual(args, [
            "cache", "rm", revision, "--yes", "--cache-dir", cacheRoot
        ])
    }

    func testDryRunArgvNoYes() throws {
        let args = try HuggingFaceRevisionIdentity.rmArguments(
            revision: revision,
            cacheRoot: cacheRoot,
            dryRun: true,
            yes: false
        )
        XCTAssertEqual(args, [
            "cache", "rm", revision, "--dry-run", "--cache-dir", cacheRoot
        ])
        XCTAssertFalse(args.contains("--yes"))
        XCTAssertFalse(args.contains("prune"))
    }

    func testRejectRepoWideAndInjection() {
        XCTAssertThrowsError(
            try HuggingFaceRevisionIdentity.validateOrThrow("model/mlx-community/whisper-large-v3-mlx")
        )
        XCTAssertThrowsError(try HuggingFaceRevisionIdentity.validateOrThrow("abc;rm -rf /"))
        XCTAssertThrowsError(try HuggingFaceRevisionIdentity.validateOrThrow("-rf"))
        XCTAssertThrowsError(try HuggingFaceRevisionIdentity.validateOrThrow("main"))
        XCTAssertFalse(
            ActionExecutionPolicy.allowsHuggingFaceNativeCleanup(
                entityID: entityID,
                path: snapshotPath,
                revision: "model/mlx-community/whisper-large-v3-mlx",
                cacheRoot: cacheRoot
            )
        )
    }

    func testExecutorExactArgvViaFakeRunner() throws {
        let fake = FakeProcessRunner(nextResult: .init(outcome: .commandAccepted, exitCode: 0))
        let exe = URL(fileURLWithPath: "/tmp/fake-hf")
        let executor = HuggingFaceNativeCleanupExecutor(
            processRunner: fake,
            resolveExecutable: { exe }
        )
        let (plan, permit) = try makePermitBundle()
        let audit = try executor.execute(
            plan: plan,
            permit: permit,
            revision: revision,
            cacheRoot: cacheRoot
        )
        XCTAssertEqual(fake.invocations.count, 1)
        XCTAssertEqual(fake.invocations[0].executablePath, exe.path)
        XCTAssertEqual(fake.invocations[0].arguments, [
            "cache", "rm", revision, "--yes", "--cache-dir", cacheRoot
        ])
        XCTAssertNil(audit.failureReason)
        XCTAssertTrue(audit.notes.contains(where: { $0.contains("NATIVE_ARGV=hf cache rm") }))
    }

    func testExecutorRejectsSecondPermitUse() throws {
        let fake = FakeProcessRunner()
        let executor = HuggingFaceNativeCleanupExecutor(
            processRunner: fake,
            resolveExecutable: { URL(fileURLWithPath: "/tmp/fake-hf") }
        )
        let (plan, permit) = try makePermitBundle(permitID: "permit-hf-reuse")
        _ = try executor.execute(plan: plan, permit: permit, revision: revision, cacheRoot: cacheRoot)
        XCTAssertThrowsError(
            try executor.execute(plan: plan, permit: permit, revision: revision, cacheRoot: cacheRoot)
        )
        XCTAssertEqual(fake.invocations.count, 1)
    }

    func testDryRunPreviewIncompleteWithoutCLI() {
        let inv = sampleInventory(revisions: [revision], shared: 0)
        let iface = unresolvedInterface()
        let preview = HuggingFaceCacheDryRunPreviewer.preview(inventory: inv, interface: iface)
        XCTAssertFalse(preview.previewComplete)
        XCTAssertEqual(preview.targetedRevisionCount, 1)
        XCTAssertTrue(preview.expectedRepoDirectoryRemoval)
        XCTAssertFalse(preview.dryRunMutationDetected)
    }

    func testDryRunVendorCompleteWithFakeCLI() {
        let hub = FileManager.default.temporaryDirectory
            .appendingPathComponent("p32b-dry-\(UUID().uuidString)/.cache/huggingface/hub")
        let snap = hub
            .appendingPathComponent("models--mlx-community--whisper-large-v3-mlx/snapshots/\(revision)")
        try? FileManager.default.createDirectory(at: snap, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(
                at: hub.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            )
        }
        let inv = HuggingFaceCacheDryRunPreviewer.captureLocalInventory(
            repoID: repo,
            revision: revision,
            itemPath: snap.path,
            uniqueBytes: 3_083_520_968,
            sharedBytes: 0
        )
        let fake = FakeProcessRunner(nextResult: .init(
            outcome: .commandAccepted,
            exitCode: 0,
            stdout: "Would delete revision \(revision) (3.08 GB)\n"
        ))
        let iface = resolvedInterface()
        let preview = HuggingFaceCacheDryRunPreviewer.preview(
            inventory: inv,
            interface: iface,
            processRunner: fake
        )
        XCTAssertEqual(fake.invocations.first?.arguments, [
            "cache", "rm", revision, "--dry-run", "--cache-dir", inv.cacheRoot
        ])
        XCTAssertTrue(preview.previewComplete)
        XCTAssertEqual(preview.targetedRevisionCount, 1)
    }

    func testMultiRevisionDoesNotExpectRepoRemoval() {
        let other = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let inv = sampleInventory(revisions: [revision, other], shared: 500)
        let preview = HuggingFaceCacheDryRunPreviewer.preview(
            inventory: inv,
            interface: unresolvedInterface()
        )
        XCTAssertFalse(preview.expectedRepoDirectoryRemoval)
        XCTAssertEqual(preview.revisionCountBefore, 2)
        XCTAssertTrue(preview.warnings.contains(where: { $0.contains("OTHER_REVISIONS_RETAINED") }))
    }

    func testUserOriginalPathBlocked() {
        XCTAssertFalse(
            ActionExecutionPolicy.allowsHuggingFaceNativeCleanup(
                entityID: "ai.hf.snapshot.custom",
                path: "\(home)/Documents/my-model/snapshots/\(revision)",
                revision: revision,
                cacheRoot: "\(home)/Documents/my-model"
            )
        )
    }

    func testPostVerifyAbsentSnapshot() {
        let result = HuggingFacePostMutationVerifier.verify(
            revision: revision,
            snapshotPath: "/tmp/definitely-missing-hf-snap-\(UUID().uuidString)",
            repoPath: "/tmp/definitely-missing-hf-repo-\(UUID().uuidString)",
            beforeUniqueBytes: 3_083_520_968,
            afterUniqueBytes: 0,
            vendorReportedFreed: 3_000_000_000,
            diskFreeDelta: 3_000_000_000
        )
        XCTAssertEqual(result.logical, .snapshotRemoved)
        XCTAssertEqual(result.storage, .recovered)
        XCTAssertEqual(result.verifiedRecoveredBytes, 3_083_520_968)
    }

    func testStrictUnknownBlocksApprovalBoundary() {
        let item = makeHFItem(notes: [
            "HF_CACHE_ROOT=\(cacheRoot)",
            "LOCAL_HF_CACHE_OWNERSHIP_VERIFIED",
            "HF_EXECUTABLE_UNRESOLVED",
            "HF_DRY_RUN_INCOMPLETE",
        ], active: .unknown, activeConf: .unknown, remoteStrict: true)
        let decision = ActionDecision(
            entityID: item.detected.entity.id,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true,
            explanationCodes: []
        )
        let snap = ActionSpecificSafetyAligner.alignHuggingFaceVendorNative(
            item: item,
            decision: decision,
            gate: nil
        )
        XCTAssertFalse(snap.unknownStrictPredicates.isEmpty)
        XCTAssertFalse(snap.isCanonicallyEligibleForApprovalBoundary)
    }

    func testIdentityHelpersFromPath() {
        let item = makeHFItem(notes: [], active: .unknown, activeConf: .unknown, remoteStrict: false)
        XCTAssertTrue(ActionPolicy.isHuggingFaceSnapshotEntity(item))
        XCTAssertEqual(ActionPolicy.huggingFaceRepoID(from: item), repo)
        XCTAssertEqual(ActionPolicy.huggingFaceRevision(from: item), revision)
    }

    // MARK: - Helpers

    private func makePermitBundle(permitID: String = "permit-hf-1") throws -> (DryRunActionPlan, ExecutionPermit) {
        let fp = ActionBindingFingerprint(
            entityID: entityID,
            action: .vendorNativeCleanup,
            canonicalPath: snapshotPath,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "t",
            transactionContractVersion: HuggingFaceNativeCleanupExecutor.contractVersion,
            semanticBindingDigest: "hf-digest"
        )
        let receipt = PreflightReceipt(
            receiptID: "r-hf",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            requiredClaims: [],
            satisfiedClaims: [],
            missingClaims: [],
            staleClaims: [],
            conflictedClaims: [],
            observedAt: Date(),
            freshnessValidity: [.runtimeFresh, .remoteStateFresh],
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            result: PreflightResultCode.satisfiedReadOnly.rawValue
        )
        let approval = UserActionApproval(
            approvalID: "a-hf",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: fp,
            consequenceSummaryVersion: "P3.2B",
            expectedRecoveryBytes: 3_083_520_968,
            approvedAt: Date(),
            expiryPolicy: "single_use",
            scope: "hf_revision:\(revision)"
        )
        let decision = ActionDecision(
            entityID: entityID,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true,
            explanationCodes: ["REVISION=\(revision)"]
        )
        guard let permit = ExecutionPermit.generate(receipt: receipt, approval: approval, decision: decision) else {
            XCTFail("permit generation failed")
            throw ActionExecutionError.permitDenied("test")
        }
        // Override ID for reuse tests via ledger — generate already registered? consume uses permitID.
        // Re-issue with known ID by constructing directly after generate succeeded (eligibility proven).
        let bound = ExecutionPermit(
            permitID: permitID,
            entityID: permit.entityID,
            action: permit.action,
            bindingFingerprint: permit.bindingFingerprint,
            preflightReceiptID: permit.preflightReceiptID,
            approvalID: permit.approvalID,
            issuedAt: permit.issuedAt
        )
        let plan = DryRunActionPlan(
            entityID: entityID,
            path: snapshotPath,
            action: StorageAction.vendorNativeCleanup.rawValue,
            readiness: MutationReadiness.approvalRequired.rawValue,
            steps: [],
            executorImplemented: true
        )
        return (plan, bound)
    }

    private func sampleInventory(revisions: [String], shared: Int64) -> HuggingFaceCacheDryRunPreviewer.LocalRevisionInventory {
        HuggingFaceCacheDryRunPreviewer.LocalRevisionInventory(
            cacheRoot: cacheRoot,
            repoID: repo,
            repoType: "model",
            revisions: revisions,
            refs: ["main": revision],
            snapshotPresent: true,
            targetRevision: revision,
            uniqueBytes: 3_083_520_968,
            sharedBytes: shared,
            exclusiveBlobCount: shared == 0 ? 1 : 1,
            sharedBlobCount: shared > 0 ? 1 : 0,
            fingerprint: "fp",
            observedAt: Date()
        )
    }

    private func unresolvedInterface() -> HuggingFaceNativeInterfaceResolution {
        HuggingFaceNativeInterfaceResolution(
            status: .unresolved,
            cliResolved: false,
            cliExecutableURL: nil,
            cliVersion: nil,
            supportsCacheLS: false,
            supportsCacheVerify: false,
            supportsCacheRM: false,
            supportsDryRun: false,
            supportsCacheDir: false,
            supportsYes: false,
            binaryFingerprint: nil,
            resolutionMethod: "NONE",
            resolvedAt: Date(),
            failureReason: "HF_CLI_UNRESOLVED",
            evidence: []
        )
    }

    private func resolvedInterface() -> HuggingFaceNativeInterfaceResolution {
        HuggingFaceNativeInterfaceResolution(
            status: .resolvedCLI,
            cliResolved: true,
            cliExecutableURL: "/tmp/fake-hf",
            cliVersion: "hf 1.0",
            supportsCacheLS: true,
            supportsCacheVerify: true,
            supportsCacheRM: true,
            supportsDryRun: true,
            supportsCacheDir: true,
            supportsYes: true,
            binaryFingerprint: "fp",
            resolutionMethod: "TEST",
            resolvedAt: Date(),
            failureReason: nil,
            evidence: []
        )
    }

    private func makeHFItem(
        notes: [String],
        active: ObservedActiveState,
        activeConf: EvidenceConfidence,
        remoteStrict: Bool
    ) -> ClassifiedItem {
        let entity = StorageEntity(
            id: entityID, kind: .cache, category: "AI_DEV", subcategory: "huggingface",
            displayName: "\(repo)@\(String(revision.prefix(12)))",
            path: snapshotPath, logicalBytes: 3_083_520_968
        )
        let detected = DetectedEntity(
            entity: entity, bucket: .developer, domain: "AI Tools",
            associatedProcesses: [], identified: true, annotation: nil
        )
        let safety = SafetyDecision(
            entity: entity, action: .noAction, safetyClass: .unknown, safetyScore: nil,
            reasonCodes: [], sideEffects: [], matchedRuleID: nil, evaluationLayer: .unknownFallback,
            evidenceConfidence: 0, userExplanationJA: "t", growthCauses: [], requiresUserApproval: true, blockedBy: nil
        )
        var item = ClassifiedItem(
            detected: detected, decision: safety, semantic: SemanticResult(from: safety),
            allocatedBytes: 3_083_520_968, actionVariants: [:], inclusiveBytes: 3_083_520_968,
            exclusiveBytes: 3_083_520_968, resolution: .l3Product, unknownReason: nil, verification: nil
        )
        var v = VerificationAnnotation()
        v.vendorProofNotes = notes + ["HF_REVISION=\(revision)"]
        v.referenceGraphConfidence = .verified
        v.uniqueBytesProven = 3_083_520_968
        v.sharedBytesProven = 0
        v.activeState = active
        v.activeStateConfidence = activeConf
        if remoteStrict {
            v.remoteReacquisitionProof = RemoteReacquisitionProof(
                vendor: .huggingFace,
                entityID: entityID,
                localIdentity: "\(repo)@\(revision)",
                remoteIdentity: repo,
                remoteRevisionOrDigest: revision,
                status: .verified,
                verifiedAt: Date(),
                freshUntil: Date().addingTimeInterval(3600),
                authenticationClass: .anonymous,
                proofMethod: .hfRevisionAPI,
                requiredObjectsChecked: 1,
                requiredObjectsVerified: 1,
                confidence: .verified,
                estimatedRedownloadBytes: 3_083_520_968,
                endpointClass: "huggingface.hub"
            )
        }
        item.verification = v
        return item
    }
}
