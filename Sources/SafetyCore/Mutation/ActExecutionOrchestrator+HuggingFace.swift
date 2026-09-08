import Foundation

/// P3.2B.3 — HF SNAPSHOT × VENDOR_NATIVE_CLEANUP product-path orchestration.
extension ActExecutionOrchestrator {
    public struct HuggingFaceExecuteInput: Sendable {
        public var authorizationText: String
        public var humanConfirmed: Bool
        public var expectedRecoveryBytes: Int64
        public var engine: SafetyRuleEngine
        public var executor: any StorageActionExecutor
        public var processRunner: any BoundedProcessRunner

        public init(
            authorizationText: String = HuggingFaceNativePostMutationProbe.authorizationText,
            humanConfirmed: Bool,
            expectedRecoveryBytes: Int64 = HuggingFaceNativePostMutationProbe.expectedUniqueBytes,
            engine: SafetyRuleEngine,
            executor: any StorageActionExecutor = StorageActionExecutorRouter(),
            processRunner: any BoundedProcessRunner = FoundationProcessRunner()
        ) {
            self.authorizationText = authorizationText
            self.humanConfirmed = humanConfirmed
            self.expectedRecoveryBytes = expectedRecoveryBytes
            self.engine = engine
            self.executor = executor
            self.processRunner = processRunner
        }
    }

    public struct HuggingFaceNativeExecutionReport: Codable, Sendable, Equatable {
        public var phase: String
        public var outcome: String
        public var entityID: String
        public var repoID: String
        public var revision: String
        public var action: String
        public var authorizationTextFingerprint: String
        public var approvalID: String?
        public var approvalConsumed: Bool
        public var approvalBindingValid: Bool
        public var finalPreflightReceiptID: String?
        public var finalPreflightReadiness: String?
        public var canonicalActionDecisionEligible: Bool
        public var strictUnknownCount: Int
        public var strictConflictCount: Int
        public var permitID: String?
        public var permitConsumed: Bool
        public var executorInvoked: Bool
        public var argvContract: [String]
        public var shellUsed: Bool
        public var rawDeleteFallback: Bool
        public var hubRemoteDeletion: Bool
        public var pruneUsed: Bool
        public var processOutcome: String?
        public var realMutationExecuted: Bool
        public var snapshotPresentBefore: Bool?
        public var snapshotPresentAfter: Bool?
        public var repoPresentAfter: Bool?
        public var logicalRemovalVerified: Bool
        public var potentialRecoveryBytesBefore: Int64?
        public var verifiedRecoveredBytes: Int64
        public var diskFreeDeltaBytes: Int64?
        public var recoveryStatus: String?
        public var postVerifyStatus: String?
        public var binaryFingerprint: String?
        public var cliExecutablePath: String?
        public var auditRecord: ActionAuditRecord?
        public var postVerify: HuggingFacePostMutationVerifier.Result?
        public var executionMs: Int
        public var abortReason: String?
        public var humanConfirmed: Bool
        public var explanation: String
        public var dryRunPreviewFingerprint: String?
        public var scope: String
    }

