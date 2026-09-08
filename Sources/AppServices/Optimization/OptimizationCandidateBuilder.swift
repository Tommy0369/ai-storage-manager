import Foundation
import SafetyCore

/// Builds planning candidates from canonical UI/Safety facts. No filesystem IO. No Safety inference.
public enum OptimizationCandidateBuilder {
    public static func build(
        items: [UICandidateItem],
        extraFacts: [OptimizationActionFact] = [],
        history: [UIActionHistoryItem] = []
    ) -> [OptimizationCandidate] {
        var out: [OptimizationCandidate] = []
        var seen = Set<String>()

        for item in items {
            let action = item.recommendedAction ?? .moveToTrash
            let candidate = fromUIItem(item, action: action, history: history)
            let key = "\(candidate.entityID)|\(candidate.action.rawValue)"
            seen.insert(key)
            out.append(candidate)
        }

        for fact in extraFacts {
            let key = "\(fact.entityID)|\(fact.action.rawValue)"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(fromFact(fact))
        }
        return out
    }

    public static func fromUIItem(
        _ item: UICandidateItem,
        action: StorageAction,
        history: [UIActionHistoryItem] = []
    ) -> OptimizationCandidate {
        let support = ActionExecutionCapabilityRegistry.support(
            for: action,
            entityID: item.entityID,
            path: item.fullPath
        )
        let bytes = max(0, item.expectedBytes ?? 0)
        let trashSemantics = action == .moveToTrash
        let recovered = verifiedRecovered(entityID: item.entityID, history: history)
        let tier = assignTier(
            safetyClass: item.safetyClass,
            group: item.group,
            readiness: item.readiness,
            support: support,
            action: action
        )
        let blast = classifyBlast(path: item.fullPath, entityID: item.entityID)
        let complexity: TransactionComplexityClass = action == .moveToTrash ? .simple : .complex
        return OptimizationCandidate(
            candidateID: "\(item.entityID)|\(action.rawValue)",
            entityID: item.entityID,
            displayName: item.displayName,
            canonicalPath: item.fullPath,
            action: action,
            readiness: item.readiness,
            executionSupport: support,
            logicalBytes: bytes,
            potentialRecoveryBytes: bytes,
            immediateExpectedRecoveryBytes: trashSemantics ? 0 : 0,
            verifiedRecoveredBytes: recovered,
            recoveryState: recovered > 0 ? "STORAGE_RECOVERY_VERIFIED" : (trashSemantics ? "NOT_IMMEDIATE" : "UNKNOWN"),
            safetyClass: item.safetyClass,
            blastRadius: blast,
            reversibility: action == .moveToTrash ? "TRASH_REVERSIBLE" : "UNKNOWN",
            transactionComplexity: complexity,
            independenceGroup: independenceGroup(path: item.fullPath),
            blockers: {
                if action == .vendorNativeCleanup { return [] }
                return item.safetyClass == .red || item.group == .protected ? ["PROTECTED_OR_BLOCKED"] : []
            }(),
            explanation: item.reasonSummary,
            whyIncluded: [],
            whyExcluded: exclusionHint(tier: tier, item: item, support: support, action: action),
            tier: tier,
            category: item.category
        )
    }

    public static func fromFact(_ fact: OptimizationActionFact) -> OptimizationCandidate {
        let support = ActionExecutionCapabilityRegistry.support(
            for: fact.action,
            entityID: fact.entityID,
            path: fact.canonicalPath
        )
        let bytes = max(0, fact.expectedLogicalBytes)
        let tier: OptimizationEligibilityTier
        if fact.blockedReasons.contains("VENDOR_ABSENT_MANAGED_DATA_REMAINS")
            || fact.blockedReasons.contains(VendorManagedDataAvailability.vendorAbsentManagedDataRemains.rawValue)
            || fact.explanation.contains("VENDOR_ABSENT_MANAGED_DATA_REMAINS") {
            tier = .requiresVendorRestoration
        } else if fact.safetyClass == .red, fact.action != .vendorNativeCleanup {
            // Generic entity RED protects trash/raw paths — not vendor-native action eligibility.
            tier = .protectedTier
        } else if support == .notSupported {
            tier = .blocked
        } else if support == .notImplemented, fact.eligible,
                  (fact.safetyClass == .green || fact.action == .vendorNativeCleanup) {
            // HF / unscoped vendor-native remain Verified Future.
            tier = .verifiedButExecutorUnavailable
        } else if support == .implemented, fact.action == .vendorNativeCleanup, fact.eligible {
            // Eligible action-specific decision → Approval Required (consent), not Ready Now.
            tier = .approvalRequired
        } else if fact.action == .vendorNativeCleanup, !fact.eligible {
            tier = .verifyMore
        } else if fact.safetyClass == .unknown || !fact.eligible {
            tier = fact.eligible ? .verifyMore : .blocked
        } else {
            tier = .blocked
        }
        return OptimizationCandidate(
            candidateID: "\(fact.entityID)|\(fact.action.rawValue)",
            entityID: fact.entityID,
            displayName: fact.displayName,
            canonicalPath: fact.canonicalPath,
            action: fact.action,
            readiness: .unknown,
            executionSupport: support,
            logicalBytes: bytes,
            potentialRecoveryBytes: bytes,
            immediateExpectedRecoveryBytes: 0,
            verifiedRecoveredBytes: 0,
            recoveryState: "NOT_IMMEDIATE",
            safetyClass: fact.safetyClass,
            blastRadius: classifyBlast(path: fact.canonicalPath, entityID: fact.entityID),
            reversibility: fact.action == .moveToICloud ? "REMOTE_PRESERVING" : "UNKNOWN",
            transactionComplexity: .complex,
            independenceGroup: independenceGroup(path: fact.canonicalPath),
            blockers: fact.blockedReasons,
            explanation: fact.explanation,
            whyExcluded: factExclusionHint(tier: tier, fact: fact, support: support),
            tier: tier,
            category: ""
        )
    }

