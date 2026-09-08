import Foundation

public struct DetectedEntity: Equatable, Sendable, Codable {
    public var entity: StorageEntity
    public var bucket: SystemDataBucket
    public var domain: String
    public var associatedProcesses: [String]
    public var identified: Bool
    public var annotation: DetectionAnnotation?
}

public protocol EntityDetector {
    var domain: String { get }
    var bucket: SystemDataBucket { get }
    var detectorID: String { get }
    var tier: DetectorTier { get }
    func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity]
}

public extension EntityDetector {
    var detectorID: String { String(describing: Self.self) }
    var tier: DetectorTier { .core }
    var runtimeStageOverride: String? { nil }
}

func node(
    id: String,
    kind: EntityKind,
    category: String,
    sub: String,
    path: String,
    scanner: ReadOnlyStorageScanner,
    bucket: SystemDataBucket,
    domain: String,
    processes: [String] = [],
    identified: Bool = true,
    annotation: DetectionAnnotation? = nil
) -> DetectedEntity? {
    guard let scanned = ScannedNodeCache.getOrScan(path: path, scanner: scanner) else { return nil }
    let entity = StorageEntity(
        id: id,
        kind: kind,
        category: category,
        subcategory: sub,
        displayName: id,
        path: scanned.path,
        logicalBytes: scanned.logicalBytes
    )
    return DetectedEntity(entity: entity, bucket: bucket, domain: domain, associatedProcesses: processes, identified: identified, annotation: annotation)
}

/// Fast size probe via `du -sk` (timeout) — avoids multi-minute DirectoryMeasurer walks on huge trees.
func lightweightNode(
    id: String,
    kind: EntityKind,
    category: String,
    sub: String,
    path: String,
    scanner: ReadOnlyStorageScanner,
    bucket: SystemDataBucket,
    domain: String,
    processes: [String] = [],
    identified: Bool = true,
    annotation: DetectionAnnotation? = nil
) -> DetectedEntity? {
    let expanded = SharedMetadataCache.canonicalPath(path)
    guard SharedMetadataCache.pathExists(expanded) else { return nil }
    let measurement = DirectorySizeCache.measurement(at: expanded, caller: "lightweightNode")
    let entity = StorageEntity(
        id: id,
        kind: kind,
        category: category,
        subcategory: sub,
        displayName: id,
        path: expanded,
        logicalBytes: measurement.accountingBytes
    )
    return DetectedEntity(entity: entity, bucket: bucket, domain: domain, associatedProcesses: processes, identified: identified, annotation: annotation)
}

enum QuickDirectorySizer {
    static func bytes(at path: String, timeoutSeconds: Double = 3.0) -> Int64? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        proc.arguments = ["-sk", path]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while proc.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if proc.isRunning {
                proc.terminate()
                return nil
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            guard let first = text.split(whereSeparator: \.isWhitespace).first,
                  let kb = Int64(first)
            else { return nil }
            return kb * 1024
        } catch {
            return nil
        }
    }
}

public struct XcodeDetector: EntityDetector {
    public let domain = "Xcode"
    public let bucket = SystemDataBucket.developer
    public init() {}
    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let base = "\(home)/Library/Developer"
        let pairs: [(String, String, EntityKind, String)] = [
            ("xcode.derived_data", "\(base)/Xcode/DerivedData", .generatedBuild, "DerivedData"),
            ("xcode.archives", "\(base)/Xcode/Archives", .userOriginal, "Archives"),
            ("xcode.simulator_devices", "\(home)/Library/Developer/CoreSimulator/Devices", .cache, "Simulator Devices"),
            ("xcode.simulator_runtimes", "\(home)/Library/Developer/CoreSimulator/Profiles/Runtimes", .cache, "Simulator Runtimes"),
            ("xcode.device_support", "\(base)/Xcode/iOS DeviceSupport", .cache, "DeviceSupport"),
            ("xcode.preview_cache", "\(base)/Xcode/UserData/Previews", .cache, "Preview Cache"),
            ("xcode.swiftpm_cache", "\(home)/Library/Caches/org.swift.swiftpm", .cache, "SwiftPM cache"),
            ("xcode.module_cache", "\(base)/Xcode/DerivedData/ModuleCache.noindex", .cache, "ModuleCache"),
            ("xcode.source_packages", "\(base)/Xcode/DerivedData/SourcePackages", .cache, "SourcePackages"),
        ]
        return pairs.compactMap {
            node(id: $0.0, kind: $0.2, category: "DEVELOPER", sub: $0.3, path: $0.1, scanner: scanner, bucket: bucket, domain: domain, processes: ["Xcode", "xcodebuild"])
        }
    }
}

