import Foundation

/// P4.0 — Foundation research freeze.
/// RESEARCH COVERAGE ≠ ENTITY COVERAGE.
/// New vendor-specific UNKNOWN does NOT reopen architecture research.

public struct FoundationResearchStatus: Codable, Sendable, Equatable {
    public var status: String
    public var frozen: Bool
    public var completedAt: String
    public var representativeFamilies: [String]
    public var remainingVendorSpecificUnknowns: [String]
    public var reopenConditions: [String]
    public var nextWorkIsProductization: Bool

    public static let completeFrozen = FoundationResearchStatus(
        status: "COMPLETE",
        frozen: true,
        completedAt: "2026-09-05",
        representativeFamilies: [
            "REGENERABLE_BUILD_ARTIFACT",
            "REACQUIRABLE_VENDOR_ARTIFACT",
            "LIVE_APPLICATION_DATABASE",
            "RECOVERY_BACKUP",
            "MULTI_VERSION_VENDOR_TOOLCHAIN",
            "USER_ORIGINAL_CLOUD_SYNC",
            "MIXED_APP_SUPPORT",
            "VM_RUNTIME_STORAGE",
        ],
        remainingVendorSpecificUnknowns: [
            "Chrome undocumented profile DBs",
            "Claude exact image redownload contract",
            "Voice Memos recording-level remote currentness",
        ],
        reopenConditions: [
            "GENUINELY_NEW_STORAGE_ARCHETYPE",
            "GENUINELY_NEW_ACTION_SEMANTIC",
            "DEMONSTRATED_SAFETY_INVARIANT_FAILURE",
            "NEW_CLOUD_LOCAL_PROPAGATION_MODEL",
            "NEW_MUTATION_PRIMITIVE_NOT_REPRESENTABLE",
        ],
        nextWorkIsProductization: true
    )
}

public enum FoundationResearchFreeze {
    public static let isFrozen = true
    public static let status = FoundationResearchStatus.completeFrozen

    /// Large folders / other browsers / IDEs do NOT reopen research.
    public static func shouldReopenResearch(
        newStorageArchetype: Bool = false,
        newActionSemantic: Bool = false,
        safetyInvariantFailure: Bool = false,
        newPropagationModel: Bool = false,
        newMutationPrimitive: Bool = false,
        anotherLargeFolderExists: Bool = false,
        anotherBrowserExists: Bool = false,
        vendorTableUnknown: Bool = false
    ) -> Bool {
        _ = anotherLargeFolderExists
        _ = anotherBrowserExists
        _ = vendorTableUnknown
        return newStorageArchetype
            || newActionSemantic
            || safetyInvariantFailure
            || newPropagationModel
            || newMutationPrimitive
    }
}
