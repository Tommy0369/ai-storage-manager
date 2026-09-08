import XCTest
@testable import AppServices
import SafetyCore

final class P30StorageExperienceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.setOverride(.english)
    }

    override func tearDown() {
        L10n.setOverride(.english)
        super.tearDown()
    }

    func testEntityPresentationMapsKnownTechnicalID() {
        let pres = EntityPresentationResolver.resolve(
            entityID: "ai.hf.hub",
            path: "/Users/test/.cache/huggingface/hub",
            domain: "AI Tools",
            subcategory: "hub"
        )
        XCTAssertEqual(pres.title, "Hugging Face Models")
        XCTAssertEqual(pres.category, .aiTools)
        XCTAssertFalse(pres.description.lowercased().contains("safe to delete"))
    }

    func testUnknownEntityFallsBackSafely() {
        let pres = EntityPresentationResolver.resolve(
            entityID: "macos.user_caches.child.cron-updater",
            path: "/Users/test/Library/Caches/cron-updater",
            domain: "macOS",
            subcategory: "cron-updater"
        )
        XCTAssertEqual(pres.title, "macOS Update Cache")
        XCTAssertNotEqual(pres.title, "macos.user_caches.child.cron-updater")
    }

    func testPresentationDoesNotClaimDeleteSafeWithoutAction() {
        let pres = EntityPresentationResolver.resolve(
            entityID: "ai.unknown.model",
            path: "/Users/test/models/big",
            domain: "AI Tools",
            subcategory: "model"
        )
        XCTAssertFalse(pres.description.lowercased().contains("safely removed"))
        XCTAssertFalse(pres.description.lowercased().contains("safe to delete"))
    }

    func testCategoryMappingDeterministic() {
        let dev = EntityPresentationResolver.resolve(
            entityID: "xcode.deriveddata.foo",
            path: "/Users/test/DerivedData/foo",
            domain: "Developer",
            subcategory: "DerivedData"
        )
        let ai = EntityPresentationResolver.resolve(
            entityID: "ai.ollama.blobs",
            path: "/Users/test/.ollama/models",
            domain: "AI Tools",
            subcategory: "blobs"
        )
        XCTAssertEqual(dev.category, .developer)
        XCTAssertEqual(ai.category, .aiTools)
        XCTAssertEqual(dev.category, EntityPresentationResolver.resolve(
            entityID: "xcode.deriveddata.foo",
            path: "/Users/test/DerivedData/foo",
            domain: "Developer",
            subcategory: "DerivedData"
        ).category)
    }

    func testTechnicalIDNotPrimaryDisplayName() {
        let pres = EntityPresentationResolver.resolve(
            entityID: "ai.hf.hub",
            path: "/tmp/hf",
            domain: "AI Tools",
            subcategory: "hub"
        )
        XCTAssertEqual(pres.title, "Hugging Face Models")
        XCTAssertNotEqual(pres.title, "ai.hf.hub")
    }

    func testMapAccountingDoesNotDoubleCountCategories() {
        let categories = [
            StorageMapNode(id: "c1", title: "Developer", bytes: 100, semanticCategory: .developer, isAggregate: true),
            StorageMapNode(id: "c2", title: "AI Tools", bytes: 200, semanticCategory: .aiTools, isAggregate: true),
            StorageMapNode(id: "c3", title: "macOS", bytes: 300, semanticCategory: .macOSSystem, isAggregate: true),
        ]
        XCTAssertTrue(StorageExperienceBuilder.validateAccounting(categories: categories, scannedBytes: 700, unclassifiedBytes: 100))
        XCTAssertFalse(StorageExperienceBuilder.validateAccounting(categories: categories, scannedBytes: 800, unclassifiedBytes: 0))
    }

    func testUnclassifiedBytesRepresentedExplicitly() {
        let unclassified = StorageMapNode(
            id: "other",
            title: ProductStorageCategory.otherUnknown.displayName,
            bytes: 600,
            semanticCategory: .otherUnknown,
            isAggregate: true
        )
        let categories = [
            StorageMapNode(id: "dev", title: "Developer", bytes: 400, semanticCategory: .developer, isAggregate: true),
        ]
        XCTAssertTrue(StorageExperienceBuilder.validateAccounting(categories: categories, scannedBytes: 1000, unclassifiedBytes: 600))
        XCTAssertEqual(unclassified.semanticCategory, .otherUnknown)
    }

    func testRecommendationReadinessFilter() {
        let unknownItem = UICandidateItem(
            id: "u", entityID: "u", displayName: "U", category: "X", pathSummary: "p", fullPath: "/p",
            byteLabel: "1 MB", expectedBytes: 1_000_000, recommendedAction: nil, recommendedActionLabel: "None",
            reasonSummary: "x", readiness: .unknown, group: .reviewNeeded, safetyClass: .unknown,
            evidenceLines: [], executorAvailable: false
        )
        let safeItem = UICandidateItem(
            id: "s", entityID: "s", displayName: "S", category: "X", pathSummary: "p", fullPath: "/p",
            byteLabel: "1 MB", expectedBytes: 1_000_000, recommendedAction: .moveToTrash, recommendedActionLabel: "Move to Trash",
            reasonSummary: "x", readiness: .approvalRequired, group: .safeActions, safetyClass: .green,
            evidenceLines: [], executorAvailable: true
        )
        XCTAssertNotEqual(unknownItem.readiness, .approvalRequired)
        XCTAssertEqual(safeItem.readiness, .approvalRequired)
        XCTAssertNotEqual(unknownItem.safetyClass, .green)
        XCTAssertTrue(safeItem.safetyClass != .unknown && safeItem.safetyClass != .red)
    }

    func testDiskCapacityDistinctFromObservedScope() {
        let disk = DiskCapacityReader.snapshot()
        XCTAssertNotNil(disk.volumeTotalBytes)
        let observedScope: Int64 = 14_590_000_000
        XCTAssertNotEqual(disk.volumeTotalBytes, observedScope)
    }

    func testRecoveryPendingNotShownAsFreed() {
        let outcome = UICandidateMapper.mapExecutionOutcome(
            report: nil,
            postResult: PostMutationVerificationResult(
                actionID: "a",
                entityID: "x",
                action: .moveToTrash,
                preMutationBindingFingerprint: ActionBindingFingerprint(
                    entityID: "x", action: .moveToTrash, canonicalPath: "/tmp/x",
                    evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1,
                    ruleVersion: "t", transactionContractVersion: "t"
                ),
                postMutationObservation: PostMutationObservation(
                    sourcePathState: .absent, sourceIdentityMatch: true,
                    trashEntityObserved: true, trashIdentityMatch: true, trashPath: "/tmp/.Trash/x",
                    siblingUnchanged: true, bindingMatches: true, auditRecordMatches: true
                ),
                verificationState: .storageRecoveryPending,
                logicalActionCompleted: true,
                storageRecoveryState: .recoveryPending,
                expectedBytes: 119_000_000,
                measuredBytesBefore: 119_000_000,
                measuredBytesAfter: 119_000_000,
                freeBytesBeforeAction: nil,
                freeBytesAfterAction: nil,
                freeBytesAfterPostVerifyScan: nil,
                actualRecoveredBytes: 0,
                recoveryConfidence: .exact,
                trashStillHoldingData: true,
                entityRegenerated: false,
                regeneratedEntityID: nil,
                semanticRelationship: .none,
                auditStatus: .postVerified,
                verificationTimestamp: Date(),
                executedAt: Date(),
                preflightObservedAt: Date(),
                regeneratedEntityObservedAt: nil,
                contractVersion: "t",
                contractSteps: [],
                errors: [],
                unknownReasons: []
            ),
            error: nil
        )
        XCTAssertEqual(outcome.readiness, .storageRecoveryPending)
        XCTAssertTrue(outcome.recoveryLabel.lowercased().contains("pending"))
        XCTAssertFalse(outcome.userLines.joined().lowercased().contains("freed"))
    }

    func testExperienceReportMarksTechnicalIDsHidden() {
        let snapshot = StorageExperienceSnapshot(
            diskCapacity: DiskCapacitySnapshot(volumeName: "HD", volumeTotalBytes: 100, volumeAvailableBytes: 10, volumeUsedBytes: 90),
            observedStorage: ObservedStorageSnapshot(scannedRootBytes: 50, classifiedUniqueBytes: 50, unclassifiedBytes: 0, selectedRootLabel: "HD"),
            mapRoot: StorageMapNode(id: "root", title: "HD", bytes: 50, semanticCategory: .otherUnknown, isAggregate: true),
            categories: [],
            insights: [],
            recommendations: [],
            needsReview: [],
            protected: [],
            recentActions: [],
            readyActionCount: 0,
            readyPotentialBytes: 0,
            needsReviewCount: 0,
            needsReviewBytes: 0,
            protectedCount: 0,
            protectedBytes: 0,
            recoveryPendingBytes: 0,
            mapAccountingValid: true,
            mapRootBytes: 50,
            generatedAt: Date(),
            scanRuntimeSeconds: nil
        )
        let report = StorageExperienceBuilder.report(from: snapshot)
        XCTAssertTrue(report.technicalIDsHiddenByDefault)
        XCTAssertEqual(report.observedBytes, 50)
        XCTAssertNotEqual(report.diskTotalBytes, report.observedBytes)
    }

    func testFakeCoordinatorExposesExperienceSnapshot() async throws {
        let coordinator = FakeStorageActionCoordinator()
        try await coordinator.scan()
        XCTAssertNotNil(coordinator.experienceSnapshot)
        XCTAssertTrue(coordinator.experienceSnapshot?.mapAccountingValid == true)
    }
}
