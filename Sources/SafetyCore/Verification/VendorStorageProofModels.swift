import Foundation

/// Exact vendor storage proof inventory. Produces evidence/claims only — never SafetyClass.
public enum VendorStorageKind: String, Codable, Sendable, CaseIterable {
    case ollama
    case huggingFace
}

public enum VendorEntityKind: String, Codable, Sendable {
    case modelsRoot = "MODELS_ROOT"
    case model = "MODEL"
    case blob = "BLOB"
    case hubRoot = "HUB_ROOT"
    case repository = "REPOSITORY"
    case snapshot = "SNAPSHOT"
    case revisionRef = "REVISION_REF"
    case unknownLocal = "UNKNOWN_LOCAL"
}

public enum VendorReferenceScope: String, Codable, Sendable {
    case exclusive = "EXCLUSIVE"
    case shared = "SHARED"
    case incomplete = "UNKNOWN_REFERENCE_SCOPE"
    case orphanIncomplete = "ORPHAN_LOOKING_INCOMPLETE"
}

public enum VendorReacquisitionState: String, Codable, Sendable {
    case unknown = "UNKNOWN"
    case originIdentityVerified = "ORIGIN_IDENTITY_VERIFIED"
    case remoteAvailabilityUnknown = "REMOTE_AVAILABILITY_UNKNOWN"
    case remoteUnavailable = "REMOTE_UNAVAILABLE"
    case authOrGatedUnknown = "AUTH_OR_GATED_UNKNOWN"
    case notApplicable = "NOT_APPLICABLE"
}

public struct VendorBlobRef: Codable, Sendable, Equatable {
    public var digest: String
    public var path: String?
    public var bytes: Int64?
    public var present: Bool
    public var referencingEntityIDs: [String]
    public var scope: VendorReferenceScope
}

public struct VendorSemanticEntity: Codable, Sendable, Equatable {
    public var vendor: VendorStorageKind
    public var entityKind: VendorEntityKind
    public var entityID: String
    public var displayIdentity: String
    public var canonicalPath: String
    public var logicalBytes: Int64
    public var uniqueBytes: Int64?
    public var sharedBytes: Int64?
    public var originIdentity: String?
    public var revisionIdentity: String?
    public var referenceScope: VendorReferenceScope
    public var referenceGraphComplete: Bool
    public var runtimeState: ObservedActiveState
    public var runtimeConfidence: EvidenceConfidence
    public var reacquisition: VendorReacquisitionState
    public var reacquisitionConfidence: EvidenceConfidence
    public var provenanceConfidence: EvidenceConfidence
    public var isUserOriginalSuspect: Bool
    public var referencedBlobDigests: [String]
    public var topBlockers: [String]
    public var preferredActionHint: StorageAction?
    public var notes: [String]

    public init(
        vendor: VendorStorageKind,
        entityKind: VendorEntityKind,
        entityID: String,
        displayIdentity: String,
        canonicalPath: String,
        logicalBytes: Int64,
        uniqueBytes: Int64? = nil,
        sharedBytes: Int64? = nil,
        originIdentity: String? = nil,
        revisionIdentity: String? = nil,
        referenceScope: VendorReferenceScope,
        referenceGraphComplete: Bool,
        runtimeState: ObservedActiveState = .unknown,
        runtimeConfidence: EvidenceConfidence = .unknown,
        reacquisition: VendorReacquisitionState = .unknown,
        reacquisitionConfidence: EvidenceConfidence = .unknown,
        provenanceConfidence: EvidenceConfidence = .unknown,
        isUserOriginalSuspect: Bool = false,
        referencedBlobDigests: [String] = [],
        topBlockers: [String] = [],
        preferredActionHint: StorageAction? = nil,
        notes: [String] = []
    ) {
        self.vendor = vendor
        self.entityKind = entityKind
        self.entityID = entityID
        self.displayIdentity = displayIdentity
        self.canonicalPath = canonicalPath
        self.logicalBytes = logicalBytes
        self.uniqueBytes = uniqueBytes
        self.sharedBytes = sharedBytes
        self.originIdentity = originIdentity
        self.revisionIdentity = revisionIdentity
        self.referenceScope = referenceScope
        self.referenceGraphComplete = referenceGraphComplete
        self.runtimeState = runtimeState
        self.runtimeConfidence = runtimeConfidence
        self.reacquisition = reacquisition
        self.reacquisitionConfidence = reacquisitionConfidence
        self.provenanceConfidence = provenanceConfidence
        self.isUserOriginalSuspect = isUserOriginalSuspect
        self.referencedBlobDigests = referencedBlobDigests
        self.topBlockers = topBlockers
        self.preferredActionHint = preferredActionHint
        self.notes = notes
    }
}

