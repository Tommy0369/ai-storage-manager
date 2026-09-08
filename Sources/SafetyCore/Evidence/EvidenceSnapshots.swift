import Foundation

public final class ProcessTableSnapshot: ProcessRunningChecker, @unchecked Sendable {
    public let names: Set<String>
    public let commandLines: [String]
    public let snapshotFailed: Bool
    public let failureReason: String?
    public let completeness: ObservationCompleteness
    public let capturedAt: Date

    public init(
        names: Set<String>,
        commandLines: [String] = [],
        snapshotFailed: Bool,
        failureReason: String?,
        completeness: ObservationCompleteness? = nil,
        capturedAt: Date = Date()
    ) {
        self.names = names
        self.commandLines = commandLines
        self.snapshotFailed = snapshotFailed
        self.failureReason = failureReason
        self.completeness = completeness ?? (snapshotFailed ? .partial : .complete)
        self.capturedAt = capturedAt
    }

    public static func capture() -> ProcessTableSnapshot {
        let names = captureNames()
        let lines = captureCommandLines(timeoutSeconds: 2.0)
        let failed = names == nil
        return ProcessTableSnapshot(
            names: names ?? Set(),
            commandLines: lines,
            snapshotFailed: failed,
            failureReason: failed ? "PS_SPAWN_FAILED" : nil,
            completeness: failed ? .partial : .complete
        )
    }

    static func captureNames() -> Set<String>? {
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
            return Set(text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        } catch {
            return nil
        }
    }

