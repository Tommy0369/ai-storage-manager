import Foundation

/// P3.3C — bounded read-only inventory of Cursor agent-cli version stores.
public enum CursorAgentCLIInventory {
    public struct VersionRecord: Codable, Sendable, Equatable {
        public var versionID: String
        public var observedBytes: Int64
        public var uniqueBytes: Int64
        public var fileCount: Int
        public var architecture: String
        public var packageName: String?
        public var hasRunningMarker: Bool
        public var userishNames: [String]
        public var selectionState: String
        public var runtimeState: String
        public var state: CursorAgentCLIVersionState
    }

    public struct RootReport: Codable, Sendable, Equatable {
        public var rootEntityID: String
        public var rootPathClass: String
        public var owner: String
        public var semanticRole: String
        public var observedBytes: Int64
        public var uniqueBytes: Int64
        public var mappedVersionBytes: Int64
        public var unknownBytes: Int64
        public var versionCount: Int
        public var accountingValid: Bool
        public var rootExecutable: Bool
        public var selectedVersion: String?
        public var hardlinkSharedBytes: Int64
    }

    public static func measureDirectory(_ path: String) -> (observed: Int64, unique: Int64, files: Int) {
        let fm = FileManager.default
        var observed: Int64 = 0
        var unique: Int64 = 0
        var files = 0
        var seen = Set<String>()
        guard let enumerator = fm.enumerator(atPath: path) else { return (0, 0, 0) }
        while let rel = enumerator.nextObject() as? String {
            let full = (path as NSString).appendingPathComponent(rel)
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let type = attrs[.type] as? FileAttributeType,
                  type != .typeDirectory else { continue }
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            files += 1
            observed += size
            let ino = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            let dev = (attrs[.systemNumber] as? NSNumber)?.uint64Value ?? 0
            let key = "\(dev):\(ino)"
            if !seen.contains(key) {
                seen.insert(key)
                unique += size
            }
        }
        return (observed, unique, files)
    }

    public static func inventory(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> (root: RootReport, versions: [VersionRecord]) {
        let versionsPath = CursorAgentCLIPathResolver.versionsRoot(home: home)
        let agentRoot = CursorAgentCLIPathResolver.agentCLIRoot(home: home)
        let selected = CursorAgentCLIPathResolver.resolveSelectedVersion(home: home)
        let rootMeasure = measureDirectory(agentRoot)
        var records: [VersionRecord] = []
        var mapped: Int64 = 0
        let fm = FileManager.default
        if let kids = try? fm.contentsOfDirectory(atPath: versionsPath) {
            for name in kids.sorted() {
                let child = (versionsPath as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue else { continue }
                let m = measureDirectory(child)
                mapped += m.unique
                let pkg = try? String(contentsOfFile: child + "/package.json", encoding: .utf8)
                let packageName: String?
                if let pkg, let data = pkg.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    packageName = json["name"] as? String
                } else {
                    packageName = nil
                }
                let running = fm.fileExists(atPath: child + "/.running")
                let top = (try? fm.contentsOfDirectory(atPath: child)) ?? []
                let userish = top.filter {
                    ["workspace", "projects", "conversations", "credentials", ".env"].contains($0.lowercased())
                }
                let isCurrent = name == selected
                let arch: String = {
                    let node = child + "/node"
                    guard fm.fileExists(atPath: node) else { return "unknown" }
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/file")
                    proc.arguments = ["-b", node]
                    let pipe = Pipe()
                    proc.standardOutput = pipe
                    proc.standardError = Pipe()
                    try? proc.run()
                    proc.waitUntilExit()
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if out.contains("arm64") { return "arm64" }
                    if out.contains("x86_64") { return "x86_64" }
                    return "unknown"
                }()
                records.append(VersionRecord(
                    versionID: name,
                    observedBytes: m.observed,
                    uniqueBytes: m.unique,
                    fileCount: m.files,
                    architecture: arch,
                    packageName: packageName,
                    hasRunningMarker: running,
                    userishNames: userish,
                    selectionState: isCurrent ? "CURRENT_SELECTED" : "NOT_SELECTED",
                    runtimeState: "RUNTIME_UNKNOWN",
                    state: isCurrent ? .currentInactive : .inactiveButReacquisitionUnknown
                ))
            }
        }
        let unknown = max(0, rootMeasure.unique - mapped)
        let root = RootReport(
            rootEntityID: "ai.cursor.agent_cli_versions",
            rootPathClass: "anysphere.cursor-agent-worker/agent-cli",
            owner: "CURSOR",
            semanticRole: "AGENT_CLI_TOOLCHAIN_VERSIONS",
            observedBytes: rootMeasure.observed,
            uniqueBytes: rootMeasure.unique,
            mappedVersionBytes: mapped,
            unknownBytes: unknown,
            versionCount: records.count,
            accountingValid: mapped <= rootMeasure.unique + 1024,
            rootExecutable: false,
            selectedVersion: selected,
            hardlinkSharedBytes: max(0, rootMeasure.observed - rootMeasure.unique)
        )
        return (root, records)
    }
}
