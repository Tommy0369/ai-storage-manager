import Foundation

/// Read-only mutation boundary. Recommendation ≠ permission. No execution in P2.0.
public enum MutationGate {
    public static func evaluate(_ input: MutationGateInput) -> MutationGateResult {
        var satisfied: [String] = []
        var missing: [String] = []
        var stale: [String] = []
        var conflicted: [String] = []
        var blocking: [String] = []
        var freshChecks: [String] = []

        let item = input.item
        let action = input.action
        let decision = input.actionDecision
        let snapshot = input.snapshot
        let preds = snapshot?.predicates

        let fingerprint = ActionBindingFingerprintBuilder.compute(input: input)
        _ = ActionBindingFingerprintBuilder.buildReceipt(input: input, fingerprint: fingerprint)

        // 1 HARD PRODUCT BLOCK
        if let hard = hardProductBlock(action: action, item: item) {
            blocking.append(hard.rawValue)
            return makeResult(
                input: input,
                readiness: .blocked,
                satisfied: satisfied,
                missing: missing,
                stale: stale,
                conflicted: conflicted,
                blocking: blocking,
                freshChecks: freshChecks,
                fingerprint: fingerprint
            )
        }

        // 2 ACTION SUPPORTED
        if action == .keep {
            satisfied.append("KEEP_ALWAYS_ALLOWED")
            return makeResult(
                input: input,
                readiness: .blocked,
                satisfied: satisfied,
                missing: missing,
                stale: stale,
                conflicted: conflicted,
                blocking: ["KEEP_NOT_MUTATION"],
                freshChecks: freshChecks,
                fingerprint: fingerprint
            )
        }
        if action == .vendorNativeCleanup {
            if ActionPolicy.isRawAIVendorBlob(item) {
                blocking.append("RAW_BLOB_NOT_SUPPORTED")
                return makeResult(input: input, readiness: .blocked, satisfied: satisfied, missing: missing,
                                  stale: stale, conflicted: conflicted, blocking: blocking, freshChecks: freshChecks,
                                  fingerprint: fingerprint)
            }
            let ollamaOK = ActionPolicy.isOllamaModelEntity(item)
            let hfOK = ActionPolicy.isHuggingFaceSnapshotEntity(item)
            if !ollamaOK && !hfOK {
                blocking.append("VENDOR_NATIVE_EXECUTOR_UNAVAILABLE")
                return makeResult(input: input, readiness: .blocked, satisfied: satisfied, missing: missing,
                                  stale: stale, conflicted: conflicted, blocking: blocking, freshChecks: freshChecks,
                                  fingerprint: fingerprint)
            }
            // Ollama MODEL / HF SNAPSHOT continue into full contract evaluation below.
        }

        // 3 ENTITY IDENTITY VERIFIED
        if item.detected.entity.id.isEmpty {
            missing.append("entity_identity")
            blocking.append("ENTITY_IDENTITY_UNVERIFIED")
        } else {
            satisfied.append("entity_identity")
        }
        if preds?.hasCanonicalPath == false, input.item.detected.entity.path.isEmpty {
            missing.append("canonical_path")
            blocking.append("CANONICAL_PATH_UNVERIFIED")
        } else {
            satisfied.append("canonical_path")
        }
        if preds?.isSymlinkAmbiguity == true {
            conflicted.append("symlink_ambiguity")
            blocking.append(ActionBlockReason.evidenceConflict.rawValue)
        }

        // 4 ACTION CONTRACT EXISTS
        let tx = input.transactionContract ?? TransactionContractRegistry.transactionContract(for: action, item: item)
        let post = input.postVerifyContract ?? TransactionContractRegistry.postVerifyContract(for: action, item: item)
        let audit = input.auditContract ?? TransactionContractRegistry.auditContract(for: action, item: item)
        if tx == nil {
            missing.append("action_contract")
            blocking.append(ActionBlockReason.relocationContractMissing.rawValue)
        } else {
            satisfied.append("action_contract")
        }

        // 5 ACTION-SPECIFIC SAFETY DECISION
        // Vendor-native uses UNKNOWN safety class by design — RED on KEEP/trash must not hard-block CLI cleanup.
        if decision.safetyClass == .red, action != .vendorNativeCleanup {
            blocking.append(ActionBlockReason.safetyClassRed.rawValue)
        }
        // Vendor-native eligibility may keep SafetyClass UNKNOWN — do not hard-block when eligible.
        if decision.safetyClass == .unknown, action != .vendorNativeCleanup {
            blocking.append(ActionBlockReason.safetyClassUnknown.rawValue)
        }
        if decision.safetyClass == .unknown, action == .vendorNativeCleanup, !decision.eligible {
            blocking.append(ActionBlockReason.safetyClassUnknown.rawValue)
        }
        if !decision.eligible {
            blocking.append(contentsOf: decision.blockedReasons.map(\.rawValue))
            missing.append(contentsOf: decision.missingClaimTypes.map(\.rawValue))
        } else {
            satisfied.append("action_safety_eligible")
        }
        if decision.blockedReasons.contains(.evidenceConflict) {
            conflicted.append("evidence_conflict")
        }

        // 6 STATIC PROOF COMPLETE
        evaluateStaticProof(action: action, item: item, snapshot: snapshot, satisfied: &satisfied, missing: &missing, blocking: &blocking)

        // 7 RUNTIME PROOF REQUIREMENTS
        evaluateRuntimeProof(input: input, satisfied: &satisfied, missing: &missing, stale: &stale, blocking: &blocking, freshChecks: &freshChecks)

        if !decision.eligible {
            return makeResult(input: input, readiness: .blocked, satisfied: satisfied, missing: missing,
                              stale: stale, conflicted: conflicted, blocking: blocking, freshChecks: freshChecks,
                              fingerprint: fingerprint)
        }

        // 8 TRANSACTION CONTRACT
        if tx == nil {
            missing.append("transaction_contract")
        } else {
            satisfied.append("transaction_contract")
        }

        // 9 POST-ACTION VERIFY CONTRACT
        if post == nil {
            missing.append("post_verify_contract")
            blocking.append("POST_VERIFY_CONTRACT_MISSING")
        } else {
            satisfied.append("post_verify_contract")
        }

        // 10 AUDIT CONTRACT
        if audit == nil {
            missing.append("audit_contract")
            blocking.append("AUDIT_CONTRACT_MISSING")
        } else {
            satisfied.append("audit_contract")
        }

        if blocking.contains(where: { isHardBlock($0) }) {
            return makeResult(input: input, readiness: .blocked, satisfied: satisfied, missing: missing,
                              stale: stale, conflicted: conflicted, blocking: blocking, freshChecks: freshChecks,
                              fingerprint: fingerprint)
        }

        // Vendor-native: any unresolved strict technical predicate → VERIFY_MORE (never APPROVAL_REQUIRED).
        if action == .vendorNativeCleanup {
            let technicalMissing = missing.filter { OllamaVendorNativeStrictPredicateCatalog.isTechnicalMissing($0) }
            let strictBlocks = blocking.filter {
                $0 == ActionBlockReason.reacquisitionNotStrictVerified.rawValue
                    || $0 == "REMOTE_PROOF_STALE"
                    || $0 == "OLLAMA_EXECUTABLE_UNRESOLVED"
                    || $0 == "OLLAMA_MODEL_RUNTIME_NOT_INACTIVE_VERIFIED"
                    || $0 == ActionBlockReason.verificationIncomplete.rawValue
                    || $0 == ActionBlockReason.userOriginalRequiresPreservation.rawValue
                    || $0 == ActionBlockReason.sourceActive.rawValue
            }
            if !technicalMissing.isEmpty || !strictBlocks.isEmpty {
                return makeResult(input: input, readiness: .verifyMore, satisfied: satisfied, missing: missing,
                                  stale: stale, conflicted: conflicted, blocking: blocking, freshChecks: freshChecks,
                                  fingerprint: fingerprint)
            }
        }

        if case .verifyMore = input.recommendation?.disposition {
            // Recommendation KEEP/verifyMore must not force VERIFY_MORE when exact vendor-native
            // action decision is already fully proven and only consent remains.
            if !(action == .vendorNativeCleanup && decision.eligible
                 && missing.filter { OllamaVendorNativeStrictPredicateCatalog.isTechnicalMissing($0) }.isEmpty
                 && blocking.filter { isHardBlock($0) || $0 == ActionBlockReason.reacquisitionNotStrictVerified.rawValue }.isEmpty) {
                return makeResult(input: input, readiness: .verifyMore, satisfied: satisfied, missing: missing,
                                  stale: stale, conflicted: conflicted, blocking: blocking, freshChecks: freshChecks,
                                  fingerprint: fingerprint)
            }
        }

        // 11 USER APPROVAL REQUIREMENT — P2.0 scan has no approvals
        let approvalRequired = action != .keep
        var hasValidApproval = false
        if let approval = input.approvalState.approval {
            hasValidApproval = ActionBindingFingerprintBuilder.isApprovalValid(approval: approval, fingerprint: fingerprint)
            if !hasValidApproval {
                stale.append("user_approval_binding_mismatch")
                blocking.append("APPROVAL_BINDING_INVALID")
            } else {
                satisfied.append("user_approval")
            }
        } else {
            missing.append("user_approval")
        }

        // 12 FRESH PREFLIGHT REQUIREMENT
        let needsFreshRuntime = tx?.freshnessRequirements.contains(.runtimeFresh) == true
        let needsFreshCloud = tx?.freshnessRequirements.contains(where: { $0 == .cloudFresh || $0 == .remoteStateFresh }) == true
        let freshSatisfied = isFreshPreflightSatisfied(
            receipt: input.freshPreflightReceipt,
            fingerprint: fingerprint,
            needsFreshRuntime: needsFreshRuntime,
            needsFreshCloud: needsFreshCloud,
            item: item,
            action: action
        )
        if needsFreshRuntime {
            freshChecks.append("fresh_runtime_preflight")
            if freshSatisfied {
                satisfied.append("fresh_runtime_preflight")
            } else {
                missing.append("fresh_runtime_preflight")
            }
        }
        if needsFreshCloud, action == .moveToICloud {
            freshChecks.append("fresh_cloud_preflight")
            if freshSatisfied, input.item.detected.bucket == .cloud {
                satisfied.append("fresh_cloud_preflight")
            } else if !freshSatisfied {
                missing.append("fresh_cloud_preflight")
            }
        }
        if !freshSatisfied, (!freshChecks.isEmpty || needsFreshRuntime || needsFreshCloud) {
            let hasFreshReceiptBlock = input.freshPreflightReceipt.map {
                $0.result != PreflightResultCode.satisfiedReadOnly.rawValue
            } ?? false
            if hasFreshReceiptBlock, let receipt = input.freshPreflightReceipt {
                if receipt.result == PreflightResultCode.candidateChanged.rawValue {
                    blocking.append("CANDIDATE_CHANGED")
                } else if receipt.result == PreflightResultCode.realStateBlock.rawValue {
                    blocking.append(contentsOf: receipt.missingClaims.map(\.rawValue))
                }
            }
            return makeResult(input: input, readiness: .preflightRequired, satisfied: satisfied, missing: missing,
                              stale: stale, conflicted: conflicted, blocking: blocking, freshChecks: freshChecks,
                              fingerprint: fingerprint)
        }

        // 13 BINDING VALIDITY
        if let approval = input.approvalState.approval {
            let invalid = ActionBindingFingerprintBuilder.invalidationReasons(
                approval: approval,
                current: fingerprint,
                decision: decision
            )
            if !invalid.isEmpty {
                stale.append(contentsOf: invalid)
                return makeResult(input: input, readiness: .blocked, satisfied: satisfied, missing: missing,
                                  stale: stale, conflicted: conflicted, blocking: invalid, freshChecks: freshChecks,
                                  fingerprint: fingerprint)
            }
        }

        // 14 CONTRACT_SATISFIED_READ_ONLY
        if approvalRequired, !hasValidApproval {
            return makeResult(input: input, readiness: .approvalRequired, satisfied: satisfied, missing: missing,
                              stale: stale, conflicted: conflicted, blocking: blocking, freshChecks: freshChecks,
                              fingerprint: fingerprint)
        }

        if !decision.eligible || tx == nil || post == nil || audit == nil {
            return makeResult(input: input, readiness: .blocked, satisfied: satisfied, missing: missing,
                              stale: stale, conflicted: conflicted, blocking: blocking, freshChecks: freshChecks,
                              fingerprint: fingerprint)
        }

        return makeResult(input: input, readiness: .contractSatisfiedReadOnly, satisfied: satisfied, missing: missing,
                          stale: stale, conflicted: conflicted, blocking: blocking, freshChecks: freshChecks,
                          fingerprint: fingerprint)
    }

