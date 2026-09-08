import Foundation
import SafetyCore

public struct P33ACurrentInventoryRebaseReport: Codable, Sendable {
    public var diskCapacityTotalBytes: Int64
    public var diskCapacityFreeBytes: Int64
    public var diskCapacityUsedBytes: Int64
    public var completedVerifiedRecoveryBytes: Int64
    public var ollamaVerifiedRecovery: Int64
    public var hfVerifiedRecovery: Int64
    public var remaining20GBGoalBytes: Int64
    public var top20UniqueEntities: [P33AEntityRank]
    public var ReadyNow: Int64
    public var ApprovalRequired: Int64
    public var VerifiedFuture: Int64
    public var VerifyMore: Int64
    public var Protected: Int64
    public var currentlyExecutableActions: [String]
    public var removedCompletedActionsExcluded: Bool
    public var qwen3Absent: Bool
    public var hfRemovedRevisionAbsent: Bool
    public var cursorStillTopTarget: Bool
    public var generatedAt: Date
}

public struct P33AEntityRank: Codable, Sendable {
    public var entityID: String
    public var uniqueBytes: Int64
    public var note: String
}

public struct P33ANextPhaseDecisionReport: Codable, Sendable {
    public var currentTopStorageEntities: [String]
    public var selectedNextCenterpin: String
    public var selectedEntity: String
    public var selectedComponent: String
    public var selectedBytes: Int64
    public var whyThisBeatsAlternatives: String
    public var expectedProofPath: String
    public var mutationNeededNextPhase: Bool
    public var humanAuthorizationNeededNextPhase: Bool
    public var rejectedAlternatives: [String]
    public var generatedAt: Date
}

public struct P33APerformanceReport: Codable, Sendable {
    public var currentInventoryRefreshMs: Int
    public var cursorRootResolutionMs: Int
    public var cursorComponentClassificationMs: Int
    public var extensionOwnershipMappingMs: Int
    public var runtimeRelationshipBuildMs: Int
    public var historyGrowthAnalysisMs: Int
    public var opportunityRankingMs: Int
    public var secondCrawlerAdded: Bool
    public var generatedAt: Date
}

public enum P33AReportBuilder {
    public static let ollamaVerified: Int64 = 2_497_293_931
    public static let hfVerified: Int64 = 3_083_520_968
    public static let goalBytes: Int64 = 20_000_000_000

    public static func writeAll(
        outDir: URL,
        inventory: P33ACurrentInventoryRebaseReport,
        cursor: CursorGlobalStorageIntelligenceReport,
        growth: [String: Any],
        runtime: [String: Any],
        decision: P33ANextPhaseDecisionReport,
        performance: P33APerformanceReport
    ) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601

        try enc.encode(inventory).write(to: outDir.appendingPathComponent("p3_3a_current_inventory_rebase.json"))
        try enc.encode(cursorRoot(from: cursor)).write(to: outDir.appendingPathComponent("p3_3a_cursor_root.json"))
        try enc.encode(components(from: cursor)).write(to: outDir.appendingPathComponent("p3_3a_cursor_components.json"))
        try enc.encode(cursor.extensionOwnership).write(to: outDir.appendingPathComponent("p3_3a_cursor_extension_ownership.json"))
        try enc.encode(opportunities(from: cursor)).write(to: outDir.appendingPathComponent("p3_3a_cursor_opportunities.json"))
        try enc.encode(decision).write(to: outDir.appendingPathComponent("p3_3a_next_phase_decision.json"))
        try enc.encode(performance).write(to: outDir.appendingPathComponent("p3_3a_performance.json"))

        let rt = try JSONSerialization.data(withJSONObject: runtime, options: [.prettyPrinted, .sortedKeys])
        try rt.write(to: outDir.appendingPathComponent("p3_3a_cursor_runtime.json"))
        let gr = try JSONSerialization.data(withJSONObject: growth, options: [.prettyPrinted, .sortedKeys])
        try gr.write(to: outDir.appendingPathComponent("p3_3a_cursor_growth.json"))
    }

    public struct CursorRootDTO: Codable, Sendable {
        public var entity: String
        public var pathClass: String
        public var owner: String
        public var semanticRole: String
        public var observedBytes: Int64
        public var uniqueBytes: Int64
        public var mappedChildBytes: Int64
        public var unknownBytes: Int64
        public var classificationCoverage: Double
        public var accountingValid: Bool
        public var appInstalled: Bool
        public var appVersion: String?
        public var appRunning: Bool
        public var rootSafety: String
        public var rootActionability: String
        public var rootExecutable: Bool
        public var privacyNote: String
    }

    public static func cursorRoot(from r: CursorGlobalStorageIntelligenceReport) -> CursorRootDTO {
        CursorRootDTO(
            entity: r.rootEntityID,
            pathClass: "ApplicationSupport/Cursor/User/globalStorage",
            owner: r.owner,
            semanticRole: r.semanticRole,
            observedBytes: r.observedBytes,
            uniqueBytes: r.uniqueBytes,
            mappedChildBytes: r.mappedChildBytes,
            unknownBytes: r.unknownBytes,
            classificationCoverage: r.classificationCoveragePercent,
            accountingValid: r.accountingValid,
            appInstalled: r.appInstalled,
            appVersion: r.appVersion,
            appRunning: r.appRunning,
            rootSafety: r.rootSafety,
            rootActionability: r.rootActionability,
            rootExecutable: r.rootExecutable,
            privacyNote: r.privacyNote
        )
    }

    public struct ComponentsDTO: Codable, Sendable {
        public var components: [CursorStorageComponent]
        public var kvNamespaceSummaries: [CursorKVNamespaceSummary]
        public var privacyNote: String
    }

    public static func components(from r: CursorGlobalStorageIntelligenceReport) -> ComponentsDTO {
        ComponentsDTO(components: r.components, kvNamespaceSummaries: r.kvNamespaceSummaries, privacyNote: r.privacyNote)
    }

    public struct OpportunitiesDTO: Codable, Sendable {
        public var opportunities: [CursorStorageOpportunity]
        public var anyCurrentExecutable: Bool
    }

    public static func opportunities(from r: CursorGlobalStorageIntelligenceReport) -> OpportunitiesDTO {
        OpportunitiesDTO(
            opportunities: r.opportunities,
            anyCurrentExecutable: r.opportunities.contains(where: \.currentExecutable)
        )
    }
}
