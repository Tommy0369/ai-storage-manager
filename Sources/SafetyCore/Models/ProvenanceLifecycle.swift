import Foundation

public enum EvidenceConfidence: String, Codable, Sendable, Equatable {
    case verified = "VERIFIED"
    case inferred = "INFERRED"
    case unknown = "UNKNOWN"

    /// Only VERIFIED may later satisfy strict Safety required predicates.
    public var canSatisfySafetyPredicate: Bool { self == .verified }
}

public enum LifecycleRole: String, Codable, Sendable, Equatable {
    case userContent = "USER_CONTENT"
    case userConfiguration = "USER_CONFIGURATION"
    case applicationState = "APPLICATION_STATE"
    case cache = "CACHE"
    case temporary = "TEMPORARY"
    case log = "LOG"
    case database = "DATABASE"
    case index = "INDEX"
    case session = "SESSION"
    case download = "DOWNLOAD"
    case generatedArtifact = "GENERATED_ARTIFACT"
    case model = "MODEL"
    case backup = "BACKUP"
    case runtime = "RUNTIME"
    case snapshot = "SNAPSHOT"
    case history = "HISTORY"
    case extensionData = "EXTENSION"
    case workspaceState = "WORKSPACE_STATE"
    case unknown = "UNKNOWN"
    case mixed = "MIXED"
}

public enum RelationshipType: String, Codable, Sendable, Equatable {
    case ownedBy = "OWNED_BY"
    case generatedBy = "GENERATED_BY"
    case derivedFrom = "DERIVED_FROM"
    case belongsToWorkspace = "BELONGS_TO_WORKSPACE"
    case belongsToDevice = "BELONGS_TO_DEVICE"
    case belongsToVersion = "BELONGS_TO_VERSION"
    /// Snapshot/store is tied to a Cursor storage UUID — not necessarily a project workspace.
    case associatedWithCursorStore = "ASSOCIATED_WITH_CURSOR_STORE"
    /// Entity observed under Cursor snapshot/context without strict workspace proof.
    case observedInCursorContext = "OBSERVED_IN_CURSOR_CONTEXT"
    /// Weak workspace hint only — never satisfies strict workspace predicates.
    case possibleWorkspaceContext = "POSSIBLE_WORKSPACE_CONTEXT"
    case referencedBy = "REFERENCED_BY"
    case contains = "CONTAINS"
    case sharesContainerWith = "SHARES_CONTAINER_WITH"
    case backupOf = "BACKUP_OF"
}

public enum RelationshipPresence: String, Codable, Sendable, Equatable {
    case present = "PRESENT"
    case missing = "MISSING"
    case unknown = "UNKNOWN"
}

public enum ObservedActiveState: String, Codable, Sendable, Equatable {
    case active = "ACTIVE"
    case inactive = "INACTIVE"
    case unknown = "UNKNOWN"
}

public struct ProductIdentity: Codable, Sendable, Equatable {
    public var name: String?
    public var bundleIdentifier: String?
    public var confidence: EvidenceConfidence

    public init(name: String? = nil, bundleIdentifier: String? = nil, confidence: EvidenceConfidence) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.confidence = confidence
    }
}

public struct ProvenanceEvidence: Codable, Sendable, Equatable {
    public var generatedByProduct: ProductIdentity?
    public var generatedByVersion: String?
    public var bundleIdentifier: String?
    public var relatedWorkspace: String?
    public var relatedDevice: String?
    public var relatedManifest: String?
    public var relatedSource: String?
    public var creationMechanism: String?
    public var storageRole: LifecycleRole
    public var confidence: EvidenceConfidence
    public var unknownReasons: [String]

    public init(
        generatedByProduct: ProductIdentity? = nil,
        generatedByVersion: String? = nil,
        bundleIdentifier: String? = nil,
        relatedWorkspace: String? = nil,
        relatedDevice: String? = nil,
        relatedManifest: String? = nil,
        relatedSource: String? = nil,
        creationMechanism: String? = nil,
        storageRole: LifecycleRole = .unknown,
        confidence: EvidenceConfidence = .unknown,
        unknownReasons: [String] = []
    ) {
        self.generatedByProduct = generatedByProduct
        self.generatedByVersion = generatedByVersion
        self.bundleIdentifier = bundleIdentifier
        self.relatedWorkspace = relatedWorkspace
        self.relatedDevice = relatedDevice
        self.relatedManifest = relatedManifest
        self.relatedSource = relatedSource
        self.creationMechanism = creationMechanism
        self.storageRole = storageRole
        self.confidence = confidence
        self.unknownReasons = unknownReasons
    }
}

