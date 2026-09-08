import Foundation

public struct AccountingInput: Equatable, Sendable {
    public var id: String
    public var path: String
    public var inclusiveBytes: Int64
    public var safetyClass: SafetyClass
    public var resolution: ResolutionLevel
    public var measurementKnown: Bool
    public var measurementQuality: MeasurementQuality

    public init(
        id: String,
        path: String,
        inclusiveBytes: Int64,
        safetyClass: SafetyClass,
        resolution: ResolutionLevel,
        measurementKnown: Bool = true,
        measurementQuality: MeasurementQuality = .exact
    ) {
        self.id = id
        self.path = (path as NSString).standardizingPath
        self.inclusiveBytes = max(0, inclusiveBytes)
        self.safetyClass = safetyClass
        self.resolution = resolution
        self.measurementKnown = measurementKnown
        self.measurementQuality = measurementQuality
    }
}

public struct AccountedNode: Equatable, Sendable, Codable {
    public var id: String
    public var path: String
    public var inclusiveBytes: Int64
    public var exclusiveBytes: Int64
    public var safetyClass: SafetyClass
    public var resolution: ResolutionLevel
    public var measurementKnown: Bool
    public var measurementQuality: MeasurementQuality
    public var exclusiveKnown: Bool
}

public struct ByteAccountingResult: Equatable, Sendable, Codable {
    public var inclusiveSumOfAllNodes: Int64
    public var exclusiveTotal: Int64
    public var uniqueTotal: Int64
    public var duplicateBytesRemoved: Int64
    public var classUnique: [String: Int64]
    public var nodes: [AccountedNode]
    public var overflowClamps: Int
    public var exactMeasurementBytes: Int64
    public var boundedMeasurementBytes: Int64
    public var partialMeasurementBytes: Int64
    public var unknownMeasurementEntities: Int
    public var unknownMeasurementBytesEstimate: Int64
    public var accountingCompletenessPercent: Double

    public var classificationExceedsUnique: Bool {
        classUnique.values.reduce(0, +) > uniqueTotal
    }
}

public enum ByteAccountant {
    public static let tolerance: Int64 = 4096

    public static func account(_ raw: [AccountingInput]) -> ByteAccountingResult {
        let merged = mergeByPath(raw)
        let paths = merged.map(\.path)
        var nodes: [AccountedNode] = []
        var clamps = 0
        var exactBytes: Int64 = 0
        var boundedBytes: Int64 = 0
        var partialBytes: Int64 = 0
        var unknownEntities = 0
        for item in merged {
            let children = merged.filter { isDirectChild(parent: item.path, child: $0.path, all: paths) }
            let measuredChildren = children.filter(\.measurementKnown)
            let childSum = measuredChildren.reduce(Int64(0)) { $0 + $1.inclusiveBytes }
            var exclusive: Int64 = 0
            var exclusiveKnown = item.measurementKnown
            if item.measurementKnown {
                exclusive = item.inclusiveBytes - childSum
                if exclusive < 0 {
                    clamps += 1
                    exclusive = 0
                }
            } else {
                unknownEntities += 1
                exclusiveKnown = false
            }
            nodes.append(AccountedNode(
                id: item.id,
                path: item.path,
                inclusiveBytes: item.inclusiveBytes,
                exclusiveBytes: exclusive,
                safetyClass: item.safetyClass,
                resolution: item.resolution,
                measurementKnown: item.measurementKnown,
                measurementQuality: item.measurementQuality,
                exclusiveKnown: exclusiveKnown
            ))
        }
        for n in nodes where n.exclusiveKnown {
            switch n.measurementQuality {
            case .exact where n.measurementKnown: exactBytes += n.exclusiveBytes
            case .bounded where n.measurementKnown: boundedBytes += n.exclusiveBytes
            case .partial: partialBytes += n.exclusiveBytes
            case .unknown: break
            case .exact, .bounded: break
            }
        }
        let inclusiveSum = merged.filter(\.measurementKnown).reduce(Int64(0)) { $0 + $1.inclusiveBytes }
        let exclusiveTotal = nodes.filter(\.exclusiveKnown).reduce(Int64(0)) { $0 + $1.exclusiveBytes }
        var classUnique: [String: Int64] = [:]
        for n in nodes where n.exclusiveKnown {
            classUnique[n.safetyClass.rawValue, default: 0] += n.exclusiveBytes
        }
        let knownInclusive = merged.filter(\.measurementKnown).reduce(Int64(0)) { $0 + $1.inclusiveBytes }
        let completeness = inclusiveSum == 0 ? 0 : Double(exclusiveTotal) / Double(max(inclusiveSum, 1)) * 100
        return ByteAccountingResult(
            inclusiveSumOfAllNodes: inclusiveSum,
            exclusiveTotal: exclusiveTotal,
            uniqueTotal: exclusiveTotal,
            duplicateBytesRemoved: max(0, knownInclusive - exclusiveTotal),
            classUnique: classUnique,
            nodes: nodes,
            overflowClamps: clamps,
            exactMeasurementBytes: exactBytes,
            boundedMeasurementBytes: boundedBytes,
            partialMeasurementBytes: partialBytes,
            unknownMeasurementEntities: unknownEntities,
            unknownMeasurementBytesEstimate: 0,
            accountingCompletenessPercent: min(100, completeness)
        )
    }

