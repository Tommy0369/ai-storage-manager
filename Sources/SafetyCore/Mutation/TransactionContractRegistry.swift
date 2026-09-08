import Foundation

public enum TransactionContractRegistry {
    public static let trashVersion = "MOVE_TO_TRASH_v0.1"
    public static let iCloudVersion = "MOVE_TO_ICLOUD_v0.1"
    public static let evictVersion = "REMOVE_LOCAL_DOWNLOAD_v0.1"
    public static let ollamaNativeVersion = OllamaNativeCleanupExecutor.contractVersion
    public static let hfNativeVersion = HuggingFaceNativeCleanupExecutor.contractVersion
    public static let auditVersion = "AUDIT_v0.1"
    public static let postVerifyTrashVersion = "POST_VERIFY_TRASH_v0.1"
    public static let postVerifyICloudVersion = "POST_VERIFY_ICLOUD_v0.1"
    public static let postVerifyEvictVersion = "POST_VERIFY_EVICT_v0.1"
    public static let postVerifyOllamaNativeVersion = "POST_VERIFY_OLLAMA_NATIVE_v0.1"
    public static let postVerifyHFNativeVersion = "POST_VERIFY_HF_NATIVE_v0.1"

    public static func transactionContract(for action: StorageAction, item: ClassifiedItem) -> TransactionContract? {
        switch action {
        case .keep:
            return nil
        case .vendorNativeCleanup:
            if ActionPolicy.isOllamaModelEntity(item), !ActionPolicy.isRawAIVendorBlob(item) {
                return TransactionContract(
                    action: .vendorNativeCleanup,
                    version: ollamaNativeVersion,
                    supportedEntitySemantics: ["OLLAMA_MODEL", "VENDOR_MANAGED_MODEL"],
                    requiredPreflightPredicates: [
                        "entity_identity_verified",
                        "canonical_path_verified",
                        "ollama_model_identity_verified",
                        "local_manifest_fingerprint_bound",
                        "reference_graph_verified",
                        "remote_reacquisition_fresh_verified",
                        "exact_model_inactive_verified",
                        "not_user_original_custom",
                        "executor_capability_ollama_model",
                    ],
                    orderedPhases: OllamaNativeCleanupPhase.allCases.map(\.rawValue),
                    failureBehavior: "STOP_NO_RAW_BLOB_DELETE_FALLBACK",
                    sourcePreservationBehavior: "VENDOR_NATIVE_RM_ONLY",
                    freshnessRequirements: [.staticClaim, .sessionStable, .runtimeFresh, .remoteStateFresh]
                )
            }
            if ActionPolicy.isHuggingFaceSnapshotEntity(item), !ActionPolicy.isRawAIVendorBlob(item) {
                return TransactionContract(
                    action: .vendorNativeCleanup,
                    version: hfNativeVersion,
                    supportedEntitySemantics: ["HF_SNAPSHOT", "HF_REVISION", "VENDOR_MANAGED_CACHE"],
                    requiredPreflightPredicates: [
                        "entity_identity_verified",
                        "canonical_path_verified",
                        "hf_snapshot_identity_verified",
                        "exact_revision_verified",
                        "local_hf_cache_ownership_verified",
                        "cache_root_bound",
                        "reference_graph_verified",
                        "remote_reacquisition_fresh_verified",
                        "vendor_dry_run_complete",
                        "exact_target_inactive_verified",
                        "not_user_original_custom",
                        "hf_native_cli_resolved",
                        "executor_capability_hf_snapshot",
                    ],
                    orderedPhases: HuggingFaceNativeCleanupPhase.allCases.map(\.rawValue),
                    failureBehavior: "STOP_NO_RAW_BLOB_DELETE_FALLBACK",
                    sourcePreservationBehavior: "VENDOR_NATIVE_CACHE_RM_ONLY",
                    freshnessRequirements: [.staticClaim, .sessionStable, .runtimeFresh, .remoteStateFresh]
                )
            }
            return nil
        case .moveToTrash:
            guard ActionPolicy.isDerivedData(item) else { return nil }
            return TransactionContract(
                action: .moveToTrash,
                version: trashVersion,
                supportedEntitySemantics: ["XCODE_DERIVED_DATA", "GENERATED_ARTIFACT"],
                requiredPreflightPredicates: [
                    "canonical_path_verified",
                    "entity_identity_verified",
                    "source_of_truth_false_verified",
                    "regenerable_true_verified",
                    "xcode_inactive_verified",
                    "open_file_safe_verified",
                    "no_evidence_conflict",
                ],
                orderedPhases: TrashTransactionPhase.allCases.map(\.rawValue),
                failureBehavior: "STOP_NO_PERMANENT_DELETE_FALLBACK",
                sourcePreservationBehavior: "TRASH_NOT_EMPTY_TRASH",
                freshnessRequirements: [.staticClaim, .sessionStable, .runtimeFresh]
            )
        case .moveToICloud:
            guard relocationAllowed(item) else { return nil }
            return TransactionContract(
                action: .moveToICloud,
                version: iCloudVersion,
                supportedEntitySemantics: ["USER_CONTENT", "USER_OWNED", "EXPLICIT_RELOCATION"],
                requiredPreflightPredicates: [
                    "entity_identity_verified",
                    "canonical_path_verified",
                    "source_exists",
                    "source_readable",
                    "source_stability_fresh",
                    "icloud_destination_contract",
                    "quota_observation",
                    "local_copy_verify",
                    "remote_persistence_verify",
                ],
                orderedPhases: ICloudTransactionPhase.allCases.map(\.rawValue),
                failureBehavior: "SOURCE_REMAINS_ON_FAILURE",
                sourcePreservationBehavior: "COPY_VERIFY_REMOTE_THEN_RELEASE",
                freshnessRequirements: [.staticClaim, .sessionStable, .runtimeFresh, .remoteStateFresh]
            )
        case .removeLocalDownload:
            guard ActionPolicy.fileProviderBacked(item, evidence: nil) else { return nil }
            return TransactionContract(
                action: .removeLocalDownload,
                version: evictVersion,
                supportedEntitySemantics: ["FILE_PROVIDER_BACKED"],
                requiredPreflightPredicates: [
                    "file_provider_verified",
                    "remote_backing_verified",
                    "sync_safe_verified",
                    "no_unsynced_local_change",
                    "native_eviction_supported",
                ],
                orderedPhases: RemoveLocalDownloadTransactionPhase.allCases.map(\.rawValue),
                failureBehavior: "NO_RAW_DELETE_FALLBACK",
                sourcePreservationBehavior: "LOGICAL_CLOUD_ITEM_PRESERVED",
                freshnessRequirements: [.runtimeFresh, .remoteStateFresh]
            )
        }
    }

