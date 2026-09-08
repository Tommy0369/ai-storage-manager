import Foundation

public enum ProofFeasibility: String, Codable, Sendable, CaseIterable {
    case explicitRouteAvailable = "EXPLICIT_ROUTE_AVAILABLE"
    case explicitRouteNotFound = "EXPLICIT_ROUTE_NOT_FOUND"
    case ambiguousRoute = "AMBIGUOUS_ROUTE"
    case expensiveOptInOnly = "EXPENSIVE_OPT_IN_ONLY"
    case notApplicable = "NOT_APPLICABLE"
    case unknown = "UNKNOWN"
}

public struct ProofFeasibilityAssessment: Codable, Sendable, Equatable {
    public var feasibility: ProofFeasibility
    public var strategyID: VerificationStrategyID?
    public var claim: VerificationClaimType?
    public var reason: String?
}

public enum ProofFeasibilityResolver {
    public static func assess(entity: DetectedEntity, strategy: VerificationStrategyID) -> ProofFeasibilityAssessment {
        switch strategy {
        case .cursorMetadata, .workspaceRelationship:
            return assessCursor(entity: entity, strategy: strategy)
        case .claudeVMActive:
            return assessClaude(entity: entity)
        case .fileProvider:
            return assessFileProvider(entity: entity)
        case .nodeModules:
            return ProofFeasibilityAssessment(feasibility: .expensiveOptInOnly, strategyID: strategy, claim: .regenerability, reason: "OPT_IN_PROOF")
        case .ollamaStorage:
            let path = entity.entity.path.lowercased()
            if entity.entity.id.contains("ollama") || path.contains("/.ollama/") {
                return ProofFeasibilityAssessment(
                    feasibility: .explicitRouteAvailable,
                    strategyID: strategy,
                    claim: .referenceGraph,
                    reason: "OLLAMA_MANIFEST_ROUTE"
                )
            }
            return ProofFeasibilityAssessment(feasibility: .notApplicable, strategyID: strategy)
        case .huggingFaceStorage:
            let path = entity.entity.path.lowercased()
            if entity.entity.id.contains("ai.hf") || path.contains("/huggingface/") {
                return ProofFeasibilityAssessment(
                    feasibility: .explicitRouteAvailable,
                    strategyID: strategy,
                    claim: .referenceGraph,
                    reason: "HF_HUB_CACHE_ROUTE"
                )
            }
            return ProofFeasibilityAssessment(feasibility: .notApplicable, strategyID: strategy)
        default:
            return ProofFeasibilityAssessment(feasibility: .notApplicable, strategyID: strategy)
        }
    }

    static func assessCursor(entity: DetectedEntity, strategy: VerificationStrategyID) -> ProofFeasibilityAssessment {
        let rels = entity.annotation?.relationships ?? []
        if rels.contains(where: { $0.type == .belongsToWorkspace && $0.confidence == .verified }) {
            return ProofFeasibilityAssessment(feasibility: .notApplicable, strategyID: strategy, claim: .belongsToWorkspace, reason: "ALREADY_VERIFIED")
        }
        let path = entity.entity.path.lowercased()
        if path.hasSuffix("/workspace.json") {
            return ProofFeasibilityAssessment(feasibility: .explicitRouteAvailable, strategyID: strategy, claim: .belongsToWorkspace, reason: "WORKSPACE_JSON")
        }
        if path.contains("/workspacestorage/") {
            let folder = (entity.entity.path as NSString).deletingLastPathComponent
            if FileManager.default.fileExists(atPath: "\(folder)/workspace.json") {
                return ProofFeasibilityAssessment(feasibility: .explicitRouteAvailable, strategyID: strategy, claim: .belongsToWorkspace, reason: "WORKSPACE_JSON_SIBLING")
            }
        }
        if path.contains("state.vscdb") || path.contains("storage.json") {
            return ProofFeasibilityAssessment(feasibility: .explicitRouteAvailable, strategyID: strategy, claim: .belongsToWorkspace, reason: "EXPLICIT_DB_OR_STORAGE_JSON")
        }
        if rels.contains(where: { $0.confidence == .inferred && ($0.type == .possibleWorkspaceContext || $0.type == .associatedWithCursorStore) }) {
            return ProofFeasibilityAssessment(feasibility: .ambiguousRoute, strategyID: strategy, claim: .belongsToWorkspace, reason: "INFERRED_ONLY")
        }
        if entity.entity.id.contains("cursor") || path.contains("cursor") || path.contains("workspacestorage") || path.contains("/snapshots/") {
            return ProofFeasibilityAssessment(
                feasibility: .explicitRouteNotFound,
                strategyID: strategy,
                claim: .belongsToWorkspace,
                reason: "NO_EXPLICIT_METADATA_ROUTE"
            )
        }
        return ProofFeasibilityAssessment(feasibility: .notApplicable, strategyID: strategy)
    }

