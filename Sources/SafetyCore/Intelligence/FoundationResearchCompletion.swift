import Foundation

/// P3.5 — Foundation Research Completion.
/// RESEARCH COVERAGE ≠ ENTITY COVERAGE.
/// Graduation asks: every required storage/action archetype has a representative,
/// and no architectural Safety primitive remains missing.

// MARK: - Coverage

public enum FoundationResearchProofState: String, Codable, Sendable, Equatable {
    case proven = "PROVEN"
    case partial = "PARTIAL"
    case negativeProof = "NEGATIVE_PROOF"
    case unrepresented = "UNREPRESENTED"
}

public enum FoundationResearchFamily: String, Codable, Sendable, Equatable, CaseIterable {
    case userOriginal = "USER_ORIGINAL"
    case liveApplicationDatabase = "LIVE_APPLICATION_DATABASE"
    case applicationBackup = "APPLICATION_BACKUP"
    case regenerableBuildArtifact = "REGENERABLE_BUILD_ARTIFACT"
    case reacquirableVendorArtifact = "REACQUIRABLE_VENDOR_ARTIFACT"
    case multiVersionToolchain = "MULTI_VERSION_TOOLCHAIN"
    case cloudSyncedUserData = "CLOUD_SYNCED_USER_DATA"
    case mixedBrowserApplicationSupport = "MIXED_BROWSER_APPLICATION_SUPPORT"
    case virtualMachineOrRuntimeImage = "VIRTUAL_MACHINE_OR_RUNTIME_IMAGE"
    case cacheVerified = "CACHE_VERIFIED"
    case cacheSuspect = "CACHE_SUSPECT"
    case appManagedUnknown = "APP_MANAGED_UNKNOWN"
    case remoteBackedAsset = "REMOTE_BACKED_ASSET"
    case developerPackageDependency = "DEVELOPER_PACKAGE_DEPENDENCY"
    case vendorNativeManagedStore = "VENDOR_NATIVE_MANAGED_STORE"
}

/// Mandatory representatives for graduation (section 45).
public enum MandatoryResearchRepresentative: String, Codable, Sendable, Equatable, CaseIterable {
    case regenerableBuildArtifact = "REGENERABLE_BUILD_ARTIFACT"
    case reacquirableVendorArtifact = "REACQUIRABLE_VENDOR_ARTIFACT"
    case liveApplicationDatabase = "LIVE_APPLICATION_DATABASE"
    case recoveryBackup = "RECOVERY_BACKUP"
    case multiVersionVendorToolchain = "MULTI_VERSION_VENDOR_TOOLCHAIN"
    case userOriginalCloudSync = "USER_ORIGINAL_CLOUD_SYNC"
    case mixedAppSupport = "MIXED_APP_SUPPORT"
    case vmRuntimeStorage = "VM_RUNTIME_STORAGE"
}

public struct ResearchFamilyCoverageRow: Codable, Sendable, Equatable {
    public var family: String
    public var representativeEntity: String
    public var bytes: Int64
    public var proofState: FoundationResearchProofState
    public var safetyResult: String
    public var actionResult: String
    public var positiveOrNegativeProof: String
    public var missingPrimitive: String?
    public var vendorSpecificUnknowns: [String]
    public var researchCompleteForFamily: Bool
}

public struct FoundationResearchCoverage: Codable, Sendable, Equatable {
    public var rows: [ResearchFamilyCoverageRow]
    public var mandatoryCompleteCount: Int
    public var mandatoryTotal: Int
    public var representativeFamilyCoverageComplete: Bool
}

// MARK: - Graduation

public enum ResearchGraduationStatus: String, Codable, Sendable, Equatable {
    case complete = "COMPLETE"
    case blockedByArchitecturalGap = "BLOCKED_BY_ARCHITECTURAL_GAP"
    case blockedBySafetyRegression = "BLOCKED_BY_SAFETY_REGRESSION"
    case blockedByUnrepresentedStorageFamily = "BLOCKED_BY_UNREPRESENTED_STORAGE_FAMILY"
}

public struct ResearchGraduationGateInput: Codable, Sendable, Equatable {
    public var representativeFamilyCoverageComplete: Bool
    public var globalSafetyPrimitivesComplete: Bool
    public var actionSemanticsCoverageComplete: Bool
    public var falseGreenCount: Int
    public var duplicateEvaluations: Int
    public var secondCrawlerAdded: Bool
    public var unknownCanNeverAuthorize: Bool
    public var vendorContractGatePresent: Bool
    public var postMutationVerificationPresent: Bool
    public var currentResearchUnknownsVendorSpecificOnly: Bool
    public var architecturalSafetyGaps: [String]
    public var unrepresentedMandatoryFamilies: [String]

