import Foundation
import SafetyCore

// P3.0 — Presentation-only models. NOT Safety authority.

public enum ProductStorageCategory: String, Codable, Sendable, CaseIterable {
    case personalFiles = "PERSONAL_FILES"
    case applications = "APPLICATIONS"
    case developer = "DEVELOPER"
    case aiTools = "AI_TOOLS"
    case cloud = "CLOUD"
    case macOSSystem = "MACOS_SYSTEM"
    case backups = "BACKUPS"
    case generatedData = "GENERATED_DATA"
    case trash = "TRASH"
    case otherUnknown = "OTHER_UNKNOWN"

    public var displayName: String {
        switch self {
        case .personalFiles: return L10n.t("category.personalFiles")
        case .applications: return L10n.t("category.applications")
        case .developer: return L10n.t("category.developer")
        case .aiTools: return L10n.t("category.aiTools")
        case .cloud: return L10n.t("category.cloud")
        case .macOSSystem: return L10n.t("category.macOSSystem")
        case .backups: return L10n.t("category.backups")
        case .generatedData: return L10n.t("category.generatedData")
        case .trash: return L10n.t("category.trash")
        case .otherUnknown: return L10n.t("category.otherUnknown")
        }
    }

    public var iconHint: String {
        switch self {
        case .personalFiles: return "folder"
        case .applications: return "app"
        case .developer: return "hammer"
        case .aiTools: return "brain"
        case .cloud: return "icloud"
        case .macOSSystem: return "gear"
        case .backups: return "externaldrive"
        case .generatedData: return "sparkles"
        case .trash: return "trash"
        case .otherUnknown: return "questionmark.folder"
        }
    }
}

public enum StoragePresentationState: String, Codable, Sendable {
    case readyToOptimize = "READY_TO_OPTIMIZE"
    case verificationNeeded = "VERIFICATION_NEEDED"
    case protected = "PROTECTED"
    case keep = "KEEP"
    case recoveryPending = "RECOVERY_PENDING"
    case noRecommendation = "NO_RECOMMENDATION"
    case informational = "INFORMATIONAL"
}

public struct DiskCapacitySnapshot: Codable, Sendable, Equatable {
    public var volumeName: String
    public var volumeTotalBytes: Int64?
    public var volumeAvailableBytes: Int64?
    public var volumeUsedBytes: Int64?
    public var observedAt: Date

    public init(
        volumeName: String,
        volumeTotalBytes: Int64?,
        volumeAvailableBytes: Int64?,
        volumeUsedBytes: Int64?,
        observedAt: Date = Date()
    ) {
        self.volumeName = volumeName
        self.volumeTotalBytes = volumeTotalBytes
        self.volumeAvailableBytes = volumeAvailableBytes
        self.volumeUsedBytes = volumeUsedBytes
        self.observedAt = observedAt
    }
}

public struct ObservedStorageSnapshot: Codable, Sendable, Equatable {
    public var scannedRootBytes: Int64
    public var classifiedUniqueBytes: Int64
    public var unclassifiedBytes: Int64
    public var selectedRootLabel: String

    public init(
        scannedRootBytes: Int64,
        classifiedUniqueBytes: Int64,
        unclassifiedBytes: Int64,
        selectedRootLabel: String
    ) {
        self.scannedRootBytes = scannedRootBytes
        self.classifiedUniqueBytes = classifiedUniqueBytes
        self.unclassifiedBytes = unclassifiedBytes
        self.selectedRootLabel = selectedRootLabel
    }
}

public struct StorageMapNode: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var entityID: String?
    public var title: String
    public var subtitle: String?
    public var bytes: Int64
    public var children: [StorageMapNode]
    public var semanticCategory: ProductStorageCategory
    public var presentationState: StoragePresentationState
    public var actionSummary: String?
    public var isAggregate: Bool
    public var pathSummary: String?
    public var iconHint: String
    public var technicalEntityID: String?

    public init(
        id: String,
        entityID: String? = nil,
        title: String,
        subtitle: String? = nil,
        bytes: Int64,
        children: [StorageMapNode] = [],
        semanticCategory: ProductStorageCategory,
        presentationState: StoragePresentationState = .informational,
        actionSummary: String? = nil,
        isAggregate: Bool = true,
        pathSummary: String? = nil,
        iconHint: String = "folder",
        technicalEntityID: String? = nil
    ) {
        self.id = id
        self.entityID = entityID
        self.title = title
        self.subtitle = subtitle
        self.bytes = max(0, bytes)
        self.children = children
        self.semanticCategory = semanticCategory
        self.presentationState = presentationState
        self.actionSummary = actionSummary
        self.isAggregate = isAggregate
        self.pathSummary = pathSummary
        self.iconHint = iconHint
        self.technicalEntityID = technicalEntityID
    }
}

