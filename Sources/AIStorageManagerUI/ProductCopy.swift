import Foundation
import AppServices

/// UI shell copy — presentation only. Values resolve through L10n.
enum ProductCopy {
    static var appTitle: String { "AI Storage Manager" }
    static var scanStorage: String { L10n.t("action.scanStorage") }
    static var scanning: String { L10n.t("action.scanning") }
    static var mappingYourMac: String { L10n.t("scan.mappingStorage") }
    static var understandingStorage: String { L10n.t("scan.understandingApps") }
    static var checkingSafeOptimize: String { L10n.t("scan.checkingSafety") }
    static var scanReady: String { L10n.t("scan.ready") }
    static var measuring: String { L10n.t("scan.deeper") }
    static var noMatchesYet: String { L10n.t("error.weDontKnowEnough") }
    static var checkingChanges: String { L10n.t("history.seeWhatChanged") }
    static var finishSafetyFirst: String { L10n.t("scan.checkingSafety") }
    static var buildingSafeOptions: String { L10n.t("scan.checkingSafety") }
    static var checkingSafety: String { L10n.t("scan.checkingSafety") }
    static var analysisStillRunning: String { L10n.t("scan.understandingApps") }
    static var mappingStorage: String { L10n.t("scan.mappingStorage") }
    static var scanStages: String { L10n.t("scan.stagesJoined") }

    static var diskTotal: String { L10n.t("disk.total") }
    static var diskUsed: String { L10n.t("disk.used") }
    static var diskFree: String { L10n.t("disk.free") }
    static var disksBreadcrumb: String { L10n.t("navigation.storage") }
    static var totalCapacity: String { L10n.t("disk.total") }
    static var usedCapacity: String { L10n.t("disk.used") }
    static var freeCapacity: String { L10n.t("disk.free") }
    static var verifiedRecovered: String { L10n.t("verification.recovered.title") }
    static var overviewTitle: String { L10n.t("navigation.storage") }
    static var exploreStorage: String { L10n.t("navigation.storage") }
    static var noScanTitle: String { L10n.t("overview.noScan.title") }
    static var noScanDescription: String { L10n.t("overview.noScan.description") }
    static var observedScope: String { L10n.t("disk.used") }
    static var uniqueClassified: String { L10n.t("navigation.storage") }
    static var scanScopeExplanation: String { L10n.t("overview.noScan.description") }
    static var unclassified: String { L10n.t("category.otherUnknown") }
    static var mappedScope: String { L10n.t("scan.mappingStorage") }
    static var folderScope: String { L10n.t("category.personalFiles") }
    static var itemScope: String { L10n.t("decision.info.title") }
    static var notScanned: String { L10n.t("overview.noScan.title") }
    /// v0.2 UX FIX 001 — coverage is a STATE ("some areas couldn't be read"),
    /// not progress ("scanning deeper…"). It persists after the scan stops, so
    /// it must not be phrased as something still happening.
    static var partialMap: String { L10n.t("scan.coverage.partial") }
    static var knownMappedStorage: String { L10n.t("scan.mappingStorage") }
    static var mappingUnavailable: String { L10n.t("error.partialScan") }
    static var storageChange: String { L10n.t("history.seeWhatChanged") }
    static var seeWhatChanged: String { L10n.t("history.seeWhatChanged") }
    static var storageHistoryStartsNow: String { L10n.t("history.empty") }
    static var runAnotherScanForChanges: String { L10n.t("history.seeWhatChanged") }
    static var storageHistoryUnavailable: String { L10n.t("error.partialScan") }
    static var sinceLastScan: String { L10n.t("history.seeWhatChanged") }
    static var largestChange: String { L10n.t("history.seeWhatChanged") }
    static var whatChanged: String { L10n.t("history.seeWhatChanged") }
    static var growing: String { L10n.t("history.seeWhatChanged") }
    static var shrinking: String { L10n.t("history.seeWhatChanged") }
    static var newItems: String { L10n.t("decision.info.title") }
    static var removedItems: String { L10n.t("decision.info.title") }
    static var categoryChanges: String { L10n.t("history.seeWhatChanged") }
    static var unexplainedChange: String { L10n.t("error.partialScan") }
    static var relatedVerifiedActions: String { L10n.t("verification.recovered.title") }
    static var noComparisonYet: String { L10n.t("history.noComparison") }