public struct NodeDetector: EntityDetector {
    public let domain = "Node"
    public let bucket = SystemDataBucket.developer
    public init() {}
    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        [
            ("node.npm_cache", "\(home)/.npm/_cacache", EntityKind.cache),
            ("node.pnpm_store", "\(home)/Library/pnpm/store", .cache),
            ("node.yarn_cache", "\(home)/Library/Caches/Yarn", .cache),
            ("node.bun_cache", "\(home)/.bun/install/cache", .cache),
        ].compactMap {
            node(id: $0.0, kind: $0.2, category: "DEVELOPER", sub: "NODE", path: $0.1, scanner: scanner, bucket: bucket, domain: domain)
        }
    }
}

public struct HomebrewDetector: EntityDetector {
    public let domain = "Homebrew"
    public let bucket = SystemDataBucket.developer
    public init() {}
    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        [
            ("homebrew.cache", "\(home)/Library/Caches/Homebrew", EntityKind.cache),
            ("homebrew.cellar", "/opt/homebrew/Cellar", .applicationSupport),
            ("homebrew.caskroom", "/opt/homebrew/Caskroom", .applicationSupport),
        ].compactMap {
            node(id: $0.0, kind: $0.2, category: "DEVELOPER", sub: "HOMEBREW", path: $0.1, scanner: scanner, bucket: bucket, domain: domain)
        }
    }
}

public struct PythonDetector: EntityDetector {
    public let domain = "Python"
    public let bucket = SystemDataBucket.developer
    public init() {}
    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        [
            ("python.pip_cache", "\(home)/Library/Caches/pip", EntityKind.cache),
            ("python.poetry_cache", "\(home)/Library/Caches/pypoetry", .cache),
            ("python.uv_cache", "\(home)/Library/Caches/uv", .cache),
        ].compactMap {
            node(id: $0.0, kind: $0.2, category: "DEVELOPER", sub: "PYTHON", path: $0.1, scanner: scanner, bucket: bucket, domain: domain)
        }
    }
}

public struct GitDetector: EntityDetector {
    public let domain = "Git"
    public let bucket = SystemDataBucket.developer
    public var tier: DetectorTier { .should }
    public var searchRoots: [String]
    public var maxRepos: Int

    public init(
        searchRoots: [String] = ["~/Workspace", "~/Projects", "~/Documents"],
        maxRepos: Int = 25
    ) {
        self.searchRoots = searchRoots
        self.maxRepos = maxRepos
    }

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let repos = discoverGitDirs(home: home).prefix(maxRepos)
        var out: [DetectedEntity] = []
        for gitDir in repos {
            let repoRoot = (gitDir as NSString).deletingLastPathComponent
            if let n = lightweightNode(id: "git.dot_git", kind: .gitHistory, category: "DEVELOPER", sub: "GIT", path: gitDir, scanner: scanner, bucket: bucket, domain: domain) {
                out.append(n)
            }
            let parts: [(String, String, EntityKind)] = [
                ("git.objects", (gitDir as NSString).appendingPathComponent("objects"), .gitHistory),
                ("git.packfiles", (gitDir as NSString).appendingPathComponent("objects/pack"), .gitHistory),
                ("git.lfs", (gitDir as NSString).appendingPathComponent("lfs"), .gitHistory),
                ("git.worktree_metadata", (gitDir as NSString).appendingPathComponent("worktrees"), .gitMetadata),
            ]
            for p in parts {
                if let n = lightweightNode(id: p.0, kind: p.2, category: "DEVELOPER", sub: "GIT", path: p.1, scanner: scanner, bucket: bucket, domain: domain) {
                    out.append(n)
                }
            }
            var working = StorageEntity(
                id: "git.working_tree",
                kind: .gitHistory,
                category: "DEVELOPER",
                subcategory: "GIT",
                displayName: "working tree",
                path: repoRoot,
                logicalBytes: 0
            )
            let status = gitStatus(repoRoot)
            working.ownerHint = status
            out.append(DetectedEntity(entity: working, bucket: bucket, domain: domain, associatedProcesses: [], identified: true))
        }
        return out
    }

    func discoverGitDirs(home: String) -> [String] {
        var found: [String] = []
        for raw in searchRoots {
            let root = PathGlob.expandHome(raw)
            guard FileManager.default.fileExists(atPath: root) else { continue }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            proc.arguments = ["-P", root, "-name", ".git", "(", "-type", "d", "-o", "-type", "f", ")", "-maxdepth", "5"]
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                for line in text.split(whereSeparator: \.isNewline) {
                    let path = String(line)
                    if path.hasSuffix("/.git") || path.hasSuffix(".git") {
                        found.append(path)
                    }
                }
            } catch {
                continue
            }
        }
        return Array(Set(found)).sorted()
    }

    func gitStatus(_ repo: String) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", repo, "status", "--porcelain"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let dirty = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let unpushed = gitUnpushed(repo)
            return "uncommitted=\(dirty);unpushed=\(unpushed)"
        } catch {
            return "uncommitted=unknown;unpushed=unknown"
        }
    }

    func gitUnpushed(_ repo: String) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", repo, "rev-list", "--count", "@{upstream}..HEAD"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 { return "unknown" }
            let text = (String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "0")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (Int(text) ?? 0) > 0 ? "true" : "false"
        } catch {
            return "unknown"
        }
    }
}

