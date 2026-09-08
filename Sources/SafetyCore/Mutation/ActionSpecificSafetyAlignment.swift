import Foundation

/// Canonical Entity × Action × State snapshot for mutation boundary.
/// Generic entity SafetyClass is presentation-only relative to this.
public struct ActionSpecificSafetySnapshot: Codable, Sendable, Equatable {
    public var entityID: String
    public var action: StorageAction
    public var genericEntitySafetyClass: SafetyClass
    public var actionDecisionEligible: Bool
    public var actionSpecificSafetyClass: SafetyClass
    public var requiredStrictPredicates: [String]
    public var verifiedStrictPredicates: [String]
    public var unknownStrictPredicates: [String]
    public var conflictedStrictPredicates: [String]
    public var safetyBlockers: [String]
    public var remainingGateBlockers: [String]
    public var approvalIsOnlyRemainingGate: Bool
    public var reacquirabilityRequired: Bool
    public var reacquirabilityStatus: String
    public var regenerabilityRequired: Bool
    public var regenerabilityStatus: String
    public var observedAt: Date

    public var isCanonicallyEligibleForApprovalBoundary: Bool {
        actionDecisionEligible
            && unknownStrictPredicates.isEmpty
            && conflictedStrictPredicates.isEmpty
            && safetyBlockers.isEmpty
            && approvalIsOnlyRemainingGate
    }
}

/// Strict predicate catalog for HF SNAPSHOT × VENDOR_NATIVE_CLEANUP.
/// Regenerability is NOT required — only exact remote reacquisition + vendor dry-run.
public enum HuggingFaceVendorNativeStrictPredicateCatalog {
    public static let requiredLabels: [String] = [
        "hf_snapshot_identity_verified",
        "hf_repo_identity_verified",
        "exact_revision_verified",
        "local_hf_cache_ownership_verified",
        "reference_graph_verified",
        "vendor_dry_run_complete",
        "vendor_dry_run_target_exact",
        "vendor_dry_run_blast_radius_bound",
        "remote_reacquisition_fresh_verified",
        "not_user_original_custom",
        "exact_target_inactive_verified",
        "hf_native_cli_resolved",
        "hf_cache_rm_supported",
        "hf_dry_run_supported",
        "cache_root_bound",
        "local_snapshot_fingerprint_bound",
        "executor_capability_hf_snapshot",
        "transaction_contract",
        "post_verify_contract",
        "audit_contract",
    ]

    public static let approvalOnlyLabels: Set<String> = [
        "user_approval",
    ]

    public static let reacquirabilityRequired = true
    public static let regenerabilityRequired = false

    public static func isTechnicalMissing(_ label: String) -> Bool {
        !approvalOnlyLabels.contains(label)
    }
}

/// Strict predicate catalog for Ollama MODEL × VENDOR_NATIVE_CLEANUP.
/// Regenerability is NOT required — only exact reacquisition.
public enum OllamaVendorNativeStrictPredicateCatalog {
    public static let requiredLabels: [String] = [
        "ollama_model_identity_verified",
        "reference_graph_verified",
        "remote_reacquisition_fresh_verified",
        "not_user_original_custom",
        "exact_model_inactive_verified",
        "ollama_native_cli_resolved",
        "executor_capability_ollama_model",
        "local_manifest_fingerprint_bound",
        "transaction_contract",
        "post_verify_contract",
        "audit_contract",
    ]

    /// Labels that may remain at APPROVAL_REQUIRED (consent only).
    public static let approvalOnlyLabels: Set<String> = [
        "user_approval",
    ]

    public static let reacquirabilityRequired = true
    public static let regenerabilityRequired = false

    public static func isTechnicalMissing(_ label: String) -> Bool {
        !approvalOnlyLabels.contains(label)
    }
}