    /// Exact product path: Fresh Preflight → Approval → Permit → Executor → PostVerify.
    /// No shell. No raw delete. No Hub delete. No prune. No automatic retry.
    public static func executeHuggingFaceRevisionCleanup(
        _ input: HuggingFaceExecuteInput
    ) throws -> HuggingFaceNativeExecutionReport {
        let started = Date()
        let authFP = HuggingFaceNativePostMutationProbe.authorizationTextFingerprint(input.authorizationText)
        let entityID = HuggingFaceNativePostMutationProbe.authorizedEntityID
        let revision = HuggingFaceNativePostMutationProbe.authorizedRevision
        let repoID = HuggingFaceNativePostMutationProbe.authorizedRepoID
        let cacheRoot = HuggingFaceNativePostMutationProbe.defaultCacheRoot
        let snapshotPath = HuggingFaceNativePostMutationProbe.authorizedSnapshotPath
        let repoPath = HuggingFaceNativePostMutationProbe.authorizedRepoPath

        func empty() -> HuggingFaceNativeExecutionReport {
            HuggingFaceNativeExecutionReport(
                phase: "P3.2B.3",
                outcome: "UNKNOWN",
                entityID: entityID,
                repoID: repoID,
                revision: revision,
                action: StorageAction.vendorNativeCleanup.rawValue,
                authorizationTextFingerprint: authFP,
                approvalID: nil,
                approvalConsumed: false,
                approvalBindingValid: false,
                finalPreflightReceiptID: nil,
                finalPreflightReadiness: nil,
                canonicalActionDecisionEligible: false,
                strictUnknownCount: -1,
                strictConflictCount: -1,
                permitID: nil,
                permitConsumed: false,
                executorInvoked: false,
                argvContract: [],
                shellUsed: false,
                rawDeleteFallback: false,
                hubRemoteDeletion: false,
                pruneUsed: false,
                processOutcome: nil,
                realMutationExecuted: false,
                snapshotPresentBefore: nil,
                snapshotPresentAfter: nil,
                repoPresentAfter: nil,
                logicalRemovalVerified: false,
                potentialRecoveryBytesBefore: nil,
                verifiedRecoveredBytes: 0,
                diskFreeDeltaBytes: nil,
                recoveryStatus: nil,
                postVerifyStatus: nil,
                binaryFingerprint: nil,
                cliExecutablePath: nil,
                auditRecord: nil,
                postVerify: nil,
                executionMs: 0,
                abortReason: nil,
                humanConfirmed: input.humanConfirmed,
                explanation: "",
                dryRunPreviewFingerprint: nil,
                scope: "LOCAL_HF_HUB_CACHE_REVISION_ONLY"
            )
        }

        func abort(_ reason: String, partial: HuggingFaceNativeExecutionReport? = nil) -> HuggingFaceNativeExecutionReport {
            var report = partial ?? empty()
            report.outcome = "ABORTED"
            report.abortReason = reason
            report.explanation = reason
            report.executionMs = Int(Date().timeIntervalSince(started) * 1000)
            return report
        }

        guard input.humanConfirmed else {
            throw ActionExecutionError.humanConfirmationRequired
        }
        let normalizedAuth = input.authorizationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedAuth = HuggingFaceNativePostMutationProbe.authorizationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedAuth == expectedAuth else {
            return abort("AUTHORIZATION_TEXT_MISMATCH")
        }

        let item = HuggingFaceNativePostMutationProbe.buildAuthorizedClassifiedItem()
        guard ActionExecutionPolicy.allowsHuggingFaceNativeCleanup(
            entityID: entityID,
            path: snapshotPath,
            revision: revision,
            cacheRoot: cacheRoot
        ) else {
            throw ActionExecutionError.unauthorizedTarget(entityID: entityID, path: snapshotPath)
        }

        let scanDecision = HuggingFaceNativePostMutationProbe.initialDecision(for: item)
        let scanGate = HuggingFaceNativePostMutationProbe.initialGate(for: item)

        let finalSession = "p32b3-final-\(entityID)-\(Int(Date().timeIntervalSince1970))"
        let finalPF = FreshReadOnlyPreflightEngine.run(
            sessionID: finalSession,
            item: item,
            action: .vendorNativeCleanup,
            scanDecision: scanDecision,
            scanGate: scanGate,
            snapshot: nil,
            recommendation: nil,
            preflight: nil,
            scanRuntimeResolution: nil,
            ruleVersion: "P3.2B.3",
            engine: input.engine,
            ollamaProcessRunner: input.processRunner,
            refreshStaleRemoteProof: true
        )

        var alignedItem = item
        if var v = alignedItem.verification {
            if let iface = finalPF.huggingFaceNativeInterface {
                v.vendorProofNotes.removeAll { $0.hasPrefix("HF_") || $0 == "LOCAL_HF_CACHE_OWNERSHIP_VERIFIED" }
                v.vendorProofNotes.append("HF_INTERFACE=\(iface.status.rawValue)")
                v.vendorProofNotes.append("HF_CACHE_ROOT=\(cacheRoot)")
                v.vendorProofNotes.append("LOCAL_HF_CACHE_OWNERSHIP_VERIFIED")
                v.vendorProofNotes.append("HF_REVISION=\(revision)")
                v.vendorProofNotes.append("HF_REPO=\(repoID)")
                if iface.executionTransportAvailable {
                    if let path = iface.cliExecutableURL {
                        v.vendorProofNotes.append("HF_CLI_RESOLVED=\(path)")
                    }
                    v.vendorProofNotes.append("HF_EXECUTION_TRANSPORT_AVAILABLE")
                    if let fp = iface.binaryFingerprint {
                        v.vendorProofNotes.append("HF_BINARY_FP=\(fp)")
                    }
                }
            }
            if let preview = finalPF.huggingFaceDryRunPreview, preview.previewComplete {
                v.vendorProofNotes.append("HF_DRY_RUN_COMPLETE")
                v.vendorProofNotes.append("HF_DRY_RUN_FP=\(preview.consequenceFingerprint)")
            }
            if finalPF.freshRuntimeResolution.openFileHandle == .false,
               finalPF.freshRuntimeResolution.openFileConfidence == .verified {
                v.activeState = .inactive
                v.activeStateConfidence = .verified
                v.activeStateCompleteness = .complete
            } else if finalPF.freshRuntimeResolution.openFileHandle == .true,
                      finalPF.freshRuntimeResolution.openFileConfidence == .verified {
                v.activeState = .active
                v.activeStateConfidence = .verified
            }
            // Re-bind remote proof for aligner (Fresh Preflight mutates an internal copy).
            let remoteEntity = VendorSemanticEntity(
                vendor: .huggingFace,
                entityKind: .snapshot,
                entityID: entityID,
                displayIdentity: "\(repoID)@\(String(revision.prefix(12)))",
                canonicalPath: snapshotPath,
                logicalBytes: input.expectedRecoveryBytes,
                uniqueBytes: input.expectedRecoveryBytes,
                sharedBytes: 0,
                originIdentity: repoID,
                revisionIdentity: revision,
                referenceScope: .exclusive,
                referenceGraphComplete: true
            )
            let remoteProof = HuggingFaceRemoteVerifier().verify(
                entity: remoteEntity,
                session: RemoteRequestSession()
            )
            RemoteReacquisitionService.apply(proof: remoteProof, to: &v)
            alignedItem.verification = v
        }

        let alignment = ActionSpecificSafetyAligner.alignHuggingFaceVendorNative(
            item: alignedItem,
            decision: finalPF.freshDecision,
            gate: finalPF.freshGateResult
        )

        var report = empty()
        report.finalPreflightReceiptID = finalPF.receipt.receiptID
        report.finalPreflightReadiness = finalPF.freshGateResult.readiness
        report.canonicalActionDecisionEligible = finalPF.freshDecision.eligible
        report.strictUnknownCount = alignment.unknownStrictPredicates.count
        report.strictConflictCount = alignment.conflictedStrictPredicates.count
        report.binaryFingerprint = finalPF.huggingFaceNativeInterface?.binaryFingerprint
        report.cliExecutablePath = finalPF.huggingFaceNativeInterface?.cliExecutableURL
        report.dryRunPreviewFingerprint = finalPF.huggingFaceDryRunPreview?.consequenceFingerprint

        guard finalPF.freshGateResult.readiness == MutationReadiness.approvalRequired.rawValue else {
            return abort(
                "FINAL_PREFLIGHT_NOT_APPROVAL_REQUIRED:\(finalPF.freshGateResult.readiness)|missing=\(finalPF.freshGateResult.missingRequirements)|blocking=\(finalPF.freshGateResult.blockingReasons)|receipt=\(finalPF.receipt.result)|unknownStrict=\(alignment.unknownStrictPredicates)",
                partial: report
            )
        }
        guard finalPF.receipt.result == PreflightResultCode.satisfiedReadOnly.rawValue else {
            return abort("FINAL_PREFLIGHT_RECEIPT:\(finalPF.receipt.result)", partial: report)
        }
        guard finalPF.freshDecision.eligible else {
            return abort("FINAL_DECISION_NOT_ELIGIBLE", partial: report)
        }
        guard finalPF.freshDecision.missingClaimTypes.isEmpty,
              finalPF.freshDecision.blockedReasons.isEmpty else {
            return abort("FINAL_DECISION_BLOCKED", partial: report)
        }
        guard alignment.unknownStrictPredicates.isEmpty,
              alignment.conflictedStrictPredicates.isEmpty else {
            return abort(
                "STRICT_PREDICATE_FAIL unknown=\(alignment.unknownStrictPredicates) conflict=\(alignment.conflictedStrictPredicates)",
                partial: report
            )
        }
        let residue = alignment.remainingGateBlockers.filter { $0 != "USER_APPROVAL" }
        if !residue.isEmpty {
            return abort("REMAINING_GATE:\(residue.joined(separator: ","))", partial: report)
        }

        // `--confirm` / humanConfirmed only acknowledges CLI submission of consent.
        // Canonical UserActionApproval is still minted here, bound to final Fresh Preflight.
        let approval = UserActionApproval(
            approvalID: "human-approval-hf-\(UUID().uuidString.prefix(8))",
            entityID: entityID,
            action: .vendorNativeCleanup,
            bindingFingerprint: finalPF.receipt.bindingFingerprint,
            consequenceSummaryVersion: "P3.2B.3_HF_REVISION_NATIVE",
            expectedRecoveryBytes: input.expectedRecoveryBytes,
            approvedAt: Date(),
            expiryPolicy: "single_use_immediate",
            scope: "hf_revision:\(revision):local_only:\(authFP)",
            approvalOrigin: HuggingFaceCLIConsentContract.approvalOrigin
        )
        report.approvalID = approval.approvalID
        report.approvalBindingValid = approval.bindingFingerprint.matches(finalPF.receipt.bindingFingerprint)
        guard report.approvalBindingValid else {
            return abort("APPROVAL_BINDING_MISMATCH", partial: report)
        }

        guard let permit = ExecutionPermit.generate(
            receipt: finalPF.receipt,
            approval: approval,
            decision: finalPF.freshDecision
        ) else {
            return abort("PERMIT_DENIED", partial: report)
        }
        report.permitID = permit.permitID
        report.approvalConsumed = true

        guard let exePath = report.cliExecutablePath,
              FileManager.default.isExecutableFile(atPath: exePath) else {
            _ = ExecutionPermitLedger.consume(permit.permitID)
            report.permitConsumed = true
            return abort("EXECUTABLE_UNRESOLVED", partial: report)
        }
        let exe = URL(fileURLWithPath: exePath)

        let before = HuggingFaceNativePostMutationProbe.captureBefore()
        report.snapshotPresentBefore = before.snapshotPresent
        report.potentialRecoveryBytesBefore = before.uniqueBytes
        guard before.snapshotPresent else {
            _ = ExecutionPermitLedger.consume(permit.permitID)
            report.permitConsumed = true
            return abort("SNAPSHOT_NOT_PRESENT_BEFORE", partial: report)
        }
        guard before.revisionCount == 1 else {
            _ = ExecutionPermitLedger.consume(permit.permitID)
            report.permitConsumed = true
            return abort("REVISION_COUNT_CHANGED:\(before.revisionCount)", partial: report)
        }

        let argv = try HuggingFaceRevisionIdentity.rmArguments(
            revision: revision,
            cacheRoot: cacheRoot,
            dryRun: false,
            yes: true
        )
        report.argvContract = argv
        guard !argv.contains("prune"),
              argv.contains("--yes"),
              !argv.contains("--dry-run"),
              argv.contains(revision) else {
            _ = ExecutionPermitLedger.consume(permit.permitID)
            report.permitConsumed = true
            return abort("ARGV_CONTRACT_REJECT", partial: report)
        }

        let plan = DryRunActionPlan(
            entityID: entityID,
            path: snapshotPath,
            action: StorageAction.vendorNativeCleanup.rawValue,
            readiness: MutationReadiness.approvalRequired.rawValue,
            steps: [
                DryRunActionStep(order: 1, step: "verify_explicit_user_approval", mutates: false),
                DryRunActionStep(order: 2, step: "hf_cache_rm_exact_revision", mutates: true),
                DryRunActionStep(order: 3, step: "verify_revision_absent", mutates: false),
            ],
            executorImplemented: true
        )

        let boundExecutor: any StorageActionExecutor = StorageActionExecutorRouter(
            huggingFaceExecutor: HuggingFaceNativeCleanupExecutor(
                processRunner: input.processRunner,
                resolveExecutable: { exe }
            )
        )

        report.executorInvoked = true
        report.realMutationExecuted = true
        let audit: ActionAuditRecord
        do {
            audit = try boundExecutor.executeHuggingFaceRevisionCleanup(
                plan: plan,
                permit: permit,
                revision: revision,
                cacheRoot: cacheRoot
            )
        } catch {
            report.permitConsumed = ExecutionPermitLedger.isConsumed(permit.permitID)
            report.outcome = "EXECUTION_FAILED"
            report.abortReason = String(describing: error)
            report.explanation = "Native HF executor threw; no raw fallback"
            report.executionMs = Int(Date().timeIntervalSince(started) * 1000)
            return report
        }
        report.auditRecord = audit
        report.permitConsumed = ExecutionPermitLedger.isConsumed(permit.permitID)
        report.processOutcome = audit.notes.first(where: { $0.hasPrefix("PROCESS_OUTCOME=") })
            .map { String($0.dropFirst("PROCESS_OUTCOME=".count)) }

        if let failure = audit.failureReason {
            report.outcome = "EXECUTION_FAILED"
            report.abortReason = failure
            report.explanation = failure
            report.executionMs = Int(Date().timeIntervalSince(started) * 1000)
            return report
        }

        // Settle briefly then post-verify.
        Thread.sleep(forTimeInterval: 0.5)
        let afterPresent = FileManager.default.fileExists(atPath: snapshotPath)
        let repoAfter = FileManager.default.fileExists(atPath: repoPath)
        let freeAfter = StorageCapacityMeasurer.freeBytes()
        let diskDelta: Int64?
        if let b = before.freeBytes, let a = freeAfter {
            diskDelta = a - b
        } else {
            diskDelta = nil
        }
        let post = HuggingFacePostMutationVerifier.verify(
            revision: revision,
            snapshotPath: snapshotPath,
            repoPath: repoPath,
            beforeUniqueBytes: before.uniqueBytes,
            afterUniqueBytes: afterPresent ? before.uniqueBytes : 0,
            vendorReportedFreed: finalPF.huggingFaceDryRunPreview?.expectedFreedBytesVendor,
            diskFreeDelta: diskDelta
        )
        report.postVerify = post
        report.snapshotPresentAfter = afterPresent
        report.repoPresentAfter = repoAfter
        report.logicalRemovalVerified = !afterPresent
        report.verifiedRecoveredBytes = post.verifiedRecoveredBytes ?? 0
        report.diskFreeDeltaBytes = diskDelta
        report.recoveryStatus = post.storage.rawValue
        report.postVerifyStatus = post.logical.rawValue
        report.outcome = afterPresent ? "SNAPSHOT_REMOVAL_NOT_VERIFIED" : "SNAPSHOT_REMOVED"
        if !afterPresent, post.storage == .recovered {
            report.outcome = "SNAPSHOT_REMOVED_STORAGE_RECOVERED"
        }
        report.explanation = afterPresent
            ? "Mutation ran but snapshot still present"
            : "Exact local HF cached revision removed; Hub untouched"
        report.executionMs = Int(Date().timeIntervalSince(started) * 1000)
        return report
    }
}
