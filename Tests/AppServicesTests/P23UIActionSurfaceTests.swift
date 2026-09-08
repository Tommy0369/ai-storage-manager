import XCTest
@testable import AppServices
import SafetyCore

final class P23UIActionSurfaceTests: XCTestCase {
    private var coordinator: FakeStorageActionCoordinator!
    private let entityID = "xcode.deriveddata.fixture"

    override func setUp() {
        coordinator = FakeStorageActionCoordinator()
    }

    func testPreflightRequiredMoveButtonDisabledUntilApproval() async throws {
        try await coordinator.scan()
        _ = coordinator.candidateDetail(entityID: entityID)
        let preflight = try await coordinator.runFreshPreflight(entityID: entityID, action: .moveToTrash)
        XCTAssertEqual(preflight.readiness, .approvalRequired)
        XCTAssertTrue(preflight.canApprove)
        XCTAssertNil(coordinator.pendingApproval)
    }

    func testApprovalRequiredAfterPreflightAndExplicitApproval() async throws {
        try await coordinator.scan()
        _ = try await coordinator.runFreshPreflight(entityID: entityID, action: .moveToTrash)
        let approval = try coordinator.submitApproval(entityID: entityID, action: .moveToTrash)
        XCTAssertEqual(approval.entityID, entityID)
        XCTAssertEqual(approval.action, .moveToTrash)
        XCTAssertNotNil(coordinator.pendingApproval)
    }

    func testUserCancelClearsApproval() async throws {
        try await coordinator.scan()
        _ = try await coordinator.runFreshPreflight(entityID: entityID, action: .moveToTrash)
        _ = try coordinator.submitApproval(entityID: entityID, action: .moveToTrash)
        coordinator.cancelApproval()
        XCTAssertNil(coordinator.pendingApproval)
    }

    func testBindingChangeBeforeExecutionAborts() async throws {
        try await coordinator.scan()
        _ = try await coordinator.runFreshPreflight(entityID: entityID, action: .moveToTrash)
        _ = try coordinator.submitApproval(entityID: entityID, action: .moveToTrash)
        coordinator.simulateBindingChangeOnExecute = true
        do {
            _ = try await coordinator.executeApprovedAction(entityID: entityID, action: .moveToTrash)
            XCTFail("expected binding change abort")
        } catch StorageActionCoordinatorError.bindingChanged {
            XCTAssertNil(coordinator.pendingApproval)
        }
    }

    func testExecutorFailureShowsFailureState() async throws {
        try await coordinator.scan()
        _ = try await coordinator.runFreshPreflight(entityID: entityID, action: .moveToTrash)
        _ = try coordinator.submitApproval(entityID: entityID, action: .moveToTrash)
        coordinator.simulateExecutorFailure = true
        let outcome = try await coordinator.executeApprovedAction(entityID: entityID, action: .moveToTrash)
        XCTAssertEqual(outcome.readiness, .failed)
        XCTAssertFalse(outcome.logicalActionCompleted)
        XCTAssertTrue(outcome.userLines.first?.contains("Nothing was moved") == true)
    }

    func testExecutorSuccessShowsPostVerifyPendingThenRecoveryPending() async throws {
        try await coordinator.scan()
        _ = try await coordinator.runFreshPreflight(entityID: entityID, action: .moveToTrash)
        _ = try coordinator.submitApproval(entityID: entityID, action: .moveToTrash)
        let outcome = try await coordinator.executeApprovedAction(entityID: entityID, action: .moveToTrash)
        XCTAssertTrue(outcome.logicalActionCompleted)
        XCTAssertEqual(outcome.readiness, .storageRecoveryPending)
        XCTAssertEqual(outcome.storageRecoveryState, .recoveryPending)
        XCTAssertEqual(outcome.postVerification?.actualRecoveredBytes, 0)
        XCTAssertEqual(outcome.recoveryLabel, "Disk recovery: Pending")
        XCTAssertNotEqual(outcome.recoveryLabel.lowercased(), "36 mb freed")
    }

    func testStorageRecoveryPendingDoesNotClaimFreedBytes() async throws {
        try await coordinator.scan()
        _ = try await coordinator.runFreshPreflight(entityID: entityID, action: .moveToTrash)
        _ = try coordinator.submitApproval(entityID: entityID, action: .moveToTrash)
        let outcome = try await coordinator.executeApprovedAction(entityID: entityID, action: .moveToTrash)
        XCTAssertEqual(outcome.postVerification?.actualRecoveredBytes, 0)
        XCTAssertTrue(outcome.trashWarning?.contains("will not empty") == true)
    }

    func testRegenerationPresentation() async throws {
        try await coordinator.scan()
        _ = try await coordinator.runFreshPreflight(entityID: entityID, action: .moveToTrash)
        _ = try coordinator.submitApproval(entityID: entityID, action: .moveToTrash)
        coordinator.simulateRegeneration = true
        let outcome = try await coordinator.executeApprovedAction(entityID: entityID, action: .moveToTrash)
        XCTAssertEqual(outcome.readiness, .regenerated)
        XCTAssertTrue(outcome.logicalActionCompleted)
        XCTAssertNotEqual(outcome.readiness, .failed)
    }

    func testExecuteWithoutApprovalThrows() async throws {
        try await coordinator.scan()
        do {
            _ = try await coordinator.executeApprovedAction(entityID: entityID, action: .moveToTrash)
            XCTFail("expected approval required")
        } catch StorageActionCoordinatorError.approvalRequired {
            XCTAssertTrue(true)
        }
    }

    func testSafeActionsMapping() async throws {
        try await coordinator.scan()
        XCTAssertEqual(coordinator.safeActions.count, 1)
        XCTAssertEqual(coordinator.safeActions[0].group, .safeActions)
        XCTAssertEqual(coordinator.reviewNeeded[0].group, .reviewNeeded)
        XCTAssertEqual(coordinator.protected[0].group, .protected)
    }

    func testSurfaceReportWritten() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p23-\(UUID().uuidString)")
        try await coordinator.scan()
        try coordinator.writeSurfaceReport(to: dir)
        let url = dir.appendingPathComponent("ui_action_surface.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: dir)
    }

    func testApprovalBindsFingerprint() async throws {
        try await coordinator.scan()
        let preflight = try await coordinator.runFreshPreflight(entityID: entityID, action: .moveToTrash)
        let approval = try coordinator.submitApproval(entityID: entityID, action: .moveToTrash)
        XCTAssertEqual(approval.approval.bindingFingerprint, preflight.bindingFingerprint)
        XCTAssertEqual(approval.receipt.receiptID, preflight.receipt?.receiptID)
    }
}

private extension UIExecutionOutcome {
    var actualRecoveredBytesFromPostVerify: Int64? {
        postVerification?.actualRecoveredBytes
    }
}