    public static func buildReport(
        items: [ClassifiedItem],
        recommendations: [ActionRecommendationResult],
        preflights: [ActionPreflightResult],
        actionDecisions: [String: [StorageAction: ActionDecision]],
        snapshotsByEntityID: [String: EntitySafetySnapshot],
        runtimeResolutions: [String: RuntimeStateResolution],
        ruleVersion: String,
        runtimeGeneration: Int
    ) -> MutationGateReport {
        var recMap: [String: ActionRecommendationResult] = [:]
        for r in recommendations { recMap[r.entityID] = r }
        var preMap: [String: [StorageAction: ActionPreflightResult]] = [:]
        for p in preflights {
            preMap[p.entityID, default: [:]][p.action] = p
        }

        var entries: [MutationGateResult] = []
        let mutatingActions: [StorageAction] = [.moveToTrash, .moveToICloud, .removeLocalDownload, .vendorNativeCleanup]

        for item in items {
            let rec = recMap[item.detected.entity.id]
            let snapshot = snapshotsByEntityID[item.detected.entity.id]
            let runtime = runtimeResolutions[item.detected.entity.id]
            let decisions = actionDecisions[item.detected.entity.id] ?? [:]

            var targetActions: [StorageAction]
            if let rec, case .actionable(let a) = rec.disposition {
                targetActions = [a]
            } else if let rec {
                targetActions = [rec.recommendedAction]
            } else {
                targetActions = mutatingActions
            }
            // Vendor-native must remain gate-visible even when recommendation is KEEP.
            if (ActionPolicy.isOllamaModelEntity(item) || ActionPolicy.isHuggingFaceSnapshotEntity(item)),
               decisions[.vendorNativeCleanup] != nil,
               !targetActions.contains(.vendorNativeCleanup) {
                targetActions.append(.vendorNativeCleanup)
            }

            for action in targetActions where action != .keep {
                guard let decision = decisions[action] else { continue }
                let tx = TransactionContractRegistry.transactionContract(for: action, item: item)
                let input = MutationGateInput(
                    item: item,
                    action: action,
                    actionDecision: decision,
                    snapshot: snapshot,
                    recommendation: rec,
                    preflight: preMap[item.detected.entity.id]?[action],
                    runtimeResolution: runtime,
                    transactionContract: tx,
                    postVerifyContract: TransactionContractRegistry.postVerifyContract(for: action, item: item),
                    auditContract: TransactionContractRegistry.auditContract(for: action, item: item),
                    approvalState: .scanDefault,
                    evidenceGeneration: snapshot?.evidence.snapshotVersion ?? 0,
                    verificationGeneration: snapshot?.verification.snapshotGeneration ?? 0,
                    runtimeGeneration: snapshot?.cacheKey.runtimeGeneration ?? runtimeGeneration,
                    ruleVersion: ruleVersion
                )
                entries.append(evaluate(input))
            }
        }

        return MutationGateReport(entries: entries.sorted { $0.entityID < $1.entityID }, executorImplemented: ActionExecutionBoundary.executorImplemented)
    }

