import Foundation

public protocol ProcessRunningChecker: Sendable {
    func isRunning(executableNames: [String]) -> PredicateValue
}

public protocol OpenHandleChecker: Sendable {
    func hasOpenHandles(path: String) -> PredicateValue
}

public struct ProcessCheck: ProcessRunningChecker {
    public init() {}

    public func isRunning(executableNames: [String]) -> PredicateValue {
        guard !executableNames.isEmpty else { return .false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-axc", "-o", "comm="]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let names = Set(text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) })
            let hit = executableNames.contains { names.contains($0) }
            return hit ? .true : .false
        } catch {
            return .unknown
        }
    }
}

public struct LSOFHandleChecker: OpenHandleChecker {
    public init() {}

    public func hasOpenHandles(path: String) -> PredicateValue {
        let expanded = PathGlob.expandHome(path)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-t", expanded]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            if proc.terminationStatus != 0, data.isEmpty {
                return .unknown
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .false : .true
        } catch {
            return .unknown
        }
    }
}

public struct EvidenceResolver: Sendable {
    public var processes: any ProcessRunningChecker
    public var handles: any OpenHandleChecker
    public var processNames: [String]

    public init(
        processes: any ProcessRunningChecker = ProcessCheck(),
        handles: any OpenHandleChecker = LSOFHandleChecker(),
        processNames: [String] = []
    ) {
        self.processes = processes
        self.handles = handles
        self.processNames = processNames
    }

    public func resolve(path: String, hints: EvidenceBundle? = nil, associatedProcesses: [String] = []) -> EvidenceBundle {
        var bundle = hints ?? EvidenceBundle(canonicalPath: PathGlob.expandHome(path), confidence: 0.2)
        let expanded = PathGlob.expandHome(path)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir)
        if exists {
            bundle.canonicalPath = (expanded as NSString).standardizingPath
            bundle.confidence = max(bundle.confidence, 0.5)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: expanded)) != nil {
                bundle.isSymlink = .true
            } else {
                bundle.isSymlink = .false
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: expanded) {
                if let owner = attrs[.ownerAccountName] as? String {
                    let me = NSUserName()
                    bundle.ownerIsCurrentUser = owner == me ? .true : .false
                }
            }
            let url = URL(fileURLWithPath: expanded)
            if let vals = try? url.resourceValues(forKeys: [.isPackageKey, .ubiquitousItemDownloadingStatusKey]) {
                bundle.isPackage = (vals.isPackage ?? false) ? .true : .false
                if vals.ubiquitousItemDownloadingStatus != nil {
                    bundle.cloudFileProvider = .true
                    bundle.iCloudEvictable = .unknown
                    bundle.syncWouldDeleteRemote = .unknown
                }
            }
        }
        if HardSafetyGates.isHardBlocked(path: expanded) {
            bundle.sipProtected = .true
        }
        let names = associatedProcesses + processNames
        if !names.isEmpty {
            bundle.owningProcessRunning = processes.isRunning(executableNames: names)
        }
        bundle.openFileHandle = handles.hasOpenHandles(path: expanded)
        fillProjectSignals(&bundle, path: expanded)
        return bundle
    }

    func fillProjectSignals(_ bundle: inout EvidenceBundle, path: String) {
        let url = URL(fileURLWithPath: path)
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let dir = isDirectory ? url : url.deletingLastPathComponent()
        let fm = FileManager.default
        let manifest = ["package.json", "Package.swift", "pyproject.toml", "Pipfile", "go.mod", "Cargo.toml"]
            .contains { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
        let lock = ["package-lock.json", "pnpm-lock.yaml", "yarn.lock", "Poetry.lock", "Cargo.lock"]
            .contains { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }
            || fm.fileExists(atPath: dir.appendingPathComponent("..").appendingPathComponent("package.json").path)
        if path.contains("node_modules") {
            let root = climbFor(file: "package.json", from: dir)
            bundle.manifestExists = root != nil ? .true : .false
            if let root {
                let hasLock = ["package-lock.json", "pnpm-lock.yaml", "yarn.lock"].contains {
                    fm.fileExists(atPath: root.appendingPathComponent($0).path)
                }
                bundle.lockfileExists = hasLock ? .true : .false
                bundle.sourceProjectExists = .true
            } else {
                bundle.lockfileExists = .false
                bundle.sourceProjectExists = .false
            }
        } else {
            if manifest { bundle.manifestExists = .true }
            if lock { bundle.lockfileExists = .true }
        }
        if path.contains("DerivedData") {
            // Prefer Info.plist WorkspacePath (VERIFIED source relation when present)
            let info = dir.appendingPathComponent("info.plist")
            if let ws = XcodeDerivedDataProofDetector.readWorkspacePath(info.path) {
                let exists = fm.fileExists(atPath: ws)
                bundle.sourceProjectExists = exists ? .true : .false
                if exists {
                    bundle.predicateConfidence["source_project_exists"] = .verified
                    bundle.extra["deriveddata_workspace_path"] = .true
                }
            } else if climbFor(file: "Package.swift", from: dir) != nil
                || climbFor(file: "project.pbxproj", from: dir) != nil {
                bundle.sourceProjectExists = .true
                bundle.predicateConfidence["source_project_exists"] = .verified
            }
        }
        let lockFiles = [".git/index.lock", "docker.pid", "yarn.lock"]
        _ = lockFiles
        if fm.fileExists(atPath: dir.appendingPathComponent(".git/index.lock").path) {
            bundle.extra["lockfile_present"] = .true
        }
    }

    func climbFor(file: String, from: URL) -> URL? {
        var current = from
        let fm = FileManager.default
        for _ in 0..<8 {
            if fm.fileExists(atPath: current.appendingPathComponent(file).path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }
}

public struct EvidenceSnapshot: Equatable, Sendable {
    public var capturedAt: Date
    public var bundle: EvidenceBundle
    public var state: RuntimeState
}

public struct ReconfirmGate {
    public var resolver: EvidenceResolver

    public init(resolver: EvidenceResolver = EvidenceResolver()) {
        self.resolver = resolver
    }

    /// TOCTOU: never act on stale evidence. Re-resolve immediately before any future action.
    public func reconfirm(path: String, previous: EvidenceSnapshot, associatedProcesses: [String]) -> (fresh: EvidenceSnapshot, stale: Bool) {
        let freshBundle = resolver.resolve(path: path, associatedProcesses: associatedProcesses)
        let running = freshBundle.owningProcessRunning == .true || freshBundle.openFileHandle == .true
        let state = RuntimeState(
            hasOpenHandles: freshBundle.openFileHandle == .true,
            owningProcessRunning: freshBundle.owningProcessRunning == .true,
            lockPresent: freshBundle.extra["lockfile_present"] == .true,
            unknownWriteActivity: running && previous.bundle.openFileHandle != freshBundle.openFileHandle
        )
        let fresh = EvidenceSnapshot(capturedAt: Date(), bundle: freshBundle, state: state)
        let stale = previous.bundle.openFileHandle != freshBundle.openFileHandle
            || previous.bundle.owningProcessRunning != freshBundle.owningProcessRunning
            || previous.bundle.isSymlink != freshBundle.isSymlink
        return (fresh, stale)
    }
}
