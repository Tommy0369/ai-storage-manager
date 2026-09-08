import Foundation

public enum ResolutionLevel: Int, Codable, Sendable, Comparable {
    case l0Unknown = 0
    case l1PathBucket = 1
    case l2Domain = 2
    case l3Product = 3
    case l4SemanticEntity = 4
    case l5Actionable = 5

    public static func < (lhs: ResolutionLevel, rhs: ResolutionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func assign(entityID: String, path: String, predicatesAllTrue: Bool, safetyClass: SafetyClass = .unknown) -> ResolutionLevel {
        let id = entityID.lowercased()
        if safetyClass == .green, predicatesAllTrue, id.contains("derived_data") || id.contains("cache") || id.contains("logs") {
            return .l5Actionable
        }
        if id.hasPrefix("macos.application_support") || id.hasPrefix("macos.containers")
            || id.hasPrefix("macos.group_containers") || id.hasPrefix("macos.user_caches")
            || id.hasPrefix("macos.logs") || id == "xcode.developer_root" {
            if id.contains(".child.") {
                // keep going — product/semantic children are not L1
            } else {
                return .l1PathBucket
            }
        }
        if id.contains("derived_data") || id.contains("archives") || id.contains("simulator")
            || id.contains("module_cache") || id.contains("source_packages") || id.contains("preview")
            || id.contains("device_support") || id.hasSuffix("_logs") || id.contains("pip_cache")
            || id.contains("npm_cache") || id.contains("volume") || id.contains("build_cache")
            || id.contains(".cache") || id.contains(".logs") || id.contains(".blobs")
            || id.contains(".history") || id.contains(".documents") || id.contains(".preferences")
            || id.contains(".tmp") || id.contains(".workspace") || id.contains(".global_storage")
            || id.contains(".extensions") || id.contains(".indexeddb") || id.contains(".hub")
            || id.contains(".datasets") || id.contains(".manifests") || id.contains(".models")
            || id.contains(".sessions") || id.contains(".projects") || id.contains(".settings")
            || id.contains(".user_settings") || id.contains(".caches") || id.contains(".app_support")
            || id.contains(".index") || id.contains("cursor.snapshots") || id.contains("claude.vm")
            || id.hasPrefix("ios.backup") || id.contains(".runtime") || id.contains(".writable")
            || id.contains(".database") || id.contains("cursor.snapshots.store")
            || id.hasPrefix("voicememos.") || id.contains("cloud.fileprovider")
            || id.contains("cloud.icloud") {
            return .l4SemanticEntity
        }
        let last = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let products = ["cursor", "claude", "code", "chrome", "slack", "discord", "spotify", "docker", "ollama", "adobe", "microsoft"]
        if products.contains(where: { last.contains($0) || id.contains($0) }) {
            let macosRoot = id.hasPrefix("macos.") && !id.contains(".child.")
            if !macosRoot { return .l3Product }
        }
        if id.hasPrefix("xcode.") || id.hasPrefix("node.") || id.hasPrefix("docker.")
            || id.hasPrefix("python.") || id.hasPrefix("git.") || id.hasPrefix("ai.") || id.hasPrefix("homebrew.")
            || id.hasPrefix("appsupport.") || id.hasPrefix("container.") || id.hasPrefix("groupcontainer.") {
            return id.contains(".") ? .l3Product : .l2Domain
        }
        if id.hasPrefix("user.") || id.hasPrefix("backup.") || id.hasPrefix("cloud.") || id.hasPrefix("icloud.") {
            return .l2Domain
        }
        return .l2Domain
    }
}

public struct SemanticCoverage: Codable, Sendable, Equatable {
    public var identifiedPercent: Double
    public var l3PlusPercent: Double
    public var l4PlusPercent: Double
    public var l5Percent: Double

    public init(identifiedPercent: Double, l3PlusPercent: Double, l4PlusPercent: Double, l5Percent: Double) {
        self.identifiedPercent = min(100, max(0, identifiedPercent))
        self.l3PlusPercent = min(100, max(0, l3PlusPercent))
        self.l4PlusPercent = min(100, max(0, l4PlusPercent))
        self.l5Percent = min(100, max(0, l5Percent))
    }
}