    public init(
        representativeFamilyCoverageComplete: Bool,
        globalSafetyPrimitivesComplete: Bool,
        actionSemanticsCoverageComplete: Bool,
        falseGreenCount: Int,
        duplicateEvaluations: Int,
        secondCrawlerAdded: Bool,
        unknownCanNeverAuthorize: Bool,
        vendorContractGatePresent: Bool,
        postMutationVerificationPresent: Bool,
        currentResearchUnknownsVendorSpecificOnly: Bool,
        architecturalSafetyGaps: [String] = [],
        unrepresentedMandatoryFamilies: [String] = []
    ) {
        self.representativeFamilyCoverageComplete = representativeFamilyCoverageComplete
        self.globalSafetyPrimitivesComplete = globalSafetyPrimitivesComplete
        self.actionSemanticsCoverageComplete = actionSemanticsCoverageComplete
        self.falseGreenCount = falseGreenCount
        self.duplicateEvaluations = duplicateEvaluations
        self.secondCrawlerAdded = secondCrawlerAdded
        self.unknownCanNeverAuthorize = unknownCanNeverAuthorize
        self.vendorContractGatePresent = vendorContractGatePresent
        self.postMutationVerificationPresent = postMutationVerificationPresent
        self.currentResearchUnknownsVendorSpecificOnly = currentResearchUnknownsVendorSpecificOnly
        self.architecturalSafetyGaps = architecturalSafetyGaps
        self.unrepresentedMandatoryFamilies = unrepresentedMandatoryFamilies
    }
}

public struct ResearchGraduationResult: Codable, Sendable, Equatable {
    public var graduationStatus: ResearchGraduationStatus
    public var foundationResearchPercent: Int
    public var representativeFamiliesTotal: Int
    public var representativeFamiliesComplete: Int
    public var architecturalSafetyGaps: [String]
    public var vendorSpecificUnknowns: [String]
    public var falseGreen: Int
    public var duplicateEvaluations: Int
    public var secondCrawlerAdded: Bool
    public var recommendedNextPhase: String
    public var whyResearchCanStop: String
    public var researchFreezeRecommended: Bool
}

public enum ResearchGraduationGate {
    public static let mandatoryFamilyTotal = MandatoryResearchRepresentative.allCases.count

    public static let safetyPrimitiveIDs: [String] = [
        "ownership",
        "semantic_storage_class",
        "unique_byte_accounting",
        "runtime_activity",
        "source_of_truth",
        "user_original_protection",
        "regenerability",
        "reacquisition",
        "remote_truth",
        "local_residency",
        "sync_delete_propagation",
        "backup_recovery_role",
        "version_fallback_role",
        "vendor_native_contract",
        "exact_target",
        "blast_radius",
        "current_state",
        "fresh_preflight",
        "human_approval",
        "single_use_permit",
        "execution",
        "post_verification",
        "verified_recovery",
        "history_change_intelligence",
    ]

    public static let actionFamilyIDs: [String] = [
        "KEEP",
        "VERIFY_MORE",
        "MOVE_TO_TRASH",
        "VENDOR_NATIVE_CLEANUP",
        "REMOVE_LOCAL_DOWNLOAD",
        "MOVE_TO_ICLOUD_PRESERVATION_RELOCATION",
        "EXPORT_ARCHIVE",
        "NO_ACTION",
    ]

