import Foundation

public struct VerificationReport: Codable, Sendable, Equatable {
    public var targetStillPresent: Bool
    public var logicalBytesRemoved: Int64
    public var physicalBytesReclaimed: Int64?
    public var availableSpaceDelta: Int64?
    public var resourceStillValid: Bool?
    public var notes: [String]

    public var conflatesLogicalAndPhysical: Bool { false }
}

public struct ResultVerifier {
    public init() {}

    public func report(
        beforeLogical: Int64,
        afterLogical: Int64,
        targetStillPresent: Bool,
        physicalReclaimed: Int64?,
        availableDelta: Int64?,
        resourceStillValid: Bool?
    ) -> VerificationReport {
        var notes: [String] = []
        if let physical = physicalReclaimed, physical != (beforeLogical - afterLogical) {
            notes.append("APFS_LOGICAL_PHYSICAL_MISMATCH")
        }
        return VerificationReport(
            targetStillPresent: targetStillPresent,
            logicalBytesRemoved: max(0, beforeLogical - afterLogical),
            physicalBytesReclaimed: physicalReclaimed,
            availableSpaceDelta: availableDelta,
            resourceStillValid: resourceStillValid,
            notes: notes
        )
    }
}
