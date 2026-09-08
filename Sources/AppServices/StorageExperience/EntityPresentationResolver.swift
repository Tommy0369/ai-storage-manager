import Foundation
import SafetyCore

/// Maps canonical entities to human-readable product copy. Does NOT infer Safety.
public enum EntityPresentationResolver {
    public struct Presentation: Sendable, Equatable {
        public var title: String
        public var subtitle: String
        public var category: ProductStorageCategory
        public var description: String
        public var whyLarge: String?
    }

    public static func resolve(item: ClassifiedItem) -> Presentation {
        let entityID = item.detected.entity.id
        let path = item.detected.entity.path
        let domain = item.detected.domain
        let sub = item.detected.entity.subcategory

        if let known = knownPresentation(entityID: entityID, path: path) {
            return known
        }

        let category = mapCategory(domain: domain, entityID: entityID, item: item)
        let title = fallbackTitle(entityID: entityID, sub: sub, path: path)
        let subtitle = category.displayName
        let description = genericDescription(for: item, category: category)
        return Presentation(
            title: title,
            subtitle: subtitle,
            category: category,
            description: description,
            whyLarge: whyLargeHint(for: item, category: category)
        )
    }

    public static func resolve(entityID: String, path: String, domain: String, subcategory: String) -> Presentation {
        if let known = knownPresentation(entityID: entityID, path: path) {
            return known
        }
        let category = mapCategoryFromDomain(domain, entityID: entityID, path: path)
        return Presentation(
            title: fallbackTitle(entityID: entityID, sub: subcategory, path: path),
            subtitle: category.displayName,
            category: category,
            description: L10n.t("entity.generic.storageUsed"),
            whyLarge: nil
        )
    }

    public static func reviewReason(item: ClassifiedItem, gate: MutationGateResult?) -> String {
        if let gate, !gate.blockingReasons.isEmpty {
            return causalFromBlockers(gate.blockingReasons)
        }
        if item.decision.safetyClass == .unknown {
            return L10n.t("review.safetyIncomplete")
        }
        if item.decision.safetyClass == .yellow {
            return L10n.t("review.manualReview")
        }
        if gate?.readiness == MutationReadiness.verifyMore.rawValue {
            return L10n.t("review.verifyInUse")
        }
        if ActionPolicy.isLibraryManagedPath(item.detected.entity.path) {
            return L10n.t("review.appManaged")
        }
        return L10n.t("review.needsMore")
    }

    public static func protectedExplanation(item: ClassifiedItem) -> String {
        let path = item.detected.entity.path.lowercased()
        let id = item.detected.entity.id.lowercased()
        if ActionPolicy.isVoiceMemo(item) || id.contains("voicememo") {
            return L10n.t("entity.protect.voiceMemos")
        }
        if ActionPolicy.isIOSBackup(item) || path.contains("mobilesync/backup") {
            return L10n.t("entity.protect.iosBackup")
        }
        if ActionPolicy.isGitRepository(item) {
            return L10n.t("entity.protect.git")
        }
        if ActionPolicy.isClaudeRuntime(item) || id.contains("claude.vm") {
            return L10n.t("entity.protect.claude")
        }
        if id.contains("chrome") || path.contains("/google/chrome") {
            return L10n.t("entity.protect.chrome")
        }
        if path.contains("cursor") || id.contains("cursor") || id.contains("state.vscdb") {
            return L10n.t("entity.protect.cursor")
        }
        if item.decision.safetyClass == .red {
            return item.decision.userExplanationJA.isEmpty
                ? L10n.t("entity.protect.generic")
                : item.decision.userExplanationJA
        }
        return L10n.t("entity.protect.noAction")
    }

    // MARK: - Known entities