    static func captureCommandLines(timeoutSeconds: Double) -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-ax", "-o", "args="]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            var data = Data()
            let fh = out.fileHandleForReading
            while proc.isRunning, Date() < deadline {
                let chunk = fh.availableData
                if !chunk.isEmpty {
                    data.append(chunk)
                    if data.count > 2_000_000 { break }
                } else {
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
            if proc.isRunning { proc.terminate() }
            data.append(fh.readDataToEndOfFile())
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    public func isRunning(executableNames: [String]) -> PredicateValue {
        if snapshotFailed || completeness != .complete { return .unknown }
        guard !executableNames.isEmpty else { return .false }
        return executableNames.contains(where: { names.contains($0) }) ? .true : .false
    }

    public func referencesPath(_ path: String) -> Bool {
        if snapshotFailed || completeness != .complete { return false }
        let expanded = (path as NSString).standardizingPath
        return commandLines.contains { $0.contains(expanded) }
    }

    public static func merge(_ a: ProcessTableSnapshot, _ b: ProcessTableSnapshot) -> ProcessTableSnapshot {
        let failed = a.snapshotFailed && b.snapshotFailed
        let reason = a.failureReason ?? b.failureReason
        let completeness: ObservationCompleteness
        if failed {
            completeness = .partial
        } else if a.completeness == .complete, b.completeness == .complete {
            completeness = .complete
        } else if a.completeness == .partial || b.completeness == .partial || a.snapshotFailed || b.snapshotFailed {
            completeness = .partial
        } else {
            completeness = .unknown
        }
        return ProcessTableSnapshot(
            names: a.names.union(b.names),
            commandLines: Array(Set(a.commandLines + b.commandLines)),
            snapshotFailed: failed,
            failureReason: reason,
            completeness: completeness
        )
    }
}

public final class OpenFileSnapshot: OpenHandleChecker, @unchecked Sendable {
    public let openPaths: [String]
    public let snapshotFailed: Bool
    public let failureReason: String?
    public let completeness: ObservationCompleteness
    public let capturedAt: Date

    public init(openPaths: [String], snapshotFailed: Bool, failureReason: String?, completeness: ObservationCompleteness? = nil, capturedAt: Date = Date()) {
        self.openPaths = openPaths
        self.snapshotFailed = snapshotFailed
        self.failureReason = failureReason
        self.completeness = completeness ?? (snapshotFailed ? .partial : .complete)
        self.capturedAt = capturedAt
    }

    public static func capture() -> OpenFileSnapshot {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-nP", "-Fn"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            let timeout: TimeInterval = 15
            let started = Date()
            var data = Data()
            let fh = out.fileHandleForReading
            while proc.isRunning {
                if Date().timeIntervalSince(started) > timeout {
                    proc.terminate()
                    return OpenFileSnapshot(openPaths: [], snapshotFailed: true, failureReason: "LSOF_TIMEOUT", completeness: .partial)
                }
                let chunk = fh.availableData
                if !chunk.isEmpty {
                    data.append(chunk)
                    if data.count > 24_000_000 {
                        proc.terminate()
                        return OpenFileSnapshot(openPaths: [], snapshotFailed: true, failureReason: "LSOF_OUTPUT_TOO_LARGE", completeness: .partial)
                    }
                } else {
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }
            data.append(fh.readDataToEndOfFile())
            if proc.terminationStatus != 0, data.isEmpty {
                return OpenFileSnapshot(openPaths: [], snapshotFailed: true, failureReason: "LSOF_PERMISSION_OR_EMPTY", completeness: .partial)
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            var paths: [String] = []
            for line in text.split(whereSeparator: \.isNewline) {
                if line.first == "n" {
                    paths.append(String(line.dropFirst()))
                }
            }
            return OpenFileSnapshot(openPaths: paths, snapshotFailed: false, failureReason: nil, completeness: .complete)
        } catch {
            return OpenFileSnapshot(openPaths: [], snapshotFailed: true, failureReason: "LSOF_SPAWN_FAILED", completeness: .partial)
        }
    }

    public func hasOpenHandles(path: String) -> PredicateValue {
        if snapshotFailed || completeness != .complete { return .unknown }
        let expanded = (PathGlob.expandHome(path) as NSString).standardizingPath
        let hit = openPaths.contains { openRaw in
            let open = (openRaw as NSString).standardizingPath
            if open == expanded { return true }
            if open.hasPrefix(expanded + "/") { return true }
            return false
        }
        return hit ? .true : .false
    }

    public func hasExactOpenHandle(path: String) -> Bool {
        if snapshotFailed || completeness != .complete { return false }
        let expanded = (PathGlob.expandHome(path) as NSString).standardizingPath
        return openPaths.contains { ($0 as NSString).standardizingPath == expanded }
    }

    public static func merge(_ a: OpenFileSnapshot, _ b: OpenFileSnapshot) -> OpenFileSnapshot {
        let failed = a.snapshotFailed && b.snapshotFailed
        let reason = a.failureReason ?? b.failureReason
        let completeness: ObservationCompleteness
        if failed {
            completeness = .partial
        } else if a.completeness == .complete, b.completeness == .complete {
            completeness = .complete
        } else if a.completeness == .partial || b.completeness == .partial || a.snapshotFailed || b.snapshotFailed {
            completeness = .partial
        } else {
            completeness = .unknown
        }
        return OpenFileSnapshot(
            openPaths: Array(Set(a.openPaths + b.openPaths)),
            snapshotFailed: failed,
            failureReason: reason,
            completeness: completeness
        )
    }
}

/// Bounded dual-snapshot window for Claude exact ACTIVE observation.
public enum RuntimeObservationWindow {
    public static let maxSnapshots = 2
    public static let gapMs = 400

    public static func capture(
        processCapture: () -> ProcessTableSnapshot = { ProcessTableSnapshot.capture() },
        fileCapture: () -> OpenFileSnapshot = { OpenFileSnapshot.capture() },
        snapshots: Int = maxSnapshots,
        gapMs: Int = gapMs
    ) -> (ProcessTableSnapshot, OpenFileSnapshot) {
        let n = min(max(snapshots, 1), maxSnapshots)
        var procs: [ProcessTableSnapshot] = []
        var files: [OpenFileSnapshot] = []
        for i in 0..<n {
            procs.append(processCapture())
            files.append(fileCapture())
            if i + 1 < n {
                Thread.sleep(forTimeInterval: Double(gapMs) / 1000.0)
            }
        }
        let proc = procs.dropFirst().reduce(procs[0]) { ProcessTableSnapshot.merge($0, $1) }
        let file = files.dropFirst().reduce(files[0]) { OpenFileSnapshot.merge($0, $1) }
        return (proc, file)
    }
}
