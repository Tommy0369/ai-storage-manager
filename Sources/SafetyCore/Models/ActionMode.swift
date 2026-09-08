import Foundation

public enum ActionMode: String, Codable, Sendable, Equatable {
    case hardBlock = "HARD_BLOCK"
    case noAction = "NO_ACTION"
    case userReview = "USER_REVIEW"
    case moveToTrash = "MOVE_TO_TRASH"
    case osAPIOnly = "OS_API_ONLY"
    case appAPIOnly = "APP_API_ONLY"
    case toolCLIOnly = "TOOL_CLI_ONLY"
    case packageManagerCommand = "PACKAGE_MANAGER_COMMAND"
    case appUninstall = "APP_UNINSTALL"
    case cloudEvictOnly = "CLOUD_EVICT_ONLY"
    /// Forbidden in v0.1 product surface.
    case permanentDelete = "PERMANENT_DELETE"
}

public enum EvaluationLayer: String, Codable, Sendable, Comparable {
    case hardBlock = "HARD_BLOCK"
    case userProtection = "USER_PROTECTION"
    case sourceOfTruth = "SOURCE_OF_TRUTH"
    case activeUse = "ACTIVE_USE"
    case syncBlastRadius = "SYNC_BLAST_RADIUS"
    case exactVendor = "EXACT_VENDOR_RULE"
    case runtimePredicates = "RUNTIME_PREDICATES"
    case genericCacheTemp = "GENERIC_CACHE_TEMP"
    case unknownFallback = "UNKNOWN_FALLBACK"

    private var order: Int {
        switch self {
        case .hardBlock: return 1
        case .userProtection: return 2
        case .sourceOfTruth: return 3
        case .activeUse: return 4
        case .syncBlastRadius: return 5
        case .exactVendor: return 6
        case .runtimePredicates: return 7
        case .genericCacheTemp: return 8
        case .unknownFallback: return 9
        }
    }

    public static func < (lhs: EvaluationLayer, rhs: EvaluationLayer) -> Bool {
        lhs.order < rhs.order
    }
}