public struct AIToolDetector: EntityDetector {
    public let domain = "AI Tools"
    public let bucket = SystemDataBucket.developer
    public init() {}
    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        [
            ("ai.cursor_logs", "\(home)/Library/Application Support/Cursor/logs", EntityKind.log, ["Cursor"]),
            ("ai.cursor_app_support", "\(home)/Library/Application Support/Cursor", .applicationSupport, ["Cursor"]),
            ("ai.claude_settings", "\(home)/.claude", .applicationSupport, []),
            ("ai.ollama_models", "\(home)/.ollama/models", .cache, ["ollama"]),
            ("ai.huggingface_cache", "\(home)/.cache/huggingface", .cache, []),
            ("ai.lm_studio", "\(home)/.cache/lm-studio", .cache, []),
            ("ai.vscode_logs", "\(home)/Library/Application Support/Code/logs", .log, ["Code"]),
        ].compactMap {
            node(id: $0.0, kind: $0.2, category: "AI_DEV", sub: domain, path: $0.1, scanner: scanner, bucket: bucket, domain: domain, processes: $0.3)
        }
    }
}

public struct MacOSDetector: EntityDetector {
    public let domain = "macOS"
    public let bucket = SystemDataBucket.generated
    public init() {}
    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        var items: [DetectedEntity] = [
            ("macos.user_caches", "\(home)/Library/Caches", EntityKind.cache, SystemDataBucket.generated),
            ("macos.logs", "\(home)/Library/Logs", .log, .generated),
            ("macos.application_support", "\(home)/Library/Application Support", .applicationSupport, .developer),
            ("macos.containers", "\(home)/Library/Containers", .applicationSupport, .developer),
            ("macos.group_containers", "\(home)/Library/Group Containers", .applicationSupport, .developer),
            ("user.downloads", "\(home)/Downloads", .userOriginal, .userData),
            ("macos.trash", "\(home)/.Trash", .cache, .generated),
            ("macos.keychain", "\(home)/Library/Keychains", .credentials, .userData),
            ("backup.ios", "\(home)/Library/Application Support/MobileSync/Backup", .userOriginal, .backup),
        ].compactMap {
            lightweightNode(id: $0.0, kind: $0.2, category: "MACOS", sub: $0.0, path: $0.1, scanner: scanner, bucket: $0.3, domain: domain)
        }
        if let t = ProcessInfo.processInfo.environment["TMPDIR"] {
            if let n = lightweightNode(id: "macos.tmpdir", kind: .temp, category: "MACOS", sub: "TEMP", path: t, scanner: scanner, bucket: .generated, domain: domain) {
                items.append(n)
            }
        }
        return items
    }
}