    public static func summarize(_ report: MutationGateReport) -> ActExecutorReadinessSummary {
        var blocked = 0, verify = 0, preflight = 0, approval = 0, satisfied = 0
        var trash = 0, iCloud = 0, evict = 0, keep = 0
        var missTx = 0, missPost = 0, missAudit = 0, missAction = 0
        for e in report.entries {
            switch StorageAction(rawValue: e.action) {
            case .moveToTrash: trash += 1
            case .moveToICloud: iCloud += 1
            case .removeLocalDownload: evict += 1
            case .keep: keep += 1
            default: break
            }
            switch MutationReadiness(rawValue: e.readiness) {
            case .blocked: blocked += 1
            case .verifyMore: verify += 1
            case .preflightRequired: preflight += 1
            case .approvalRequired: approval += 1
            case .contractSatisfiedReadOnly: satisfied += 1
            case .none: blocked += 1
            }
            if !e.transactionContractAvailable { missTx += 1 }
            if !e.postVerifyContractAvailable { missPost += 1 }
            if !e.auditContractAvailable { missAudit += 1 }
            if e.blockingReasons.contains(ActionBlockReason.relocationContractMissing.rawValue) { missAction += 1 }
        }
        return ActExecutorReadinessSummary(
            totalEvaluated: report.entries.count,
            keepCount: keep,
            moveToTrashCount: trash,
            moveToICloudCount: iCloud,
            removeLocalDownloadCount: evict,
            blockedCount: blocked,
            verifyMoreCount: verify,
            preflightRequiredCount: preflight,
            approvalRequiredCount: approval,
            contractSatisfiedReadOnlyCount: satisfied,
            missingActionContracts: missAction,
            missingTransactionContracts: missTx,
            missingPostVerifyContracts: missPost,
            missingAuditContracts: missAudit,
            executorImplemented: ActionExecutionBoundary.executorImplemented
        )
    }

