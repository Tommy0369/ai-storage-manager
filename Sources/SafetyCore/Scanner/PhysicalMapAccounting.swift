import Foundation

/// Map geometry accounting. Distinguishes UNKNOWN measurement from observed zero.
public enum PhysicalMapAccountingBasis: String, Codable, Sendable, Equatable {
    case rootMeasured = "ROOT_MEASURED"
    case knownChildrenLowerBound = "KNOWN_CHILDREN_LOWER_BOUND"
    case noMeasurement = "NO_MEASUREMENT"
}

public enum PhysicalMapCoverage: String, Codable, Sendable, Equatable {
    case complete = "COMPLETE"
    case partial = "PARTIAL"
    case unknown = "UNKNOWN"
}

public enum PhysicalRootMeasurementStatus: String, Codable, Sendable, Equatable {
    case exact = "EXACT"
    case timeout = "TIMEOUT"
    case unknown = "UNKNOWN"
    case unavailable = "UNAVAILABLE"
}

public struct PhysicalMapAccounting: Codable, Sendable, Equatable {
    public var mappedBytes: Int64?
    public var basis: PhysicalMapAccountingBasis
    public var coverage: PhysicalMapCoverage
    public var rootMeasurementStatus: PhysicalRootMeasurementStatus
    public var rootMeasuredBytes: Int64?
    public var rootTotalKnown: Bool
    public var knownChildMappedBytes: Int64
    public var fallbackUsed: Bool
    public var accountingValid: Bool
    public var unknownRemainderKnown: Bool

    public init(
        mappedBytes: Int64?,
        basis: PhysicalMapAccountingBasis,
        coverage: PhysicalMapCoverage,
        rootMeasurementStatus: PhysicalRootMeasurementStatus,
        rootMeasuredBytes: Int64?,
        rootTotalKnown: Bool,
        knownChildMappedBytes: Int64,
        fallbackUsed: Bool,
        accountingValid: Bool,
        unknownRemainderKnown: Bool
    ) {
        self.mappedBytes = mappedBytes
        self.basis = basis
        self.coverage = coverage
        self.rootMeasurementStatus = rootMeasurementStatus
        self.rootMeasuredBytes = rootMeasuredBytes
        self.rootTotalKnown = rootTotalKnown
        self.knownChildMappedBytes = knownChildMappedBytes
        self.fallbackUsed = fallbackUsed
        self.accountingValid = accountingValid
        self.unknownRemainderKnown = unknownRemainderKnown
    }

    /// Bytes to feed map geometry. Nil means no drawable numeric total.
    public var geometryBytes: Int64? { mappedBytes }

    /// Report field: numeric mapped bytes, 0 only when no usable measurement exists.
    public var reportMappedBytes: Int64 { mappedBytes ?? 0 }
}

/// Resolves honest mapped totals from an existing physical tree.
/// Reuses already-observed child node bytes — no secondary filesystem IO.
public enum PhysicalMapAccountingResolver {
    public static func resolve(for node: PhysicalStorageNode) -> PhysicalMapAccounting {
        let knownChildren = drawableKnownChildren(of: node)
        let knownChildBytes = knownChildren.reduce(Int64(0)) { $0 + $1.bytes }
        let status = measurementStatus(of: node)
        let duplicates = PhysicalHierarchyBuilder.hasDuplicateByteOwnership(node)

        if node.bytesKnown {
            let allChildrenKnown = node.children.allSatisfy { $0.bytesKnown || $0.isRestricted }
            let childSumOK = knownChildBytes <= node.bytes
            let exclusiveOK = !node.exclusiveKnown || (node.exclusiveBytes + knownChildBytes == node.bytes)
            return PhysicalMapAccounting(
                mappedBytes: node.bytes,
                basis: .rootMeasured,
                coverage: allChildrenKnown ? .complete : .partial,
                rootMeasurementStatus: status,
                rootMeasuredBytes: node.bytes,
                rootTotalKnown: true,
                knownChildMappedBytes: knownChildBytes,
                fallbackUsed: false,
                accountingValid: !duplicates && childSumOK && exclusiveOK,
                unknownRemainderKnown: true
            )
        }

        // Root/focus measurement unavailable — do NOT collapse UNKNOWN into observed zero.
        if knownChildBytes > 0 {
            return PhysicalMapAccounting(
                mappedBytes: knownChildBytes,
                basis: .knownChildrenLowerBound,
                coverage: .partial,
                rootMeasurementStatus: status,
                rootMeasuredBytes: nil,
                rootTotalKnown: false,
                knownChildMappedBytes: knownChildBytes,
                fallbackUsed: true,
                accountingValid: !duplicates,
                unknownRemainderKnown: false
            )
        }

        return PhysicalMapAccounting(
            mappedBytes: nil,
            basis: .noMeasurement,
            coverage: .unknown,
            rootMeasurementStatus: status,
            rootMeasuredBytes: nil,
            rootTotalKnown: false,
            knownChildMappedBytes: 0,
            fallbackUsed: false,
            accountingValid: !duplicates,
            unknownRemainderKnown: false
        )
    }

    /// Direct children with trustworthy measured bytes. Skips restricted/unknown.
    /// Inclusive child bytes are non-overlapping siblings — do not also add grandchildren.
    public static func drawableKnownChildren(of node: PhysicalStorageNode) -> [PhysicalStorageNode] {
        node.children.filter { child in
            child.bytesKnown && !child.isRestricted && child.bytes >= 0
        }
    }

    public static func measurementStatus(of node: PhysicalStorageNode) -> PhysicalRootMeasurementStatus {
        if node.bytesKnown { return .exact }
        let reason = (node.measurementReason ?? "").uppercased()
        if reason.contains("TIMEOUT") { return .timeout }
        if node.isRestricted || reason.contains("PERMISSION") || reason.contains("HARD_BLOCKED") {
            return .unavailable
        }
        return .unknown
    }
}
