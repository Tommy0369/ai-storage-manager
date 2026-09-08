import Foundation

public struct RuntimeObservationIndex: Sendable {
    public let runtimeGeneration: Int
    public let observedAt: Date
    public let processCompleteness: ObservationCompleteness
    public let handleCompleteness: ObservationCompleteness
    public let processSnapshotFailed: Bool
    public let handleSnapshotFailed: Bool
    public let processNames: Set<String>
    public let exactOpenPaths: Set<String>
    public let sortedOpenPaths: [String]
    public let referencedCommandPaths: Set<String>
    public let commandLineBlob: String
    public let buildRuntimeMs: Int
    public let parseFailures: Int

    public static func build(
        processes: any ProcessRunningChecker,
        handles: any OpenHandleChecker,
        observedAt: Date = Date()
    ) -> RuntimeObservationIndex {
        let started = Date()
        var parseFailures = 0
        let procSnap = processes as? ProcessTableSnapshot
        let fileSnap = handles as? OpenFileSnapshot
        let processCompleteness = procSnap?.completeness ?? .unknown
        let handleCompleteness = fileSnap?.completeness ?? .unknown
        let processFailed = procSnap?.snapshotFailed ?? true
        let handleFailed = fileSnap?.snapshotFailed ?? true

        var names = Set<String>()
        if let snap = procSnap, !snap.snapshotFailed {
            names = snap.names
        }

        var exactOpen = Set<String>()
        var sortedOpen: [String] = []
        if let snap = fileSnap, !snap.snapshotFailed {
            exactOpen = Set(snap.openPaths.map { RuntimePathMatcher.canonical($0) })
            sortedOpen = exactOpen.sorted()
        }

        var referenced = Set<String>()
        var blob = ""
        if let snap = procSnap, snap.completeness == .complete, !snap.snapshotFailed {
            blob = snap.commandLines.joined(separator: "\n")
            for line in snap.commandLines {
                referenced.formUnion(extractPathTokens(from: line, parseFailures: &parseFailures))
            }
        }

        let ms = Int(Date().timeIntervalSince(started) * 1000)
        var hasher = Hasher()
        hasher.combine(processCompleteness.rawValue)
        hasher.combine(handleCompleteness.rawValue)
        hasher.combine(exactOpen.count)
        hasher.combine(referenced.count)
        hasher.combine(observedAt.timeIntervalSince1970)
        let generation = hasher.finalize()

        return RuntimeObservationIndex(
            runtimeGeneration: generation,
            observedAt: observedAt,
            processCompleteness: processCompleteness,
            handleCompleteness: handleCompleteness,
            processSnapshotFailed: processFailed,
            handleSnapshotFailed: handleFailed,
            processNames: names,
            exactOpenPaths: exactOpen,
            sortedOpenPaths: sortedOpen,
            referencedCommandPaths: referenced,
            commandLineBlob: blob,
            buildRuntimeMs: ms,
            parseFailures: parseFailures
        )
    }

    public func report() -> RuntimeObservationIndexReport {
        RuntimeObservationIndexReport(
            processObservationsIndexed: referencedCommandPaths.count + processNames.count,
            openFileObservationsIndexed: exactOpenPaths.count,
            exactPathKeys: exactOpenPaths.count,
            commandPathKeys: referencedCommandPaths.count,
            buildRuntimeMs: buildRuntimeMs,
            parseFailures: parseFailures,
            processCompleteness: processCompleteness.rawValue,
            openFileCompleteness: handleCompleteness.rawValue,
            runtimeGeneration: runtimeGeneration
        )
    }

    public func hasOpenHandle(entityPath: String, contract: RuntimeSensitiveContract) -> PredicateValue {
        _ = contract
        return openHandleMatchingReference(path: entityPath)
    }

    public func openHandleMatchingReference(path: String) -> PredicateValue {
        if handleSnapshotFailed || handleCompleteness != .complete { return .unknown }
        let expanded = RuntimePathMatcher.canonical(path)
        if exactOpenPaths.contains(expanded) { return .true }
        if hasOpenDescendant(of: expanded) { return .true }
        return .false
    }

    public func hasExactOpenHandle(path: String) -> Bool {
        if handleSnapshotFailed || handleCompleteness != .complete { return false }
        return exactOpenPaths.contains(RuntimePathMatcher.canonical(path))
    }

    public func referencesPath(_ entityPath: String, contract: RuntimeSensitiveContract) -> Bool {
        _ = contract
        if processSnapshotFailed || processCompleteness != .complete { return false }
        let expanded = RuntimePathMatcher.canonical(entityPath)
        if referencedCommandPaths.contains(expanded) { return true }
        return commandLineBlob.contains(expanded)
    }

    public func isRunning(executableNames: [String]) -> PredicateValue {
        if processSnapshotFailed || processCompleteness != .complete { return .unknown }
        guard !executableNames.isEmpty else { return .false }
        return executableNames.contains(where: { processNames.contains($0) }) ? .true : .false
    }

    func hasOpenDescendant(of entityPath: String) -> Bool {
        let prefix = entityPath + "/"
        var lo = 0
        var hi = sortedOpenPaths.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedOpenPaths[mid] < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo < sortedOpenPaths.count && sortedOpenPaths[lo].hasPrefix(prefix)
    }

    static func extractPathTokens(from line: String, parseFailures: inout Int) -> Set<String> {
        var out = Set<String>()
        let parts = line.split(whereSeparator: { $0.isWhitespace })
        var tokenCount = 0
        for part in parts {
            tokenCount += 1
            if tokenCount > 64 { break }
            let s = String(part)
            guard s.contains("/"), s.count >= 2, s.count <= 4096 else { continue }
            if s.hasPrefix("/") || s.contains("/Users/") || s.contains("/Library/") || s.contains("/Volumes/") {
                out.insert(RuntimePathMatcher.canonical(s))
            }
        }
        if tokenCount > 64 { parseFailures += 1 }
        return out
    }
}
