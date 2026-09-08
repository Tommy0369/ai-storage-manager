import Foundation

public enum LifecycleArtifactClassifier {
    public static func classify(name: String) -> (LifecycleRole, EvidenceConfidence, EntityKind) {
        let n = name.lowercased()
        if n.contains("snapshot") { return (.snapshot, .inferred, .generatedBuild) }
        if n.contains("cache") { return (.cache, .inferred, .cache) }
        if n.contains("log") { return (.log, .inferred, .log) }
        if n.contains("tmp") || n.contains("temp") || n == "staging" { return (.temporary, .inferred, .temp) }
        if n.contains("session") { return (.session, .inferred, .applicationSupport) }
        if n.contains("history") { return (.history, .inferred, .applicationSupport) }
        if n.contains("model") || n.contains("blob") { return (.model, .inferred, .applicationSupport) }
        if n.contains("workspace") { return (.workspaceState, .inferred, .applicationSupport) }
        if n.contains("globalstorage") || n.contains("global_storage") { return (.applicationState, .inferred, .applicationSupport) }
        if n.contains("extension") { return (.extensionData, .inferred, .applicationSupport) }
        if n.contains("index") || n.contains("embedding") { return (.index, .inferred, .applicationSupport) }
        if n.contains("download") { return (.download, .inferred, .applicationSupport) }
        if n.contains("sqlite") || n.hasSuffix(".db") || n == "db" || n.contains("database") {
            return (.database, .inferred, .applicationSupport)
        }
        if n.contains("config") || n.contains("setting") || n.contains("pref") {
            return (.userConfiguration, .inferred, .applicationSupport)
        }
        if n.contains("state") { return (.applicationState, .inferred, .applicationSupport) }
        return (.unknown, .unknown, .unknown)
    }
}

public enum ProductIdentityResolver {
    public static func resolve(bundleID: String?) -> ProductIdentity {
        guard let bundleID, !bundleID.isEmpty else {
            return ProductIdentity(confidence: .unknown)
        }
        if let mapped = BundleCatalog.known(bundleID) {
            return ProductIdentity(name: mapped.name, bundleIdentifier: bundleID, confidence: .verified)
        }
        return ProductIdentity(name: nil, bundleIdentifier: bundleID, confidence: .unknown)
    }
}

public enum WorkspaceRelationshipResolver {
    /// Folder-name inference only — never VERIFIED. Use CursorWorkspaceIdentityResolver for VERIFIED.
    public static func resolve(rootFolderName: String, home: String) -> EntityRelationship {
        let workspace = inferredWorkspacePath(from: rootFolderName, home: home)
        guard let workspace else {
            return EntityRelationship(
                type: .belongsToWorkspace,
                target: rootFolderName,
                presence: .unknown,
                confidence: .unknown
            )
        }
        let exists = FileManager.default.fileExists(atPath: workspace)
        return EntityRelationship(
            type: .belongsToWorkspace,
            target: workspace,
            presence: exists ? .present : .missing,
            confidence: .inferred
        )
    }

    public static func inferredWorkspacePath(from folderName: String, home: String) -> String? {
        var base = folderName
        if let range = folderName.range(of: "-[0-9a-fA-F]{6,}$", options: .regularExpression) {
            base = String(folderName[..<range.lowerBound])
        }
        guard !base.isEmpty else { return nil }
        let candidate = "\(home)/Workspace/\(base)"
        if FileManager.default.fileExists(atPath: candidate) { return candidate }
        return candidate
    }
}

public enum DeviceRelationshipResolver {
    public static func backupOf(deviceID: String, deviceName: String?) -> [EntityRelationship] {
        let label = deviceName ?? deviceID
        return [
            EntityRelationship(type: .backupOf, target: label, presence: .present, confidence: deviceName == nil ? .inferred : .verified),
            EntityRelationship(type: .belongsToDevice, target: deviceID, presence: .present, confidence: .verified),
        ]
    }
}

public enum VersionRelationshipResolver {
    public static func claudeDesktopVersion() -> String? {
        let plist = "/Applications/Claude.app/Contents/Info.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plist)),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return (obj["CFBundleShortVersionString"] as? String) ?? (obj["CFBundleVersion"] as? String)
    }

    public static func relate(appVersion: String?, artifactToken: String?) -> (EvidenceConfidence, String) {
        guard let appVersion else {
            return (.unknown, UnknownReasonCode.productVersionUnknown.rawValue)
        }
        guard let artifactToken, !artifactToken.isEmpty else {
            return (.unknown, UnknownReasonCode.versionRelationUnknown.rawValue)
        }
        if artifactToken.contains(appVersion) {
            return (.verified, appVersion)
        }
        return (.inferred, appVersion)
    }
}
