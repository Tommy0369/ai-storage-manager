import Foundation

public struct AuditEvent: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var entityID: String
    public var pathBasename: String
    public var pathDirectoryDepth: Int
    public var logicalBytes: Int64
    public var previousClass: SafetyClass?
    public var safetyClass: SafetyClass
    public var reasonCodes: [String]
    public var action: ActionMode
    public var userApproved: Bool?
    public var executionOK: Bool?
    public var verificationNotes: [String]

    public init(
        timestamp: Date = Date(),
        entityID: String,
        path: String,
        logicalBytes: Int64,
        previousClass: SafetyClass?,
        safetyClass: SafetyClass,
        reasonCodes: [String],
        action: ActionMode,
        userApproved: Bool?,
        executionOK: Bool?,
        verificationNotes: [String]
    ) {
        self.timestamp = timestamp
        self.entityID = entityID
        self.pathBasename = URL(fileURLWithPath: path).lastPathComponent
        self.pathDirectoryDepth = URL(fileURLWithPath: path).pathComponents.count
        self.logicalBytes = logicalBytes
        self.previousClass = previousClass
        self.safetyClass = safetyClass
        self.reasonCodes = reasonCodes
        self.action = action
        self.userApproved = userApproved
        self.executionOK = executionOK
        self.verificationNotes = verificationNotes
    }
}

public final class AuditLog: @unchecked Sendable {
    private var events: [AuditEvent] = []
    private let lock = NSLock()

    public init() {}

    public func record(_ event: AuditEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    public func all() -> [AuditEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
