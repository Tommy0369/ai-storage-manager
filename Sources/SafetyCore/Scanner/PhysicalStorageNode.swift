import Foundation

/// Observation-only filesystem node for visual exploration.
/// Does NOT decide Safety. PATH ALONE IS NOT SAFETY.
public enum PhysicalNodeKind: String, Codable, Sendable, Equatable {
    case volume
    case directory
    case file
    case package
    case symlink
    case restricted
    case otherAggregate
}

public struct PhysicalStorageNode: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var canonicalPath: String
    public var displayName: String
    public var nodeKind: PhysicalNodeKind
    public var bytes: Int64
    public var bytesKnown: Bool
    public var exclusiveBytes: Int64
    public var exclusiveKnown: Bool
    public var children: [PhysicalStorageNode]
    public var depth: Int
    public var isDirectory: Bool
    public var isFile: Bool
    public var isPackage: Bool
    public var isSymlink: Bool
    public var isRestricted: Bool
    public var isAggregate: Bool
    public var measurementQuality: MeasurementQuality
    public var measurementReason: String?
    public var semanticEntityID: String?
    public var semanticCategoryRaw: String?

    public init(
        id: String,
        canonicalPath: String,
        displayName: String,
        nodeKind: PhysicalNodeKind,
        bytes: Int64,
        bytesKnown: Bool,
        exclusiveBytes: Int64 = 0,
        exclusiveKnown: Bool = false,
        children: [PhysicalStorageNode] = [],
        depth: Int,
        isDirectory: Bool,
        isFile: Bool,
        isPackage: Bool,
        isSymlink: Bool,
        isRestricted: Bool = false,
        isAggregate: Bool = false,
        measurementQuality: MeasurementQuality = .unknown,
        measurementReason: String? = nil,
        semanticEntityID: String? = nil,
        semanticCategoryRaw: String? = nil
    ) {
        self.id = id
        self.canonicalPath = canonicalPath
        self.displayName = displayName
        self.nodeKind = nodeKind
        self.bytes = max(0, bytes)
        self.bytesKnown = bytesKnown
        self.exclusiveBytes = max(0, exclusiveBytes)
        self.exclusiveKnown = exclusiveKnown
        self.children = children
        self.depth = depth
        self.isDirectory = isDirectory
        self.isFile = isFile
        self.isPackage = isPackage
        self.isSymlink = isSymlink
        self.isRestricted = isRestricted
        self.isAggregate = isAggregate
        self.measurementQuality = measurementQuality
        self.measurementReason = measurementReason
        self.semanticEntityID = semanticEntityID
        self.semanticCategoryRaw = semanticCategoryRaw
    }

    public var childInclusiveSum: Int64 {
        children.reduce(Int64(0)) { partial, child in
            guard child.bytesKnown else { return partial }
            return partial + child.bytes
        }
    }
}

public struct PhysicalHierarchyStats: Codable, Sendable, Equatable {
    public var physicalNodeCount: Int
    public var maxDepth: Int
    public var largestFanout: Int
    public var representedBytes: Int64
    public var restrictedNodeCount: Int
    public var unknownByteNodeCount: Int
    public var accountingValid: Bool
    public var duplicateByteOwnership: Bool
    public var timeToFirstHierarchyMs: Int
    public var timeToFirstUsefulMapMs: Int

    public init(
        physicalNodeCount: Int,
        maxDepth: Int,
        largestFanout: Int,
        representedBytes: Int64,
        restrictedNodeCount: Int,
        unknownByteNodeCount: Int,
        accountingValid: Bool,
        duplicateByteOwnership: Bool,
        timeToFirstHierarchyMs: Int,
        timeToFirstUsefulMapMs: Int? = nil
    ) {
        self.physicalNodeCount = physicalNodeCount
        self.maxDepth = maxDepth
        self.largestFanout = largestFanout
        self.representedBytes = representedBytes
        self.restrictedNodeCount = restrictedNodeCount
        self.unknownByteNodeCount = unknownByteNodeCount
        self.accountingValid = accountingValid
        self.duplicateByteOwnership = duplicateByteOwnership
        self.timeToFirstHierarchyMs = timeToFirstHierarchyMs
        self.timeToFirstUsefulMapMs = timeToFirstUsefulMapMs ?? timeToFirstHierarchyMs
    }
}

public struct PhysicalHierarchyConfig: Sendable {
    public var maxDepth: Int
    public var maxChildrenPerDirectory: Int
    public var maxNodes: Int
    public var expandPackages: Bool
    public var followSymlinks: Bool
    public var rootTimeoutSeconds: Double
    public var childTimeoutSeconds: Double

    public static let visualDefault = PhysicalHierarchyConfig(
        maxDepth: 3,
        maxChildrenPerDirectory: 32,
        maxNodes: 400,
        expandPackages: false,
        followSymlinks: false,
        rootTimeoutSeconds: 45,
        childTimeoutSeconds: 8
    )

    public static let expandDefault = PhysicalHierarchyConfig(
        maxDepth: 2,
        maxChildrenPerDirectory: 40,
        maxNodes: 200,
        expandPackages: false,
        followSymlinks: false,
        rootTimeoutSeconds: 20,
        childTimeoutSeconds: 6
    )

    public init(
        maxDepth: Int,
        maxChildrenPerDirectory: Int,
        maxNodes: Int,
        expandPackages: Bool,
        followSymlinks: Bool,
        rootTimeoutSeconds: Double,
        childTimeoutSeconds: Double
    ) {
        self.maxDepth = maxDepth
        self.maxChildrenPerDirectory = maxChildrenPerDirectory
        self.maxNodes = maxNodes
        self.expandPackages = expandPackages
        self.followSymlinks = followSymlinks
        self.rootTimeoutSeconds = rootTimeoutSeconds
        self.childTimeoutSeconds = childTimeoutSeconds
    }
}
