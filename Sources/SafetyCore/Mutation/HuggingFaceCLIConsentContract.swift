import Foundation

/// P3.2B.4 — CLI `--confirm` is not a Safety/consent bypass.
/// It only acknowledges that explicit human authorization is submitted through the CLI flow.
/// Orchestrator must still mint/validate canonical UserActionApproval bound to Fresh Preflight.
public enum HuggingFaceCLIConsentContract {
    public static let cliEntryPoint = "storage-intel execute-hf"
    public static let confirmFlagMeaning =
        "ACKNOWLEDGE_EXPLICIT_HUMAN_AUTHORIZATION_THROUGH_CLI_FLOW"
    public static let canonicalApprovalRequired = true
    public static let freshPreflightRequired = true
    public static let strictUnknownCanBeOverridden = false
    public static let exactRevisionRequired = true
    public static let repoWideAllowed = false
    public static let pruneAllowed = false
    public static let hubDeleteAllowed = false
    public static let permitRequired = true
    public static let executorDirectBypassPossible = false
    public static let approvalOrigin = "CLI_EXPLICIT_HUMAN_CONFIRMATION"

    public enum CLIArgValidationError: String, Error, Sendable, Equatable {
        case missingConfirm = "MISSING_CONFIRM"
        case missingRepo = "MISSING_REPO"
        case missingRevision = "MISSING_REVISION"
        case wildcardAll = "WILDCARD_ALL_FORBIDDEN"
        case pruneFlag = "PRUNE_FORBIDDEN"
        case hubDeleteFlag = "HUB_DELETE_FORBIDDEN"
        case targetMismatch = "TARGET_MISMATCH"
        case repoOnly = "REPO_ONLY_FORBIDDEN"
    }

    public struct ValidatedTarget: Sendable, Equatable {
        public var repo: String
        public var revision: String
        public init(repo: String, revision: String) {
            self.repo = repo
            self.revision = revision
        }
    }

    /// Parse and validate execute-hf argv. Does not skip approval/preflight.
    public static func validateExecuteArguments(
        _ args: [String],
        authorizedRepo: String,
        authorizedRevision: String
    ) -> Swift.Result<ValidatedTarget, CLIArgValidationError> {
        guard args.contains("--confirm") else {
            return .failure(.missingConfirm)
        }
        if args.contains("--all") || args.contains("-a") {
            return .failure(.wildcardAll)
        }
        if args.contains("prune") || args.contains("--prune") {
            return .failure(.pruneFlag)
        }
        if args.contains("--hub-delete") || args.contains("--delete-remote") {
            return .failure(.hubDeleteFlag)
        }

        var repo: String?
        var revision: String?
        var i = 0
        while i < args.count {
            if args[i] == "--repo", i + 1 < args.count {
                repo = args[i + 1]
                i += 2
                continue
            }
            if args[i] == "--revision", i + 1 < args.count {
                revision = args[i + 1]
                i += 2
                continue
            }
            i += 1
        }

        guard let repo, !repo.isEmpty else {
            return .failure(.missingRepo)
        }
        guard let revision, !revision.isEmpty else {
            return .failure(.repoOnly)
        }
        guard repo == authorizedRepo, revision == authorizedRevision else {
            return .failure(.targetMismatch)
        }
        return .success(ValidatedTarget(repo: repo, revision: revision))
    }

    public static func asReportDictionary() -> [String: Any] {
        [
            "cliEntryPoint": cliEntryPoint,
            "confirmFlagMeaning": confirmFlagMeaning,
            "canonicalApprovalRequired": canonicalApprovalRequired,
            "freshPreflightRequired": freshPreflightRequired,
            "strictUnknownCanBeOverridden": strictUnknownCanBeOverridden,
            "exactRevisionRequired": exactRevisionRequired,
            "repoWideAllowed": repoWideAllowed,
            "pruneAllowed": pruneAllowed,
            "hubDeleteAllowed": hubDeleteAllowed,
            "permitRequired": permitRequired,
            "executorDirectBypassPossible": executorDirectBypassPossible,
            "approvalOrigin": approvalOrigin,
        ]
    }
}

/// Local cleanup candidates require current local storage — remote alone never synthesizes one.
public enum HuggingFaceLocalCandidatePolicy {
    public static func mayCreateVendorNativeCleanupCandidate(
        localSnapshotPresent: Bool,
        remoteExactRevisionAvailable: Bool
    ) -> Bool {
        _ = remoteExactRevisionAvailable
        return localSnapshotPresent
    }
}