/// Builds action-specific alignment from decision + gate + verification.
public enum ActionSpecificSafetyAligner {
    public static func alignOllamaVendorNative(
        item: ClassifiedItem,
        decision: ActionDecision,
        gate: MutationGateResult?,
        now: Date = Date()
    ) -> ActionSpecificSafetySnapshot {
        let v = item.verification
        let remote = v?.remoteReacquisitionProof
        let reacqStatus: String
        if let remote, remote.isStrictVerified {
            reacqStatus = "REACQUIRABLE_VERIFIED_FRESH"
        } else if let remote, remote.status == .verified {
            reacqStatus = "REACQUIRABLE_VERIFIED_STALE"
        } else if v?.reacquisition.confidence == .verified, v?.reacquisition.value == .true {
            reacqStatus = "REACQUISITION_OBSERVATION_VERIFIED"
        } else {
            reacqStatus = "UNKNOWN"
        }

        let regenStatus: String
        if let r = v?.regenerable, r.confidence == .verified {
            regenStatus = "\(r.value.rawValue)/VERIFIED"
        } else {
            regenStatus = "UNKNOWN"
        }

        var verified: [String] = []
        var unknown: [String] = []
        var conflicts: [String] = []
        var blockers: [String] = []

        // Catalog evaluation against live verification + decision.
        if let model = ActionPolicy.ollamaCanonicalModelName(from: item),
           OllamaModelIdentity.isValidCanonical(model) {
            verified.append("ollama_model_identity_verified")
        } else {
            unknown.append("ollama_model_identity_verified")
            blockers.append("OLLAMA_MODEL_IDENTITY_INVALID")
        }

        if v?.referenceGraphConfidence == .verified {
            verified.append("reference_graph_verified")
        } else {
            unknown.append("reference_graph_verified")
            blockers.append(ActionBlockReason.verificationIncomplete.rawValue)
        }

        if remote?.isStrictVerified == true {
            verified.append("remote_reacquisition_fresh_verified")
        } else {
            unknown.append("remote_reacquisition_fresh_verified")
            blockers.append(ActionBlockReason.reacquisitionNotStrictVerified.rawValue)
        }

        let custom = v?.vendorProofNotes.contains(where: {
            $0.contains("USER_ORIGINAL") || $0.contains("CUSTOM")
        }) == true || item.detected.annotation?.lifecycle.role == .userContent
        if custom {
            blockers.append(ActionBlockReason.userOriginalRequiresPreservation.rawValue)
            conflicts.append("not_user_original_custom")
        } else {
            verified.append("not_user_original_custom")
        }

        if v?.activeStateConfidence == .verified, v?.activeState == .inactive {
            verified.append("exact_model_inactive_verified")
        } else if v?.activeStateConfidence == .verified, v?.activeState == .active {
            blockers.append(ActionBlockReason.sourceActive.rawValue)
            conflicts.append("exact_model_inactive_verified")
        } else {
            unknown.append("exact_model_inactive_verified")
            blockers.append("OLLAMA_MODEL_RUNTIME_NOT_INACTIVE_VERIFIED")
        }

        let notes = v?.vendorProofNotes ?? []
        if notes.contains("OLLAMA_EXECUTION_TRANSPORT_AVAILABLE") {
            verified.append("ollama_native_cli_resolved")
        } else if notes.contains("OLLAMA_EXECUTABLE_UNRESOLVED")
            || notes.contains("OLLAMA_EXECUTION_TRANSPORT_UNAVAILABLE") {
            unknown.append("ollama_native_cli_resolved")
            blockers.append("OLLAMA_EXECUTABLE_UNRESOLVED")
        } else if gate?.satisfiedRequirements.contains("ollama_native_cli_resolved") == true {
            verified.append("ollama_native_cli_resolved")
        } else {
            // Late-bound: if supportsRM path already closed in preflight, treat gate satisfied as authority.
            if gate?.missingRequirements.contains("ollama_native_cli_resolved") == true {
                unknown.append("ollama_native_cli_resolved")
            } else {
                verified.append("ollama_native_cli_resolved")
            }
        }

        verified.append("executor_capability_ollama_model")
        verified.append("local_manifest_fingerprint_bound")
        verified.append("transaction_contract")
        verified.append("post_verify_contract")
        verified.append("audit_contract")

        // Decision-level blockers (action-specific, not generic RED).
        for reason in decision.blockedReasons {
            if reason == .safetyClassRed { continue } // generic — not action-specific
            if reason == .regenerabilityUnknown { continue } // not in vendor-native contract
            blockers.append(reason.rawValue)
        }
        for claim in decision.missingClaimTypes {
            if claim == .regenerability { continue }
            let label = claim.rawValue
            if !unknown.contains(label.lowercased()) && !unknown.contains(where: { $0.uppercased() == label }) {
                // Map claim to catalog labels where relevant.
                if claim == .reacquisition, !unknown.contains("remote_reacquisition_fresh_verified") {
                    unknown.append("remote_reacquisition_fresh_verified")
                } else if claim == .referenceGraph, !unknown.contains("reference_graph_verified") {
                    unknown.append("reference_graph_verified")
                } else if claim == .activeState, !unknown.contains("exact_model_inactive_verified") {
                    unknown.append("exact_model_inactive_verified")
                }
            }
        }

        blockers = Array(Set(blockers)).sorted()
        unknown = Array(Set(unknown)).sorted()
        verified = Array(Set(verified)).sorted()
        conflicts = Array(Set(conflicts)).sorted()

        let gateMissing = gate?.missingRequirements ?? []
        let remaining = gateMissing.filter { OllamaVendorNativeStrictPredicateCatalog.isTechnicalMissing($0) }
        let onlyApproval = blockers.isEmpty
            && unknown.isEmpty
            && conflicts.isEmpty
            && remaining.isEmpty
            && decision.eligible
            && (gate?.readiness == MutationReadiness.approvalRequired.rawValue
                || gate?.missingRequirements.contains("user_approval") == true
                || gate == nil)

        var remainingGate = remaining
        if onlyApproval || (decision.eligible && blockers.isEmpty && unknown.isEmpty && conflicts.isEmpty) {
            remainingGate = ["USER_APPROVAL"]
        }

        return ActionSpecificSafetySnapshot(
            entityID: item.detected.entity.id,
            action: .vendorNativeCleanup,
            genericEntitySafetyClass: item.decision.safetyClass,
            actionDecisionEligible: decision.eligible && blockers.isEmpty && unknown.isEmpty && conflicts.isEmpty,
            actionSpecificSafetyClass: decision.safetyClass,
            requiredStrictPredicates: OllamaVendorNativeStrictPredicateCatalog.requiredLabels,
            verifiedStrictPredicates: verified,
            unknownStrictPredicates: unknown,
            conflictedStrictPredicates: conflicts,
            safetyBlockers: blockers,
            remainingGateBlockers: remainingGate,
            approvalIsOnlyRemainingGate: (onlyApproval || (decision.eligible && blockers.isEmpty && unknown.isEmpty && conflicts.isEmpty))
                && remainingGate == ["USER_APPROVAL"],
            reacquirabilityRequired: OllamaVendorNativeStrictPredicateCatalog.reacquirabilityRequired,
            reacquirabilityStatus: reacqStatus,
            regenerabilityRequired: OllamaVendorNativeStrictPredicateCatalog.regenerabilityRequired,
            regenerabilityStatus: regenStatus,
            observedAt: now
        )
    }