    // MARK: - Private helpers

    private static func hardProductBlock(action: StorageAction, item: ClassifiedItem) -> HardProductBlock? {
        // Ollama MODEL native cleanup is intentional vendor-managed mutation — not generic auto-cleanup.
        if action == .vendorNativeCleanup {
            if ActionPolicy.isOllamaModelEntity(item), !ActionPolicy.isRawAIVendorBlob(item) {
                return nil
            }
            if ActionPolicy.isHuggingFaceSnapshotEntity(item), !ActionPolicy.isRawAIVendorBlob(item) {
                return nil
            }
            return .autoCleanup
        }
        if ActionPolicy.isVoiceMemo(item), action == .moveToICloud || action == .removeLocalDownload {
            return .genericLibraryRelocation
        }
        if ActionPolicy.isIOSBackup(item), action == .moveToICloud { return .genericLibraryRelocation }
        if ActionPolicy.isGitRepository(item), action == .moveToICloud { return .genericLibraryRelocation }
        if ActionPolicy.isClaudeRuntime(item), action != .keep { return .genericLibraryRelocation }
        if ActionPolicy.isLibraryManagedPath(item.detected.entity.path), action == .moveToICloud {
            return .genericLibraryRelocation
        }
        return nil
    }

    private static func evaluateStaticProof(
        action: StorageAction,
        item: ClassifiedItem,
        snapshot: EntitySafetySnapshot?,
        satisfied: inout [String],
        missing: inout [String],
        blocking: inout [String]
    ) {
        // Vendor-native Fresh Preflight updates item.verification — prefer live item over stale snapshot.
        let v: VerificationAnnotation?
        if action == .vendorNativeCleanup {
            v = item.verification ?? snapshot?.verification
        } else {
            v = snapshot?.verification ?? item.verification
        }
        let preds = snapshot?.predicates
        if preds?.hasEvidenceConflict == true {
            blocking.append(ActionBlockReason.evidenceConflict.rawValue)
        }
        if action == .moveToTrash, ActionPolicy.isDerivedData(item) {
            if v?.sourceOfTruth.value == .false, v?.sourceOfTruth.confidence == .verified {
                satisfied.append("source_of_truth_false_verified")
            } else {
                missing.append("source_of_truth_false_verified")
                if v?.sourceOfTruth.confidence != .verified { blocking.append(ActionBlockReason.sourceOfTruthUnknown.rawValue) }
            }
            if v?.regenerable.value == .true, v?.regenerable.confidence == .verified {
                satisfied.append("regenerable_true_verified")
            } else {
                missing.append("regenerable_true_verified")
                if v?.regenerable.confidence != .verified { blocking.append(ActionBlockReason.regenerabilityUnknown.rawValue) }
            }
        }
        if action == .vendorNativeCleanup, ActionPolicy.isOllamaModelEntity(item) {
            if let model = ActionPolicy.ollamaCanonicalModelName(from: item),
               OllamaModelIdentity.isValidCanonical(model) {
                satisfied.append("ollama_model_identity_verified")
            } else {
                missing.append("ollama_model_identity_verified")
                blocking.append("OLLAMA_MODEL_IDENTITY_INVALID")
            }
            if v?.referenceGraphConfidence == .verified {
                satisfied.append("reference_graph_verified")
            } else {
                missing.append("reference_graph_verified")
                blocking.append(ActionBlockReason.verificationIncomplete.rawValue)
            }
            let remote = v?.remoteReacquisitionProof
            if let remote, remote.isStrictVerified {
                satisfied.append("remote_reacquisition_fresh_verified")
            } else if let remote, remote.status == .verified, !remote.isFresh {
                missing.append("remote_reacquisition_fresh_verified")
                blocking.append("REMOTE_PROOF_STALE")
            } else {
                missing.append("remote_reacquisition_fresh_verified")
                // Do not alias to REGENERABILITY_UNKNOWN — contract requires reacquisition only.
                blocking.append(ActionBlockReason.reacquisitionNotStrictVerified.rawValue)
            }
            if v?.vendorProofNotes.contains(where: { $0.contains("USER_ORIGINAL") || $0.contains("CUSTOM") }) == true
                || item.detected.annotation?.lifecycle.role == .userContent {
                blocking.append(ActionBlockReason.userOriginalRequiresPreservation.rawValue)
            } else {
                satisfied.append("not_user_original_custom")
            }
            satisfied.append("executor_capability_ollama_model")
            satisfied.append("local_manifest_fingerprint_bound")
            // Executable transport is late-bound at Fresh Preflight; only block when unresolved evidence is present.
            let notes = v?.vendorProofNotes ?? []
            if notes.contains("OLLAMA_EXECUTION_TRANSPORT_AVAILABLE") {
                satisfied.append("ollama_native_cli_resolved")
            } else if notes.contains("OLLAMA_EXECUTABLE_UNRESOLVED")
                || notes.contains("OLLAMA_EXECUTION_TRANSPORT_UNAVAILABLE") {
                missing.append("ollama_native_cli_resolved")
                blocking.append("OLLAMA_EXECUTABLE_UNRESOLVED")
            }
        }
        if action == .vendorNativeCleanup, ActionPolicy.isHuggingFaceSnapshotEntity(item) {
            if let rev = ActionPolicy.huggingFaceRevision(from: item),
               HuggingFaceRevisionIdentity.isValidFullRevision(rev) {
                satisfied.append("exact_revision_verified")
                satisfied.append("hf_snapshot_identity_verified")
            } else {
                missing.append("exact_revision_verified")
                missing.append("hf_snapshot_identity_verified")
                blocking.append("HF_REVISION_IDENTITY_INVALID")
            }
            if ActionPolicy.huggingFaceRepoID(from: item) != nil {
                satisfied.append("hf_repo_identity_verified")
            } else {
                missing.append("hf_repo_identity_verified")
                blocking.append("HF_REPO_IDENTITY_INVALID")
            }
            let notes = v?.vendorProofNotes ?? []
            if notes.contains(where: { $0.hasPrefix("HF_CACHE_ROOT=") || $0 == "LOCAL_HF_CACHE_OWNERSHIP_VERIFIED" })
                || item.detected.entity.path.lowercased().contains("/huggingface/hub/") {
                satisfied.append("local_hf_cache_ownership_verified")
                satisfied.append("cache_root_bound")
            } else {
                missing.append("local_hf_cache_ownership_verified")
                missing.append("cache_root_bound")
                blocking.append("HF_CACHE_ROOT_UNBOUND")
            }
            if v?.referenceGraphConfidence == .verified {
                satisfied.append("reference_graph_verified")
            } else {
                missing.append("reference_graph_verified")
                blocking.append(ActionBlockReason.verificationIncomplete.rawValue)
            }
            let remote = v?.remoteReacquisitionProof
            if let remote, remote.isStrictVerified {
                satisfied.append("remote_reacquisition_fresh_verified")
            } else if let remote, remote.status == .verified, !remote.isFresh {
                missing.append("remote_reacquisition_fresh_verified")
                blocking.append("REMOTE_PROOF_STALE")
            } else {
                missing.append("remote_reacquisition_fresh_verified")
                blocking.append(ActionBlockReason.reacquisitionNotStrictVerified.rawValue)
            }
            if notes.contains("USER_ORIGINAL") || notes.contains(where: { $0.contains("CUSTOM") })
                || item.detected.annotation?.lifecycle.role == .userContent {
                blocking.append(ActionBlockReason.userOriginalRequiresPreservation.rawValue)
            } else {
                satisfied.append("not_user_original_custom")
            }
            if notes.contains("HF_DRY_RUN_COMPLETE") {
                satisfied.append("vendor_dry_run_complete")
                satisfied.append("vendor_dry_run_target_exact")
                satisfied.append("vendor_dry_run_blast_radius_bound")
            } else if notes.contains("HF_DRY_RUN_INCOMPLETE") || notes.contains("HF_CLI_UNRESOLVED") {
                missing.append("vendor_dry_run_complete")
                blocking.append("HF_DRY_RUN_INCOMPLETE")
            }
            if notes.contains("HF_EXECUTION_TRANSPORT_AVAILABLE") {
                satisfied.append("hf_native_cli_resolved")
                satisfied.append("hf_cache_rm_supported")
                satisfied.append("hf_dry_run_supported")
            } else if notes.contains("HF_EXECUTABLE_UNRESOLVED")
                || notes.contains("HF_EXECUTION_TRANSPORT_UNAVAILABLE")
                || notes.contains("HF_CLI_UNRESOLVED") {
                missing.append("hf_native_cli_resolved")
                missing.append("hf_cache_rm_supported")
                missing.append("hf_dry_run_supported")
                blocking.append("HF_EXECUTABLE_UNRESOLVED")
            }
            satisfied.append("executor_capability_hf_snapshot")
            satisfied.append("local_snapshot_fingerprint_bound")
        }
        if action == .moveToICloud {
            if ActionPolicy.userOwnedVerified(item) || preds?.isUserOwnedVerified == true {
                satisfied.append("user_owned_verified")
            } else {
                missing.append("user_owned_verified")
            }
            if v?.sourceOfTruth.value == .true, v?.sourceOfTruth.confidence == .verified {
                satisfied.append("sot_true_allowed_for_preservation")
            }
        }
    }

