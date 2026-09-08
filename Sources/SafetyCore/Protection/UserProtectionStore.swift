import Foundation

public struct UserProtectionRule: Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var pathPrefixes: [String]
    public var entityKinds: [EntityKind]
    public var naturalLanguageOrigin: String?

    public init(
        id: String,
        label: String,
        pathPrefixes: [String] = [],
        entityKinds: [EntityKind] = [],
        naturalLanguageOrigin: String? = nil
    ) {
        self.id = id
        self.label = label
        self.pathPrefixes = pathPrefixes
        self.entityKinds = entityKinds
        self.naturalLanguageOrigin = naturalLanguageOrigin
    }

    public func matches(entity: StorageEntity) -> Bool {
        if entityKinds.contains(entity.kind) { return true }
        let path = PathGlob.expandHome(entity.path)
        return pathPrefixes.contains { prefix in
            let p = PathGlob.expandHome(prefix)
            return path == p || path.hasPrefix(p + "/")
        }
    }
}

public final class UserProtectionStore: @unchecked Sendable {
    private var rules: [UserProtectionRule]
    private let lock = NSLock()

    public init(rules: [UserProtectionRule] = UserProtectionStore.defaultRules) {
        self.rules = rules
    }

    public static let defaultRules: [UserProtectionRule] = [
        UserProtectionRule(
            id: "protect.photos",
            label: "Photos",
            pathPrefixes: ["~/Pictures", "~/Photos"],
            naturalLanguageOrigin: "写真は絶対消すな"
        ),
        UserProtectionRule(
            id: "protect.documents",
            label: "Documents",
            pathPrefixes: ["~/Documents"]
        ),
        UserProtectionRule(
            id: "protect.desktop",
            label: "Desktop",
            pathPrefixes: ["~/Desktop"]
        ),
        UserProtectionRule(
            id: "protect.projects",
            label: "Projects",
            pathPrefixes: ["~/Projects", "~/Workspace"]
        ),
        UserProtectionRule(
            id: "protect.fcp",
            label: "Final Cut Libraries",
            pathPrefixes: [],
            entityKinds: []
        ),
    ]

    public func all() -> [UserProtectionRule] {
        lock.lock()
        defer { lock.unlock() }
        return rules
    }

    public func add(_ rule: UserProtectionRule) {
        lock.lock()
        defer { lock.unlock() }
        rules.append(rule)
    }

    public func matching(entity: StorageEntity) -> UserProtectionRule? {
        all().first { $0.matches(entity: entity) }
    }
}
