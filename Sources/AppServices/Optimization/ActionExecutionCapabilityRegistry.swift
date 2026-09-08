import Foundation
import SafetyCore

/// Concrete executor support. Enum existence is NOT implementation.
public enum ActionExecutionSupport: String, Codable, Sendable, Equatable {
    case implemented = "IMPLEMENTED"
    case notImplemented = "NOT_IMPLEMENTED"
    case notSupported = "NOT_SUPPORTED"
}

/// Scoped capability key — action alone is insufficient for vendor-native.
public struct ExecutionCapabilityKey: Hashable, Sendable, Equatable {
    public var action: StorageAction
    public var vendor: VendorStorageKind?
    public var entityKind: VendorEntityKind?

    public init(
        action: StorageAction,
        vendor: VendorStorageKind? = nil,
        entityKind: VendorEntityKind? = nil
    ) {
        self.action = action
        self.vendor = vendor
        self.entityKind = entityKind
    }
}

public enum ActionExecutionCapabilityRegistry {
    /// Legacy action-only lookup. Vendor-native without scope remains NOT_IMPLEMENTED.
    public static func support(for action: StorageAction) -> ActionExecutionSupport {
        support(for: ExecutionCapabilityKey(action: action))
    }

    public static func support(
        for action: StorageAction,
        item: ClassifiedItem
    ) -> ActionExecutionSupport {
        support(for: key(for: action, item: item))
    }

    public static func support(
        for action: StorageAction,
        vendor: VendorStorageKind?,
        entityKind: VendorEntityKind?
    ) -> ActionExecutionSupport {
        support(for: ExecutionCapabilityKey(action: action, vendor: vendor, entityKind: entityKind))
    }

    public static func support(
        for action: StorageAction,
        entityID: String,
        path: String
    ) -> ActionExecutionSupport {
        support(for: key(for: action, entityID: entityID, path: path))
    }

    public static func support(for key: ExecutionCapabilityKey) -> ActionExecutionSupport {
        switch key.action {
        case .moveToTrash:
            return .implemented
        case .keep, .moveToICloud, .removeLocalDownload:
            return .notImplemented
        case .vendorNativeCleanup:
            if key.vendor == .ollama, key.entityKind == .blob {
                return .notSupported
            }
            if key.vendor == .huggingFace, key.entityKind == .blob {
                return .notSupported
            }
            if key.vendor == .ollama, key.entityKind == .model {
                return .implemented
            }
            if key.vendor == .huggingFace, key.entityKind == .snapshot {
                return .implemented
            }
            // Repo/hub/cache-root and unscoped vendor-native remain unavailable.
            return .notImplemented
        }
    }

    public static func key(for action: StorageAction, item: ClassifiedItem) -> ExecutionCapabilityKey {
        ExecutionCapabilityKey(
            action: action,
            vendor: ActionPolicy.vendorStorageKind(item),
            entityKind: ActionPolicy.vendorEntityKind(item)
        )
    }

    public static func key(
        for action: StorageAction,
        entityID: String,
        path: String
    ) -> ExecutionCapabilityKey {
        ExecutionCapabilityKey(
            action: action,
            vendor: ActionPolicy.vendorStorageKind(entityID: entityID, path: path),
            entityKind: ActionPolicy.vendorEntityKind(entityID: entityID, path: path)
        )
    }

    public static var reportMap: [String: String] {
        var map: [String: String] = [:]
        for action in StorageAction.allCases {
            map[action.rawValue] = support(for: action).rawValue
        }
        map["VENDOR_NATIVE_CLEANUP|OLLAMA|MODEL"] = support(
            for: .vendorNativeCleanup, vendor: .ollama, entityKind: .model
        ).rawValue
        map["VENDOR_NATIVE_CLEANUP|HUGGING_FACE|SNAPSHOT"] = support(
            for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .snapshot
        ).rawValue
        map["VENDOR_NATIVE_CLEANUP|HUGGING_FACE|REPOSITORY"] = support(
            for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .repository
        ).rawValue
        map["VENDOR_NATIVE_CLEANUP|HUGGING_FACE|BLOB"] = support(
            for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .blob
        ).rawValue
        map["VENDOR_NATIVE_CLEANUP|OLLAMA|BLOB"] = support(
            for: .vendorNativeCleanup, vendor: .ollama, entityKind: .blob
        ).rawValue
        return map
    }
}
