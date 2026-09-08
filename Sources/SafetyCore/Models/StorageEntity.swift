import Foundation

public enum EntityKind: String, Codable, Sendable {
    case systemProtected
    case userOriginal
    case cache
    case log
    case temp
    case generatedBuild
    case cloudPlaceholder
    case cloudLocalMaterialized
    case dockerVolume
    case dockerCache
    case dockerImage
    case dockerContainer
    case gitHistory
    case gitMetadata
    case credentials
    case applicationSupport
    case unknown
}

public struct StorageEntity: Codable, Sendable, Equatable {
    public var id: String
    public var kind: EntityKind
    public var category: String
    public var subcategory: String
    public var displayName: String
    public var path: String
    public var logicalBytes: Int64
    public var ownerHint: String?

    public init(
        id: String,
        kind: EntityKind,
        category: String,
        subcategory: String,
        displayName: String,
        path: String,
        logicalBytes: Int64,
        ownerHint: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.category = category
        self.subcategory = subcategory
        self.displayName = displayName
        self.path = path
        self.logicalBytes = logicalBytes
        self.ownerHint = ownerHint
    }
}

public struct RuntimeState: Codable, Sendable, Equatable {
    public var hasOpenHandles: Bool
    public var owningProcessRunning: Bool
    public var lockPresent: Bool
    public var mounted: Bool
    public var syncInProgress: Bool
    public var unknownWriteActivity: Bool
    public var lastModifiedDays: Int?

    public init(
        hasOpenHandles: Bool = false,
        owningProcessRunning: Bool = false,
        lockPresent: Bool = false,
        mounted: Bool = false,
        syncInProgress: Bool = false,
        unknownWriteActivity: Bool = false,
        lastModifiedDays: Int? = nil
    ) {
        self.hasOpenHandles = hasOpenHandles
        self.owningProcessRunning = owningProcessRunning
        self.lockPresent = lockPresent
        self.mounted = mounted
        self.syncInProgress = syncInProgress
        self.unknownWriteActivity = unknownWriteActivity
        self.lastModifiedDays = lastModifiedDays
    }

    public var isActivelyUsed: Bool {
        hasOpenHandles
            || owningProcessRunning
            || lockPresent
            || mounted
            || syncInProgress
            || unknownWriteActivity
    }
}
