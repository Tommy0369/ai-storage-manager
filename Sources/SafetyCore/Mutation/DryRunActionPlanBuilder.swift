import Foundation

public enum DryRunActionPlanBuilder {
    public static func build(from gateReport: MutationGateReport) -> DryRunActionPlanReport {
        var plans: [DryRunActionPlan] = []
        for entry in gateReport.entries {
            guard let action = StorageAction(rawValue: entry.action), action != .keep else { continue }
            plans.append(plan(for: entry, action: action))
        }
        return DryRunActionPlanReport(plans: plans, executorImplemented: ActionExecutionBoundary.executorImplemented)
    }

    public static func plan(for entry: MutationGateResult, action: StorageAction) -> DryRunActionPlan {
        var steps: [DryRunActionStep] = []
        func add(_ order: Int, _ step: String, mutates: Bool = false) {
            steps.append(DryRunActionStep(order: order, step: step, mutates: mutates))
        }

        switch action {
        case .moveToTrash:
            add(1, "refresh_runtime_evidence")
            add(2, "revalidate_canonical_path")
            add(3, "verify_source_identity")
            add(4, "reevaluate_safety")
            add(5, "verify_binding_fingerprint")
            add(6, "verify_explicit_user_approval")
            add(7, "future_trash_executor", mutates: true)
            add(8, "verify_trash_result")
            add(9, "remeasure_disk")
            add(10, "finalize_audit")
        case .moveToICloud:
            add(1, "recheck_source_identity")
            add(2, "check_source_stability")
            add(3, "check_icloud_availability")
            add(4, "check_quota")
            add(5, "check_destination_conflict")
            add(6, "copy_to_destination", mutates: true)
            add(7, "verify_local_copy")
            add(8, "observe_upload")
            add(9, "verify_remote_backing")
            add(10, "recheck_source_unchanged")
            add(11, "evaluate_local_release_eligibility")
            add(12, "verify_explicit_release_approval")
            add(13, "release_local_copy", mutates: true)
            add(14, "post_verify")
            add(15, "remeasure_storage")
            add(16, "finalize_audit")
        case .removeLocalDownload:
            add(1, "refresh_file_provider_identity")
            add(2, "verify_remote_backing")
            add(3, "refresh_sync_state")
            add(4, "verify_no_unsynced_local_change")
            add(5, "verify_native_eviction_capability")
            add(6, "verify_explicit_approval")
            add(7, "future_native_eviction", mutates: true)
            add(8, "verify_local_materialization_removed")
            add(9, "verify_logical_cloud_item_remains")
            add(10, "remeasure_disk")
            add(11, "finalize_audit")
        case .keep, .vendorNativeCleanup:
            break
        }

        // Replace empty vendor-native plan with real dry-run steps.
        if action == .vendorNativeCleanup {
            steps = []
            add(1, "refresh_ollama_running_models")
            add(2, "revalidate_exact_model_identity")
            add(3, "revalidate_local_manifest_fingerprint")
            add(4, "revalidate_reference_graph")
            add(5, "refresh_remote_reacquisition_if_stale")
            add(6, "reevaluate_action_safety")
            add(7, "verify_binding_fingerprint")
            add(8, "verify_explicit_user_approval")
            add(9, "future_ollama_native_rm", mutates: true)
            add(10, "verify_exact_model_absent")
            add(11, "remeasure_storage_recovery")
            add(12, "finalize_audit")
        }

        let executorOK: Bool
        switch action {
        case .moveToTrash:
            executorOK = ActionExecutionBoundary.executorImplemented
        case .vendorNativeCleanup:
            executorOK = entry.executorImplemented
        default:
            executorOK = false
        }

        return DryRunActionPlan(
            entityID: entry.entityID,
            path: entry.path,
            action: entry.action,
            readiness: entry.readiness,
            steps: steps,
            executorImplemented: executorOK
        )
    }
}