    public static func postVerifyContract(for action: StorageAction, item: ClassifiedItem) -> PostActionVerificationContract? {
        guard transactionContract(for: action, item: item) != nil else { return nil }
        switch action {
        case .moveToTrash:
            return PostActionVerificationContract(
                action: .moveToTrash,
                version: postVerifyTrashVersion,
                verificationSteps: [
                    "verify_source_no_longer_owns",
                    "verify_trash_operation_result",
                    "remeasure_storage",
                    "record_actual_recovered_bytes",
                    "complete_audit",
                ]
            )
        case .moveToICloud:
            return PostActionVerificationContract(
                action: .moveToICloud,
                version: postVerifyICloudVersion,
                verificationSteps: [
                    "verify_remote_persistence",
                    "verify_logical_entity_preserved",
                    "verify_local_release_outcome",
                    "remeasure_storage",
                    "complete_audit",
                ]
            )
        case .removeLocalDownload:
            return PostActionVerificationContract(
                action: .removeLocalDownload,
                version: postVerifyEvictVersion,
                verificationSteps: [
                    "verify_logical_cloud_item_exists",
                    "verify_remote_backing_valid",
                    "verify_local_materialization_gone",
                    "remeasure_local_bytes",
                    "complete_audit",
                ]
            )
        case .vendorNativeCleanup:
            if ActionPolicy.isHuggingFaceSnapshotEntity(item) {
                return PostActionVerificationContract(
                    action: .vendorNativeCleanup,
                    version: postVerifyHFNativeVersion,
                    verificationSteps: [
                        "verify_exact_revision_absent",
                        "verify_snapshot_directory_absent",
                        "verify_refs_state",
                        "remeasure_storage",
                        "record_actual_recovered_bytes",
                        "record_remaining_shared_blob_bytes",
                        "complete_audit",
                    ]
                )
            }
            return PostActionVerificationContract(
                action: .vendorNativeCleanup,
                version: postVerifyOllamaNativeVersion,
                verificationSteps: [
                    "verify_exact_model_absent",
                    "remeasure_storage",
                    "record_actual_recovered_bytes",
                    "record_remaining_blob_bytes",
                    "complete_audit",
                ]
            )
        case .keep:
            return nil
        }
    }

