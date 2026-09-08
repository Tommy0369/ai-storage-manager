import Foundation

public struct ImmediateChild: Equatable, Sendable {
    public var name: String
    public var path: String
}

public struct ChildFolderEnumerator {
    public var maxChildren: Int

    public init(maxChildren: Int = 80) {
        self.maxChildren = maxChildren
    }

    public func immediateDirectories(at path: String, caller: String = "ChildFolderEnumerator") -> [ImmediateChild] {
        let expanded = PathGlob.expandHome(path)
        let started = Date()
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: expanded) else { return [] }
        var kids: [ImmediateChild] = []
        for name in names where !name.hasPrefix(".") {
            let child = (expanded as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue else { continue }
            if (try? fm.destinationOfSymbolicLink(atPath: child)) != nil { continue }
            kids.append(ImmediateChild(name: name, path: child))
        }
        let result = Array(kids.prefix(maxChildren))
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        ScanSessionContext.current?.recordDirectoryEnumeration(at: expanded, childCount: result.count, caller: caller, durationMs: ms)
        return result
    }
}

public struct FolderDecomposer: EntityDetector {
    public var domain: String
    public var bucket: SystemDataBucket
    public var parentID: String
    public var parentPath: String
    public var enumerator: ChildFolderEnumerator
    public var kind: EntityKind

    public var runtimeStageOverride: String? {
        if parentID.contains("containers") { return "detector_matching_containers" }
        if parentID.contains("group_containers") { return "detector_matching_group_containers" }
        if parentID.contains("caches") || parentID.contains("user_caches") { return "detector_matching_caches" }
        if parentID.contains("application_support") { return "detector_matching_application_support" }
        return nil
    }

    public init(
        domain: String,
        bucket: SystemDataBucket,
        parentID: String,
        parentPath: String,
        kind: EntityKind = .applicationSupport,
        maxChildren: Int = 80
    ) {
        self.domain = domain
        self.bucket = bucket
        self.parentID = parentID
        self.parentPath = parentPath
        self.kind = kind
        self.enumerator = ChildFolderEnumerator(maxChildren: maxChildren)
    }

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let parent = PathGlob.expandHome(parentPath)
        return enumerator.immediateDirectories(at: parent, caller: "FolderDecomposer.\(parentID)").compactMap { child in
            let id = "\(parentID).child.\(sanitize(child.name))"
            return measuredNode(
                id: id,
                kind: kind,
                category: "MACOS",
                sub: child.name,
                path: child.path,
                scanner: scanner,
                bucket: bucket,
                domain: domainForChild(child.name)
            )
        }
    }

    func measuredNode(
        id: String,
        kind: EntityKind,
        category: String,
        sub: String,
        path: String,
        scanner: ReadOnlyStorageScanner,
        bucket: SystemDataBucket,
        domain: String
    ) -> DetectedEntity? {
        guard let scanned = ScannedNodeCache.getOrScan(path: path, scanner: scanner, caller: "FolderDecomposer") else { return nil }
        let entity = StorageEntity(
            id: id,
            kind: kind,
            category: category,
            subcategory: sub,
            displayName: id,
            path: scanned.path,
            logicalBytes: scanned.logicalBytes
        )
        return DetectedEntity(entity: entity, bucket: bucket, domain: domain, associatedProcesses: [], identified: true, annotation: nil)
    }

    func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    func domainForChild(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("cursor") || n.contains("claude") || n.contains("ollama") || n.contains("code") {
            return "AI Tools"
        }
        if n.contains("docker") { return "Docker" }
        if n.contains("google") || n.contains("chrome") || n.contains("slack") { return "macOS" }
        return domain
    }
}