    static func assessClaude(entity: DetectedEntity) -> ProofFeasibilityAssessment {
        guard entity.entity.id.contains("claude.vm") else {
            return ProofFeasibilityAssessment(feasibility: .notApplicable, strategyID: .claudeVMActive)
        }
        if entity.associatedProcesses.isEmpty {
            return ProofFeasibilityAssessment(feasibility: .explicitRouteNotFound, strategyID: .claudeVMActive, claim: .activeState, reason: "NO_EXPLICIT_RUNTIME_ROUTE")
        }
        return ProofFeasibilityAssessment(feasibility: .explicitRouteAvailable, strategyID: .claudeVMActive, claim: .activeState, reason: "PROCESS_ASSOCIATED")
    }

    static func assessFileProvider(entity: DetectedEntity) -> ProofFeasibilityAssessment {
        guard entity.bucket == .cloud || entity.entity.path.lowercased().contains("mobile documents") else {
            return ProofFeasibilityAssessment(feasibility: .notApplicable, strategyID: .fileProvider)
        }
        if entity.entity.kind == .cloudPlaceholder || entity.entity.kind == .cloudLocalMaterialized {
            return ProofFeasibilityAssessment(feasibility: .explicitRouteAvailable, strategyID: .fileProvider, claim: .remoteCopyExists, reason: "CLOUD_ENTITY_KIND")
        }
        return ProofFeasibilityAssessment(
            feasibility: .explicitRouteNotFound,
            strategyID: .fileProvider,
            claim: .remoteCopyExists,
            reason: "UNKNOWN_NO_PROVIDER_EVIDENCE"
        )
    }

    public static func feasibilityFactor(_ feasibility: ProofFeasibility) -> Double {
        switch feasibility {
        case .explicitRouteAvailable: return 1.0
        case .notApplicable: return 0.8
        case .unknown: return 0.5
        case .ambiguousRoute: return 0.2
        case .explicitRouteNotFound: return 0.05
        case .expensiveOptInOnly: return 0.1
        }
    }
}

public struct BacklogFeasibilityReport: Codable, Sendable, Equatable {
    public var assessments: [BacklogFeasibilityEntry]
    public var blockedNoRouteCount: Int
    public var explicitRouteAvailableCount: Int
}

public struct BacklogFeasibilityEntry: Codable, Sendable, Equatable {
    public var entityID: String
    public var path: String
    public var strategyID: String
    public var claim: String
    public var feasibility: ProofFeasibility
    public var reason: String?
}

public struct P111RuntimeComparison: Codable, Sendable, Equatable {
    public var p110TotalSeconds: Double
    public var p111TotalSeconds: Double
    public var safetyEvalP110Ms: Int
    public var safetyEvalP111Ms: Int
    public var entityVerificationLoopP110Ms: Int
    public var entityVerificationLoopP111Ms: Int
}

extension P111RuntimeComparison {
    public static let p110Baseline = P111RuntimeComparison(
        p110TotalSeconds: 89.4,
        p111TotalSeconds: 0,
        safetyEvalP110Ms: 26_100,
        safetyEvalP111Ms: 0,
        entityVerificationLoopP110Ms: 31_500,
        entityVerificationLoopP111Ms: 0
    )
}