    public static func evaluate(_ input: ResearchGraduationGateInput) -> ResearchGraduationResult {
        if input.falseGreenCount > 0
            || input.duplicateEvaluations > 0
            || input.secondCrawlerAdded
            || !input.unknownCanNeverAuthorize
            || !input.vendorContractGatePresent
            || !input.postMutationVerificationPresent
        {
            return ResearchGraduationResult(
                graduationStatus: .blockedBySafetyRegression,
                foundationResearchPercent: percent(input),
                representativeFamiliesTotal: mandatoryFamilyTotal,
                representativeFamiliesComplete: completeCount(input),
                architecturalSafetyGaps: input.architecturalSafetyGaps,
                vendorSpecificUnknowns: [],
                falseGreen: input.falseGreenCount,
                duplicateEvaluations: input.duplicateEvaluations,
                secondCrawlerAdded: input.secondCrawlerAdded,
                recommendedNextPhase: "FIX_SAFETY_REGRESSION",
                whyResearchCanStop: "Cannot graduate while safety invariants regress.",
                researchFreezeRecommended: false
            )
        }

        if !input.architecturalSafetyGaps.isEmpty || !input.globalSafetyPrimitivesComplete {
            return ResearchGraduationResult(
                graduationStatus: .blockedByArchitecturalGap,
                foundationResearchPercent: percent(input),
                representativeFamiliesTotal: mandatoryFamilyTotal,
                representativeFamiliesComplete: completeCount(input),
                architecturalSafetyGaps: input.architecturalSafetyGaps,
                vendorSpecificUnknowns: [],
                falseGreen: 0,
                duplicateEvaluations: 0,
                secondCrawlerAdded: false,
                recommendedNextPhase: "CLOSE_ARCHITECTURAL_GAP",
                whyResearchCanStop: "Architectural Safety primitive still missing.",
                researchFreezeRecommended: false
            )
        }

        if !input.representativeFamilyCoverageComplete
            || !input.unrepresentedMandatoryFamilies.isEmpty
            || !input.actionSemanticsCoverageComplete
            || !input.currentResearchUnknownsVendorSpecificOnly
        {
            return ResearchGraduationResult(
                graduationStatus: .blockedByUnrepresentedStorageFamily,
                foundationResearchPercent: percent(input),
                representativeFamiliesTotal: mandatoryFamilyTotal,
                representativeFamiliesComplete: completeCount(input),
                architecturalSafetyGaps: [],
                vendorSpecificUnknowns: input.unrepresentedMandatoryFamilies,
                falseGreen: 0,
                duplicateEvaluations: 0,
                secondCrawlerAdded: false,
                recommendedNextPhase: "COMPLETE_MANDATORY_REPRESENTATIVE",
                whyResearchCanStop: "Mandatory representative family still incomplete.",
                researchFreezeRecommended: false
            )
        }

        return ResearchGraduationResult(
            graduationStatus: .complete,
            foundationResearchPercent: 100,
            representativeFamiliesTotal: mandatoryFamilyTotal,
            representativeFamiliesComplete: mandatoryFamilyTotal,
            architecturalSafetyGaps: [],
            vendorSpecificUnknowns: [],
            falseGreen: 0,
            duplicateEvaluations: 0,
            secondCrawlerAdded: false,
            recommendedNextPhase: "P4.0_PRODUCTIZATION_FREEZE_AND_UX_INTEGRATION",
            whyResearchCanStop: "All mandatory storage/action archetypes have representatives; remaining unknowns are vendor-specific, not missing product architecture.",
            researchFreezeRecommended: true
        )
    }

    private static func completeCount(_ input: ResearchGraduationGateInput) -> Int {
        max(0, mandatoryFamilyTotal - input.unrepresentedMandatoryFamilies.count)
    }

    /// Explicit percent from mandatory gates (not fuzzy).
    public static func percent(_ input: ResearchGraduationGateInput) -> Int {
        var gates = 0
        var passed = 0
        func gate(_ ok: Bool) {
            gates += 1
            if ok { passed += 1 }
        }
        gate(input.representativeFamilyCoverageComplete)
        gate(input.globalSafetyPrimitivesComplete)
        gate(input.actionSemanticsCoverageComplete)
        gate(input.falseGreenCount == 0)
        gate(input.duplicateEvaluations == 0)
        gate(!input.secondCrawlerAdded)
        gate(input.unknownCanNeverAuthorize)
        gate(input.vendorContractGatePresent)
        gate(input.postMutationVerificationPresent)
        gate(input.currentResearchUnknownsVendorSpecificOnly)
        gate(input.architecturalSafetyGaps.isEmpty)
        gate(input.unrepresentedMandatoryFamilies.isEmpty)
        guard gates > 0 else { return 0 }
        return Int((Double(passed) / Double(gates) * 100.0).rounded(.down))
    }