public struct CloudDetector: EntityDetector {
    public let domain = "Cloud"
    public let bucket = SystemDataBucket.cloud
    public init() {}
    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        var out: [DetectedEntity] = []
        if let n = node(id: "icloud.local_materialized", kind: .cloudLocalMaterialized, category: "CLOUD", sub: "ICLOUD", path: "\(home)/Library/Mobile Documents", scanner: scanner, bucket: bucket, domain: domain) {
            out.append(n)
        }
        if let n = node(id: "cloud.fileprovider_generic", kind: .cloudPlaceholder, category: "CLOUD", sub: "FILEPROVIDER", path: "\(home)/Library/CloudStorage", scanner: scanner, bucket: bucket, domain: domain) {
            out.append(n)
        }
        return out
    }
}

public struct DetectorCatalog {
    public var detectors: [any EntityDetector]
    public var proofTargets: Set<String>
    /// Process-local shared Cursor identity index (built once per detectAll / home).
    nonisolated(unsafe) public static var sharedCursorIndex: CursorIdentityIndex?
    nonisolated(unsafe) public static var sharedCursorIndexHome: String?
    nonisolated(unsafe) public static var lastCatalogTelemetry: DetectorCatalogRuntimeReport?

    /// proofTargets: "derived-data", "node-modules" (opt-in heavy/targeted proof)
    public init(detectors: [any EntityDetector]? = nil, proofTargets: Set<String> = ["derived-data"]) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let detectors {
            self.detectors = detectors
            self.proofTargets = proofTargets
            return
        }
        var list: [any EntityDetector] = [
            XcodeDetector(), NodeDetector(), DockerDetector(), HomebrewDetector(),
            PythonDetector(), GitDetector(), AIToolDetector(), MacOSDetector(), CloudDetector(),
            FolderDecomposer(domain: "macOS", bucket: .developer, parentID: "macos.application_support", parentPath: "\(home)/Library/Application Support"),
            FolderDecomposer(domain: "macOS", bucket: .developer, parentID: "macos.containers", parentPath: "\(home)/Library/Containers", kind: .applicationSupport, maxChildren: 60),
            FolderDecomposer(domain: "macOS", bucket: .developer, parentID: "macos.group_containers", parentPath: "\(home)/Library/Group Containers", kind: .applicationSupport, maxChildren: 40),
            FolderDecomposer(domain: "macOS", bucket: .generated, parentID: "macos.user_caches", parentPath: "\(home)/Library/Caches", kind: .cache, maxChildren: 40),
            AIToolDeepDetector(),
            ContainerDeepDetector(),
            AppSupportDeepDetector(),
            CursorSnapshotDetector(),
            ClaudeVMBundleDetector(),
            IOSBackupDetector(),
            GroupContainerLifecycleDetector(),
            CursorStoresVerificationDetector(),
            CloudResolutionDetector(),
            VoiceMemosDetector(),
        ]
        // P1.6: lightweight DerivedData proof is default (info.plist + du timeout, no recursive DirectoryMeasurer).
        if proofTargets.contains("derived-data") {
            list.append(XcodeDerivedDataProofDetector(maxChildren: 4))
        }
        // node_modules remains opt-in only — multi-GiB walks.
        if proofTargets.contains("node-modules") {
            list.append(NodeModulesProofDetector(maxProjects: 3))
        }
        // P1.7 SHOULD: semantic deep dive (lightweight, no Safety promotion)
        list.append(CursorWorkspaceStorageDetector(maxChildren: 12))
        list.append(ChromeAppSupportDetector())
        list.append(TomyLocalInspectorDetector())
        self.detectors = list
        self.proofTargets = proofTargets
    }

    public func detectAll(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        scanner: ReadOnlyStorageScanner = ReadOnlyStorageScanner(),
        telemetry: DetectorCatalogTelemetry? = nil,
        resetCaches: Bool = true
    ) -> [DetectedEntity] {
        let tel = telemetry ?? DetectorCatalogTelemetry()
        if resetCaches {
            DirectorySizeCache.reset()
            ScannedNodeCache.reset()
            SharedMetadataCache.reset()
            Self.sharedCursorIndex = nil
            Self.sharedCursorIndexHome = nil
        }

        if Self.sharedCursorIndex == nil || Self.sharedCursorIndexHome != home {
            tel.measureStage("catalog_initialization", note: "detectors=\(detectors.count)") {
                Self.sharedCursorIndex = CursorWorkspaceIdentityResolver.buildIndex(home: home)
                Self.sharedCursorIndexHome = home
            }
        }

        var merged: [DetectedEntity] = []
        let grouped = Self.groupDetectors(detectors)

        for (stage, group) in grouped {
            tel.measureStage(stage) {
                for detector in group {
                    let sizeBefore = DirectorySizeCache.stats()
                    let scanBefore = ScannedNodeCache.stats()
                    let started = Date()
                    let found = detector.detect(home: home, scanner: scanner)
                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    let sizeAfter = DirectorySizeCache.stats()
                    let scanAfter = ScannedNodeCache.stats()
                    let semanticBytes = found.reduce(Int64(0)) { $0 + ($1.annotation == nil ? 0 : $1.entity.logicalBytes) }
                    tel.recordDetector(
                        id: detector.detectorID,
                        tier: detector.tier,
                        domain: detector.domain,
                        durationMs: ms,
                        matchCount: found.count,
                        dirMeasures: sizeAfter.spawns - sizeBefore.spawns,
                        cacheHits: (sizeAfter.hits - sizeBefore.hits) + (scanAfter.hits - scanBefore.hits),
                        cacheMisses: (sizeAfter.spawns - sizeBefore.spawns) + (scanAfter.misses - scanBefore.misses),
                        semanticBytes: semanticBytes
                    )
                    merged.append(contentsOf: found)
                }
            }
        }

        let normalized = tel.measureStage("path_normalization_conflict_merge", entityCount: merged.count) {
            DetectorConflictResolver.merge(merged)
        }
        tel.measureStage("report_model_assembly", entityCount: normalized.count) { }
        Self.lastCatalogTelemetry = tel.snapshot()
        return normalized
    }

    static func groupDetectors(_ detectors: [any EntityDetector]) -> [(String, [any EntityDetector])] {
        var buckets: [String: [any EntityDetector]] = [:]
        for d in detectors {
            let stage = stageFor(detector: d)
            buckets[stage, default: []].append(d)
        }
        let order = [
            "detector_matching_core",
            "detector_matching_xcode_deriveddata",
            "detector_matching_node",
            "detector_matching_cursor",
            "detector_matching_claude",
            "detector_matching_chrome_tomylocal",
            "detector_matching_application_support",
            "detector_matching_containers",
            "detector_matching_group_containers",
            "detector_matching_caches",
            "detector_matching_generic_fallback",
            "detector_matching_opt_in_proof",
        ]
        var out: [(String, [any EntityDetector])] = []
        for key in order {
            if let items = buckets.removeValue(forKey: key), !items.isEmpty {
                out.append((key, items))
            }
        }
        for (k, v) in buckets.sorted(by: { $0.key < $1.key }) where !v.isEmpty {
            out.append((k, v))
        }
        return out
    }

    static func stageFor(detector: any EntityDetector) -> String {
        if let override = detector.runtimeStageOverride { return override }
        let id = detector.detectorID
        if detector.tier == .optInProof { return "detector_matching_opt_in_proof" }
        if id.contains("DerivedData") || id.contains("Xcode") { return "detector_matching_xcode_deriveddata" }
        if id.contains("Node") { return "detector_matching_node" }
        if id.contains("Cursor") { return "detector_matching_cursor" }
        if id.contains("Claude") { return "detector_matching_claude" }
        if id.contains("Chrome") || id.contains("TomyLocal") { return "detector_matching_chrome_tomylocal" }
        if id.contains("AppSupport") || id.contains("FolderDecomposer") && detector.domain == "macOS" {
            if id.contains("containers") || id.contains("Container") { return "detector_matching_containers" }
            if id.contains("group") || id.contains("Group") { return "detector_matching_group_containers" }
            if id.contains("Caches") || id.contains("cache") { return "detector_matching_caches" }
            return "detector_matching_application_support"
        }
        if id.contains("Container") { return "detector_matching_containers" }
        if id.contains("GroupContainer") { return "detector_matching_group_containers" }
        if id.contains("Git") || id.contains("Docker") || id.contains("Homebrew") || id.contains("Python") || id.contains("Cloud") || id.contains("MacOS") || id.contains("AITool") {
            return "detector_matching_core"
        }
        return "detector_matching_generic_fallback"
    }

    /// Legacy entry — prefer detectAll with telemetry from pipeline.
    public func detectAllLegacy(home: String = FileManager.default.homeDirectoryForCurrentUser.path, scanner: ReadOnlyStorageScanner = ReadOnlyStorageScanner()) -> [DetectedEntity] {
        detectAll(home: home, scanner: scanner)
    }
}