    public static func coverage(uniqueBytes: Int64, scannedBytes: Int64) -> Double {
        guard scannedBytes > 0 else { return 0 }
        return min(100, Double(uniqueBytes) / Double(scannedBytes) * 100)
    }

    public static func semanticCoverage(nodes: [AccountedNode], scannedBytes: Int64) -> SemanticCoverage {
        let denom = max(scannedBytes, 1)
        func pct(_ pred: (ResolutionLevel) -> Bool) -> Double {
            let n = nodes.filter { pred($0.resolution) }.reduce(Int64(0)) { $0 + $1.exclusiveBytes }
            return coverage(uniqueBytes: n, scannedBytes: denom)
        }
        return SemanticCoverage(
            identifiedPercent: coverage(uniqueBytes: nodes.reduce(0) { $0 + $1.exclusiveBytes }, scannedBytes: scannedBytes),
            l3PlusPercent: pct { $0 >= .l3Product },
            l4PlusPercent: pct { $0 >= .l4SemanticEntity },
            l5Percent: pct { $0 >= .l5Actionable }
        )
    }

    static func mergeByPath(_ raw: [AccountingInput]) -> [AccountingInput] {
        var map: [String: AccountingInput] = [:]
        for item in raw {
            if let existing = map[item.path] {
                if item.resolution > existing.resolution || item.inclusiveBytes > existing.inclusiveBytes {
                    map[item.path] = item
                }
            } else {
                map[item.path] = item
            }
        }
        return Array(map.values)
    }

    static func isDirectChild(parent: String, child: String, all: [String]) -> Bool {
        guard child != parent, child.hasPrefix(parent + "/") else { return false }
        for mid in all where mid != parent && mid != child {
            if child.hasPrefix(mid + "/"), mid.hasPrefix(parent + "/") {
                return false
            }
        }
        return true
    }

    public static func measurementCoverage(result: ByteAccountingResult, denominatorBytes: Int64) -> SizeMeasurementCoverageReport {
        let denom = max(denominatorBytes, result.uniqueTotal, 1)
        let cappedExact = min(result.exactMeasurementBytes, result.uniqueTotal)
        let cappedBounded = min(result.boundedMeasurementBytes, max(0, result.uniqueTotal - cappedExact))
        let cappedPartial = min(result.partialMeasurementBytes, max(0, result.uniqueTotal - cappedExact - cappedBounded))
        let measuredKnown = cappedExact + cappedBounded + cappedPartial
        let unknownBytes = max(0, result.uniqueTotal - measuredKnown)
        return SizeMeasurementCoverageReport(
            exactBytes: cappedExact,
            boundedBytes: cappedBounded,
            partialBytes: cappedPartial,
            unknownMeasurementEntities: result.unknownMeasurementEntities,
            unknownMeasurementBytesEstimate: unknownBytes,
            byteMeasurementCoveragePercent: min(100, Double(cappedExact) / Double(denom) * 100),
            accountingCompletenessPercent: result.accountingCompletenessPercent,
            totalKnownUniqueBytes: result.uniqueTotal,
            denominatorBytes: denominatorBytes
        )
    }
}