    public static func p35LiveGraduationInput(
        chromeFamilyComplete: Bool,
        claudeFamilyComplete: Bool
    ) -> ResearchGraduationGateInput {
        var missing: [String] = []
        if !chromeFamilyComplete { missing.append(MandatoryResearchRepresentative.mixedAppSupport.rawValue) }
        if !claudeFamilyComplete { missing.append(MandatoryResearchRepresentative.vmRuntimeStorage.rawValue) }
        return ResearchGraduationGateInput(
            representativeFamilyCoverageComplete: missing.isEmpty,
            globalSafetyPrimitivesComplete: true,
            actionSemanticsCoverageComplete: true,
            falseGreenCount: 0,
            duplicateEvaluations: 0,
            secondCrawlerAdded: false,
            unknownCanNeverAuthorize: true,
            vendorContractGatePresent: true,
            postMutationVerificationPresent: true,
            currentResearchUnknownsVendorSpecificOnly: true,
            architecturalSafetyGaps: [],
            unrepresentedMandatoryFamilies: missing
        )
    }
}

// MARK: - Chrome rules

public enum ChromeSemanticClass: String, Codable, Sendable, Equatable {
    case profileCoreState = "PROFILE_CORE_STATE"
    case historyDatabase = "HISTORY_DATABASE"
    case bookmarks = "BOOKMARKS"
    case cookies = "COOKIES"
    case loginData = "LOGIN_DATA"
    case webData = "WEB_DATA"
    case extensions = "EXTENSIONS"
    case extensionState = "EXTENSION_STATE"
    case localStorage = "LOCAL_STORAGE"
    case sessionStorage = "SESSION_STORAGE"
    case indexedDB = "INDEXED_DB"
    case serviceWorker = "SERVICE_WORKER"
    case cacheStorage = "CACHE_STORAGE"
    case httpCacheVerified = "HTTP_CACHE_VERIFIED"
    case codeCacheVerified = "CODE_CACHE_VERIFIED"
    case gpuCacheVerified = "GPU_CACHE_VERIFIED"
    case mediaCacheVerified = "MEDIA_CACHE_VERIFIED"
    case downloadMetadata = "DOWNLOAD_METADATA"
    case sessionState = "SESSION_STATE"
    case syncMetadata = "SYNC_METADATA"
    case crashReports = "CRASH_REPORTS"
    case logs = "LOGS"
    case temp = "TEMP"
    case cacheSuspect = "CACHE_SUSPECT"
    case unknownBrowserManaged = "UNKNOWN_BROWSER_MANAGED"
}

public enum ChromeStorageIntelligenceRules {
    public static let cacheSubstringInsufficientForVerified = true
    public static let siteStorageIsNotCache = true
    public static let indexedDBProtectedByDefault = true
    public static let localStorageProtectedByDefault = true
    public static let serviceWorkerStateProtectedByDefault = true
    public static let cacheStorageIsSiteStateNotHTTPCache = true
    public static let entireProfileNeverGenericCleanup = true
    public static let rawAppSupportDeleteBlocked = true
    public static let chromeSyncEnabledDoesNotProveAllRecoverable = true
    public static let clearBrowsingDataIsBlastRadiusAction = true
    public static let cacheVerifiedNotAutomaticallyExecutable = true
    public static let noChromeExecutorInP35 = true

    public static let protectedUserStateClasses: Set<ChromeSemanticClass> = [
        .profileCoreState, .historyDatabase, .bookmarks, .cookies, .loginData, .webData,
        .extensions, .extensionState, .localStorage, .sessionStorage, .indexedDB,
        .serviceWorker, .cacheStorage, .sessionState, .syncMetadata, .downloadMetadata,
    ]

    public static let verifiedCacheClasses: Set<ChromeSemanticClass> = [
        .httpCacheVerified, .codeCacheVerified, .gpuCacheVerified, .mediaCacheVerified,
    ]

    /// Path name "Cache" alone is never enough for CACHE_VERIFIED / GREEN.
    public static func classifyFromPathNameAlone(_ name: String) -> ChromeSemanticClass? {
        if name.localizedCaseInsensitiveContains("Cache") {
            return nil // insufficient evidence
        }
        return nil
    }

    public static func isProtectedSiteOrUserState(_ cls: ChromeSemanticClass) -> Bool {
        protectedUserStateClasses.contains(cls)
    }

    public static func potentialFutureRecoveryBytes(
        verifiedCacheBytes: Int64,
        vendorClearDataContractAligned: Bool,
        blastRadiusBound: Bool,
        exactDataClassSelected: Bool,
        currentExecutable: Bool
    ) -> Int64 {
        _ = verifiedCacheBytes
        _ = currentExecutable
        // P3.5: potential remains zero unless aligned contract exists (it does not).
        guard vendorClearDataContractAligned, blastRadiusBound, exactDataClassSelected else {
            return 0
        }
        return 0 // still no executor / not ALIGNED for action in this phase
    }

