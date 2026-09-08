import Foundation

public struct ScannedNode: Codable, Sendable, Equatable {
    public var path: String
    public var canonicalPath: String
    public var logicalBytes: Int64
    public var allocatedBytes: Int64
    public var fileCount: Int
    public var isDirectory: Bool
    public var isSymlink: Bool
    public var isPackage: Bool
    public var isHidden: Bool
    public var owner: String?
    public var posixPermissions: Int?
    public var created: Date?
    public var modified: Date?
    public var accessed: Date?
    public var skippedBecauseSymlink: Bool
    public var measurementQuality: MeasurementQuality
    public var measurementKnown: Bool
    public var measurementReason: String?

    public init(
        path: String,
        canonicalPath: String,
        logicalBytes: Int64,
        allocatedBytes: Int64,
        fileCount: Int,
        isDirectory: Bool,
        isSymlink: Bool,
        isPackage: Bool,
        isHidden: Bool,
        owner: String?,
        posixPermissions: Int?,
        created: Date?,
        modified: Date?,
        accessed: Date?,
        skippedBecauseSymlink: Bool,
        measurementQuality: MeasurementQuality = .unknown,
        measurementKnown: Bool = false,
        measurementReason: String? = nil
    ) {
        self.path = path
        self.canonicalPath = canonicalPath
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.owner = owner
        self.posixPermissions = posixPermissions
        self.created = created
        self.modified = modified
        self.accessed = accessed
        self.skippedBecauseSymlink = skippedBecauseSymlink
        self.measurementQuality = measurementQuality
        self.measurementKnown = measurementKnown
        self.measurementReason = measurementReason
    }
}

public struct DirectoryMeasurer {
    public init() {}

    /// Read-only size. Does not follow symlinks (`du -P`).
    public func measure(path: String) -> (logical: Int64, allocated: Int64, files: Int) {
        let expanded = PathGlob.expandHome(path)
        let url = URL(fileURLWithPath: expanded)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) else {
            return (0, 0, 0)
        }
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: expanded) {
            _ = dest
            if let vals = resourceValues(url, keys: [.fileSizeKey, .totalFileAllocatedSizeKey]) {
                let logical = Int64(vals.fileSize ?? 0)
                let alloc = Int64(vals.totalFileAllocatedSize ?? vals.fileSize ?? 0)
                return (logical, alloc, 1)
            }
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        proc.arguments = ["-skP", expanded]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            let kb = Int64(text.split(whereSeparator: { $0.isWhitespace }).first.flatMap { Int64($0) } ?? 0)
            let allocated = kb * 1024
            return (allocated, allocated, isDir.boolValue ? 1 : 1)
        } catch {
            return (0, 0, 0)
        }
    }

    func resourceValues(_ url: URL, keys: Set<URLResourceKey>) -> URLResourceValues? {
        try? url.resourceValues(forKeys: keys)
    }
}

public struct ReadOnlyStorageScanner {
    public var measurer: DirectoryMeasurer

    public init(measurer: DirectoryMeasurer = DirectoryMeasurer()) {
        self.measurer = measurer
    }

    public static var caseStudyRoots: [String] {
        [
            "~/Library/Caches",
            "~/Library/Developer",
            "~/Library/Application Support",
            "~/Library/Containers",
            "~/Library/Group Containers",
            "~/Library/Logs",
            "~/Library/Mobile Documents",
            "~/Library/Preferences",
            "~/Downloads",
            "~/.Trash",
            "~/.npm",
            "~/.ollama",
            "~/.cache",
            "~/.claude",
            "~/Library/CloudStorage",
            "/opt/homebrew/Cellar",
            "/opt/homebrew/Caskroom",
        ]
    }

    public func scanNode(path: String, caller: String = "scanner") -> ScannedNode? {
        let expanded = PathGlob.expandHome(path)
        if HardSafetyGates.isHardBlocked(path: expanded) {
            return nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) else {
            return nil
        }
        let url = URL(fileURLWithPath: expanded)
        let keys: Set<URLResourceKey> = [
            .isSymbolicLinkKey, .isDirectoryKey, .isPackageKey, .isHiddenKey,
            .creationDateKey, .contentModificationDateKey, .contentAccessDateKey,
            .fileResourceTypeKey, .fileSizeKey, .totalFileAllocatedSizeKey,
        ]
        let vals = try? url.resourceValues(forKeys: keys)
        let isLink = vals?.isSymbolicLink ?? false
        let canonical: String
        if isLink {
            canonical = expanded
        } else {
            canonical = (expanded as NSString).standardizingPath
        }

        let measurement: SizeMeasurement
        if let session = ScanSessionContext.current {
            measurement = session.measure(path: expanded, caller: caller, mode: isDir.boolValue ? "bounded_du" : "metadata_file")
        } else {
            measurement = DirectorySizeCache.measurement(at: expanded, caller: caller)
                ?? SizeMeasurement.unknown(reason: "NO_SESSION", method: "fallback")
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: expanded)
        let perm = attrs?[.posixPermissions] as? Int
        let owner = attrs?[.ownerAccountName] as? String
        let logical = measurement.accountingBytes
        let allocated = measurement.isKnown ? logical : 0
        return ScannedNode(
            path: expanded,
            canonicalPath: canonical,
            logicalBytes: logical,
            allocatedBytes: allocated,
            fileCount: measurement.isKnown ? 1 : 0,
            isDirectory: isDir.boolValue,
            isSymlink: isLink,
            isPackage: vals?.isPackage ?? false,
            isHidden: vals?.isHidden ?? false,
            owner: owner,
            posixPermissions: perm,
            created: vals?.creationDate,
            modified: vals?.contentModificationDate,
            accessed: vals?.contentAccessDate,
            skippedBecauseSymlink: isLink,
            measurementQuality: measurement.quality,
            measurementKnown: measurement.isKnown,
            measurementReason: measurement.reason
        )
    }

    public func scanRoots(_ roots: [String] = ReadOnlyStorageScanner.caseStudyRoots) -> [ScannedNode] {
        var out: [ScannedNode] = []
        for root in roots {
            let started = Date()
            if let node = scanNode(path: root, caller: "scanRoots") {
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                let m = SizeMeasurement(
                    bytes: node.measurementKnown ? node.logicalBytes : nil,
                    quality: node.measurementQuality,
                    method: "scanRoots",
                    complete: node.measurementKnown,
                    timedOut: node.measurementReason == "DU_TIMEOUT",
                    reason: node.measurementReason
                )
                ScanSessionContext.current?.recordRootScan(path: node.path, durationMs: ms, measurement: m)
                out.append(node)
            }
        }
        return out
    }
}
