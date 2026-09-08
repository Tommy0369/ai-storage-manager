import XCTest
@testable import AppServices
import SafetyCore

final class P303OptimizationPlanTests: XCTestCase {
    func testUnknownNeverEntersReadyNow() throws {
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(5),
            items: [
                item("u", "Unknown", 8_000_000_000, .unknown, .verifyMore, .reviewNeeded, executor: false)
            ],
            snapshotID: "s1"
        )
        XCTAssertEqual(plan.availableNowPotentialBytes, 0)
        XCTAssertFalse(plan.selectedEntries.contains { $0.candidate.safetyClass == .unknown })
        XCTAssertEqual(plan.goalStatus, .needsMoreVerification)
    }

    func testRedNeverEntersPlanSelection() throws {
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(5),
            items: [
                item("r", "Voice Memos", 9_000_000_000, .red, .unknown, .protected, executor: false)
            ],
            snapshotID: "s1"
        )
        XCTAssertTrue(plan.selectedEntries.isEmpty)
        XCTAssertEqual(plan.goalStatus, .noSafeOptions)
        XCTAssertTrue(plan.excludedSummary.contains { $0.entityID == "r" })
        XCTAssertTrue(plan.excludedSummary.contains { $0.reason.lowercased().contains("protected") })
        XCTAssertFalse(plan.excludedSummary.contains { $0.reason.lowercased().contains("verified opportunity") && $0.entityID == "r" })
    }

    func testUnsupportedExecutorNotExecutable() throws {
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(5),
            items: [],
            extraFacts: [
                OptimizationActionFact(
                    entityID: "vid",
                    displayName: "Videos",
                    canonicalPath: "/tmp/Videos",
                    action: .moveToICloud,
                    eligible: true,
                    safetyClass: .green,
                    expectedLogicalBytes: 6_100_000_000
                )
            ],
            snapshotID: "s1"
        )
        let future = plan.entries.first { $0.candidate.entityID == "vid" }
        XCTAssertEqual(future?.candidate.tier, .verifiedButExecutorUnavailable)
        XCTAssertEqual(future?.candidate.executionSupport, .notImplemented)
        XCTAssertFalse(future?.selected ?? true)
        XCTAssertGreaterThan(plan.verifiedFuturePotentialBytes, 0)
        XCTAssertEqual(plan.availableNowPotentialBytes, 0)
    }

    func testPreflightRequiredNotGuaranteedAvailableNow() throws {
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(5),
            items: [
                item("p", "Needs check", 4_000_000_000, .green, .preflightRequired, .safeActions, executor: true)
            ],
            snapshotID: "s1"
        )
        XCTAssertEqual(plan.availableNowPotentialBytes, 0)
        XCTAssertEqual(plan.preflightPossibleBytes, 4_000_000_000)
        XCTAssertTrue(plan.selectedEntries.isEmpty)
    }

    func testApprovalRequiredCountsAsReadyNow() throws {
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(5),
            items: [
                item("a", "Xcode Build Data", 4_200_000_000, .green, .approvalRequired, .safeActions, executor: true)
            ],
            snapshotID: "s1"
        )
        XCTAssertEqual(plan.availableNowPotentialBytes, 4_200_000_000)
        XCTAssertEqual(plan.selectedEntries.count, 1)
        XCTAssertEqual(plan.selectedEntries.first?.candidate.immediateExpectedRecoveryBytes, 0)
        XCTAssertEqual(plan.shortfallBytes, 800_000_000)
        XCTAssertEqual(plan.goalStatus, .partiallyAchievable)
    }

    func testGoalExactlyAchievableAndOvershootPrefersSmallerPair() throws {
        let exact = OptimizationPlanEngine.plan(
            goal: try OptimizationGoal(targetBytes: 6_300_000_000),
            items: [
                item("a", "A", 4_200_000_000, .green, .approvalRequired, .safeActions, path: "/tmp/a", executor: true),
                item("b", "B", 2_100_000_000, .green, .approvalRequired, .safeActions, path: "/tmp/b", executor: true)
            ],
            snapshotID: "s1"
        )
        XCTAssertEqual(exact.goalStatus, .achievableNow)
        XCTAssertEqual(exact.shortfallBytes, 0)

        let overshoot = OptimizationPlanEngine.plan(
            goal: try OptimizationGoal(targetBytes: 10_000_000_000),
            items: [
                item("big", "20 GB item", 20_000_000_000, .green, .approvalRequired, .safeActions, path: "/tmp/big", executor: true),
                item("n9", "9 GB", 9_000_000_000, .green, .approvalRequired, .safeActions, path: "/tmp/n9", executor: true),
                item("n2", "2 GB", 2_000_000_000, .green, .approvalRequired, .safeActions, path: "/tmp/n2", executor: true)
            ],
            snapshotID: "s1"
        )
        let ids = Set(overshoot.selectedEntries.map { $0.candidate.entityID })
        XCTAssertEqual(ids, Set(["n9", "n2"]))
        XCTAssertFalse(ids.contains("big"))
    }

    func testZeroSafeCandidatesAndInvalidGoal() {
        XCTAssertThrowsError(try OptimizationGoal(targetBytes: 0))
        XCTAssertThrowsError(try OptimizationGoal(targetBytes: -1))
        XCTAssertThrowsError(try OptimizationGoal(targetBytes: OptimizationGoal.maxReasonableBytes + 1))
        XCTAssertNoThrow(try OptimizationGoal(targetBytes: 1))
    }

    func testParentChildNotDoubleCounted() throws {
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(50),
            items: [
                item("parent", "Parent", 20_000_000_000, .green, .approvalRequired, .safeActions, path: "/tmp/Parent", executor: true),
                item("child", "Child", 8_000_000_000, .green, .approvalRequired, .safeActions, path: "/tmp/Parent/Child", executor: true)
            ],
            snapshotID: "s1"
        )
        XCTAssertEqual(plan.selectedEntries.count, 1)
        XCTAssertGreaterThan(plan.overlapBytesPrevented, 0)
        XCTAssertTrue(OptimizationPlanEngine.pathsOverlap("/tmp/Parent", "/tmp/Parent/Child"))
    }

    func testSameEntityDifferentActionsConflict() throws {
        let trash = item("e", "Entity", 5_000_000_000, .green, .approvalRequired, .safeActions, path: "/tmp/E", executor: true)
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(10),
            items: [trash],
            extraFacts: [
                OptimizationActionFact(
                    entityID: "e",
                    displayName: "Entity",
                    canonicalPath: "/tmp/E",
                    action: .moveToICloud,
                    eligible: true,
                    safetyClass: .green,
                    expectedLogicalBytes: 5_000_000_000
                )
            ],
            snapshotID: "s1"
        )
        let selected = plan.selectedEntries.map { $0.candidate.action }
        XCTAssertEqual(selected, [.moveToTrash])
    }

    func testTrashDoesNotClaimImmediateVerifiedRecovery() throws {
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(4),
            items: [
                item("t", "Cache", 4_200_000_000, .green, .approvalRequired, .safeActions, executor: true)
            ],
            snapshotID: "s1"
        )
        let entry = try XCTUnwrap(plan.selectedEntries.first)
        XCTAssertEqual(entry.candidate.potentialRecoveryBytes, 4_200_000_000)
        XCTAssertEqual(entry.candidate.immediateExpectedRecoveryBytes, 0)
        XCTAssertEqual(entry.candidate.verifiedRecoveredBytes, 0)
        XCTAssertTrue(plan.warnings.contains { $0.lowercased().contains("trash") })
    }

    func testPlanningCreatesNoApprovalPermitOrExecutorCall() throws {
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(4),
            items: [
                item("t", "Cache", 4_200_000_000, .green, .approvalRequired, .safeActions, executor: true)
            ],
            snapshotID: "s1"
        )
        XCTAssertFalse(plan.approvalCreated)
        XCTAssertFalse(plan.executionPermitCreated)
        XCTAssertFalse(plan.executorCalled)
        XCTAssertFalse(plan.bulkActionPresent)
    }

    func testStalenessWhenSnapshotChanges() throws {
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(4),
            items: [
                item("t", "Cache", 4_200_000_000, .green, .approvalRequired, .safeActions, executor: true)
            ],
            snapshotID: "gen-1"
        )
        let stale = OptimizationPlanEngine.markStale(plan, currentSnapshotID: "gen-2")
        XCTAssertEqual(stale.freshness, .stale)
        XCTAssertTrue(stale.entries.allSatisfy(\.stale))
        XCTAssertEqual(OptimizationPlanEngine.markStale(plan, currentSnapshotID: "gen-1").freshness, .current)
    }

    func testGrowthDoesNotCreateEligibility() throws {
        let change = StorageChangeService.demoChangeReport()
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(20),
            items: [
                item("ollama", "Ollama Models", 8_100_000_000, .unknown, .verifyMore, .reviewNeeded, executor: false)
            ],
            snapshotID: "s1",
            changeReport: change
        )
        XCTAssertTrue(plan.selectedEntries.isEmpty)
        XCTAssertTrue(plan.contextNotes.contains { $0.lowercased().contains("growth") })
        XCTAssertFalse(plan.selectedEntries.contains { $0.candidate.entityID == "ollama" })
    }

    func testUserRemoveDoesNotAutoAddUnsafeReplacement() throws {
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(10),
            items: [
                item("a", "A", 4_200_000_000, .green, .approvalRequired, .safeActions, path: "/tmp/a", executor: true),
                item("unsafe", "Unsafe", 20_000_000_000, .unknown, .verifyMore, .reviewNeeded, path: "/tmp/u", executor: false)
            ],
            snapshotID: "s1"
        )
        let reduced = OptimizationPlanEngine.removing(entityID: "a", from: plan)
        XCTAssertFalse(reduced.selectedEntries.contains { $0.candidate.entityID == "a" })
        XCTAssertFalse(reduced.selectedEntries.contains { $0.candidate.entityID == "unsafe" })
        XCTAssertGreaterThan(reduced.shortfallBytes, plan.shortfallBytes)
    }

    func testCompletionUpdatesWithoutTreatingExecutorReturnAsFreedDisk() throws {
        let plan = OptimizationPlanEngine.plan(
            goal: try .gigabytes(4),
            items: [
                item("t", "Cache", 4_200_000_000, .green, .approvalRequired, .safeActions, executor: true)
            ],
            snapshotID: "s1"
        )
        let outcome = UIExecutionOutcome(
            entityID: "t",
            action: .moveToTrash,
            readiness: .storageRecoveryPending,
            logicalActionCompleted: true,
            storageRecoveryState: .recoveryPending,
            recoveryLabel: "pending",
            userLines: []
        )
        let updated = OptimizationPlanEngine.applyCompletion(plan, entityID: "t", outcome: outcome)
        XCTAssertEqual(updated.entries.first?.completionState, "Recovery pending")
        XCTAssertEqual(updated.entries.first?.candidate.verifiedRecoveredBytes, 0)
        XCTAssertEqual(updated.entries.first?.candidate.immediateExpectedRecoveryBytes, 0)
    }

    func testDemoPartialAndNoSafePlans() throws {
        let partial = try OptimizationPlanService.demoPartialPlan()
        XCTAssertEqual(partial.goalStatus, .partiallyAchievable)
        XCTAssertEqual(partial.availableNowPotentialBytes, 6_300_000_000)
        XCTAssertEqual(partial.verifiedFuturePotentialBytes, 6_100_000_000)
        XCTAssertGreaterThan(partial.shortfallBytes, 0)
        XCTAssertTrue(partial.excludedSummary.contains { $0.displayName.contains("Claude") || $0.entityID.contains("claude") })

        let none = try OptimizationPlanService.demoNoSafePlan()
        XCTAssertTrue([OptimizationGoalStatus.noSafeOptions, .needsMoreVerification].contains(none.goalStatus))
        XCTAssertEqual(none.availableNowPotentialBytes, 0)

        let achievable = try OptimizationPlanService.demoAchievablePlan()
        XCTAssertEqual(achievable.goalStatus, .achievableNow)
    }

    func testGigabytesRejectsOverflowAndZero() {
        XCTAssertThrowsError(try OptimizationGoal.gigabytes(0))
        XCTAssertThrowsError(try OptimizationGoal.gigabytes(-3))
        XCTAssertThrowsError(try OptimizationGoal.gigabytes(20_000))
        XCTAssertNoThrow(try OptimizationGoal.gigabytes(20))
    }

    func testCapabilityRegistryDoesNotInferFromEnum() {
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToTrash), .implemented)
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .moveToICloud), .notImplemented)
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .removeLocalDownload), .notImplemented)
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .vendorNativeCleanup), .notImplemented)
    }

    func testSignedByteMath() throws {
        let a: Int64 = 9_000_000_000
        let b: Int64 = 2_000_000_000
        XCTAssertEqual(a &+ b, 11_000_000_000)
        XCTAssertEqual(max(0, 10_000_000_000 &- 11_000_000_000), 0)
    }

    private func item(
        _ id: String,
        _ name: String,
        _ bytes: Int64,
        _ safety: SafetyClass,
        _ readiness: UIReadinessState,
        _ group: UICandidateGroup,
        path: String? = nil,
        executor: Bool
    ) -> UICandidateItem {
        UICandidateItem(
            id: id,
            entityID: id,
            displayName: name,
            category: "Test",
            pathSummary: path ?? "/tmp/\(id)",
            fullPath: path ?? "/tmp/\(id)",
            byteLabel: UICandidateMapper.byteLabel(bytes),
            expectedBytes: bytes,
            recommendedAction: executor ? .moveToTrash : nil,
            recommendedActionLabel: executor ? "Move to Trash" : "None",
            reasonSummary: "test",
            readiness: readiness,
            group: group,
            safetyClass: safety,
            evidenceLines: [],
            executorAvailable: executor
        )
    }
}