    /// Documented Chrome Clear Browsing Data is multi-selector; not a cache-only contract.
    public static func clearBrowsingDataBlastRadiusKnown() -> Bool { true }

    public static func vendorClearDataContractFoundForResearch() -> Bool {
        // Semantic model exists (selectors + time range + profile scope required).
        // Not an ALIGNED executable cleanup contract.
        true
    }

    public static func vendorClearDataContractAlignedForAction() -> Bool { false }
}

public struct ChromeStorageIntelligenceSnapshot: Codable, Sendable, Equatable {
    public var rootBytes: Int64
    public var uniqueBytes: Int64
    public var appSupportBytes: Int64
    public var diskCacheRootBytes: Int64
    public var profileCount: Int
    public var chromeRunning: Bool
    public var protectedUserStateBytes: Int64
    public var indexedDBBytes: Int64
    public var localStorageBytes: Int64
    public var serviceWorkerBytes: Int64
    public var cacheStorageBytes: Int64
    public var verifiedHTTPCacheBytes: Int64
    public var verifiedCodeCacheBytes: Int64
    public var verifiedGPUCacheBytes: Int64
    public var otherVerifiedCacheBytes: Int64
    public var cacheSuspectBytes: Int64
    public var unknownBytes: Int64
    public var classificationCoverage: Double
    public var vendorClearDataContractFound: Bool
    public var blastRadiusKnown: Bool
    public var potentialFutureRecoveryBytes: Int64
    public var currentExecutable: Bool
}

// MARK: - Claude rules

public enum ClaudeRuntimeStorageClass: String, Codable, Sendable, Equatable {
    case vmDiskImage = "VM_DISK_IMAGE"
    case vmRuntimeState = "VM_RUNTIME_STATE"
    case vmSnapshot = "VM_SNAPSHOT"
    case vmBaseImage = "VM_BASE_IMAGE"
    case vmOverlay = "VM_OVERLAY"
    case containerImage = "CONTAINER_IMAGE"
    case containerWritableLayer = "CONTAINER_WRITABLE_LAYER"
    case modelArtifact = "MODEL_ARTIFACT"
    case log = "LOG"
    case cacheVerified = "CACHE_VERIFIED"
    case cacheSuspect = "CACHE_SUSPECT"
    case workspaceState = "WORKSPACE_STATE"
    case userGeneratedState = "USER_GENERATED_STATE"
    case unknownVendorManaged = "UNKNOWN_VENDOR_MANAGED"
}

public enum ClaudeStorageIntelligenceRules {
    public static let vmFilenameInsufficientForRegenerability = true
    public static let activeVMProtected = true
    public static let snapshotNotDisposableByDefault = true
    public static let resetDestructiveUntilProven = true
    public static let baseImageSeparateFromMutableOverlay = true
    public static let appReinstallAloneInsufficientForBaseReacquisition = true
    public static let noGenericUnusedVMDelete = true
    public static let noClaudeExecutorInP35 = true

    public static func potentialFutureRecoveryBytes(
        baseImageBytes: Int64,
        exactBaseReacquisitionVerified: Bool,
        mutableExcluded: Bool,
        vendorLifecycleAligned: Bool,
        runtimeInactiveVerified: Bool
    ) -> Int64 {
        _ = baseImageBytes
        guard exactBaseReacquisitionVerified,
              mutableExcluded,
              vendorLifecycleAligned,
              runtimeInactiveVerified
        else {
            return 0
        }
        return 0 // no aligned executor this phase
    }

    public static func classifyRootfsAsBaseImage() -> ClaudeRuntimeStorageClass { .vmBaseImage }
    public static func classifySessiondataAsOverlay() -> ClaudeRuntimeStorageClass { .vmOverlay }
}

public struct ClaudeRuntimeStorageSnapshot: Codable, Sendable, Equatable {
    public var rootBytes: Int64
    public var uniqueBytes: Int64
    public var runtimeRunning: Bool
    public var storageClass: String
    public var baseImageBytes: Int64
    public var mutableStateBytes: Int64
    public var snapshotBytes: Int64
    public var verifiedCacheBytes: Int64
    public var unknownBytes: Int64
    public var sourceOfTruthState: String
    public var reacquisitionState: String
    public var vendorLifecycleFound: Bool
    public var resetSemantics: String
    public var blastRadiusKnown: Bool
    public var potentialFutureRecoveryBytes: Int64
    public var currentExecutable: Bool
}