    public static func assignTier(
        safetyClass: SafetyClass,
        group: UICandidateGroup,
        readiness: UIReadinessState,
        support: ActionExecutionSupport,
        action: StorageAction
    ) -> OptimizationEligibilityTier {
        // Action-specific: generic entity RED/PROTECTED does not collapse vendor-native eligibility.
        if action == .vendorNativeCleanup {
            if support == .notImplemented { return .verifiedButExecutorUnavailable }
            if support == .notSupported { return .blocked }
            switch readiness {
            case .approvalRequired:
                return .approvalRequired
            case .preflightRequired:
                return .preflightRequired
            case .verifyMore:
                return .verifyMore
            default:
                return .preflightRequired
            }
        }
        if safetyClass == .red || group == .protected {
            return .protectedTier
        }
        if safetyClass == .unknown {
            return .verifyMore
        }
        if readiness == .verifyMore {
            return .verifyMore
        }
        if support == .notImplemented {
            if safetyClass == .green {
                return .verifiedButExecutorUnavailable
            }
            return .blocked
        }
        if support == .notSupported {
            return .blocked
        }
        if action != .moveToTrash {
            return .blocked
        }
        switch readiness {
        case .approvalRequired:
            return .executableNow
        case .preflightRequired:
            return .preflightRequired
        case .completed, .storageRecoveryPending, .regenerated, .postVerifyPending, .executing:
            return .blocked
        default:
            return .blocked
        }
    }

    public static func classifyBlast(path: String, entityID: String) -> BlastRadiusClass {
        let p = path.lowercased()
        let id = entityID.lowercased()
        if p.hasSuffix("/downloads") || p.hasSuffix("/documents") || p.hasSuffix("/desktop") {
            return .high
        }
        if id.contains("deriveddata") && p.contains("/deriveddata/") && !p.hasSuffix("/deriveddata") {
            return .low
        }
        if p.contains("/caches/") || p.contains("xcode") {
            return .low
        }
        if p.contains("/library/") && p.split(separator: "/").count <= 5 {
            return .high
        }
        return .medium
    }

    public static func independenceGroup(path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static func verifiedRecovered(entityID: String, history: [UIActionHistoryItem]) -> Int64 {
        _ = entityID
        _ = history
        // Past recovery is never treated as future available bytes.
        return 0
    }

    private static func exclusionHint(
        tier: OptimizationEligibilityTier,
        item: UICandidateItem,
        support: ActionExecutionSupport,
        action: StorageAction
    ) -> String? {
        switch tier {
        case .protectedTier:
            return "This item is protected. AI Storage Manager cannot prove it is safe to move."
        case .verifyMore:
            return "More verification is required before this can enter a safe plan."
        case .verifiedButExecutorUnavailable:
            return "\(action.rawValue) is a verified opportunity, but the executor is not available in this version."
        case .requiresVendorRestoration:
            return "The vendor app is not installed. Restore vendor management before cleanup can be considered. This is not Ready Now."
        case .blocked:
            return item.reasonSummary
        case .preflightRequired:
            return "A fresh safety check is required. This is not guaranteed recovery."
        default:
            return support == .implemented ? nil : "Action is not executable in this version."
        }
    }

    private static func factExclusionHint(
        tier: OptimizationEligibilityTier,
        fact: OptimizationActionFact,
        support: ActionExecutionSupport
    ) -> String? {
        switch tier {
        case .protectedTier:
            return "This item is protected. AI Storage Manager cannot prove it is safe to move."
        case .verifyMore:
            return "More verification is required before this can enter a safe plan."
        case .verifiedButExecutorUnavailable:
            return "\(fact.action.rawValue) is a verified opportunity, but the executor is not available in this version."
        case .requiresVendorRestoration:
            return fact.explanation.isEmpty
                ? "Vendor app is absent. Restore vendor management first. Raw deletion is not offered."
                : fact.explanation
        case .blocked:
            return fact.blockedReasons.isEmpty ? (fact.explanation.isEmpty ? "This action is not currently eligible." : fact.explanation) : fact.blockedReasons.joined(separator: ", ")
        default:
            return support == .notImplemented ? "Action is not executable in this version." : nil
        }
    }
}
