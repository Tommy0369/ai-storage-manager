import Foundation

/// Per-scan-session measurement authority. Scanner owns capacity observation; detectors consume.
public final class ScanSessionContext: @unchecked Sendable {
    public static let p18Baseline = P19RuntimeComparison(
        p18TotalSeconds: 142.3,
        p19TotalSeconds: 0,
        scannerFilesystemWalkP18Ms: 47_513,
        scannerFilesystemWalkP19Ms: 0,
        detectorCatalogP18Ms: 45_432,
        detectorCatalogP19Ms: 0,
        duSpawnsP19: 0,
        duTimeoutsP19: 0,
        duplicateMeasurementCountP19: 0
    )

    nonisolated(unsafe) public static var current: ScanSessionContext?

    private var measurements: [String: SizeMeasurement] = [:]
    private var scannedNodes: [String: ScannedNode] = [:]
    private var opCounts: [String: (count: Int, diskCount: Int, callers: Set<String>, ms: Int)] = [:]
    private var pathTimings: [ScannerPathTiming] = []
    private var rootTimings: [ScannerRootTiming] = []
    private var budgetEvents: [ScannerBudgetEvent] = []
    private var duSpawnRecords: [(path: String, ms: Int, timedOut: Bool, caller: String)] = []
    private let lock = NSLock()

    public var budget: ScanBudgetConfig
    public var directoriesVisited: Int = 0
    public var directoryEnumerations: Int = 0
    public var metadataReads: Int = 0
    public var cacheHits: Int = 0
    public var cacheMisses: Int = 0
    public var measurementCacheHits: Int = 0
    public var measurementCacheMisses: Int = 0
    public var nodeCacheHits: Int = 0
    public var nodeCacheMisses: Int = 0
    public var errors: Int = 0
    public var measurementRequests: Int = 0
    public var uniqueMeasurementKeys: Int = 0
    public var coalescedRequests: Int = 0
    public var maxMeasurementConcurrency: Int = 0
    public let performanceTrace = ScanPerformanceTrace()
    public var testMeasurementOverride: (@Sendable (String) -> SizeMeasurement?)?

    private var inFlight: [String: MeasurementSlot] = [:]
    private var liveDuCount = 0
    private let duGate: DispatchSemaphore

    private final class MeasurementSlot: @unchecked Sendable {
        let condition = NSCondition()
        var result: SizeMeasurement?
    }

    public init(budget: ScanBudgetConfig = .default) {
        self.budget = budget
        self.duGate = DispatchSemaphore(value: max(1, budget.maxConcurrentMeasurements))
    }

    public static func begin(budget: ScanBudgetConfig = .default) -> ScanSessionContext {
        let session = ScanSessionContext(budget: budget)
        current = session
        DirectorySizeCache.bind(session)
        ScannedNodeCache.bind(session)
        SharedMetadataCache.bind(session)
        return session
    }

    public static func end() {
        DirectorySizeCache.unbind()
        ScannedNodeCache.unbind()
        SharedMetadataCache.unbind()
        current = nil
    }

    public func canonical(_ path: String) -> String {
        (PathGlob.expandHome(path) as NSString).standardizingPath
    }

    func recordOp(path: String, operation: String, caller: String, durationMs: Int, diskIO: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(operation)|\(canonical(path))"
        var entry = opCounts[key] ?? (0, 0, [], 0)
        entry.count += 1
        if diskIO { entry.diskCount += 1 }
        entry.callers.insert(caller)
        entry.ms += durationMs
        opCounts[key] = entry
    }