    private static func evaluateRuntimeProof(
        input: MutationGateInput,
        satisfied: inout [String],
        missing: inout [String],
        stale: inout [String],
        blocking: inout [String],
        freshChecks: inout [String]
    ) {
        let runtime = input.runtimeResolution
        let preds = input.snapshot?.predicates
        let v = input.item.verification ?? input.snapshot?.verification

        if input.action == .vendorNativeCleanup, ActionPolicy.isHuggingFaceSnapshotEntity(input.item) {
            // Exact snapshot inactivity via open-file proof — never invent `hf ps`.
            let openBlocked = runtime?.openFileHandle == .true
                && runtime?.openFileConfidence == .verified
            let openUnknown = runtime == nil
                || runtime?.openFileConfidence == .unknown
                || runtime?.disposition != .resolved
            let inactiveVerified = v?.activeStateConfidence == .verified
                && v?.activeState == .inactive
                && runtime?.openFileHandle == .false
                && runtime?.openFileConfidence == .verified
            if openBlocked {
                blocking.append(ActionBlockReason.sourceOpen.rawValue)
                blocking.append("HF_TARGET_OPEN_FILE")
            } else if v?.activeStateConfidence == .verified, v?.activeState == .active {
                blocking.append(ActionBlockReason.sourceActive.rawValue)
                blocking.append("HF_TARGET_RUNTIME_ACTIVE")
            } else if inactiveVerified {
                satisfied.append("exact_target_inactive_verified")
                satisfied.append("active_inactive_verified")
                satisfied.append("open_file_safe_verified")
            } else if openUnknown {
                missing.append("exact_target_inactive_verified")
                missing.append("open_file_state")
                stale.append("hf_target_runtime_unknown")
                blocking.append("HF_TARGET_RUNTIME_NOT_INACTIVE_VERIFIED")
            } else {
                missing.append("exact_target_inactive_verified")
                blocking.append("HF_TARGET_RUNTIME_NOT_INACTIVE_VERIFIED")
            }
            freshChecks.append("fresh_hf_open_file_at_execution")
            freshChecks.append("fresh_remote_reacquisition_at_execution")
            return
        }

        if input.action == .vendorNativeCleanup, ActionPolicy.isOllamaModelEntity(input.item) {
            // Exact model inactivity — never infer from ollama service process alone.
            if let v, v.activeStateConfidence == .verified, v.activeState == .inactive {
                satisfied.append("exact_model_inactive_verified")
                satisfied.append("active_inactive_verified")
            } else if let v, v.activeStateConfidence == .verified, v.activeState == .active {
                blocking.append(ActionBlockReason.sourceActive.rawValue)
                blocking.append("OLLAMA_MODEL_RUNTIME_NOT_INACTIVE_VERIFIED")
            } else {
                missing.append("exact_model_inactive_verified")
                missing.append("active_state")
                stale.append("ollama_model_runtime_unknown")
                blocking.append("OLLAMA_MODEL_RUNTIME_NOT_INACTIVE_VERIFIED")
            }
            freshChecks.append("fresh_ollama_ps_at_execution")
            freshChecks.append("fresh_remote_reacquisition_at_execution")
            // Open-file is not the primary Ollama model predicate.
            if let runtime, runtime.disposition == .resolved,
               runtime.openFileConfidence == .verified, runtime.openFileHandle == .false {
                satisfied.append("open_file_safe_verified")
            }
            return
        }

        if let runtime {
            switch runtime.disposition {
            case .deferred:
                stale.append("runtime_deferred_not_evidence")
            case .resolved:
                if runtime.activeStateConfidence == .verified, runtime.activeState == .inactive {
                    satisfied.append("active_inactive_verified")
                } else if runtime.activeStateConfidence == .verified, runtime.activeState == .active {
                    blocking.append(ActionBlockReason.sourceActive.rawValue)
                } else if runtime.activeStateConfidence == .unknown {
                    missing.append("active_state")
                    stale.append("runtime_stale_or_unknown")
                }
                if runtime.openFileConfidence == .verified, runtime.openFileHandle == .false {
                    satisfied.append("open_file_safe_verified")
                } else if runtime.openFileHandle == .true {
                    blocking.append(ActionBlockReason.sourceOpen.rawValue)
                } else if runtime.openFileConfidence == .unknown {
                    missing.append("open_file_state")
                    stale.append("open_file_unknown")
                }
            }
        } else if input.action != .keep {
            missing.append("runtime_resolution")
            stale.append("runtime_stale")
        }
        if preds?.activeStateConfidence == .inferred {
            blocking.append("INFERRED_CANNOT_SATISFY_STRICT")
        }
        if input.action == .moveToTrash || input.action == .removeLocalDownload {
            freshChecks.append("fresh_runtime_at_execution")
        }
        _ = blocking
    }

