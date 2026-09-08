import Foundation

/// P5.3 — translation coverage + locale Safety invariant helpers.
public enum LocalizationCoverageAudit {
    public static let shippingLocaleIDs: [String] = [
        "en", "ja", "zh-Hans", "zh-Hant", "ko", "es", "fr", "de", "pt-BR",
    ]

    public static func fullReport() -> LocalizationCoverageReport {
        let per = shippingLocaleIDs.map { L10n.coverage(for: $0) }
        let missing = per.map(\.missingKeys).reduce(0, +)
        return LocalizationCoverageReport(
            supportedLocales: shippingLocaleIDs,
            defaultBehavior: "SYSTEM",
            languageOverrideAvailable: true,
            totalProductionKeys: L10n.productionKeys.count,
            perLocale: per,
            safetySemanticChanges: 0,
            missingKeyCount: missing,
            rawKeyVisibleCount: per.map(\.missingKeys).reduce(0, +),
            localizationReleaseBlockers: missing == 0 ? [] : ["missing_production_keys"]
        )
    }

    /// Critical Safety copy keys that must exist in every locale.
    public static let criticalSafetyKeys: [String] = [
        "decision.keep.title",
        "decision.protected.title",
        "decision.verifyMore.title",
        "decision.ready.title",
        "decision.needsApproval.title",
        "action.moveToTrash.title",
        "verification.recovered.title",
        "verification.recoveryPending.trash",
        "verification.trashStillOccupies",
        "entity.voiceMemos.what",
        "entity.voiceMemos.block",
        "entity.cursorState.keepReason",
        "entity.chrome.block",
        "entity.claude.keepReason",
        "permission.fullDiskAccess.description",
        "error.weDontKnowEnough",
    ]
}

public struct LocalizationCoverageReport: Codable, Sendable, Equatable {
    public var supportedLocales: [String]
    public var defaultBehavior: String
    public var languageOverrideAvailable: Bool
    public var totalProductionKeys: Int
    public var perLocale: [LocalizationLocaleCoverage]
    public var safetySemanticChanges: Int
    public var missingKeyCount: Int
    public var rawKeyVisibleCount: Int
    public var localizationReleaseBlockers: [String]
}