    public func measure(
        path: String,
        caller: String,
        timeoutSeconds: Double? = nil,
        mode: String = "bounded_du"
    ) -> SizeMeasurement {
        let key = canonical(path)
        lock.lock()
        measurementRequests += 1
        if let hit = measurements[key] {
            measurementCacheHits += 1
            cacheHits += 1
            lock.unlock()
            recordOp(path: key, operation: "size_calculation", caller: caller, durationMs: 0, diskIO: false)
            return hit
        }
        if let slot = inFlight[key] {
            coalescedRequests += 1
            lock.unlock()
            slot.condition.lock()
            while slot.result == nil {
                slot.condition.wait()
            }
            let value = slot.result!
            slot.condition.unlock()
            recordOp(path: key, operation: "size_calculation", caller: caller, durationMs: 0, diskIO: false)
            return value
        }
        let slot = MeasurementSlot()
        inFlight[key] = slot
        uniqueMeasurementKeys += 1
        measurementCacheMisses += 1
        cacheMisses += 1
        lock.unlock()

        let result: SizeMeasurement
        if let override = testMeasurementOverride?(key) {
            result = override
        } else {
            duGate.wait()
            lock.lock()
            liveDuCount += 1
            maxMeasurementConcurrency = max(maxMeasurementConcurrency, liveDuCount)
            lock.unlock()
            result = performMeasurement(key: key, caller: caller, timeoutSeconds: timeoutSeconds, mode: mode)
            lock.lock()
            liveDuCount -= 1
            lock.unlock()
            duGate.signal()
        }

        store(key, result)
        lock.lock()
        inFlight[key] = nil
        lock.unlock()
        slot.condition.lock()
        slot.result = result
        slot.condition.broadcast()
        slot.condition.unlock()
        return result
    }

    public func waitForMeasurement(path: String, timeoutSeconds: Double) -> SizeMeasurement? {
        let key = canonical(path)
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            lock.lock()
            if let hit = measurements[key] {
                lock.unlock()
                return hit
            }
            let slot = inFlight[key]
            lock.unlock()
            if let slot {
                slot.condition.lock()
                if slot.result == nil {
                    _ = slot.condition.wait(until: min(deadline, Date().addingTimeInterval(0.05)))
                }
                let value = slot.result
                slot.condition.unlock()
                if let value { return value }
            } else {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        lock.lock(); defer { lock.unlock() }
        return measurements[key]
    }

    private func performMeasurement(
        key: String,
        caller: String,
        timeoutSeconds: Double?,
        mode: String
    ) -> SizeMeasurement {
        let started = Date()
        let timeout = timeoutSeconds ?? Double(budget.duTimeoutMs) / 1000.0
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: key, isDirectory: &isDir) else {
            return SizeMeasurement.unknown(reason: "PATH_NOT_PRESENT", method: "existence_check")
        }

        let result: SizeMeasurement
        if isDir.boolValue {
            if let bytes = boundedDu(at: key, timeoutSeconds: timeout, caller: caller) {
                result = SizeMeasurement.exact(bytes: bytes, method: mode)
            } else {
                result = SizeMeasurement.unknown(reason: "DU_TIMEOUT", timedOut: true, method: mode)
            }
        } else {
            metadataReads += 1
            if let vals = try? URL(fileURLWithPath: key).resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) {
                let b = Int64(vals.fileSize ?? vals.totalFileAllocatedSize ?? 0)
                result = SizeMeasurement.exact(bytes: b, method: "metadata_file")
            } else {
                result = SizeMeasurement.unknown(reason: "METADATA_READ_FAILED", method: "metadata_file")
            }
        }

