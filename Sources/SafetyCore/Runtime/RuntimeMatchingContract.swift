import Foundation

public struct RuntimeSensitiveContract: Sendable, Equatable {
    public var entityID: String
    public var allowsDescendantOpenMatch: Bool
    public var allowsProcessArgExactMatch: Bool
    public var allowsProcessExecutableOnly: Bool
    public var relatedExactPaths: [String]

    public static func forEntity(_ entity: DetectedEntity) -> RuntimeSensitiveContract {
        let path = entity.entity.path
        let id = entity.entity.id.lowercased()
        let isClaudeVM = id.contains("claude.vm") || path.lowercased().contains("rootfs.img") || path.lowercased().contains("vm_bundles")
        let isDerivedData = path.lowercased().contains("deriveddata") || id.contains("deriveddata")
        let related = VerificationStrategies.claudeRelatedPaths(entity: entity)
        return RuntimeSensitiveContract(
            entityID: entity.entity.id,
            allowsDescendantOpenMatch: isClaudeVM || isDerivedData,
            allowsProcessArgExactMatch: true,
            allowsProcessExecutableOnly: false,
            relatedExactPaths: related
        )
    }
}

public enum RuntimePathMatcher {
    public static func canonical(_ path: String) -> String {
        (PathGlob.expandHome(path) as NSString).standardizingPath
    }

    public static func relation(entityPath: String, observedPath: String) -> PathObservationRelation {
        let entity = canonical(entityPath)
        let observed = canonical(observedPath)
        if entity == observed { return .exactEntityPath }
        if observed.hasPrefix(entity + "/") { return .observationInsideEntity }
        if entity.hasPrefix(observed + "/") { return .entityInsideObservedParent }
        let entityParent = (entity as NSString).deletingLastPathComponent
        let observedParent = (observed as NSString).deletingLastPathComponent
        if entityParent == observedParent, entity != observed { return .siblingObservation }
        return .unrelated
    }

    public static func openMatch(entityPath: String, observedOpenPath: String, contract: RuntimeSensitiveContract) -> Bool {
        let rel = relation(entityPath: entityPath, observedPath: observedOpenPath)
        switch rel {
        case .exactEntityPath:
            return true
        case .observationInsideEntity:
            return contract.allowsDescendantOpenMatch
        case .entityInsideObservedParent, .siblingObservation, .unrelated:
            return false
        }
    }

    public static func commandArgMatch(entityPath: String, referencedPath: String, contract: RuntimeSensitiveContract) -> Bool {
        let rel = relation(entityPath: entityPath, observedPath: referencedPath)
        switch rel {
        case .exactEntityPath:
            return contract.allowsProcessArgExactMatch
        case .observationInsideEntity:
            return contract.allowsDescendantOpenMatch && contract.allowsProcessArgExactMatch
        default:
            return false
        }
    }
}