    public static func auditContract(for action: StorageAction, item: ClassifiedItem) -> ActionAuditContract? {
        guard transactionContract(for: action, item: item) != nil else { return nil }
        return ActionAuditContract(
            action: action,
            version: auditVersion,
            requiredFields: [
                "actionID", "entityID", "action", "sourceIdentity", "bindingFingerprint",
                "safetyResult", "matchedRule", "verifiedClaims", "preflightReceipt",
                "userApprovalReference", "transactionPhases", "expectedBytes",
                "actualRecoveredBytes", "postVerification", "errorState", "timestamps",
            ],
            auditBeginsBeforeMutation: true
        )
    }

    public static func actionContractAvailable(for action: StorageAction, item: ClassifiedItem) -> Bool {
        transactionContract(for: action, item: item) != nil
    }

    private static func relocationAllowed(_ item: ClassifiedItem) -> Bool {
        if ActionPolicy.isVoiceMemo(item) || ActionPolicy.isIOSBackup(item) { return false }
        if ActionPolicy.isGitRepository(item) || ActionPolicy.isClaudeRuntime(item) { return false }
        if ActionPolicy.isDerivedData(item) { return false }
        if ActionPolicy.isLibraryManagedPath(item.detected.entity.path) { return false }
        return ActionPolicy.userOwnedVerified(item)
            || ActionArchitecture.mayOfferMoveToICloud(
                path: item.detected.entity.path,
                userOwnedVerified: ActionPolicy.userOwnedVerified(item),
                relocationContractVerified: false
            )
    }
}

private extension TrashTransactionPhase {
    static var allCases: [TrashTransactionPhase] {
        [.notStarted, .preflight, .approvalRequired, .ready, .movingToTrash,
         .verifyingTrashResult, .postVerify, .completed, .failed, .cancelled, .unknown]
    }
}

private extension ICloudTransactionPhase {
    static var allCases: [ICloudTransactionPhase] {
        [.notStarted, .preflight, .approvalRequired, .copying, .localCopyVerified, .uploadPending,
         .verifyingRemote, .remoteVerified, .localReleaseEligible, .releasingLocalCopy,
         .postVerify, .completed, .failed, .unknown, .cancelled]
    }
}

private extension RemoveLocalDownloadTransactionPhase {
    static var allCases: [RemoveLocalDownloadTransactionPhase] {
        [.notStarted, .preflight, .approvalRequired, .ready, .requestingNativeEviction,
         .verifyingLocalRelease, .verifyingRemotePreservation, .postVerify,
         .completed, .failed, .unknown, .cancelled]
    }
}

private extension OllamaNativeCleanupPhase {
    static var allCases: [OllamaNativeCleanupPhase] {
        [.notStarted, .preflight, .approvalRequired, .ready, .invokingNativeRm,
         .verifyingModelAbsent, .measuringStorage, .postVerify, .completed, .failed, .cancelled, .unknown]
    }
}