    private static func knownPresentation(entityID: String, path: String) -> Presentation? {
        let id = entityID.lowercased()
        let p = path.lowercased()

        // Prefer exact / high-confidence product titles (P4.0).
        if id.contains("state.vscdb.backup") || p.hasSuffix("state.vscdb.backup") {
            return Presentation(
                title: L10n.t("entity.cursorBackup.title"),
                subtitle: ProductStorageCategory.aiTools.displayName,
                category: .aiTools,
                description: L10n.t("entity.cursorBackup.keepReason"),
                whyLarge: L10n.t("entity.cursorState.whyLarge")
            )
        }
        if id.contains("state.vscdb") || p.hasSuffix("state.vscdb") {
            return Presentation(
                title: L10n.t("entity.cursorState.title"),
                subtitle: ProductStorageCategory.aiTools.displayName,
                category: .aiTools,
                description: L10n.t("entity.cursorState.what"),
                whyLarge: L10n.t("entity.cursorState.whyLarge")
            )
        }
        if id.contains("agent-cli") || id.contains("agent_cli") || p.contains("cursor-agent") {
            return Presentation(
                title: L10n.t("entity.cursorAgentCLI.title"),
                subtitle: ProductStorageCategory.aiTools.displayName,
                category: .aiTools,
                description: L10n.t("entity.cursorState.what"),
                whyLarge: L10n.t("entity.cursorState.whyLarge")
            )
        }
        if id.contains("voicememo") || p.contains("voicememos") {
            return Presentation(
                title: L10n.t("entity.voiceMemos.title"),
                subtitle: ProductStorageCategory.personalFiles.displayName,
                category: .personalFiles,
                description: L10n.t("entity.voiceMemos.what"),
                whyLarge: L10n.t("entity.voiceMemos.whyLarge")
            )
        }
        if id.contains("chrome") && (id.contains("indexeddb") || p.contains("/indexeddb")) {
            return Presentation(
                title: L10n.t("entity.chromeWebsiteState.title"),
                subtitle: ProductStorageCategory.applications.displayName,
                category: .applications,
                description: L10n.t("entity.chrome.what"),
                whyLarge: L10n.t("entity.chrome.whyLarge")
            )
        }
        if id.contains("chrome") {
            return Presentation(
                title: L10n.t("entity.chrome.title"),
                subtitle: ProductStorageCategory.applications.displayName,
                category: .applications,
                description: L10n.t("entity.chrome.what"),
                whyLarge: L10n.t("entity.chrome.whyLarge")
            )
        }
        if id.contains("claude.vm") && (id.contains("writable") || p.contains("sessiondata")) {
            return Presentation(
                title: L10n.t("entity.claudeMutableState.title"),
                subtitle: ProductStorageCategory.aiTools.displayName,
                category: .aiTools,
                description: L10n.t("entity.claude.what"),
                whyLarge: L10n.t("entity.claude.what")
            )
        }
        if id.contains("claude.vm") && (id.contains("runtime") || p.contains("rootfs")) {
            return Presentation(
                title: L10n.t("entity.claudeRuntimeBase.title"),
                subtitle: ProductStorageCategory.aiTools.displayName,
                category: .aiTools,
                description: L10n.t("entity.claude.what"),
                whyLarge: L10n.t("entity.claude.what")
            )
        }
        if id.contains("claude.vm") || (p.contains("/claude/") && p.contains("vm_bundles")) {
            return Presentation(
                title: L10n.t("entity.claude.title"),
                subtitle: ProductStorageCategory.aiTools.displayName,
                category: .aiTools,
                description: L10n.t("entity.claude.what"),
                whyLarge: L10n.t("entity.claude.what")
            )
        }

        let mappings: [(String, String, ProductStorageCategory, String, String?)] = [
            ("deriveddata", "entity.xcodeBuildData.title", .developer, "entity.xcodeBuildData.what", "entity.xcodeBuildData.what"),
            ("ai.hf", "entity.hfModels.title", .aiTools, "entity.hfSnapshot.what", "entity.hfSnapshot.what"),
            ("ai.ollama", "entity.ollamaModels.title", .aiTools, "entity.ollamaModel.what", "entity.ollamaModel.what"),
            ("ai.claude", "entity.claudeData.title", .aiTools, "entity.claude.what", "entity.claude.what"),
            ("ai.cursor", "entity.cursor.title", .aiTools, "entity.cursorState.what", "entity.cursorState.whyLarge"),
            ("ai.codex", "entity.codex.title", .aiTools, "entity.desc.aiTools", nil),
            ("xcode.simulator", "entity.simulatorDevices.title", .developer, "entity.desc.developer", "entity.why.developer"),
            ("git.", "entity.gitRepository.title", .developer, "entity.desc.developer", nil),
            ("icloud", "entity.icloudData.title", .cloud, "entity.desc.cloud", nil),
            ("cron-updater", "entity.macosUpdateCache.title", .macOSSystem, "entity.desc.macOSSystem", nil),
            ("mobilesync", "entity.iphoneBackup.title", .backups, "entity.desc.backups", "entity.why.backups"),
            (".trash", "entity.trash.title", .trash, "entity.generic.storageUsed", nil),
        ]
        for (needle, titleKey, cat, descKey, whyKey) in mappings {
            if id.contains(needle) || p.contains(needle.replacingOccurrences(of: ".", with: "")) {
                return Presentation(
                    title: L10n.t(titleKey),
                    subtitle: cat.displayName,
                    category: cat,
                    description: L10n.t(descKey),
                    whyLarge: whyKey.map { L10n.t($0) }
                )
            }
        }
        return nil
    }