    static var permissionBenefitTitle: String { L10n.t("permission.fullDiskAccess.title") }
    static var permissionBenefitBody: String { L10n.t("permission.fullDiskAccess.description") }
    static var permissionDeniedSafeNote: String { L10n.t("permission.limitedVisibility.note") }

    static var storageByCategory: String { L10n.t("navigation.storage") }
    static var largestChildren: String { L10n.t("navigation.storage") }
    static var mapCenterTitle: String { L10n.t("navigation.storage") }
    static var mapCenterFootnote: String { L10n.t("verification.recovered.hint") }
    static var mapMode: String { L10n.t("navigation.storage") }
    static var largestItems: String { L10n.t("navigation.storage") }
    static var searchPlaceholder: String { L10n.t("common.searchPlaceholder") }
    static var clearSearch: String { L10n.t("common.clear") }
    static var whatIsThis: String { L10n.t("inspector.whatIsThis") }
    static var whyLarge: String { L10n.t("inspector.whyLarge") }
    static var doINeedIt: String { L10n.t("inspector.doINeedIt") }
    static var whyCantAct: String { L10n.t("inspector.whyCantAct") }
    static var revealInFinder: String { L10n.t("action.revealInFinder") }
    static var preview: String { L10n.t("action.preview") }
    static var futureAskStorageAI: String { L10n.t("common.firstRunPromise") }

    static var storageIntelligence: String { L10n.t("overview.atAGlance") }
    static var intelligenceSectionTitle: String { L10n.t("overview.atAGlance") }
    static var readyActions: String { L10n.t("decision.ready.title") }
    static var needsReview: String { L10n.t("decision.verifyMore.title") }
    static var protectedItems: String { L10n.t("decision.protected.title") }
    static var largestCategory: String { L10n.t("navigation.storage") }
    static var readyActionsHint: String { L10n.t("overview.readyHint") }
    static var needsReviewHint: String { L10n.t("overview.needsReviewHint") }
    static var protectedHint: String { L10n.t("overview.protectedHint") }
    static var potentiallyOptimizable: String { L10n.t("decision.verifyMore.title") }
    static var itemsReady: String { L10n.t("decision.ready.title") }
    static var needVerification: String { L10n.t("decision.verifyMore.title") }
    static var protectedLabel: String { L10n.t("decision.protected.title") }
    static var reviewRecommendations: String { L10n.t("action.reviewAndApprove") }

    static var noActionsReady: String { L10n.t("plan.noActionsReady") }
    static var needsVerificationSuffix: String { L10n.t("decision.verifyMore.title") }

    static var selectItemHint: String { L10n.t("inspector.selectHint") }
    static var detailPaneHint: String { L10n.t("inspector.selectHint") }
    static var mapAccessibilityHint: String { L10n.t("a11y.mapHint") }

    static var technicalDetails: String { L10n.t("settings.technicalDetails") }
    static var checkCurrentSafety: String { L10n.t("action.checkCurrentSafety") }
    static var reviewAndApprove: String { L10n.t("action.reviewAndApprove") }
    static var storageGoal: String { L10n.t("navigation.plan") }
    static var needMoreSpace: String { L10n.t("plan.needMoreSpace") }
    static var howMuchSpace: String { L10n.t("plan.howMuch") }
    static var buildSafePlan: String { L10n.t("action.buildSafePlan") }
    static var refreshPlan: String { L10n.t("action.refreshPlan") }
    static var free10GB: String { L10n.t("plan.free10GB") }
    static var free20GB: String { L10n.t("plan.free20GB") }
    static var customGoal: String { L10n.t("plan.custom") }
    static var yourPlan: String { L10n.t("plan.yourPlan") }
    static var readyNow: String { L10n.t("decision.ready.title") }
    static var verifiedOpportunities: String { L10n.t("decision.verifyMore.title") }
    static var needsVerification: String { L10n.t("decision.verifyMore.title") }
    static var notAvailableInThisVersion: String { L10n.t("plan.noActionsReady") }
    static var remainingGoal: String { L10n.t("plan.yourPlan") }
    static var currentSafePlan: String { L10n.t("plan.yourPlan") }
    static var moveToTrashPotential: String { L10n.t("plan.moveToTrashPotential") }
    static var diskRecoveryLater: String { L10n.t("plan.diskRecoveryLater") }
    static var noSafeExecutablePlan: String { L10n.t("plan.noActionsReady") }
    static var importantDataExcluded: String { L10n.t("plan.importantExcluded") }
    static var reviewItem: String { L10n.t("action.reviewAgain") }
    static var checkSafety: String { L10n.t("action.checkCurrentSafety") }
    static var removeFromPlan: String { L10n.t("common.clear") }
    static var whyNotChosen: String { L10n.t("inspector.whyCantAct") }
    static var notExecutable: String { L10n.t("plan.noActionsReady") }
    static var planStale: String { L10n.t("plan.stale") }
    static var futureOptimizationPlan: String { L10n.t("navigation.plan") }
    static var historyNav: String { L10n.t("navigation.history") }
    static var settingsNav: String { L10n.t("navigation.settings") }
    static var somethingChanged: String { L10n.t("verification.somethingChanged") }
    static var reviewAgain: String { L10n.t("action.reviewAgain") }
    static var recoveredPendingTrash: String { L10n.t("verification.recoveryPending.trash") }