    private static func isFreshPreflightSatisfied(
        receipt: PreflightReceipt?,
        fingerprint: ActionBindingFingerprint,
        needsFreshRuntime: Bool,
        needsFreshCloud: Bool,
        item: ClassifiedItem,
        action: StorageAction
    ) -> Bool {
        guard let receipt else { return false }
        guard receipt.result == PreflightResultCode.satisfiedReadOnly.rawValue else { return false }
        guard receipt.bindingFingerprint.matches(fingerprint) else { return false }
        guard receipt.missingClaims.isEmpty, receipt.staleClaims.isEmpty, receipt.conflictedClaims.isEmpty else { return false }
        if needsFreshCloud, action == .moveToICloud, item.detected.bucket != .cloud { return false }
        _ = needsFreshRuntime
        return true
    }

    private static func isHardBlock(_ reason: String) -> Bool {
        [
            ActionBlockReason.safetyClassRed.rawValue,
            ActionBlockReason.evidenceConflict.rawValue,
            ActionBlockReason.voiceMemoNativeSyncRequired.rawValue,
            ActionBlockReason.iosBackupRequiresDeviceAwareMigration.rawValue,
            ActionBlockReason.reacquisitionNotStrictVerified.rawValue,
            HardProductBlock.genericLibraryRelocation.rawValue,
            "POST_VERIFY_CONTRACT_MISSING",
            "AUDIT_CONTRACT_MISSING",
            "INFERRED_CANNOT_SATISFY_STRICT",
            "REMOTE_PROOF_STALE",
            "OLLAMA_MODEL_RUNTIME_NOT_INACTIVE_VERIFIED",
        ].contains(reason)
    }

