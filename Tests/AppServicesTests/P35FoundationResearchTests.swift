import XCTest
@testable import SafetyCore

final class P35FoundationResearchTests: XCTestCase {

    // MARK: - Chrome

    func testChromeCacheNameAloneInsufficient() {
        XCTAssertTrue(ChromeStorageIntelligenceRules.cacheSubstringInsufficientForVerified)
        XCTAssertNil(ChromeStorageIntelligenceRules.classifyFromPathNameAlone("Cache"))
        XCTAssertNil(ChromeStorageIntelligenceRules.classifyFromPathNameAlone("SomeCacheDir"))
    }

    func testChromeIndexedDBProtectedNotCache() {
        XCTAssertTrue(ChromeStorageIntelligenceRules.indexedDBProtectedByDefault)
        XCTAssertTrue(ChromeStorageIntelligenceRules.siteStorageIsNotCache)
        XCTAssertTrue(ChromeStorageIntelligenceRules.isProtectedSiteOrUserState(.indexedDB))
        XCTAssertFalse(ChromeStorageIntelligenceRules.verifiedCacheClasses.contains(.indexedDB))
        XCTAssertTrue(ChromeStorageIntelligenceRules.cacheStorageIsSiteStateNotHTTPCache)
        XCTAssertTrue(ChromeStorageIntelligenceRules.isProtectedSiteOrUserState(.cacheStorage))
    }

    func testChromeClearDataBlastRadiusNotGenericCacheAuth() {
        XCTAssertTrue(ChromeStorageIntelligenceRules.clearBrowsingDataIsBlastRadiusAction)
        XCTAssertTrue(ChromeStorageIntelligenceRules.clearBrowsingDataBlastRadiusKnown())
        XCTAssertTrue(ChromeStorageIntelligenceRules.vendorClearDataContractFoundForResearch())
        XCTAssertFalse(ChromeStorageIntelligenceRules.vendorClearDataContractAlignedForAction())
        XCTAssertTrue(ChromeStorageIntelligenceRules.cacheVerifiedNotAutomaticallyExecutable)
        let potential = ChromeStorageIntelligenceRules.potentialFutureRecoveryBytes(
            verifiedCacheBytes: 4_000_000_000,
            vendorClearDataContractAligned: false,
            blastRadiusBound: true,
            exactDataClassSelected: true,
            currentExecutable: false
        )
        XCTAssertEqual(potential, 0)
    }

    func testChromeEntireProfileNeverGenericCleanup() {
        XCTAssertTrue(ChromeStorageIntelligenceRules.entireProfileNeverGenericCleanup)
        XCTAssertTrue(ChromeStorageIntelligenceRules.rawAppSupportDeleteBlocked)
        XCTAssertTrue(ChromeStorageIntelligenceRules.chromeSyncEnabledDoesNotProveAllRecoverable)
        XCTAssertTrue(ChromeStorageIntelligenceRules.noChromeExecutorInP35)
    }

    // MARK: - Claude

    func testClaudeVMFilenameInsufficient() {
        XCTAssertTrue(ClaudeStorageIntelligenceRules.vmFilenameInsufficientForRegenerability)
        XCTAssertEqual(ClaudeStorageIntelligenceRules.classifyRootfsAsBaseImage(), .vmBaseImage)
        XCTAssertEqual(ClaudeStorageIntelligenceRules.classifySessiondataAsOverlay(), .vmOverlay)
        XCTAssertTrue(ClaudeStorageIntelligenceRules.baseImageSeparateFromMutableOverlay)
    }

    func testClaudeActiveVMProtected() {
        XCTAssertTrue(ClaudeStorageIntelligenceRules.activeVMProtected)
        XCTAssertTrue(ClaudeStorageIntelligenceRules.noGenericUnusedVMDelete)
    }

    func testClaudeSnapshotAndResetDefaults() {
        XCTAssertTrue(ClaudeStorageIntelligenceRules.snapshotNotDisposableByDefault)
        XCTAssertTrue(ClaudeStorageIntelligenceRules.resetDestructiveUntilProven)
        XCTAssertTrue(ClaudeStorageIntelligenceRules.appReinstallAloneInsufficientForBaseReacquisition)
        let potential = ClaudeStorageIntelligenceRules.potentialFutureRecoveryBytes(
            baseImageBytes: 10_737_418_240,
            exactBaseReacquisitionVerified: false,
            mutableExcluded: true,
            vendorLifecycleAligned: false,
            runtimeInactiveVerified: false
        )
        XCTAssertEqual(potential, 0)
        XCTAssertTrue(ClaudeStorageIntelligenceRules.noClaudeExecutorInP35)
    }

    // MARK: - Research completion semantics

    func testKeepOutcomeCountsAsResearchComplete() {
        XCTAssertTrue(FoundationResearchInvariants.negativeProofCountsAsSuccess)
        let coverage = FoundationResearchAudits.coverageMatrix(chromeBytes: 1, claudeBytes: 1)
        let voice = coverage.rows.first { $0.family == FoundationResearchFamily.cloudSyncedUserData.rawValue }
        XCTAssertEqual(voice?.safetyResult, "KEEP_USER_ORIGINAL")
        XCTAssertTrue(voice?.researchCompleteForFamily == true)
        XCTAssertEqual(voice?.positiveOrNegativeProof, "NEGATIVE")
    }