    private static func mapCategory(domain: String, entityID: String, item: ClassifiedItem) -> ProductStorageCategory {
        mapCategoryFromDomain(domain, entityID: entityID, path: item.detected.entity.path)
    }

    private static func mapCategoryFromDomain(_ domain: String, entityID: String, path: String) -> ProductStorageCategory {
        let lower = path.lowercased()
        if lower.contains("/.trash") { return .trash }
        if ActionPolicy.isDerivedDataPath(path) || entityID.contains("deriveddata") { return .developer }
        if domain == "AI Tools" || entityID.hasPrefix("ai.") { return .aiTools }
        if domain == "Developer" || entityID.hasPrefix("xcode.") || entityID.hasPrefix("git.") { return .developer }
        if domain == "Cloud" || entityID.hasPrefix("icloud.") || entityID.hasPrefix("cloud.") { return .cloud }
        if entityID.contains("backup") || lower.contains("mobilesync") { return .backups }
        if domain == "macOS" || entityID.hasPrefix("macos.") { return .macOSSystem }
        if itemKindGenerated(path) { return .generatedData }
        if lower.contains("/applications/") { return .applications }
        if lower.contains("/documents") || lower.contains("/downloads") || lower.contains("/desktop") {
            return .personalFiles
        }
        return .otherUnknown
    }

    private static func itemKindGenerated(_ path: String) -> Bool {
        path.lowercased().contains("/caches/") || path.lowercased().contains("deriveddata")
    }

    private static func fallbackTitle(entityID: String, sub: String, path: String) -> String {
        if !sub.isEmpty, sub != entityID { return sub.replacingOccurrences(of: "_", with: " ") }
        let name = (path as NSString).lastPathComponent
        if !name.isEmpty, name != "." { return name }
        return entityID
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private static func genericDescription(for item: ClassifiedItem, category: ProductStorageCategory) -> String {
        switch category {
        case .developer: return L10n.t("entity.desc.developer")
        case .aiTools: return L10n.t("entity.desc.aiTools")
        case .cloud: return L10n.t("entity.desc.cloud")
        case .backups: return L10n.t("entity.desc.backups")
        case .macOSSystem: return L10n.t("entity.desc.macOSSystem")
        case .generatedData: return L10n.t("entity.desc.generatedData")
        case .personalFiles: return L10n.t("entity.desc.personalFiles")
        default: return item.decision.userExplanationJA.isEmpty ? L10n.t("entity.generic.storageUsed") : item.decision.userExplanationJA
        }
    }

    private static func whyLargeHint(for item: ClassifiedItem, category: ProductStorageCategory) -> String? {
        switch category {
        case .aiTools: return L10n.t("entity.why.aiTools")
        case .developer: return L10n.t("entity.why.developer")
        case .backups: return L10n.t("entity.why.backups")
        default: return nil
        }
    }

    private static func causalFromBlockers(_ blockers: [String]) -> String {
        let joined = blockers.joined(separator: " ").uppercased()
        if joined.contains("SOURCE_ACTIVE") || joined.contains("XCODE") {
            return L10n.t("review.verifyInUse")
        }
        if joined.contains("OPEN") { return L10n.t("review.openByProcess") }
        if joined.contains("ICLOUD") || joined.contains("CLOUD") { return L10n.t("review.verifyCloud") }
        if joined.contains("SOURCE_OF_TRUTH") { return L10n.t("review.cannotVerifySource") }
        if joined.contains("APPLICATION") { return L10n.t("review.appManaged") }
        return L10n.t("review.needsMore")
    }
}

private extension ActionPolicy {
    static func isDerivedDataPath(_ path: String) -> Bool {
        path.lowercased().contains("/deriveddata/")
    }
}
