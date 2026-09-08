import Foundation

public struct VerificationLoopContext: Sendable {
    public var resolver: EvidenceResolver
    public var processes: any ProcessRunningChecker
    public var handles: any OpenHandleChecker
    public var processCompleteness: ObservationCompleteness
    public var handleCompleteness: ObservationCompleteness
    public var proofTargets: Set<String>
    public var budget: VerificationBudgetConfig
    public var observedAt: Date

    public init(
        resolver: EvidenceResolver,
        processes: any ProcessRunningChecker,
        handles: any OpenHandleChecker,
        processCompleteness: ObservationCompleteness,
        handleCompleteness: ObservationCompleteness,
        proofTargets: Set<String> = ["derived-data"],
        budget: VerificationBudgetConfig = .default,
        observedAt: Date = Date()
    ) {
        self.resolver = resolver
        self.processes = processes
        self.handles = handles
        self.processCompleteness = processCompleteness
        self.handleCompleteness = handleCompleteness
        self.proofTargets = proofTargets
        self.budget = budget
        self.observedAt = observedAt
    }
}

public enum VerificationCandidateBuilder {
    public static func build(
        from detected: [DetectedEntity],
        context: VerificationLoopContext,
        byteHints: [String: Int64] = [:]
    ) -> [VerificationCandidate] {
        detected.compactMap { entity in
            buildOne(entity: entity, context: context, byteHints: byteHints)
        }.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.entityID < rhs.entityID
        }
    }

    static func buildOne(
        entity: DetectedEntity,
        context: VerificationLoopContext,
        byteHints: [String: Int64]
    ) -> VerificationCandidate? {
        let path = (entity.entity.path as NSString).standardizingPath
        let id = entity.entity.id
        let level = ResolutionLevel.assign(
            entityID: id,
            path: path,
            predicatesAllTrue: false,
            safetyClass: .unknown
        ).rawValue
        let bytes = byteHints[path] ?? entity.entity.logicalBytes
        let measurementKnown = bytes > 0 || ScanSessionContext.current?.measurement(for: path)?.isKnown == true

        var unresolved = unresolvedClaims(for: entity, context: context)
        var blocking: [String] = []
        let strategies = availableStrategies(for: entity, unresolved: &unresolved, context: context, blocking: &blocking)
        if unresolved.isEmpty, strategies.isEmpty { return nil }

        if !measurementKnown, bytes == 0, isHugeUnknownRoot(path) {
            blocking.append("BLOCKED_NO_BOUNDED_STRATEGY")
            unresolved = unresolved.filter { $0.tier <= 2 }
        }
        if strategies.isEmpty, !unresolved.isEmpty {
            blocking.append("BLOCKED_NO_BOUNDED_STRATEGY")
        }

        let cost = estimatedCost(strategies: strategies, entity: entity)
        let priority = scorePriority(
            entity: entity,
            level: level,
            bytes: bytes,
            unresolved: unresolved,
            strategies: strategies,
            cost: cost,
            blocking: blocking
        )
        let tier = proofTier(for: entity, context: context)

        return VerificationCandidate(
            entityID: id,
            canonicalPath: path,
            domain: entity.domain,
            semanticLevel: level,
            uniqueBytes: bytes,
            measurementKnown: measurementKnown,
            unresolvedClaims: unresolved,
            strategiesAvailable: strategies,
            priority: priority,
            estimatedCostMs: cost,
            blockingReasons: blocking,
            attemptState: blocking.contains("BLOCKED_NO_BOUNDED_STRATEGY") ? .blocked : .notAttempted,
            proofTier: tier
        )
    }

    static func unresolvedClaims(for entity: DetectedEntity, context: VerificationLoopContext) -> [VerificationClaimType] {
        var claims: [VerificationClaimType] = []
        let id = entity.entity.id
        let path = entity.entity.path.lowercased()
        let rels = entity.annotation?.relationships ?? []
        let prov = entity.annotation?.provenance.confidence ?? .unknown

        if prov != .verified { claims.append(.provenance) }

        if id.contains("cursor") || path.contains("workspaceStorage") {
            let hasVerifiedWS = rels.contains { $0.type == .belongsToWorkspace && $0.confidence == .verified }
            if !hasVerifiedWS { claims.append(.belongsToWorkspace) }
        }

        if path.contains("deriveddata") {
            let hasDerived = rels.contains {
                ($0.type == .derivedFrom || $0.type == .belongsToWorkspace) && $0.confidence == .verified
            }
            if !hasDerived { claims.append(.derivedFrom) }
            claims.append(.sourceOfTruth)
            claims.append(.regenerability)
        }

        if id.contains("claude.vm") {
            claims.append(.activeState)
        }

        if entity.bucket == .cloud || path.contains("cloudstorage") || path.contains("mobile documents") {
            claims.append(.remoteCopyExists)
            claims.append(.syncState)
        }

        if path.contains("node_modules"), context.proofTargets.contains("node-modules") {
            claims.append(.regenerability)
            claims.append(.derivedFrom)
        }

        if isOllamaPath(id: id, path: path) {
            claims.append(.owningProduct)
            claims.append(.referenceGraph)
            claims.append(.sharedByteStatus)
            claims.append(.reacquisition)
            claims.append(.activeState)
        }
        if isHuggingFacePath(id: id, path: path) {
            claims.append(.owningProduct)
            claims.append(.referenceGraph)
            claims.append(.sharedByteStatus)
            claims.append(.reacquisition)
            claims.append(.belongsToVersion)
        }

        if entity.associatedProcesses.isEmpty == false {
            claims.append(.openFileState)
        }

        return dedupeClaims(claims)
    }

    static func availableStrategies(
        for entity: DetectedEntity,
        unresolved: inout [VerificationClaimType],
        context: VerificationLoopContext,
        blocking: inout [String]
    ) -> [VerificationStrategyID] {
        var strategies: [VerificationStrategyID] = []
        let id = entity.entity.id
        let path = entity.entity.path.lowercased()

        if id.contains("cursor") || path.contains("workspaceStorage") {
            let assessment = ProofFeasibilityResolver.assess(entity: entity, strategy: .cursorMetadata)
            if assessment.feasibility == .explicitRouteAvailable || assessment.feasibility == .notApplicable {
                strategies.append(.cursorMetadata)
                strategies.append(.workspaceRelationship)
            } else if assessment.feasibility == .explicitRouteNotFound || assessment.feasibility == .ambiguousRoute {
                blocking.append("NO_EXPLICIT_METADATA_ROUTE")
            }
        }
        if id.contains("claude.vm") {
            strategies.append(.claudeVMActive)
        }
        if path.contains("deriveddata"), context.proofTargets.contains("derived-data") {
            strategies.append(.derivedData)
        }
        if path.contains("node_modules"), context.proofTargets.contains("node-modules") {
            strategies.append(.nodeModules)
        }
        if entity.bucket == .cloud {
            strategies.append(.fileProvider)
        }
        if isOllamaPath(id: id, path: path) {
            strategies.append(.ollamaStorage)
        }
        if isHuggingFacePath(id: id, path: path) {
            strategies.append(.huggingFaceStorage)
        }

        if unresolved.contains(.sourceOfTruth) { strategies.append(.resolverSourceOfTruth) }
        if unresolved.contains(.regenerability) { strategies.append(.resolverRegenerability) }
        if unresolved.contains(.activeState) || unresolved.contains(.openFileState) {
            strategies.append(.resolverActiveState)
        }

        return Array(Set(strategies)).sorted { $0.rawValue < $1.rawValue }
    }

    static func proofTier(for entity: DetectedEntity, context: VerificationLoopContext) -> VerificationProofTier {
        let path = entity.entity.path.lowercased()
        if path.contains("node_modules") { return .optIn }
        if path.contains("deriveddata") || entity.entity.id.contains("cursor") || entity.entity.id.contains("claude.vm") {
            return .boundedDefault
        }
        if isOllamaPath(id: entity.entity.id, path: path) || isHuggingFacePath(id: entity.entity.id, path: path) {
            return .boundedDefault
        }
        return .core
    }

    static func isOllamaPath(id: String, path: String) -> Bool {
        if id.contains("ollama.log") || path.contains("/.ollama/logs") { return false }
        return id.contains("ollama") || path.contains("/.ollama/")
    }

    static func isHuggingFacePath(id: String, path: String) -> Bool {
        if id.contains("ai.hf.datasets") { return true }
        return id.contains("ai.hf") || id.contains("huggingface") || path.contains("/huggingface/")
    }

    static func scorePriority(
        entity: DetectedEntity,
        level: Int,
        bytes: Int64,
        unresolved: [VerificationClaimType],
        strategies: [VerificationStrategyID],
        cost: Int,
        blocking: [String]
    ) -> Double {
        if !blocking.isEmpty { return 0 }
        let tier1 = Double(unresolved.filter { $0.tier == 1 }.count) * 100.0
        let tier2 = Double(unresolved.filter { $0.tier == 2 }.count) * 40.0
        let tier3 = Double(unresolved.filter { $0.tier == 3 }.count) * 10.0
        let levelBoost = level >= ResolutionLevel.l4SemanticEntity.rawValue ? 50.0 : (level >= ResolutionLevel.l3Product.rawValue ? 25.0 : 0.0)
        let strategyBoost = strategies.isEmpty ? -1000.0 : Double(strategies.count) * 5.0
        let byteFactor = min(20.0, log10(max(1.0, Double(bytes))) * 2.0)
        let costPenalty = Double(cost) / 100.0
        let feasibilityBoost = feasibilityBoost(for: entity, strategies: strategies)
        var total = tier1
        total += tier2
        total += tier3
        total += levelBoost
        total += strategyBoost
        total += byteFactor
        total += feasibilityBoost
        total -= costPenalty
        return total
    }

    static func feasibilityBoost(for entity: DetectedEntity, strategies: [VerificationStrategyID]) -> Double {
        guard !strategies.isEmpty else { return 0 }
        let factors = strategies.map { ProofFeasibilityResolver.feasibilityFactor(ProofFeasibilityResolver.assess(entity: entity, strategy: $0).feasibility) }
        return (factors.max() ?? 0) * 30.0
    }

    static func estimatedCost(strategies: [VerificationStrategyID], entity: DetectedEntity) -> Int {
        var cost = 5
        for s in strategies {
            switch s {
            case .cursorMetadata: cost += 50
            case .claudeVMActive: cost += 10
            case .derivedData: cost += 30
            case .nodeModules: cost += 80
            case .fileProvider: cost += 20
            case .ollamaStorage, .huggingFaceStorage: cost += 40
            default: cost += 5
            }
        }
        if entity.entity.path.lowercased().contains("deriveddata") { cost += 10 }
        return cost
    }

    static func isHugeUnknownRoot(_ path: String) -> Bool {
        let roots = [
            "/Library/Caches",
            "/Library/Application Support",
            "/Library/Containers",
            "/Library/Group Containers",
        ]
        let expanded = (PathGlob.expandHome(path) as NSString).standardizingPath
        return roots.contains { expanded.hasSuffix($0) || expanded == PathGlob.expandHome("~\($0)") }
    }

    static func dedupeClaims(_ claims: [VerificationClaimType]) -> [VerificationClaimType] {
        var seen = Set<VerificationClaimType>()
        return claims.filter { seen.insert($0).inserted }
    }
}

public enum VerificationStrategySelector {
    public static func select(
        candidate: VerificationCandidate,
        dependencyBlockers: Set<VerificationClaimType>
    ) -> [VerificationStrategyID] {
        candidate.strategiesAvailable.filter { strategy in
            let claims = claimsForStrategy(strategy)
            return !claims.contains(where: { dependencyBlockers.contains($0) })
        }
    }

    static func claimsForStrategy(_ strategy: VerificationStrategyID) -> [VerificationClaimType] {
        switch strategy {
        case .derivedData, .nodeModules:
            return [.derivedFrom, .sourceExists, .sourceOfTruth]
        case .resolverRegenerability:
            return [.derivedFrom, .sourceOfTruth]
        case .claudeVMActive:
            return [.activeState]
        case .cursorMetadata, .workspaceRelationship:
            return [.belongsToWorkspace]
        case .fileProvider:
            return [.remoteCopyExists]
        case .ollamaStorage, .huggingFaceStorage:
            return [.owningProduct, .referenceGraph, .sharedByteStatus, .reacquisition]
        default:
            return []
        }
    }
}