    private static func makeResult(
        input: MutationGateInput,
        readiness: MutationReadiness,
        satisfied: [String],
        missing: [String],
        stale: [String],
        conflicted: [String],
        blocking: [String],
        freshChecks: [String],
        fingerprint: ActionBindingFingerprint
    ) -> MutationGateResult {
        let tx = input.transactionContract ?? TransactionContractRegistry.transactionContract(for: input.action, item: input.item)
        let post = input.postVerifyContract ?? TransactionContractRegistry.postVerifyContract(for: input.action, item: input.item)
        let audit = input.auditContract ?? TransactionContractRegistry.auditContract(for: input.action, item: input.item)
        let recAction = input.recommendation?.recommendedAction.rawValue
        return MutationGateResult(
            entityID: input.item.detected.entity.id,
            path: input.item.detected.entity.path,
            action: input.action.rawValue,
            safetyClass: input.actionDecision.safetyClass.rawValue,
            recommendation: recAction,
            readiness: readiness.rawValue,
            satisfiedRequirements: Array(Set(satisfied)).sorted(),
            missingRequirements: Array(Set(missing)).sorted(),
            staleRequirements: Array(Set(stale)).sorted(),
            conflictedRequirements: Array(Set(conflicted)).sorted(),
            blockingReasons: Array(Set(blocking)).sorted(),
            requiredFreshChecks: Array(Set(freshChecks)).sorted(),
            actionBindingFingerprint: fingerprint,
            transactionContractAvailable: tx != nil,
            postVerifyContractAvailable: post != nil,
            auditContractAvailable: audit != nil,
            freshRuntimeCheckRequired: tx?.freshnessRequirements.contains(.runtimeFresh) == true,
            freshCloudCheckRequired: tx?.freshnessRequirements.contains(where: { $0 == .cloudFresh || $0 == .remoteStateFresh }) == true,
            approvalRequired: input.action != .keep,
            executorImplemented: ActionExecutionCapabilitySupport.gateFlag(for: input.action, item: input.item)
        )
    }
}

/// Thin bridge so MutationGate (SafetyCore) can report scoped executor presence without importing AppServices.
enum ActionExecutionCapabilitySupport {
    static func gateFlag(for action: StorageAction, item: ClassifiedItem) -> Bool {
        switch action {
        case .moveToTrash:
            return true
        case .vendorNativeCleanup:
            if ActionPolicy.isRawAIVendorBlob(item) { return false }
            return ActionPolicy.isOllamaModelEntity(item)
                || ActionPolicy.isHuggingFaceSnapshotEntity(item)
        default:
            return false
        }
    }
}