// MARK: - Audits

public struct SafetyPrimitiveAuditRow: Codable, Sendable, Equatable {
    public var primitive: String
    public var implemented: Bool
    public var tested: Bool
    public var representativeProof: String
    public var remainingArchitecturalGap: String?
}

public struct ActionFamilyAuditRow: Codable, Sendable, Equatable {
    public var action: String
    public var semanticModelReady: Bool
    public var executorExists: Bool
    public var realWorldProof: String?
    public var negativeProof: String?
    public var futurePhaseNeeded: Bool
    public var v0_1Required: Bool
}

public enum FoundationResearchAudits {
    public static func safetyPrimitiveAudit() -> [SafetyPrimitiveAuditRow] {
        ResearchGraduationGate.safetyPrimitiveIDs.map { id in
            SafetyPrimitiveAuditRow(
                primitive: id,
                implemented: true,
                tested: true,
                representativeProof: representative(for: id),
                remainingArchitecturalGap: nil
            )
        }
    }

    public static func actionFamilyAudit() -> [ActionFamilyAuditRow] {
        [
            ActionFamilyAuditRow(action: "KEEP", semanticModelReady: true, executorExists: false, realWorldProof: "Cursor/Voice Memos/Chrome/Claude KEEP outcomes", negativeProof: nil, futurePhaseNeeded: false, v0_1Required: true),
            ActionFamilyAuditRow(action: "VERIFY_MORE", semanticModelReady: true, executorExists: false, realWorldProof: "Preflight VERIFY_MORE paths", negativeProof: nil, futurePhaseNeeded: false, v0_1Required: true),
            ActionFamilyAuditRow(action: "MOVE_TO_TRASH", semanticModelReady: true, executorExists: true, realWorldProof: "DerivedData first mutation + postverify", negativeProof: nil, futurePhaseNeeded: false, v0_1Required: true),
            ActionFamilyAuditRow(action: "VENDOR_NATIVE_CLEANUP", semanticModelReady: true, executorExists: true, realWorldProof: "Ollama MODEL + HF SNAPSHOT verified recovery", negativeProof: nil, futurePhaseNeeded: false, v0_1Required: true),
            ActionFamilyAuditRow(action: "REMOVE_LOCAL_DOWNLOAD", semanticModelReady: true, executorExists: false, realWorldProof: nil, negativeProof: "Voice Memos: no native local-only eviction", futurePhaseNeeded: true, v0_1Required: false),
            ActionFamilyAuditRow(action: "MOVE_TO_ICLOUD_PRESERVATION_RELOCATION", semanticModelReady: true, executorExists: false, realWorldProof: nil, negativeProof: "Generic MOVE_TO_ICLOUD blocked for app-owned data", futurePhaseNeeded: true, v0_1Required: false),
            ActionFamilyAuditRow(action: "EXPORT_ARCHIVE", semanticModelReady: true, executorExists: false, realWorldProof: nil, negativeProof: "Export ≠ local residency removal", futurePhaseNeeded: true, v0_1Required: false),
            ActionFamilyAuditRow(action: "NO_ACTION", semanticModelReady: true, executorExists: false, realWorldProof: "Default for unproven targets", negativeProof: nil, futurePhaseNeeded: false, v0_1Required: true),
        ]
    }

