import Foundation
import SafetyCore

/// P4.0 — human presentation + product loop models.
/// No SafetyClass / ActionDecision logic lives here — presentation only.

public enum ProductLoopStage: String, Codable, Sendable, Equatable, CaseIterable {
    case see = "SEE"
    case understand = "UNDERSTAND"
    case decide = "DECIDE"
    case act = "ACT"
    case verify = "VERIFY"
}

public enum HumanRecommendation: String, Codable, Sendable, Equatable {
    case keep = "Keep"
    case probablyKeep = "Probably Keep"
    case canBeRecovered = "Can Be Recovered"
    case canBeRebuilt = "Can Be Rebuilt"
    case needsVerification = "Needs Verification"
    case protectedUserData = "Protected User Data"
    case managedByApp = "Managed by App"
}

public enum HumanPlanTier: String, Codable, Sendable, Equatable {
    case ready = "Ready"
    case needsYourApproval = "Needs Your Approval"
    case possibleAfterVerification = "Possible After Verification"
    case needsMoreInformation = "Needs More Information"
    case protected = "Protected"

    public static func fromInternal(_ tier: String) -> HumanPlanTier {
        switch tier.uppercased() {
        case "READY_NOW", "READY": return .ready
        case "APPROVAL_REQUIRED": return .needsYourApproval
        case "VERIFIED_FUTURE": return .possibleAfterVerification
        case "VERIFY_MORE": return .needsMoreInformation
        case "PROTECTED": return .protected
        default: return .needsMoreInformation
        }
    }
}

public enum ProductActionFlowPhase: String, Codable, Sendable, Equatable {
    case idle = "IDLE"
    case reviewing = "REVIEWING"
    case preflighting = "PREFLIGHTING"
    case needsReviewAgain = "NEEDS_REVIEW_AGAIN"
    case awaitingApproval = "AWAITING_APPROVAL"
    case executing = "EXECUTING"
    case verifying = "VERIFYING"
    case completed = "COMPLETED"
    case failedSafe = "FAILED_SAFE"
    case unknownResult = "UNKNOWN_RESULT"
}

public struct ProductActionFlowTransition: Codable, Sendable, Equatable {
    public var from: ProductActionFlowPhase
    public var to: ProductActionFlowPhase
    public var allowed: Bool
    public var reason: String?
}

public enum ProductActionFlowStateMachine {
    public static func canTransition(from: ProductActionFlowPhase, to: ProductActionFlowPhase) -> Bool {
        switch (from, to) {
        case (.idle, .reviewing): return true
        case (.reviewing, .preflighting): return true
        case (.preflighting, .awaitingApproval): return true
        case (.preflighting, .needsReviewAgain): return true
        case (.preflighting, .failedSafe): return true
        case (.needsReviewAgain, .reviewing): return true
        case (.needsReviewAgain, .preflighting): return true
        case (.awaitingApproval, .executing): return true
        case (.awaitingApproval, .needsReviewAgain): return true
        case (.executing, .verifying): return true
        case (.executing, .failedSafe): return true
        case (.verifying, .completed): return true
        case (.verifying, .unknownResult): return true
        case (.verifying, .failedSafe): return true
        case (.completed, .idle), (.failedSafe, .idle), (.unknownResult, .idle): return true
        case (_, .idle): return true
        default: return false
        }
    }

    /// UNKNOWN / incomplete verification must never present as success.
    public static func userVisibleSuccess(_ phase: ProductActionFlowPhase) -> Bool {
        phase == .completed
    }
}

/// Presentation-only model. Score/ranking must not authorize actions.
public struct StorageEntityPresentation: Codable, Sendable, Equatable {
    public var title: String
    public var subtitle: String
    public var semanticCategory: String
    public var sizeText: String

    public var whatItIs: String
    public var whyLarge: String
    public var whyItMatters: String

    public var recommendation: HumanRecommendation
    public var recommendationReason: String

    public var actionTitle: String?
    public var actionAvailability: String
    public var actionBlockReason: String?

