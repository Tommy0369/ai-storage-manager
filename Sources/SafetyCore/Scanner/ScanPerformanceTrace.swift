import Foundation

public struct ScanPerformanceSpan: Codable, Sendable, Equatable {
    public var name: String
    public var startMs: Int
    public var endMs: Int
    public var durationMs: Int
    public var nodeCount: Int
    public var cacheHits: Int
    public var cacheMisses: Int
    public var ioType: String
    public var timeoutCount: Int
    public var budgetExhausted: Bool
    public var blocking: Bool

    public init(
        name: String,
        startMs: Int,
        endMs: Int,
        durationMs: Int,
        nodeCount: Int = 0,
        cacheHits: Int = 0,
        cacheMisses: Int = 0,
        ioType: String = "none",
        timeoutCount: Int = 0,
        budgetExhausted: Bool = false,
        blocking: Bool = true
    ) {
        self.name = name
        self.startMs = startMs
        self.endMs = endMs
        self.durationMs = durationMs
        self.nodeCount = nodeCount
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
        self.ioType = ioType
        self.timeoutCount = timeoutCount
        self.budgetExhausted = budgetExhausted
        self.blocking = blocking
    }
}

/// Privacy-safe scan stage timings. No path payloads.
public final class ScanPerformanceTrace: @unchecked Sendable {
    private let lock = NSLock()
    private let started: Date
    private var open: [String: (startMs: Int, hits: Int, misses: Int)] = [:]
    public private(set) var spans: [ScanPerformanceSpan] = []

    public init(started: Date = Date()) {
        self.started = started
    }

    public func nowMs() -> Int {
        Int(Date().timeIntervalSince(started) * 1000)
    }

    public func start(_ name: String, cacheHits: Int = 0, cacheMisses: Int = 0) {
        lock.lock()
        open[name] = (nowMs(), cacheHits, cacheMisses)
        lock.unlock()
    }

    public func end(
        _ name: String,
        nodeCount: Int = 0,
        cacheHits: Int = 0,
        cacheMisses: Int = 0,
        ioType: String = "none",
        timeoutCount: Int = 0,
        budgetExhausted: Bool = false,
        blocking: Bool = true
    ) {
        lock.lock()
        let end = nowMs()
        let opened = open.removeValue(forKey: name)
        let start = opened?.startMs ?? end
        spans.append(ScanPerformanceSpan(
            name: name,
            startMs: start,
            endMs: end,
            durationMs: max(0, end - start),
            nodeCount: nodeCount,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            ioType: ioType,
            timeoutCount: timeoutCount,
            budgetExhausted: budgetExhausted,
            blocking: blocking
        ))
        lock.unlock()
    }

    public func snapshot() -> [ScanPerformanceSpan] {
        lock.lock(); defer { lock.unlock() }
        return spans.sorted { $0.durationMs > $1.durationMs }
    }
}

public enum PhysicalHierarchyPublication: String, Codable, Sendable, Equatable {
    case firstUsefulMap = "FIRST_USEFUL_MAP"
    case directChildrenMeasured = "DIRECT_CHILDREN_MEASURED"
    case complete = "COMPLETE"
}