public enum StorageInsightKind: String, Codable, Sendable {
    case largeStorageDriver = "LARGE_STORAGE_DRIVER"
    case safeActionReady = "SAFE_ACTION_READY"
    case verificationNeeded = "VERIFICATION_NEEDED"
    case protectedImportant = "PROTECTED_IMPORTANT_DATA"
    case cloudOptimization = "CLOUD_OPTIMIZATION_OPPORTUNITY"
    case generatedData = "GENERATED_DATA"
    case regeneratedData = "REGENERATED_DATA"
    case recoveryPending = "STORAGE_RECOVERY_PENDING"
}

public struct StorageInsight: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: StorageInsightKind
    public var title: String
    public var message: String
    public var bytes: Int64?
    public var category: ProductStorageCategory?

    public init(
        id: String,
        kind: StorageInsightKind,
        title: String,
        message: String,
        bytes: Int64? = nil,
        category: ProductStorageCategory? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.bytes = bytes
        self.category = category
    }
}

public struct RecommendationCard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var entityID: String
    public var title: String
    public var subtitle: String
    public var bytes: Int64
    public var byteLabel: String
    public var description: String
    public var evidenceLines: [String]
    public var recommendedActionLabel: String
    public var potentialRecoveryLabel: String?
    public var readiness: UIReadinessState
    public var technicalEntityID: String
    public var fullPath: String
}

public struct ReviewItemPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var entityID: String
    public var title: String
    public var bytes: Int64
    public var byteLabel: String
    public var reason: String
    public var category: ProductStorageCategory
    public var technicalEntityID: String
}

public struct ProtectedItemPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var entityID: String
    public var title: String
    public var bytes: Int64
    public var byteLabel: String
    public var explanation: String
    public var category: ProductStorageCategory
    public var technicalEntityID: String
}

public struct StorageExperienceSnapshot: Codable, Sendable, Equatable {
    public var diskCapacity: DiskCapacitySnapshot
    public var observedStorage: ObservedStorageSnapshot
    public var mapRoot: StorageMapNode
    public var categories: [StorageMapNode]
    public var insights: [StorageInsight]
    public var recommendations: [RecommendationCard]
    public var needsReview: [ReviewItemPresentation]
    public var protected: [ProtectedItemPresentation]
    public var recentActions: [UIActionHistoryItem]
    public var readyActionCount: Int
    public var readyPotentialBytes: Int64
    public var needsReviewCount: Int
    public var needsReviewBytes: Int64
    public var protectedCount: Int
    public var protectedBytes: Int64
    public var recoveryPendingBytes: Int64
    public var mapAccountingValid: Bool
    public var mapRootBytes: Int64
    public var generatedAt: Date
    public var scanRuntimeSeconds: Double?

    public init(
        diskCapacity: DiskCapacitySnapshot,
        observedStorage: ObservedStorageSnapshot,
        mapRoot: StorageMapNode,
        categories: [StorageMapNode],
        insights: [StorageInsight],
        recommendations: [RecommendationCard],
        needsReview: [ReviewItemPresentation],
        protected: [ProtectedItemPresentation],
        recentActions: [UIActionHistoryItem],
        readyActionCount: Int,
        readyPotentialBytes: Int64,
        needsReviewCount: Int,
        needsReviewBytes: Int64,
        protectedCount: Int,
        protectedBytes: Int64,
        recoveryPendingBytes: Int64,
        mapAccountingValid: Bool,
        mapRootBytes: Int64,
        generatedAt: Date,
        scanRuntimeSeconds: Double? = nil
    ) {
        self.diskCapacity = diskCapacity
        self.observedStorage = observedStorage
        self.mapRoot = mapRoot
        self.categories = categories
        self.insights = insights
        self.recommendations = recommendations
        self.needsReview = needsReview
        self.protected = protected
        self.recentActions = recentActions
        self.readyActionCount = readyActionCount
        self.readyPotentialBytes = readyPotentialBytes
        self.needsReviewCount = needsReviewCount
        self.needsReviewBytes = needsReviewBytes
        self.protectedCount = protectedCount
        self.protectedBytes = protectedBytes
        self.recoveryPendingBytes = recoveryPendingBytes
        self.mapAccountingValid = mapAccountingValid
        self.mapRootBytes = mapRootBytes
        self.generatedAt = generatedAt
        self.scanRuntimeSeconds = scanRuntimeSeconds
    }
}

public struct P30StorageExperienceReport: Codable, Sendable, Equatable {
    public var diskTotalBytes: Int64?
    public var diskUsedBytes: Int64?
    public var diskAvailableBytes: Int64?
    public var observedBytes: Int64
    public var mapRootBytes: Int64
    public var unclassifiedBytes: Int64
    public var topCategories: [[String: String]]
    public var topEntities: [[String: String]]
    public var readyActionCount: Int
    public var readyPotentialBytes: Int64
    public var needsReviewCount: Int
    public var needsReviewBytes: Int64
    public var protectedCount: Int
    public var protectedBytes: Int64
    public var recoveryPendingBytes: Int64
    public var recentActionCount: Int
    public var mapAccountingValid: Bool
    public var technicalIDsHiddenByDefault: Bool
    public var generatedAt: Date
}
