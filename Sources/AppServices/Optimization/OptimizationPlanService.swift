import Foundation
import SafetyCore

public enum OptimizationPlanService {
    public static func build(
        goal: OptimizationGoal,
        snapshot: StorageExperienceSnapshot?,
        explorer: StorageExplorerSnapshot?,
        safe: [UICandidateItem],
        review: [UICandidateItem],
        protected: [UICandidateItem],
        extraFacts: [OptimizationActionFact] = [],
        changeReport: StorageChangeReport? = nil,
        history: [UIActionHistoryItem] = [],
        falseGREEN: Int = 0,
        duplicateEvaluations: Int = 0
    ) -> OptimizationPlan {
        let snapshotID = explorer?.snapshotID ?? "experience-\(snapshot?.generatedAt.timeIntervalSince1970 ?? 0)"
        return OptimizationPlanEngine.plan(
            goal: goal,
            items: safe + review + protected,
            extraFacts: extraFacts,
            snapshotID: snapshotID,
            changeReport: changeReport,
            history: history,
            falseGREEN: falseGREEN,
            duplicateEvaluations: duplicateEvaluations
        )
    }

    public static func extraFacts(from report: ReadOnlyAnalysisReport) -> [OptimizationActionFact] {
        var facts: [OptimizationActionFact] = []
        let catalog = ReadOnlyAnalysisPipeline.lastExecutionContext?.decisionCatalog
        // Late path only — not first-map. Resolve Ollama interface once per plan build.
        var ollamaInterface: OllamaNativeInterfaceResolution?
        for item in report.items {
            let map = catalog?.set(for: item.detected.entity.id)?.decisionMap ?? [:]
            for (action, decision) in map where action != .keep && action != .moveToTrash {
                var blocked = decision.blockedReasons.map(\.rawValue)
                var explanation = decision.explanationCodes.joined(separator: ", ")
                if action == .vendorNativeCleanup, ActionPolicy.isOllamaModelEntity(item) {
                    if ollamaInterface == nil {
                        ollamaInterface = OllamaNativeInterfaceResolver.resolve(
                            context: .init(modelDataPresent: true)
                        )
                    }
                    if let iface = ollamaInterface {
                        let rem = VendorAbsentManagedDataAnalyzer.evaluateOllamaModel(
                            item: item,
                            interface: iface
                        )
                        if rem.managedDataAvailability == .vendorAbsentManagedDataRemains {
                            blocked.append(VendorManagedDataAvailability.vendorAbsentManagedDataRemains.rawValue)
                            explanation = rem.explanation
                        }
                    }
                }
                facts.append(OptimizationActionFact(
                    entityID: item.detected.entity.id,
                    displayName: item.detected.entity.displayName.isEmpty
                        ? item.detected.entity.id : item.detected.entity.displayName,
                    canonicalPath: item.detected.entity.path,
                    action: action,
                    eligible: decision.eligible,
                    safetyClass: decision.safetyClass,
                    expectedLogicalBytes: decision.expectedLogicalBytesMoved
                        ?? item.verification?.uniqueBytesProven
                        ?? item.exclusiveBytes,
                    blockedReasons: blocked,
                    explanation: explanation
                ))
            }
        }
        return facts
    }

    public static func demoPartialPlan() throws -> OptimizationPlan {
        try plan(
            goalGB: 20,
            items: [
                ui("xcode.derived", "Xcode Build Data", 4_200_000_000, .green, .approvalRequired, .safeActions, "/tmp/DerivedData/a", true),
                ui("cache.gen", "Generated Cache", 2_100_000_000, .green, .approvalRequired, .safeActions, "/tmp/Caches/gen", true),
                ui("icloud.videos", "iCloud-backed Videos", 6_100_000_000, .green, .unknown, .reviewNeeded, "/tmp/Videos", false, action: .moveToICloud),
                ui("ollama.models", "AI model storage", 8_400_000_000, .unknown, .verifyMore, .reviewNeeded, "/tmp/.ollama/models", false),
                ui("claude.runtime", "Claude runtime data", 12_000_000_000, .red, .unknown, .protected, "/tmp/Claude", false)
            ],
            extra: [
                OptimizationActionFact(
                    entityID: "icloud.videos",
                    displayName: "iCloud-backed Videos",
                    canonicalPath: "/tmp/Videos",
                    action: .moveToICloud,
                    eligible: true,
                    safetyClass: .green,
                    expectedLogicalBytes: 6_100_000_000,
                    explanation: "Local copy is iCloud-backed. Executor not implemented."
                )
            ],
            change: StorageChangeService.demoChangeReport()
        )
    }

    public static func demoAchievablePlan() throws -> OptimizationPlan {
        try plan(
            goalGB: 6,
            items: [
                ui("xcode.derived", "Xcode Build Data", 4_200_000_000, .green, .approvalRequired, .safeActions, "/tmp/DerivedData/a", true),
                ui("cache.gen", "Generated Cache", 2_100_000_000, .green, .approvalRequired, .safeActions, "/tmp/Caches/gen", true)
            ]
        )
    }

    public static func demoNoSafePlan() throws -> OptimizationPlan {
        try plan(
            goalGB: 20,
            items: [
                ui("voice", "Voice Memos", 3_000_000_000, .red, .unknown, .protected, "/tmp/Recordings", false),
                ui("unknown.big", "Unresolved 12 GB folder", 12_000_000_000, .unknown, .verifyMore, .reviewNeeded, "/tmp/Huge", false)
            ]
        )
    }

    private static func plan(
        goalGB: Int,
        items: [UICandidateItem],
        extra: [OptimizationActionFact] = [],
        change: StorageChangeReport? = nil
    ) throws -> OptimizationPlan {
        OptimizationPlanEngine.plan(
            goal: try .gigabytes(goalGB),
            items: items,
            extraFacts: extra,
            snapshotID: "fixture-p303",
            changeReport: change
        )
    }

    private static func ui(
        _ id: String,
        _ name: String,
        _ bytes: Int64,
        _ safety: SafetyClass,
        _ readiness: UIReadinessState,
        _ group: UICandidateGroup,
        _ path: String,
        _ executor: Bool,
        action: StorageAction? = nil
    ) -> UICandidateItem {
        UICandidateItem(
            id: id,
            entityID: id,
            displayName: name,
            category: "Fixture",
            pathSummary: path,
            fullPath: path,
            byteLabel: UICandidateMapper.byteLabel(bytes),
            expectedBytes: bytes,
            recommendedAction: executor ? .moveToTrash : action,
            recommendedActionLabel: executor ? "Move to Trash" : "No action available",
            reasonSummary: safety == .red ? "Protected user data" : "Canonical fixture",
            readiness: readiness,
            group: group,
            safetyClass: safety,
            evidenceLines: [],
            executorAvailable: executor
        )
    }
}