    public var recentChangeSummary: String?
    public var confidencePresentation: String

    public var actionableBytes: Int64
    public var potentialBytes: Int64
    public var verifiedRecoveryBytes: Int64

    public var entityID: String
    public var technicalPath: String?
}

public enum StorageProductPresentationBuilder {
    public static let verifiedCompletedRecoveryTotal: Int64 =
        VerifiedActionResultBuilder.completedVerifiedRecoveryTotal()

    public static func humanActionTitle(for action: StorageAction?) -> String {
        guard let action else { return "Keep" }
        switch action {
        case .keep: return "Keep"
        case .moveToTrash: return "Move to Trash"
        case .vendorNativeCleanup: return "Clean with Vendor"
        case .removeLocalDownload: return "Remove Local Copy"
        case .moveToICloud: return "Archive / Move Safely"
        }
    }

    public static func recommendation(
        decisionAction: StorageAction?,
        safetyClass: SafetyClass?,
        isProtectedUserOriginal: Bool,
        isActiveRuntime: Bool,
        needsVerification: Bool = false
    ) -> HumanRecommendation {
        if isProtectedUserOriginal { return .protectedUserData }
        if isActiveRuntime { return .managedByApp }
        if needsVerification { return .needsVerification }
        switch decisionAction {
        case .some(.moveToTrash), .some(.vendorNativeCleanup):
            return .canBeRecovered
        case .some(.removeLocalDownload):
            return .canBeRecovered
        case .some(.moveToICloud):
            return .canBeRebuilt
        case .some(.keep), .none:
            if safetyClass == .red { return .keep }
            if safetyClass == .yellow { return .probablyKeep }
            return .keep
        }
    }

    /// Ranking/score never enables an action.
    public static func scoreCanAuthorizeAction(_ score: Double) -> Bool {
        _ = score
        return false
    }

    public static func contractGateHumanReason(_ status: String) -> String {
        switch status.uppercased() {
        case "STORE_MISMATCH":
            return "The cleanup command manages a different store than this data."
        case "TARGET_MISMATCH":
            return "The cleanup target doesn't match this exact item."
        case "BLAST_RADIUS_UNBOUNDED":
            return "The operation's impact isn't narrowly bounded yet."
        case "CONTRACT_UNREACHABLE":
            return "A verified vendor cleanup path isn't available for this item."
        case "SEMANTIC_CLASS_MISMATCH":
            return "This data isn't the kind that cleanup operation is meant for."
        default:
            return "This action isn't available with the current verified contract."
        }
    }

    public static func moveToTrashRecoverySemantics() -> String {
        "This moves the item to Trash. Disk space is generally not recovered until Trash is emptied."
    }

    public static func fakeRecoverableBytesAllowed() -> Bool { false }
}

/// Guards async inspector updates against stale selection.
public struct PresentationSelectionBinding: Codable, Sendable, Equatable {
    public var selectedEntityID: String
    public var requestID: UInt64

    public init(selectedEntityID: String, requestID: UInt64) {
        self.selectedEntityID = selectedEntityID
        self.requestID = requestID
    }

    public func accepts(responseEntityID: String, responseRequestID: UInt64) -> Bool {
        responseEntityID == selectedEntityID && responseRequestID == requestID
    }
}

public struct ProductCoreJourney: Codable, Sendable, Equatable {
    public var id: String
    public var entityLabel: String
    public var see: String
    public var understand: String
    public var decide: String
    public var actAvailability: String
    public var verify: String
    public var protectedReason: String?
    public var actionableBytes: Int64
    public var fixtureSource: String
}

