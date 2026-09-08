import XCTest
@testable import SafetyCore
@testable import AppServices

final class P41ConsumerUXPolishTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.setOverride(.english)
    }

    func testResearchStillFrozen() {
        XCTAssertTrue(FoundationResearchFreeze.isFrozen)
        XCTAssertFalse(FoundationResearchFreeze.shouldReopenResearch(anotherLargeFolderExists: true))
    }

    func testConsumerCopyHasNoEnumLeaks() {
        for snap in ConsumerPresentationCopy.representativeSnapshots() {
            XCTAssertFalse(snap.technicalEnumLeak)
            XCTAssertFalse(ConsumerPresentationCopy.containsTechnicalEnumLeak(snap.title))
            XCTAssertFalse(ConsumerPresentationCopy.containsTechnicalEnumLeak(snap.whatItIs))
            XCTAssertFalse(ConsumerPresentationCopy.containsTechnicalEnumLeak(snap.whyLarge))
            XCTAssertFalse(ConsumerPresentationCopy.containsTechnicalEnumLeak(snap.recommendation))
            XCTAssertFalse(ConsumerPresentationCopy.containsTechnicalEnumLeak(snap.recommendationReason))
            if let block = snap.actionBlockReason {
                XCTAssertFalse(ConsumerPresentationCopy.containsTechnicalEnumLeak(block))
            }
        }
    }

    func testRepresentativeTitlesMatchProductVoice() {
        let byTitle = Dictionary(uniqueKeysWithValues: ConsumerPresentationCopy.representativeSnapshots().map { ($0.title, $0) })
        XCTAssertEqual(byTitle["Your recordings"]?.recommendation, "Keep")
        XCTAssertTrue(byTitle["Your recordings"]?.actionBlockReason?.lowercased().contains("local") == true)
        XCTAssertEqual(byTitle["Cursor AI & conversation state"]?.recommendation, "Keep")
        XCTAssertTrue(byTitle["Chrome browser data"]?.whyLarge.lowercased().contains("website") == true
                      || byTitle["Chrome browser data"]?.whyLarge.lowercased().contains("cache") == true)
        XCTAssertTrue(byTitle["Claude runtime"]?.whyLarge.lowercased().contains("runtime") == true)
        XCTAssertTrue(byTitle["Xcode Build Data"]?.whatItIs.lowercased().contains("build") == true)
    }

    func testHumanDecisionLabelsNotRawSafetyColors() {
        XCTAssertEqual(ConsumerPresentationCopy.humanDecisionLabel(state: .readyToOptimize), "Ready")
        XCTAssertEqual(ConsumerPresentationCopy.humanDecisionLabel(state: .protected), "Protected")
        XCTAssertEqual(ConsumerPresentationCopy.humanDecisionLabel(state: .keep), "Keep")
        XCTAssertEqual(ConsumerPresentationCopy.humanDecisionLabel(state: .verificationNeeded), "Needs Verification")
        for state in [StoragePresentationState.readyToOptimize, .protected, .keep, .verificationNeeded] {
            let label = ConsumerPresentationCopy.humanDecisionLabel(state: state)
            XCTAssertFalse(label.contains("GREEN"))
            XCTAssertFalse(label.contains("RED"))
            XCTAssertFalse(label.contains("YELLOW"))
        }
    }

    func testVerifiedRecoveredCanonicalAndHint() {
        XCTAssertEqual(StorageProductPresentationBuilder.verifiedCompletedRecoveryTotal, 5_580_814_899)
        XCTAssertFalse(ConsumerPresentationCopy.verifiedRecoveredHint.isEmpty)
        XCTAssertFalse(StorageProductPresentationBuilder.fakeRecoverableBytesAllowed())
    }

    func testNoNewExecutorNoMutation() {
        XCTAssertTrue(ProductizationInvariants.noNewExecutor)
        XCTAssertTrue(ProductizationInvariants.noRealMutationInP40)
        XCTAssertEqual(ProductizationInvariants.existingExecutors.count, 3)
        XCTAssertFalse(ProductizationInvariants.secondCrawlerAdded)
    }

    func testAsyncSelectionStillGuarded() {
        let binding = PresentationSelectionBinding(selectedEntityID: "b", requestID: 9)
        XCTAssertFalse(binding.accepts(responseEntityID: "a", responseRequestID: 9))
        XCTAssertTrue(binding.accepts(responseEntityID: "b", responseRequestID: 9))
    }

    func testNorthStarAndFirstRunPromise() {
        XCTAssertTrue(ConsumerPresentationCopy.productNorthStar.contains("DaisyDisk"))
        XCTAssertTrue(ConsumerPresentationCopy.firstRunPromise.lowercased().contains("safe"))
    }

    func testScannerStagesHumanized() {
        XCTAssertEqual(ConsumerPresentationCopy.scanningStages.last, "Ready")
        XCTAssertFalse(ConsumerPresentationCopy.scanningStages.contains(where: { $0.contains("RuntimeObservation") }))
    }
}