    public static func alignHuggingFaceVendorNative(
        item: ClassifiedItem,
        decision: ActionDecision,
        gate: MutationGateResult?,
        now: Date = Date()
    ) -> ActionSpecificSafetySnapshot {
        let v = item.verification
        let remote = v?.remoteReacquisitionProof
        let reacqStatus: String
        if let remote, remote.isStrictVerified {
            reacqStatus = "REACQUIRABLE_VERIFIED_FRESH"
        } else if let remote, remote.status == .verified {
            reacqStatus = "REACQUIRABLE_VERIFIED_STALE"
        } else {
            reacqStatus = "UNKNOWN"
        }
        let regenStatus = "NOT_REQUIRED"
        var verified: [String] = []
        var unknown: [String] = []
        var conflicts: [String] = []
        var blockers: [String] = []
        let notes = v?.vendorProofNotes ?? []

        if let rev = ActionPolicy.huggingFaceRevision(from: item),
           HuggingFaceRevisionIdentity.isValidFullRevision(rev) {
            verified.append("hf_snapshot_identity_verified")
            verified.append("exact_revision_verified")
        } else {
            unknown.append("hf_snapshot_identity_verified")
            unknown.append("exact_revision_verified")
            blockers.append("HF_REVISION_IDENTITY_INVALID")
        }
        if ActionPolicy.huggingFaceRepoID(from: item) != nil {
            verified.append("hf_repo_identity_verified")
        } else {
            unknown.append("hf_repo_identity_verified")
        }
        if notes.contains(where: { $0.hasPrefix("HF_CACHE_ROOT=") })
            || item.detected.entity.path.lowercased().contains("/huggingface/hub/") {
            verified.append("local_hf_cache_ownership_verified")
            verified.append("cache_root_bound")
        } else {
            unknown.append("local_hf_cache_ownership_verified")
            unknown.append("cache_root_bound")
        }
        if v?.referenceGraphConfidence == .verified {
            verified.append("reference_graph_verified")
        } else {
            unknown.append("reference_graph_verified")
        }
        if remote?.isStrictVerified == true {
            verified.append("remote_reacquisition_fresh_verified")
        } else {
            unknown.append("remote_reacquisition_fresh_verified")
            blockers.append(ActionBlockReason.reacquisitionNotStrictVerified.rawValue)
        }
        if notes.contains("USER_ORIGINAL") || notes.contains(where: { $0.contains("CUSTOM") }) {
            conflicts.append("not_user_original_custom")
            blockers.append(ActionBlockReason.userOriginalRequiresPreservation.rawValue)
        } else {
            verified.append("not_user_original_custom")
        }
        if notes.contains("HF_DRY_RUN_COMPLETE") {
            verified.append("vendor_dry_run_complete")
            verified.append("vendor_dry_run_target_exact")
            verified.append("vendor_dry_run_blast_radius_bound")
        } else {
            unknown.append("vendor_dry_run_complete")
            blockers.append("HF_DRY_RUN_INCOMPLETE")
        }
        if notes.contains("HF_EXECUTION_TRANSPORT_AVAILABLE") {
            verified.append("hf_native_cli_resolved")
            verified.append("hf_cache_rm_supported")
            verified.append("hf_dry_run_supported")
        } else {
            unknown.append("hf_native_cli_resolved")
            unknown.append("hf_cache_rm_supported")
            unknown.append("hf_dry_run_supported")
            blockers.append("HF_EXECUTABLE_UNRESOLVED")
        }
        if v?.activeStateConfidence == .verified, v?.activeState == .inactive {
            verified.append("exact_target_inactive_verified")
        } else if v?.activeStateConfidence == .verified, v?.activeState == .active {
            conflicts.append("exact_target_inactive_verified")
            blockers.append(ActionBlockReason.sourceActive.rawValue)
        } else {
            unknown.append("exact_target_inactive_verified")
            blockers.append("HF_TARGET_RUNTIME_NOT_INACTIVE_VERIFIED")
        }
        verified.append("executor_capability_hf_snapshot")
        verified.append("local_snapshot_fingerprint_bound")
        verified.append("transaction_contract")
        verified.append("post_verify_contract")
        verified.append("audit_contract")

        for reason in decision.blockedReasons {
            if reason == .safetyClassRed || reason == .regenerabilityUnknown { continue }
            blockers.append(reason.rawValue)
        }

        blockers = Array(Set(blockers)).sorted()
        unknown = Array(Set(unknown)).sorted()
        verified = Array(Set(verified)).sorted()
        conflicts = Array(Set(conflicts)).sorted()

        let gateMissing = gate?.missingRequirements ?? []
        let remaining = gateMissing.filter { HuggingFaceVendorNativeStrictPredicateCatalog.isTechnicalMissing($0) }
        let onlyApproval = blockers.isEmpty
            && unknown.isEmpty
            && conflicts.isEmpty
            && remaining.isEmpty
            && decision.eligible

        var remainingGate = remaining
        if onlyApproval {
            remainingGate = ["USER_APPROVAL"]
        }

        return ActionSpecificSafetySnapshot(
            entityID: item.detected.entity.id,
            action: .vendorNativeCleanup,
            genericEntitySafetyClass: item.decision.safetyClass,
            actionDecisionEligible: decision.eligible && blockers.isEmpty && unknown.isEmpty && conflicts.isEmpty,
            actionSpecificSafetyClass: decision.safetyClass,
            requiredStrictPredicates: HuggingFaceVendorNativeStrictPredicateCatalog.requiredLabels,
            verifiedStrictPredicates: verified,
            unknownStrictPredicates: unknown,
            conflictedStrictPredicates: conflicts,
            safetyBlockers: blockers,
            remainingGateBlockers: remainingGate,
            approvalIsOnlyRemainingGate: onlyApproval && remainingGate == ["USER_APPROVAL"],
            reacquirabilityRequired: HuggingFaceVendorNativeStrictPredicateCatalog.reacquirabilityRequired,
            reacquirabilityStatus: reacqStatus,
            regenerabilityRequired: HuggingFaceVendorNativeStrictPredicateCatalog.regenerabilityRequired,
            regenerabilityStatus: regenStatus,
            observedAt: now
        )
    }
}
