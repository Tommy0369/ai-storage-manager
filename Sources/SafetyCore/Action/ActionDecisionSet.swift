import Foundation

/// Immutable canonical Action decisions for one EntitySafetySnapshot generation.
public struct ActionDecisionSet: Codable, Sendable, Equatable {
    public var entityID: String
    public var snapshotGeneration: Int
    public var evidenceGeneration: Int
    public var runtimeGeneration: Int
    public var decisions: [String: ActionDecision]

    public init(
        entityID: String,
        snapshotGeneration: Int,
        evidenceGeneration: Int,
        runtimeGeneration: Int,
        decisions: [StorageAction: ActionDecision]
    ) {
        self.entityID = entityID
        self.snapshotGeneration = snapshotGeneration
        self.evidenceGeneration = evidenceGeneration
        self.runtimeGeneration = runtimeGeneration
        self.decisions = Dictionary(uniqueKeysWithValues: decisions.map { ($0.key.rawValue, $0.value) })
    }

    public func decision(for action: StorageAction) -> ActionDecision? {
        decisions[action.rawValue]
    }

    public var decisionMap: [StorageAction: ActionDecision] {
        var out: [StorageAction: ActionDecision] = [:]
        for (key, value) in decisions {
            if let action = StorageAction(rawValue: key) {
                out[action] = value
            }
        }
        return out
    }
}

public struct ActionSafetyEvalDedupReport: Codable, Sendable, Equatable {
    public var actionSafetyEvaluatorInvocations: Int
    public var uniqueEntityActionPairs: Int
    public var duplicateEvaluations: Int
    public var decisionReuseCount: Int
    public var entitiesEvaluated: Int
    public var buildRuntimeMs: Int
}

public struct ActionDecisionCatalog: Sendable {
    public var setsByEntityID: [String: ActionDecisionSet]
    public var telemetry: ActionSafetyEvalDedupReport

    public func set(for entityID: String) -> ActionDecisionSet? {
        setsByEntityID[entityID]
    }
}

public enum ActionDecisionBuilder {
    public static func buildCatalog(
        items: [ClassifiedItem],
        engine: SafetyRuleEngine,
        snapshotsByEntityID: [String: EntitySafetySnapshot],
        safetyDecisionsByEntityID: [String: [ActionMode: SafetyDecision]],
        userContext: ActionUserContext = .default,
        evidenceByEntityID: [String: EvidenceBundle] = [:],
        stateByEntityID: [String: RuntimeState] = [:]
    ) -> ActionDecisionCatalog {
        let started = Date()
        var sets: [String: ActionDecisionSet] = [:]
        var invocations = 0
        for item in items {
            let snapshot = snapshotsByEntityID[item.detected.entity.id]
            let evidence = snapshot?.evidence
                ?? evidenceByEntityID[item.detected.entity.id]
                ?? ActionArchitecture.evidenceBundle(from: item, snapshot: snapshot)
            let state = snapshot?.state ?? stateByEntityID[item.detected.entity.id] ?? RuntimeState()
            invocations += StorageAction.allCases.count
            let map = ActionSafetyEvaluator.evaluateAll(
                item: item,
                engine: engine,
                evidence: evidence,
                state: state,
                userContext: userContext,
                snapshot: snapshot,
                safetyDecisions: safetyDecisionsByEntityID[item.detected.entity.id]
            )
            let cacheKey = snapshot?.cacheKey
            sets[item.detected.entity.id] = ActionDecisionSet(
                entityID: item.detected.entity.id,
                snapshotGeneration: cacheKey?.verificationGeneration ?? item.verification?.snapshotGeneration ?? 0,
                evidenceGeneration: cacheKey?.evidenceVersion ?? snapshot?.evidence.snapshotVersion ?? 0,
                runtimeGeneration: cacheKey?.runtimeGeneration ?? 0,
                decisions: map
            )
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        let pairs = items.count * StorageAction.allCases.count
        return ActionDecisionCatalog(
            setsByEntityID: sets,
            telemetry: ActionSafetyEvalDedupReport(
                actionSafetyEvaluatorInvocations: invocations,
                uniqueEntityActionPairs: pairs,
                duplicateEvaluations: 0,
                decisionReuseCount: 0,
                entitiesEvaluated: items.count,
                buildRuntimeMs: ms
            )
        )
    }

    public static func recordReuse(_ telemetry: inout ActionSafetyEvalDedupReport, count: Int = 1) {
        telemetry.decisionReuseCount += count
    }
}

extension ActionDecisionCatalog {
    public var decisionMapByEntityID: [String: [StorageAction: ActionDecision]] {
        Dictionary(uniqueKeysWithValues: setsByEntityID.map { ($0.key, $0.value.decisionMap) })
    }
}