public struct LifecycleEvidence: Codable, Sendable, Equatable {
    public var role: LifecycleRole
    public var roleConfidence: EvidenceConfidence
    public var activeState: ObservedActiveState
    public var mixedContent: Bool
    public var unknownReasons: [String]

    public init(
        role: LifecycleRole,
        roleConfidence: EvidenceConfidence,
        activeState: ObservedActiveState = .unknown,
        mixedContent: Bool = false,
        unknownReasons: [String] = []
    ) {
        self.role = role
        self.roleConfidence = roleConfidence
        self.activeState = activeState
        self.mixedContent = mixedContent
        self.unknownReasons = unknownReasons
    }
}

public struct EntityRelationship: Codable, Sendable, Equatable {
    public var type: RelationshipType
    public var target: String
    public var presence: RelationshipPresence
    public var confidence: EvidenceConfidence

    public init(
        type: RelationshipType,
        target: String,
        presence: RelationshipPresence,
        confidence: EvidenceConfidence
    ) {
        self.type = type
        self.target = target
        self.presence = presence
        self.confidence = confidence
    }
}

public struct DetectionAnnotation: Codable, Sendable, Equatable {
    public var detectorID: String
    public var specificity: Int
    public var semanticType: String
    public var lifecycle: LifecycleEvidence
    public var provenance: ProvenanceEvidence
    public var relationships: [EntityRelationship]
    public var owningProducts: [ProductIdentity]
    public var unknownReasons: [String]

    public init(
        detectorID: String,
        specificity: Int,
        semanticType: String,
        lifecycle: LifecycleEvidence,
        provenance: ProvenanceEvidence = ProvenanceEvidence(),
        relationships: [EntityRelationship] = [],
        owningProducts: [ProductIdentity] = [],
        unknownReasons: [String] = []
    ) {
        self.detectorID = detectorID
        self.specificity = min(100, max(0, specificity))
        self.semanticType = semanticType
        self.lifecycle = lifecycle
        self.provenance = provenance
        self.relationships = relationships
        self.owningProducts = owningProducts
        self.unknownReasons = unknownReasons
    }
}

public struct DetectionGraphReport: Codable, Sendable, Equatable {
    public var provenanceConfidence: [String: Int]
    public var lifecycleRoles: [String: Int]
    public var relationshipTypes: [String: Int]
    public var detectorWins: [String: Int]

    public static func build(_ items: [ClassifiedItem]) -> DetectionGraphReport {
        var prov: [String: Int] = [:]
        var roles: [String: Int] = [:]
        var rels: [String: Int] = [:]
        var dets: [String: Int] = [:]
        for item in items {
            guard let a = item.detected.annotation else { continue }
            prov[a.provenance.confidence.rawValue, default: 0] += 1
            roles[a.lifecycle.role.rawValue, default: 0] += 1
            dets[a.detectorID, default: 0] += 1
            for r in a.relationships {
                rels[r.type.rawValue, default: 0] += 1
            }
        }
        return DetectionGraphReport(provenanceConfidence: prov, lifecycleRoles: roles, relationshipTypes: rels, detectorWins: dets)
    }
}

public enum DetectorConflictResolver {
    public static func merge(_ raw: [DetectedEntity]) -> [DetectedEntity] {
        var map: [String: DetectedEntity] = [:]
        for item in raw {
            let path = (item.entity.path as NSString).standardizingPath
            if let existing = map[path] {
                let incoming = item.annotation?.specificity ?? 40
                let held = existing.annotation?.specificity ?? 40
                if incoming > held {
                    map[path] = item
                }
            } else {
                map[path] = item
            }
        }
        return Array(map.values)
    }
}
