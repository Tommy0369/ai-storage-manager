import Foundation

public struct KnowledgeValidationIssue: Equatable, Sendable {
    public var severity: String
    public var message: String
}

public struct KnowledgeCompileReport: Equatable, Sendable {
    public var ruleCount: Int
    public var issues: [KnowledgeValidationIssue]
    public var duplicateIDs: [String]
    public var greenMissingPredicates: [String]
    public var bootstrapConflicts: [String]

    public var isValid: Bool { issues.filter { $0.severity == "error" }.isEmpty }
}

public enum PredicateCatalog {
    public static let known: Set<String> = [
        "canonical_path", "owner_current_user", "not_symlink", "no_open_file_handle",
        "owning_process_not_running", "not_source_of_truth", "regenerable",
        "source_project_exists", "manifest_exists", "lockfile_exists", "backup_exists",
        "sync_would_not_delete_remote", "not_sip_protected", "icloud_evictable",
        "always", "active_file_handles", "unknown_bundle_owner", "source_project_missing",
        "unknown_manual_files_present", "sync_in_progress", "sync_would_delete_remote",
        "offline_needed", "private_dependency", "local_patch", "zero_install",
        "manifest_missing", "unpushed_local_image", "container_running",
        "simulator_booted", "worktree_still_checked_out", "model_in_use",
        "active_vector_db",
    ]
}

public struct KnowledgeCompiler {
    public init() {}

    public func validate(_ document: KnowledgeBaseDocument, bootstrap: KnowledgeBaseDocument? = nil) -> KnowledgeCompileReport {
        var issues: [KnowledgeValidationIssue] = []
        var seen: [String: Int] = [:]
        var greenMissing: [String] = []
        for rule in document.rules {
            seen[rule.id, default: 0] += 1
            if rule.defaultClass == .green, rule.requiredPredicates.isEmpty {
                greenMissing.append(rule.id)
                issues.append(.init(severity: "error", message: "GREEN rule \(rule.id) has no required_predicates"))
            }
            if rule.actionMode == .permanentDelete {
                issues.append(.init(severity: "error", message: "\(rule.id) uses PERMANENT_DELETE"))
            }
            let preds = rule.requiredPredicates + rule.demoteToYellowIf + rule.demoteToRedIf + rule.hardBlockIf
            for p in preds where !PredicateCatalog.known.contains(p) {
                issues.append(.init(severity: "error", message: "\(rule.id) unknown predicate \(p)"))
            }
        }
        let dups = seen.filter { $0.value > 1 }.map(\.key).sorted()
        for id in dups {
            issues.append(.init(severity: "error", message: "duplicate id \(id)"))
        }
        var conflicts: [String] = []
        if let bootstrap {
            let b = Dictionary(uniqueKeysWithValues: bootstrap.rules.map { ($0.id, $0) })
            for rule in document.rules {
                if let old = b[rule.id], old.defaultClass != rule.defaultClass || old.actionMode != rule.actionMode {
                    conflicts.append(rule.id)
                    issues.append(.init(severity: "warning", message: "conflict with bootstrap \(rule.id); keep bootstrap"))
                }
            }
        }
        return KnowledgeCompileReport(
            ruleCount: document.rules.count,
            issues: issues,
            duplicateIDs: dups,
            greenMissingPredicates: greenMissing,
            bootstrapConflicts: conflicts
        )
    }
}