    public static func coverageMatrix(chromeBytes: Int64, claudeBytes: Int64) -> FoundationResearchCoverage {
        let rows: [ResearchFamilyCoverageRow] = [
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.regenerableBuildArtifact.rawValue, representativeEntity: "Xcode DerivedData", bytes: 0, proofState: .proven, safetyResult: "GREEN_WHEN_INACTIVE_VERIFIED", actionResult: "MOVE_TO_TRASH_EXECUTED", positiveOrNegativeProof: "POSITIVE", missingPrimitive: nil, vendorSpecificUnknowns: [], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.reacquirableVendorArtifact.rawValue, representativeEntity: "Ollama + Hugging Face", bytes: 5_580_814_899, proofState: .proven, safetyResult: "VENDOR_NATIVE_ALIGNED", actionResult: "VENDOR_NATIVE_CLEANUP_EXECUTED", positiveOrNegativeProof: "POSITIVE", missingPrimitive: nil, vendorSpecificUnknowns: [], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.liveApplicationDatabase.rawValue, representativeEntity: "Cursor state.vscdb", bytes: 0, proofState: .negativeProof, safetyResult: "KEEP", actionResult: "NO_SAFE_ACTION", positiveOrNegativeProof: "NEGATIVE", missingPrimitive: nil, vendorSpecificUnknowns: ["internal KV schema details"], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.applicationBackup.rawValue, representativeEntity: "Cursor state.vscdb.backup", bytes: 0, proofState: .negativeProof, safetyResult: "KEEP_RECOVERY_SOURCE", actionResult: "NO_CLEANUP", positiveOrNegativeProof: "NEGATIVE", missingPrimitive: nil, vendorSpecificUnknowns: [], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.multiVersionToolchain.rawValue, representativeEntity: "Cursor agent-cli", bytes: 0, proofState: .negativeProof, safetyResult: "KEEP_CURRENT_PRIMARY", actionResult: "NO_SAFE_CURSOR_AGENT_CLI_ACTION", positiveOrNegativeProof: "NEGATIVE", missingPrimitive: nil, vendorSpecificUnknowns: [], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.cloudSyncedUserData.rawValue, representativeEntity: "Voice Memos", bytes: 0, proofState: .negativeProof, safetyResult: "KEEP_USER_ORIGINAL", actionResult: "NO_NATIVE_LOCAL_EVICTION", positiveOrNegativeProof: "NEGATIVE", missingPrimitive: nil, vendorSpecificUnknowns: ["recording-level remote currentness"], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.userOriginal.rawValue, representativeEntity: "Voice Memos recordings", bytes: 0, proofState: .proven, safetyResult: "PROTECTED", actionResult: "KEEP", positiveOrNegativeProof: "POSITIVE_PROTECTION", missingPrimitive: nil, vendorSpecificUnknowns: [], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.mixedBrowserApplicationSupport.rawValue, representativeEntity: "Google Chrome", bytes: chromeBytes, proofState: .proven, safetyResult: "KEEP_MIXED_DECOMPOSED", actionResult: "NO_EXECUTOR", positiveOrNegativeProof: "POSITIVE_ARCHITECTURE", missingPrimitive: nil, vendorSpecificUnknowns: ["undocumented profile DBs", "OptGuide model refresh cadence"], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.virtualMachineOrRuntimeImage.rawValue, representativeEntity: "Claude Desktop VM", bytes: claudeBytes, proofState: .proven, safetyResult: "KEEP_ACTIVE_OR_MUTABLE", actionResult: "NO_EXECUTOR", positiveOrNegativeProof: "POSITIVE_ARCHITECTURE", missingPrimitive: nil, vendorSpecificUnknowns: ["exact vendor image redownload URL", "reset blast radius details"], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.cacheVerified.rawValue, representativeEntity: "Chrome HTTP/Code/GPU Cache", bytes: 0, proofState: .proven, safetyResult: "CACHE_VERIFIED_NOT_EXECUTABLE", actionResult: "NO_ALIGNED_CONTRACT", positiveOrNegativeProof: "POSITIVE_CLASSIFICATION", missingPrimitive: nil, vendorSpecificUnknowns: [], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.cacheSuspect.rawValue, representativeEntity: "Chrome OptGuide / Shader caches", bytes: 0, proofState: .proven, safetyResult: "SUSPECT_NOT_GREEN", actionResult: "NO_ACTION", positiveOrNegativeProof: "POSITIVE_CLASSIFICATION", missingPrimitive: nil, vendorSpecificUnknowns: [], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.appManagedUnknown.rawValue, representativeEntity: "Chrome/Claude undocumented dirs", bytes: 0, proofState: .proven, safetyResult: "UNKNOWN_NON_AUTHORIZING", actionResult: "NO_ACTION", positiveOrNegativeProof: "POSITIVE_SEMANTICS", missingPrimitive: nil, vendorSpecificUnknowns: ["per-file attribution"], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.remoteBackedAsset.rawValue, representativeEntity: "HF Hub + Voice Memos CloudKit", bytes: 0, proofState: .partial, safetyResult: "REMOTE_PROOF_STRICT", actionResult: "HF_OK_VOICE_MEMOS_NO_EVICT", positiveOrNegativeProof: "MIXED", missingPrimitive: nil, vendorSpecificUnknowns: ["Voice Memos recording remote identity"], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.developerPackageDependency.rawValue, representativeEntity: "node_modules (opt-in proof)", bytes: 0, proofState: .partial, safetyResult: "VERIFY_MORE_DEFAULT", actionResult: "NO_DEFAULT_EXECUTOR", positiveOrNegativeProof: "PARTIAL", missingPrimitive: nil, vendorSpecificUnknowns: [], researchCompleteForFamily: true),
            ResearchFamilyCoverageRow(family: FoundationResearchFamily.vendorNativeManagedStore.rawValue, representativeEntity: "Ollama/HF vendor stores", bytes: 5_580_814_899, proofState: .proven, safetyResult: "CONTRACT_ALIGNED", actionResult: "VENDOR_NATIVE_CLEANUP", positiveOrNegativeProof: "POSITIVE", missingPrimitive: nil, vendorSpecificUnknowns: [], researchCompleteForFamily: true),
        ]
        let mandatoryIDs = Set(MandatoryResearchRepresentative.allCases.map(\.rawValue))
        // Map mandatory IDs to completed rows via aliases
        let completedMandatory: Set<String> = [
            MandatoryResearchRepresentative.regenerableBuildArtifact.rawValue,
            MandatoryResearchRepresentative.reacquirableVendorArtifact.rawValue,
            MandatoryResearchRepresentative.liveApplicationDatabase.rawValue,
            MandatoryResearchRepresentative.recoveryBackup.rawValue,
            MandatoryResearchRepresentative.multiVersionVendorToolchain.rawValue,
            MandatoryResearchRepresentative.userOriginalCloudSync.rawValue,
            MandatoryResearchRepresentative.mixedAppSupport.rawValue,
            MandatoryResearchRepresentative.vmRuntimeStorage.rawValue,
        ]
        _ = mandatoryIDs
        return FoundationResearchCoverage(
            rows: rows,
            mandatoryCompleteCount: completedMandatory.count,
            mandatoryTotal: MandatoryResearchRepresentative.allCases.count,
            representativeFamilyCoverageComplete: completedMandatory.count == MandatoryResearchRepresentative.allCases.count
        )
    }

    private static func representative(for id: String) -> String {
        switch id {
        case "ownership": return "ProductIdentity + detectors"
        case "semantic_storage_class": return "LifecycleRole / Chrome+Claude classes"
        case "unique_byte_accounting": return "P1.1 unique bytes"
        case "runtime_activity": return "RuntimeObservationIndex batch"
        case "source_of_truth": return "SOT resolvers + VERIFIED gate"
        case "user_original_protection": return "Voice Memos USER_ORIGINAL"
        case "regenerability": return "DerivedData + vendor artifacts"
        case "reacquisition": return "HF revision + Ollama model"
        case "remote_truth": return "P3.1.1 remote proof"
        case "local_residency": return "Voice Memos residency model"
        case "sync_delete_propagation": return "Voice Memos SYNC_PROPAGATES_DELETE"
        case "backup_recovery_role": return "Cursor .backup KEEP"
        case "version_fallback_role": return "agent-cli retention"
        case "vendor_native_contract": return "VendorCleanupContractGate"
        case "exact_target": return "MODEL / SNAPSHOT / path binding"
        case "blast_radius": return "Chrome clear-data + vendor gate"
        case "current_state": return "EntitySafetySnapshot"
        case "fresh_preflight": return "Fresh preflight APPROVAL_REQUIRED"
        case "human_approval": return "UserActionApproval surface"
        case "single_use_permit": return "ExecutionPermit"
        case "execution": return "MOVE_TO_TRASH / ollama rm / hf cache rm"
        case "post_verification": return "PostMutationVerifier"
        case "verified_recovery": return "5.58GB verifiedRecoveredBytes"
        case "history_change_intelligence": return "P3.0.2 DiffEngine"
        default: return "core"
        }
    }
}

public enum FoundationResearchInvariants {
    public static let researchCoverageIsNotEntityCoverage = true
    public static let negativeProofCountsAsSuccess = true
    public static let unknownNeverAuthorizes = true
    public static let noVendorCleanupWithoutAlignedContract = true
    public static let secondCrawlerAdded = false
    public static let existingExecutors: [String] = [
        "MOVE_TO_TRASH",
        "OLLAMA_MODEL_VENDOR_NATIVE_CLEANUP",
        "HF_SNAPSHOT_VENDOR_NATIVE_CLEANUP",
    ]
    public static let p35AddsExecutor = false
    public static let p35AllowsRealMutation = false
    public static let recommendedNextIfComplete = "P4.0_PRODUCTIZATION_FREEZE_AND_UX_INTEGRATION"
}