public struct VendorProofInventory: Codable, Sendable, Equatable {
    public var vendor: VendorStorageKind
    public var rootPath: String
    public var entities: [VendorSemanticEntity]
    public var blobs: [VendorBlobRef]
    public var claimsAttempted: Int
    public var claimsVerified: Int
    public var claimsUnknown: Int
    public var claimsConflicted: Int
    public var metadataReads: Int
    public var vendorCLICalls: Int
    public var networkCalls: Int
    public var proofRuntimeMs: Int
    public var secondCrawlerAdded: Bool
    public var notes: [String]

    public var totalLogicalBytes: Int64 {
        entities.filter { $0.entityKind == .model || $0.entityKind == .repository || $0.entityKind == .snapshot }
            .reduce(0) { $0 + $1.logicalBytes }
    }

    public var totalUniqueBytesKnown: Int64 {
        entities.compactMap(\.uniqueBytes).reduce(0, +)
    }

    public var totalSharedBytesKnown: Int64 {
        // Shared blob unique storage — each shared blob counted once.
        blobs.filter { $0.scope == .shared }.compactMap(\.bytes).reduce(0, +)
    }
}

public protocol VendorStorageProofProvider: Sendable {
    var vendor: VendorStorageKind { get }
    /// Inspect exact known vendor metadata under an already-discovered root. Not a second home crawl.
    func prove(rootPath: String, budgetMs: Int) -> VendorProofInventory
}

public enum VendorStorageProofIndex {
    private static let lock = NSLock()
    private static var byRoot: [String: VendorProofInventory] = [:]
    private static var byEntityID: [String: VendorSemanticEntity] = [:]

    public static func reset() {
        lock.lock()
        byRoot.removeAll()
        byEntityID.removeAll()
        lock.unlock()
    }

    /// Drop cached inventory for one vendor root so post-mutation proof can rebuild.
    public static func invalidate(forRoot path: String) {
        let key = (path as NSString).standardizingPath
        lock.lock()
        if let existing = byRoot.removeValue(forKey: key) {
            for entity in existing.entities {
                byEntityID.removeValue(forKey: entity.entityID)
            }
        } else if let match = byRoot.first(where: { key.hasPrefix($0.key) || $0.key.hasPrefix(key) }) {
            let removed = byRoot.removeValue(forKey: match.key)
            for entity in removed?.entities ?? [] {
                byEntityID.removeValue(forKey: entity.entityID)
            }
        }
        lock.unlock()
    }

    public static func store(_ inventory: VendorProofInventory) {
        let key = (inventory.rootPath as NSString).standardizingPath
        lock.lock()
        byRoot[key] = inventory
        for entity in inventory.entities {
            byEntityID[entity.entityID] = entity
        }
        lock.unlock()
    }

    public static func inventory(forRoot path: String) -> VendorProofInventory? {
        let key = (path as NSString).standardizingPath
        lock.lock()
        let hit = byRoot[key] ?? byRoot.first(where: { key.hasPrefix($0.key) || $0.key.hasPrefix(key) })?.value
        lock.unlock()
        return hit
    }

    public static func entity(id: String) -> VendorSemanticEntity? {
        lock.lock()
        let hit = byEntityID[id]
        lock.unlock()
        return hit
    }

    public static func allInventories() -> [VendorProofInventory] {
        lock.lock()
        let values = Array(byRoot.values)
        lock.unlock()
        return values
    }

    public static func lookup(pathOrID: String) -> VendorSemanticEntity? {
        lock.lock()
        defer { lock.unlock() }
        if let direct = byEntityID[pathOrID] { return direct }
        let std = (pathOrID as NSString).standardizingPath
        return byEntityID.values.first { ($0.canonicalPath as NSString).standardizingPath == std }
            ?? byEntityID.values.first { std.hasPrefix(($0.canonicalPath as NSString).standardizingPath) }
    }
}
