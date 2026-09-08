import XCTest
@testable import SafetyCore
@testable import AppServices

final class P40ProductizationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.setOverride(.english)
    }

    func testResearchFrozen() {
        XCTAssertTrue(FoundationResearchFreeze.isFrozen)
        XCTAssertEqual(FoundationResearchStatus.completeFrozen.status, "COMPLETE")
        XCTAssertTrue(FoundationResearchStatus.completeFrozen.frozen)
        XCTAssertTrue(FoundationResearchStatus.completeFrozen.nextWorkIsProductization)
        XCTAssertFalse(FoundationResearchFreeze.shouldReopenResearch(anotherLargeFolderExists: true))
        XCTAssertFalse(FoundationResearchFreeze.shouldReopenResearch(anotherBrowserExists: true))
        XCTAssertFalse(FoundationResearchFreeze.shouldReopenResearch(vendorTableUnknown: true))
        XCTAssertTrue(FoundationResearchFreeze.shouldReopenResearch(newStorageArchetype: true))
        XCTAssertTrue(FoundationResearchFreeze.shouldReopenResearch(safetyInvariantFailure: true))
    }

    func testPrimaryProductLoop() {
        XCTAssertEqual(
            ProductizationInvariants.primaryLoop.map(\.rawValue),
            ["SEE", "UNDERSTAND", "DECIDE", "ACT", "VERIFY"]
        )
    }

    func testPresentationTitlesForKeyEntities() {
        let cursor = EntityPresentationResolver.resolve(
            entityID: "cursor.globalStorage.state.vscdb",
            path: "/Users/x/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            domain: "AI Tools",
            subcategory: "Cursor"
        )
        XCTAssertEqual(cursor.title, "Cursor AI & conversation state")

        let backup = EntityPresentationResolver.resolve(
            entityID: "cursor.globalStorage.state.vscdb.backup",
            path: "/Users/x/Library/Application Support/Cursor/User/globalStorage/state.vscdb.backup",
            domain: "AI Tools",
            subcategory: "Cursor"
        )
        XCTAssertEqual(backup.title, "Cursor recovery backup")

        let voice = EntityPresentationResolver.resolve(
            entityID: "voicememo.recordings",
            path: "/Users/x/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings",
            domain: "macOS",
            subcategory: "VoiceMemos"
        )
        XCTAssertEqual(voice.title, "Your recordings")

        let chromeIDB = EntityPresentationResolver.resolve(
            entityID: "chrome.profile.profile_1.indexeddb",
            path: "/Users/x/Library/Application Support/Google/Chrome/Profile 1/IndexedDB",
            domain: "macOS",
            subcategory: "Chrome"
        )
        XCTAssertEqual(chromeIDB.title, "Website & app data")

        let claudeBase = EntityPresentationResolver.resolve(
            entityID: "claude.vm.bundle.claudevm.bundle.runtime",
            path: "/Users/x/Library/Application Support/Claude/vm_bundles/claudevm.bundle/rootfs.img",
            domain: "AI Tools",
            subcategory: "Claude"
        )
        XCTAssertEqual(claudeBase.title, "Claude runtime base")

        let claudeMutable = EntityPresentationResolver.resolve(
            entityID: "claude.vm.bundle.claudevm.bundle.writable",
            path: "/Users/x/Library/Application Support/Claude/vm_bundles/claudevm.bundle/sessiondata.img",
            domain: "AI Tools",
            subcategory: "Claude"
        )
        XCTAssertEqual(claudeMutable.title, "Claude session state")
    }

    func testNoFakeRecoverableBytesOnProtectedJourneys() {
        for journey in ProductCoreJourneys.all where journey.protectedReason != nil {
            XCTAssertEqual(journey.actionableBytes, 0)
        }
        XCTAssertFalse(StorageProductPresentationBuilder.fakeRecoverableBytesAllowed())
        XCTAssertEqual(
            StorageProductPresentationBuilder.verifiedCompletedRecoveryTotal,
            5_580_814_899
        )
    }

    func testScoreDoesNotAuthorize() {
        XCTAssertFalse(StorageProductPresentationBuilder.scoreCanAuthorizeAction(9999))
        XCTAssertFalse(StorageProductPresentationBuilder.scoreCanAuthorizeAction(0))
    }

    func testContractGateHumanCopy() {
        let reason = StorageProductPresentationBuilder.contractGateHumanReason("STORE_MISMATCH")
        XCTAssertFalse(reason.contains("STORE_MISMATCH"))
        XCTAssertTrue(reason.lowercased().contains("store"))
    }

    func testMoveToTrashPendingSemantics() {
        let copy = StorageProductPresentationBuilder.moveToTrashRecoverySemantics()
        XCTAssertTrue(copy.lowercased().contains("trash"))
        XCTAssertTrue(copy.lowercased().contains("emptied") || copy.lowercased().contains("empty"))
    }

    func testActionFlowStateMachine() {
        XCTAssertTrue(ProductActionFlowStateMachine.canTransition(from: .idle, to: .reviewing))
        XCTAssertTrue(ProductActionFlowStateMachine.canTransition(from: .preflighting, to: .needsReviewAgain))
        XCTAssertTrue(ProductActionFlowStateMachine.canTransition(from: .verifying, to: .completed))
        XCTAssertFalse(ProductActionFlowStateMachine.canTransition(from: .idle, to: .completed))
        XCTAssertFalse(ProductActionFlowStateMachine.userVisibleSuccess(.unknownResult))
        XCTAssertTrue(ProductActionFlowStateMachine.userVisibleSuccess(.completed))
    }

    func testAsyncSelectionBinding() {
        let binding = PresentationSelectionBinding(selectedEntityID: "a", requestID: 2)
        XCTAssertTrue(binding.accepts(responseEntityID: "a", responseRequestID: 2))
        XCTAssertFalse(binding.accepts(responseEntityID: "b", responseRequestID: 2))
        XCTAssertFalse(binding.accepts(responseEntityID: "a", responseRequestID: 1))
    }

    func testCoreJourneysCoverRequiredEntities() {
        let ids = Set(ProductCoreJourneys.all.map(\.id))
        for needed in ["deriveddata", "ollama", "huggingface", "cursor", "voicememos", "chrome", "claude"] {
            XCTAssertTrue(ids.contains(needed), "missing journey \(needed)")
        }
    }

    func testHumanPlanTier() {
        XCTAssertEqual(HumanPlanTier.fromInternal("READY_NOW"), .ready)
        XCTAssertEqual(HumanPlanTier.fromInternal("APPROVAL_REQUIRED"), .needsYourApproval)
        XCTAssertEqual(HumanPlanTier.fromInternal("PROTECTED"), .protected)
    }

    func testExecutorSetUnchangedAndNoMutationInP40() {
        XCTAssertEqual(ProductizationInvariants.existingExecutors.count, 3)
        XCTAssertTrue(ProductizationInvariants.noNewExecutor)
        XCTAssertTrue(ProductizationInvariants.noRealMutationInP40)
        XCTAssertFalse(ProductizationInvariants.secondCrawlerAdded)
        XCTAssertEqual(ProductizationInvariants.unknownAuthorizationCount, 0)
        XCTAssertEqual(ProductizationInvariants.contractGateBypassCount, 0)
        XCTAssertEqual(ProductizationInvariants.approvalBypassCount, 0)
        XCTAssertEqual(ProductizationInvariants.unverifiedRecoveryPresentationCount, 0)
    }

    func testLensesExist() {
        XCTAssertEqual(StorageMapLens.allCases.map(\.rawValue), ["STRUCTURE", "MEANING", "DECISION"])
    }
}
