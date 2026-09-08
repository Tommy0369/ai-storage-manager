import Foundation

public enum SystemDataBucket: String, Codable, Sendable {
    case developer
    case generated
    case backup
    case cloud
    case userData
    case unknown
}

public struct SemanticBreakdownItem: Codable, Sendable, Equatable {
    public var bucket: SystemDataBucket
    public var domain: String
    public var logicalBytes: Int64
    public var safetyClass: SafetyClass
}

public struct SemanticBreakdown: Codable, Sendable {
    public var totalLogicalBytes: Int64
    public var items: [SemanticBreakdownItem]

    public func bytes(in bucket: SystemDataBucket) -> Int64 {
        items.filter { $0.bucket == bucket }.reduce(0) { $0 + $1.logicalBytes }
    }
}

public struct BreakdownPlanner {
    public init() {}

    public func classify(path: String) -> (SystemDataBucket, String) {
        let p = path.lowercased()
        if p.contains("/library/developer") || p.contains("/.docker") || p.contains("/library/caches/homebrew") {
            return (.developer, "Developer")
        }
        if p.contains("/library/caches") || p.contains("/tmp") || p.contains("/logs") {
            return (.generated, "Generated")
        }
        if p.contains("mobile documents") || p.contains("cloudstorage") || p.contains("fileprovider") {
            return (.cloud, "Cloud")
        }
        if p.contains("backup") || p.contains("snapshots") {
            return (.backup, "Backup")
        }
        if p.contains("/documents") || p.contains("/pictures") || p.contains("/movies") || p.contains("/downloads") {
            return (.userData, "User Data")
        }
        return (.unknown, "Unknown")
    }
}