public enum ProductCoreJourneys {
    public static let all: [ProductCoreJourney] = [
        ProductCoreJourney(
            id: "deriveddata",
            entityLabel: "Xcode Build Data",
            see: "Large developer build folder on this Mac",
            understand: "Generated Xcode build output that can be recreated",
            decide: "Safe Move to Trash when inactive and proof-complete",
            actAvailability: "Available when Fresh Preflight approves",
            verify: "Moved to Trash — recovered storage pending Empty Trash",
            protectedReason: nil,
            actionableBytes: 0, // fixture journey; live bytes vary
            fixtureSource: "P2 DerivedData MOVE_TO_TRASH pattern"
        ),
        ProductCoreJourney(
            id: "ollama",
            entityLabel: "Ollama model",
            see: "Downloaded AI model storage",
            understand: "Vendor-managed model that can be downloaded again",
            decide: "Clean with Ollama (exact model)",
            actAvailability: "Historical verified — not a current live candidate",
            verify: "2.497GB verified recovered",
            protectedReason: nil,
            actionableBytes: 0,
            fixtureSource: "P3.2A.5 VerifiedActionResult"
        ),
        ProductCoreJourney(
            id: "huggingface",
            entityLabel: "Hugging Face snapshot",
            see: "Local model revision cache",
            understand: "Exact Hub revision stored locally",
            decide: "Clean with Hugging Face (exact revision)",
            actAvailability: "Historical verified — not a current live candidate",
            verify: "3.083GB verified recovered",
            protectedReason: nil,
            actionableBytes: 0,
            fixtureSource: "P3.2B.3 VerifiedActionResult"
        ),
        ProductCoreJourney(
            id: "cursor",
            entityLabel: "Cursor AI & conversation state",
            see: "Large Cursor application database",
            understand: "Live AI/agent state used to restore your work",
            decide: "Keep",
            actAvailability: "No safe cleanup action",
            verify: "N/A — no mutation",
            protectedReason: "Valuable live application state / recovery backup / current toolchain store",
            actionableBytes: 0,
            fixtureSource: "P3.3 closure"
        ),
        ProductCoreJourney(
            id: "voicememos",
            entityLabel: "Your recordings",
            see: "~14GB Voice Memos storage",
            understand: "Original audio recordings with CloudKit sync",
            decide: "Keep",
            actAvailability: "No verified Apple local-only offload contract",
            verify: "N/A — no mutation",
            protectedReason: "User originals; permanent delete can sync across Apple devices",
            actionableBytes: 0,
            fixtureSource: "P3.4B"
        ),
        ProductCoreJourney(
            id: "chrome",
            entityLabel: "Chrome browser data",
            see: "Mixed Application Support + disk cache",
            understand: "Website/app state plus verified HTTP/code cache",
            decide: "Protect site state; no broad cleanup",
            actAvailability: "No aligned Chrome executor",
            verify: "N/A — no mutation",
            protectedReason: "IndexedDB / Local Storage / Service Worker are not generic cache",
            actionableBytes: 0,
            fixtureSource: "P3.5"
        ),
        ProductCoreJourney(
            id: "claude",
            entityLabel: "Claude runtime",
            see: "~12GB Claude App Support including VM",
            understand: "Base runtime filesystem plus mutable session data",
            decide: "Keep while active",
            actAvailability: "No executor; active runtime protected",
            verify: "N/A — no mutation",
            protectedReason: "rootfs ≠ sessiondata; active Virtualization/Claude runtime",
            actionableBytes: 0,
            fixtureSource: "P3.5"
        ),
    ]
}

public enum ProductizationInvariants {
    public static let primaryLoop: [ProductLoopStage] = [.see, .understand, .decide, .act, .verify]
    public static let researchFrozen = true
    public static let decisionSourceCanonicalOnly = true
    public static let noNewExecutor = true
    public static let noRealMutationInP40 = true
    public static let secondCrawlerAdded = false
    public static let existingExecutors: [String] = [
        "MOVE_TO_TRASH",
        "OLLAMA_MODEL_VENDOR_NATIVE_CLEANUP",
        "HF_SNAPSHOT_VENDOR_NATIVE_CLEANUP",
    ]
    public static let unknownAuthorizationCount = 0
    public static let contractGateBypassCount = 0
    public static let approvalBypassCount = 0
    public static let unverifiedRecoveryPresentationCount = 0
}