    func testVendorSpecificUnknownDoesNotBlockGraduation() {
        let input = ResearchGraduationGate.p35LiveGraduationInput(
            chromeFamilyComplete: true,
            claudeFamilyComplete: true
        )
        XCTAssertTrue(input.currentResearchUnknownsVendorSpecificOnly)
        let result = ResearchGraduationGate.evaluate(input)
        XCTAssertEqual(result.graduationStatus, .complete)
        XCTAssertEqual(result.foundationResearchPercent, 100)
    }

    func testArchitecturalGapBlocksGraduation() {
        var input = ResearchGraduationGate.p35LiveGraduationInput(
            chromeFamilyComplete: true,
            claudeFamilyComplete: true
        )
        input.architecturalSafetyGaps = ["NEW_UNMODELED_PRIMITIVE"]
        input.globalSafetyPrimitivesComplete = false
        let result = ResearchGraduationGate.evaluate(input)
        XCTAssertEqual(result.graduationStatus, .blockedByArchitecturalGap)
        XCTAssertLessThan(result.foundationResearchPercent, 100)
    }

    func testFalseGreenBlocksGraduation() {
        var input = ResearchGraduationGate.p35LiveGraduationInput(
            chromeFamilyComplete: true,
            claudeFamilyComplete: true
        )
        input.falseGreenCount = 1
        let result = ResearchGraduationGate.evaluate(input)
        XCTAssertEqual(result.graduationStatus, .blockedBySafetyRegression)
    }

    func testUnrepresentedFamilyBlocksGraduation() {
        let input = ResearchGraduationGate.p35LiveGraduationInput(
            chromeFamilyComplete: false,
            claudeFamilyComplete: true
        )
        let result = ResearchGraduationGate.evaluate(input)
        XCTAssertEqual(result.graduationStatus, .blockedByUnrepresentedStorageFamily)
        XCTAssertTrue(result.vendorSpecificUnknowns.contains(MandatoryResearchRepresentative.mixedAppSupport.rawValue))
    }

    func testMandatoryFamiliesAllRepresentedWhenChromeClaudeComplete() {
        let coverage = FoundationResearchAudits.coverageMatrix(chromeBytes: 10, claudeBytes: 10)
        XCTAssertEqual(coverage.mandatoryTotal, 8)
        XCTAssertEqual(coverage.mandatoryCompleteCount, 8)
        XCTAssertTrue(coverage.representativeFamilyCoverageComplete)

        let chrome = coverage.rows.first { $0.family == FoundationResearchFamily.mixedBrowserApplicationSupport.rawValue }
        let claude = coverage.rows.first { $0.family == FoundationResearchFamily.virtualMachineOrRuntimeImage.rawValue }
        XCTAssertTrue(chrome?.researchCompleteForFamily == true)
        XCTAssertTrue(claude?.researchCompleteForFamily == true)
    }

    func testSafetyPrimitiveAuditHasNoArchitecturalGaps() {
        let rows = FoundationResearchAudits.safetyPrimitiveAudit()
        XCTAssertEqual(rows.count, ResearchGraduationGate.safetyPrimitiveIDs.count)
        XCTAssertTrue(rows.allSatisfy { $0.implemented && $0.tested && $0.remainingArchitecturalGap == nil })
    }

    func testActionFamilyAuditSemanticReadyWithoutNewExecutors() {
        let rows = FoundationResearchAudits.actionFamilyAudit()
        XCTAssertEqual(rows.count, ResearchGraduationGate.actionFamilyIDs.count)
        XCTAssertTrue(rows.allSatisfy(\.semanticModelReady))
        let executors = rows.filter(\.executorExists).map(\.action)
        XCTAssertEqual(Set(executors), Set(["MOVE_TO_TRASH", "VENDOR_NATIVE_CLEANUP"]))
        XCTAssertFalse(FoundationResearchInvariants.p35AddsExecutor)
        XCTAssertEqual(FoundationResearchInvariants.existingExecutors.count, 3)
    }

    func testGraduationCompleteRecommendsP40NotAnotherEntity() {
        let input = ResearchGraduationGate.p35LiveGraduationInput(
            chromeFamilyComplete: true,
            claudeFamilyComplete: true
        )
        let result = ResearchGraduationGate.evaluate(input)
        XCTAssertEqual(result.graduationStatus, .complete)
        XCTAssertEqual(result.foundationResearchPercent, 100)
        XCTAssertTrue(result.researchFreezeRecommended)
        XCTAssertEqual(result.recommendedNextPhase, FoundationResearchInvariants.recommendedNextIfComplete)
        XCTAssertFalse(result.recommendedNextPhase.lowercased().contains("safari"))
        XCTAssertFalse(result.recommendedNextPhase.lowercased().contains("docker"))
    }

    func testInvariants() {
        XCTAssertTrue(FoundationResearchInvariants.researchCoverageIsNotEntityCoverage)
        XCTAssertTrue(FoundationResearchInvariants.unknownNeverAuthorizes)
        XCTAssertTrue(FoundationResearchInvariants.noVendorCleanupWithoutAlignedContract)
        XCTAssertFalse(FoundationResearchInvariants.secondCrawlerAdded)
        XCTAssertFalse(FoundationResearchInvariants.p35AllowsRealMutation)
    }

    func testPercentExplicitFromGates() {
        var input = ResearchGraduationGate.p35LiveGraduationInput(
            chromeFamilyComplete: true,
            claudeFamilyComplete: true
        )
        XCTAssertEqual(ResearchGraduationGate.percent(input), 100)
        input.falseGreenCount = 1
        XCTAssertLessThan(ResearchGraduationGate.percent(input), 100)
    }
}