    static var recommendations: String { L10n.t("list.recommendations") }
    static var recommendation: String { L10n.t("list.recommendation") }
    static var review: String { L10n.t("list.review") }
    static var needsReviewEmpty: String { L10n.t("list.needsReviewEmpty") }
    static var protectedEmpty: String { L10n.t("list.protectedEmpty") }
    static var recentActionsTitle: String { L10n.t("history.recentActions") }
    static var noActionsYet: String { L10n.t("history.noActionsYet") }
    static var unexplainedNotMappedGrowth: String { L10n.t("history.unexplainedNotMappedGrowth") }
    static var whyRemovable: String { L10n.t("detail.whyRemovable") }
    static var recommended: String { L10n.t("detail.recommended") }
    static var checkingCurrentSafety: String { L10n.t("detail.checkingSafety") }
    static var freshSafetyCheck: String { L10n.t("detail.freshSafetyCheck") }
    static var movingToTrash: String { L10n.t("detail.movingToTrash") }
    static var runSafetyCheckAgain: String { L10n.t("detail.runSafetyCheckAgain") }
    static var openFullReview: String { L10n.t("detail.openFullReview") }
    static var whatShouldIDo: String { L10n.t("detail.whatShouldIDo") }
    static var storageItem: String { L10n.t("detail.storageItem") }
    static var runSafetyCheck: String { L10n.t("action.runSafetyCheck") }
    static var moveToTrash: String { L10n.t("action.moveToTrash.title") }
    static var approveAction: String { L10n.t("approval.title") }
    static var actionMoveToTrash: String { L10n.t("approval.actionMoveToTrash") }
    static func expectedSize(_ label: String) -> String { L10n.t("approval.expectedSize", label) }
    static var whatWillHappen: String { L10n.t("approval.whatWillHappen") }
    static var diskRecovery: String { L10n.t("approval.diskRecovery") }
    static var cancel: String { L10n.t("common.cancel") }
    static var listView: String { L10n.t("map.listView") }
    static var mapListAlternativeA11y: String { L10n.t("a11y.mapListAlternative") }
    static var diskSummaryA11y: String { L10n.t("a11y.diskSummary") }
    static var goalLabel: String { L10n.t("plan.goalLabel") }
    static var technicalDebugTitle: String { L10n.t("debug.technicalTitle") }
    static var debugSearchPlaceholder: String { L10n.t("debug.searchPlaceholder") }
    static var safeActions: String { L10n.t("debug.safeActions") }

    static func scanStageLabel(_ stage: StorageScanStage) -> String {
        switch stage {
        case .idle: return scanReady
        case .scanningFiles: return L10n.t("scan.mappingStorage")
        case .hierarchyAvailable: return L10n.t("scan.mappingStorage")
        case .understandingStorage: return L10n.t("scan.understandingApps")
        case .checkingSafety: return L10n.t("scan.checkingSafety")
        case .complete: return scanReady
        case .failed: return L10n.t("scan.failed")
        }
    }

    static func verificationAreas(_ count: Int) -> String {
        L10n.t("plural.verificationAreas", count)
    }
}

enum AppSidebarSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case storageGoal
    case recentActions
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L10n.t("navigation.storage")
        case .storageGoal: return L10n.t("navigation.plan")
        case .recentActions: return L10n.t("navigation.history")
        case .settings: return L10n.t("navigation.settings")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.pie"
        case .storageGoal: return "target"
        case .recentActions: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}