        let ms = Int(Date().timeIntervalSince(started) * 1000)
        recordOp(path: key, operation: "size_calculation", caller: caller, durationMs: ms)
        lock.lock()
        pathTimings.append(ScannerPathTiming(
            path: key,
            operation: "size_calculation",
            durationMs: ms,
            depth: key.split(separator: "/").count,
            childrenCount: 0,
            measurementMode: mode,
            cacheHit: false,
            timedOut: result.timedOut,
            bytesResult: result.bytes,
            measurementQuality: result.quality,
            caller: caller
        ))
        lock.unlock()
        return result
    }

    func store(_ key: String, _ measurement: SizeMeasurement) {
        lock.lock()
        measurements[key] = measurement
        lock.unlock()
    }

    public func measurement(for path: String) -> SizeMeasurement? {
        lock.lock(); defer { lock.unlock() }
        return measurements[canonical(path)]
    }

    public func getOrScanNode(path: String, scanner: ReadOnlyStorageScanner, caller: String) -> ScannedNode? {
        let key = canonical(path)
        lock.lock()
        if let hit = scannedNodes[key] {
            nodeCacheHits += 1
            cacheHits += 1
            lock.unlock()
            recordOp(path: key, operation: "scan_node", caller: caller, durationMs: 0, diskIO: false)
            return hit
        }
        nodeCacheMisses += 1
        cacheMisses += 1
        lock.unlock()
        guard let node = scanner.scanNode(path: path, caller: caller) else { return nil }
        lock.lock()
        scannedNodes[key] = node
        lock.unlock()
        return node
    }

    public func recordRootScan(path: String, durationMs: Int, measurement: SizeMeasurement) {
        rootTimings.append(ScannerRootTiming(
            rootPath: path,
            durationMs: durationMs,
            measurementQuality: measurement.quality,
            bytes: measurement.bytes,
            timedOut: measurement.timedOut
        ))
    }

    public func recordDirectoryEnumeration(at path: String, childCount: Int, caller: String, durationMs: Int) {
        directoryEnumerations += 1
        directoriesVisited += childCount
        recordOp(path: path, operation: "directory_enumeration", caller: caller, durationMs: durationMs)
    }

    public func recordBudgetEvent(_ event: String, path: String?, budgetMs: Int, elapsedMs: Int, note: String? = nil) {
        budgetEvents.append(ScannerBudgetEvent(event: event, path: path, budgetMs: budgetMs, elapsedMs: elapsedMs, note: note))
    }

    func boundedDu(at path: String, timeoutSeconds: Double, caller: String) -> Int64? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        proc.arguments = ["-skP", path]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        let started = Date()
        do {
            try proc.run()
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while proc.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if proc.isRunning {
                proc.terminate()
                lock.lock()
                duSpawnRecords.append((path, ms, true, caller))
                lock.unlock()
                recordBudgetEvent("DU_TIMEOUT", path: path, budgetMs: Int(timeoutSeconds * 1000), elapsedMs: ms)
                return nil
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            guard let first = text.split(whereSeparator: \.isWhitespace).first,
                  let kb = Int64(first)
            else {
                lock.lock()
                duSpawnRecords.append((path, ms, false, caller))
                lock.unlock()
                return nil
            }
            lock.lock()
            duSpawnRecords.append((path, ms, false, caller))
            lock.unlock()
            return kb * 1024
        } catch {
            errors += 1
            return nil
        }
    }

    public func filesystemRuntimeReport(totalMs: Int) -> ScannerFilesystemRuntimeReport {
        lock.lock()
        let ops = opCounts
        let timings = pathTimings
        let roots = rootTimings
        let duRecords = duSpawnRecords
        let hits = cacheHits
        let misses = cacheMisses
        lock.unlock()
        let slowest = timings.sorted { $0.durationMs > $1.durationMs }.prefix(20)
        return ScannerFilesystemRuntimeReport(
            totalDurationMs: totalMs,
            roots: roots,
            directoriesVisited: directoriesVisited,
            directoryEnumerations: directoryEnumerations,
            sizeCalculations: ops.filter { $0.key.hasPrefix("size_calculation|") }.values.map(\.count).reduce(0, +),
            metadataReads: metadataReads,
            cacheHits: hits,
            cacheMisses: misses,
            duSpawns: duRecords.count,
            duTimeouts: duRecords.filter(\.timedOut).count,
            budgetExceeded: budgetEvents.count,
            errors: errors,
            slowestPaths: Array(slowest)
        )
    }

    public func duplicationReport() -> ScannerIODuplicationReport {
        lock.lock()
        let ops = opCounts
        lock.unlock()
        var entries: [ScannerIODuplicationEntry] = []
        var totalDup = 0
        var totalMs = 0
        for (key, val) in ops where val.diskCount > 1 {
            let parts = key.split(separator: "|", maxSplits: 1)
            let op = parts.first.map(String.init) ?? key
            let path = parts.count > 1 ? String(parts[1]) : key
            let dup = val.diskCount - 1
            let estMs = val.diskCount > 0 ? (val.ms / val.diskCount) * dup : 0
            totalDup += dup
            totalMs += estMs
            entries.append(ScannerIODuplicationEntry(
                path: path,
                operation: op,
                count: val.count,
                estimatedDuplicatedRuntimeMs: estMs,
                callers: Array(val.callers).sorted(),
                cacheable: op != "directory_enumeration"
            ))
        }
        entries.sort { $0.estimatedDuplicatedRuntimeMs > $1.estimatedDuplicatedRuntimeMs }
        return ScannerIODuplicationReport(
            entries: entries,
            totalDuplicatedOperations: totalDup,
            estimatedDuplicatedRuntimeMs: totalMs
        )
    }

    public func budgetEventsReport() -> [ScannerBudgetEvent] {
        lock.lock(); defer { lock.unlock() }
        return budgetEvents
    }

    public func duSpawnCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return duSpawnRecords.count
    }

    public func duTimeoutCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return duSpawnRecords.filter(\.timedOut).count
    }
}
