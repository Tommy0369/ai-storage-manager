import Foundation
import SafetyCore

/// P4.1 — centralized consumer-facing copy.
/// Presentation only. Does not authorize actions.

public struct ConsumerEntityCopy: Codable, Sendable, Equatable {
    public var title: String
    public var whatItIs: String
    public var whyLarge: String
    public var recommendation: String
    public var recommendationReason: String
    public var actionBlockReason: String?
    public var technicalEnumLeak: Bool
}

public enum ConsumerPresentationCopy {
    public static let productNorthStar =
        "DaisyDisk-class visual storage exploration + AI Storage Decision Intelligence"

    public static var firstRunPromise: String { L10n.t("common.firstRunPromise") }

    public static var verifiedRecoveredHint: String { L10n.t("verification.recovered.hint") }

    public static var unknownHuman: String { L10n.t("decision.unknown.human") }

    public static var scanningStages: [String] {
        [
            L10n.t("scan.mappingStorage"),
            L10n.t("scan.understandingApps"),
            L10n.t("scan.checkingSafety"),
            L10n.t("scan.ready"),
        ]
    }

    public static func representativeSnapshots() -> [ConsumerEntityCopy] {
        [
            ConsumerEntityCopy(
                title: L10n.t("entity.xcodeBuildData.title"),
                whatItIs: L10n.t("entity.xcodeBuildData.what"),
                whyLarge: L10n.t("entity.xcodeBuildData.what"),
                recommendation: L10n.t("action.moveToTrash.title"),
                recommendationReason: L10n.t("plan.diskRecoveryLater"),
                actionBlockReason: nil,
                technicalEnumLeak: false
            ),
            ConsumerEntityCopy(
                title: L10n.t("entity.ollamaModel.title"),
                whatItIs: L10n.t("entity.ollamaModel.what"),
                whyLarge: L10n.t("entity.ollamaModel.what"),
                recommendation: L10n.t("action.vendorCleanup.title", "Ollama"),
                recommendationReason: L10n.t("entity.ollamaModel.what"),
                actionBlockReason: nil,
                technicalEnumLeak: false
            ),
            ConsumerEntityCopy(
                title: L10n.t("entity.hfSnapshot.title"),
                whatItIs: L10n.t("entity.hfSnapshot.what"),
                whyLarge: L10n.t("entity.hfSnapshot.what"),
                recommendation: L10n.t("action.vendorCleanup.title", "Hugging Face"),
                recommendationReason: L10n.t("entity.hfSnapshot.what"),
                actionBlockReason: nil,
                technicalEnumLeak: false
            ),
            ConsumerEntityCopy(
                title: L10n.t("entity.cursorState.title"),
                whatItIs: L10n.t("entity.cursorState.what"),
                whyLarge: L10n.t("entity.cursorState.whyLarge"),
                recommendation: L10n.t("decision.keep.title"),
                recommendationReason: L10n.t("entity.cursorState.keepReason"),
                actionBlockReason: L10n.t("entity.cursorState.what"),
                technicalEnumLeak: false
            ),
            ConsumerEntityCopy(
                title: L10n.t("entity.cursorBackup.title"),
                whatItIs: L10n.t("entity.cursorBackup.keepReason"),
                whyLarge: L10n.t("entity.cursorState.whyLarge"),
                recommendation: L10n.t("decision.keep.title"),
                recommendationReason: L10n.t("entity.cursorBackup.keepReason"),
                actionBlockReason: L10n.t("entity.cursorBackup.block"),
                technicalEnumLeak: false
            ),
            ConsumerEntityCopy(
                title: L10n.t("entity.cursorAgentCLI.title"),
                whatItIs: L10n.t("entity.cursorState.what"),
                whyLarge: L10n.t("entity.cursorState.whyLarge"),
                recommendation: L10n.t("decision.keep.title"),
                recommendationReason: L10n.t("entity.cursorState.keepReason"),
                actionBlockReason: L10n.t("entity.cursorState.what"),
                technicalEnumLeak: false
            ),
            ConsumerEntityCopy(
                title: L10n.t("entity.voiceMemos.title"),
                whatItIs: L10n.t("entity.voiceMemos.what"),
                whyLarge: L10n.t("entity.voiceMemos.whyLarge"),
                recommendation: L10n.t("decision.keep.title"),
                recommendationReason: L10n.t("entity.voiceMemos.keepReason"),
                actionBlockReason: L10n.t("entity.voiceMemos.block"),
                technicalEnumLeak: false
            ),
            ConsumerEntityCopy(
                title: L10n.t("entity.chrome.title"),
                whatItIs: L10n.t("entity.chrome.what"),
                whyLarge: L10n.t("entity.chrome.whyLarge"),
                recommendation: L10n.t("decision.keep.title"),
                recommendationReason: L10n.t("entity.chrome.keepReason"),
                actionBlockReason: L10n.t("entity.chrome.block"),
                technicalEnumLeak: false
            ),
            ConsumerEntityCopy(
                title: L10n.t("entity.claude.title"),
                whatItIs: L10n.t("entity.claude.what"),
                whyLarge: L10n.t("entity.claude.what"),
                recommendation: L10n.t("decision.keep.title"),
                recommendationReason: L10n.t("entity.claude.keepReason"),
                actionBlockReason: L10n.t("entity.claude.block"),
                technicalEnumLeak: false
            ),
        ]
    }

    public static func humanDecisionLabel(state: StoragePresentationState) -> String {
        switch state {
        case .readyToOptimize: return L10n.t("decision.ready.title")
        case .verificationNeeded: return L10n.t("decision.verifyMore.title")
        case .protected: return L10n.t("decision.protected.title")
        case .keep: return L10n.t("decision.keep.title")
        case .recoveryPending: return L10n.t("decision.recoveryPending.title")
        case .noRecommendation: return L10n.t("decision.noRecommendation.title")
        case .informational: return L10n.t("decision.info.title")
        }
    }

    public static func containsTechnicalEnumLeak(_ text: String) -> Bool {
        let needles = [
            "SafetyClass", "ActionDecision", "VENDOR_NATIVE", "SOT ", "USER_ORIGINAL",
            "RECOVERY_SOURCE", "MutationGate", "VerificationChain", "GREEN", "YELLOW", "RED",
            "STORE_MISMATCH", "BLAST_RADIUS",
        ]
        return needles.contains { text.contains($0) }
    }
}
