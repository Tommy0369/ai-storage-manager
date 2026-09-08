import Foundation

public struct PlannedAction: Codable, Sendable, Equatable {
    public var decision: SafetyDecision
    public var previewRequired: Bool
    public var nativeCommand: String?
    public var forbidden: Bool

    public var executableInV01: Bool {
        !forbidden
            && decision.requiresUserApproval
            && decision.action != .permanentDelete
            && decision.action != .hardBlock
            && decision.safetyClass != .red
            && decision.safetyClass != .unknown
    }
}

public struct ActionPlanner {
    public init() {}

    public func plan(_ decision: SafetyDecision) -> PlannedAction {
        if decision.action == .permanentDelete || decision.action == .hardBlock {
            return PlannedAction(
                decision: decision,
                previewRequired: true,
                nativeCommand: nil,
                forbidden: true
            )
        }

        let native: String?
        switch decision.action {
        case .cloudEvictOnly:
            native = "brctl evict"
        case .packageManagerCommand:
            native = commandHint(for: decision.matchedRuleID)
        case .toolCLIOnly:
            native = commandHint(for: decision.matchedRuleID)
        case .osAPIOnly:
            native = "FileManager.trashItem / native OS API"
        case .appAPIOnly:
            native = commandHint(for: decision.matchedRuleID)
        case .moveToTrash:
            native = nil
        default:
            native = nil
        }

        return PlannedAction(
            decision: decision,
            previewRequired: true,
            nativeCommand: native,
            forbidden: false
        )
    }

    func commandHint(for ruleID: String?) -> String? {
        switch ruleID {
        case "docker.build_cache": return "docker builder prune"
        case "homebrew.cache": return "brew cleanup"
        case "node.npm_cache": return "npm cache clean --force"
        case "node.pnpm_store": return "pnpm store prune"
        case "node.yarn_cache": return "yarn cache clean"
        case "python.pip_cache": return "pip cache purge"
        case "git.worktree_metadata": return "git worktree prune"
        case "xcode.derived_data": return nil
        default: return nil
        }
    }
}
