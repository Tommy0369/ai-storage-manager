import Foundation
import SafetyCore

/// Fake coordinator for UI tests — never touches real filesystem mutation.
public final class FakeStorageActionCoordinator: StorageActionCoordinating {
    public var overview: StorageOverviewState = .empty
    public var safeActions: [UICandidateItem] = []
    public var reviewNeeded: [UICandidateItem] = []
    public var protected: [UICandidateItem] = []
    public var recentActions: [UIActionHistoryItem] = []
    public var isScanning = false
    public var selectedCandidateID: String?
    public var lastPreflight: UIPreflightResult?
    public var pendingApproval: UIApprovalState?
    public var lastExecution: UIExecutionOutcome?
    public var lastSurfaceReport: UIActionSurfaceReport?
    public var experienceSnapshot: StorageExperienceSnapshot?
    public var explorerSnapshot: StorageExplorerSnapshot?
    public var changeReport: StorageChangeReport?
    public var historyStatus: P302HistoryStatusReport?
    public var optimizationPlan: OptimizationPlan?
    public var optimizationFacts: [OptimizationActionFact] = []
    public var scanStage: StorageScanStage = .idle
    public var scanProgressHandler: (@Sendable (StorageScanStage) -> Void)?

    public var simulateBindingChangeOnExecute = false
    public var simulateExecutorFailure = false
    public var simulateRegeneration = false

    private let fixtureEntityID = "xcode.deriveddata.fixture"
    private let fixturePath = "/tmp/ai-storage-manager-fixture/DerivedData/fixture"

    public init() {
        seedFixtures()
    }

    public func scan() async throws {
        isScanning = true
        scanStage = .scanningFiles
        scanProgressHandler?(.scanningFiles)
        try await Task.sleep(nanoseconds: 40_000_000)
        scanStage = .hierarchyAvailable
        explorerSnapshot = PreviewSnapshotFactory.explorerDemo(experience: experienceSnapshot)
        scanProgressHandler?(.hierarchyAvailable)
        try await Task.sleep(nanoseconds: 20_000_000)
        seedFixtures()
        changeReport = StorageChangeService.demoChangeReport()
        optimizationPlan = try? OptimizationPlanService.demoPartialPlan()
        historyStatus = P302HistoryStatusReport(
            historySnapshotCount: 2,
            oldestSnapshotAt: Date().addingTimeInterval(-7 * 24 * 3600),
            newestSnapshotAt: Date(),
            historyStoreLocationType: "fixture",
            snapshotWriteSuccess: true,
            privacyFieldsStored: StorageHistoryBuilder.privacyFieldsStored
        )
        scanStage = .complete
        scanProgressHandler?(.complete)
        isScanning = false
    }

    public func expandPhysicalNode(id: String) {}

    public func candidateDetail(entityID: String) -> UICandidateDetail? {
        selectedCandidateID = entityID
        guard let item = find(entityID) else { return nil }
        return UICandidateMapper.mapDetail(item, gate: nil)
    }

    public func runFreshPreflight(entityID: String, action: StorageAction) async throws -> UIPreflightResult {
        guard find(entityID) != nil else { throw StorageActionCoordinatorError.candidateNotFound }
        let readiness: UIReadinessState = entityID.contains("blocked") ? .verifyMore : .approvalRequired
        let result = UIPreflightResult(
            entityID: entityID,
            action: action,
            readiness: readiness,
            satisfiedLines: [
                UIEvidenceLine(id: "1", satisfied: true, userText: "Item identity unchanged", technicalDetail: nil),
                UIEvidenceLine(id: "2", satisfied: true, userText: "Xcode can regenerate this data.", technicalDetail: nil),
            ],
            blockingLines: readiness == .verifyMore
                ? [UIEvidenceLine(id: "b", satisfied: false, userText: "Xcode is currently using this data", technicalDetail: nil)]
                : [],
            bindingFingerprint: fixtureFingerprint(entityID: entityID),
            receipt: fixtureReceipt(entityID: entityID),
            canApprove: readiness == .approvalRequired,
            userMessage: readiness == .approvalRequired ? "Ready for your approval" : "Safety check incomplete"
        )
        lastPreflight = result
        return result
    }

    public func submitApproval(entityID: String, action: StorageAction) throws -> UIApprovalState {
        guard let preflight = lastPreflight, preflight.canApprove else {
            throw StorageActionCoordinatorError.approvalRequired
        }
        guard let receipt = preflight.receipt, let fp = preflight.bindingFingerprint else {
            throw StorageActionCoordinatorError.preflightRequired
        }
        let approval = UserActionApproval(
            approvalID: "fake-approval-\(entityID)",
            entityID: entityID,
            action: action,
            bindingFingerprint: fp,
            consequenceSummaryVersion: "P2.3_TEST",
            expectedRecoveryBytes: 36_000_000,
            approvedAt: Date(),
            expiryPolicy: "single_use_immediate",
            scope: "test"
        )
        let state = UIApprovalState(approval: approval, receipt: receipt, entityID: entityID, action: action, boundAt: Date())
        pendingApproval = state
        return state
    }

    public func executeApprovedAction(entityID: String, action: StorageAction) async throws -> UIExecutionOutcome {
        guard pendingApproval != nil else { throw StorageActionCoordinatorError.approvalRequired }
        if simulateBindingChangeOnExecute {
            pendingApproval = nil
            throw StorageActionCoordinatorError.bindingChanged
        }
        if simulateExecutorFailure {
            let outcome = UICandidateMapper.mapExecutionOutcome(
                report: nil, postResult: nil,
                error: "Xcode started using this data after your safety check. Nothing was moved."
            )
            lastExecution = outcome
            pendingApproval = nil
            return outcome
        }

        let post = PostMutationVerificationResult(
            actionID: "fake-permit",
            entityID: entityID,
            action: action,
            preMutationBindingFingerprint: fixtureFingerprint(entityID: entityID)!,
            postMutationObservation: PostMutationObservation(
                sourcePathState: .absent,
                sourceIdentityMatch: true,
                trashEntityObserved: true,
                trashIdentityMatch: true,
                trashPath: "/tmp/.Trash/fixture",
                siblingUnchanged: true,
                bindingMatches: true,
                auditRecordMatches: true
            ),
            verificationState: simulateRegeneration ? .regenerated : .storageRecoveryPending,
            logicalActionCompleted: true,
            storageRecoveryState: .recoveryPending,
            expectedBytes: 36_000_000,
            measuredBytesBefore: 36_000_000,
            measuredBytesAfter: 36_000_000,
            freeBytesBeforeAction: nil,
            freeBytesAfterAction: nil,
            freeBytesAfterPostVerifyScan: nil,
            actualRecoveredBytes: 0,
            recoveryConfidence: .exact,
            trashStillHoldingData: true,
            entityRegenerated: simulateRegeneration,
            regeneratedEntityID: simulateRegeneration ? "xcode.deriveddata.new" : nil,
            semanticRelationship: simulateRegeneration ? .semanticSuccessor : .none,
            auditStatus: .postVerified,
            verificationTimestamp: Date(),
            executedAt: Date(),
            preflightObservedAt: Date(),
            regeneratedEntityObservedAt: simulateRegeneration ? Date() : nil,
            contractVersion: TransactionContractRegistry.postVerifyTrashVersion,
            contractSteps: [],
            errors: [],
            unknownReasons: []
        )
        let outcome = UICandidateMapper.mapExecutionOutcome(report: nil, postResult: post, error: nil)
        lastExecution = outcome
        pendingApproval = nil
        recentActions.insert(UIActionHistoryItem(
            id: "fake-\(entityID)",
            timestamp: Date(),
            entityID: entityID,
            displayName: "Xcode Derived Data",
            action: action,
            actionLabel: "Moved to Trash",
            logicalVerified: true,
            storageRecoveryPending: true,
            readiness: outcome.readiness,
            summaryLines: outcome.userLines
        ), at: 0)
        return outcome
    }

    public func cancelApproval() {
        pendingApproval = nil
        lastPreflight = nil
    }

    public func writeSurfaceReport(to directory: URL) throws {
        lastSurfaceReport = UICandidateMapper.surfaceReport(
            overview: overview,
            safe: safeActions,
            review: reviewNeeded,
            protected: protected,
            selectedID: selectedCandidateID,
            preflight: lastPreflight,
            approval: pendingApproval,
            execution: lastExecution
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(lastSurfaceReport!).write(to: directory.appendingPathComponent("ui_action_surface.json"))
    }

    public func writeExperienceReport(to directory: URL) throws {
        try writeSurfaceReport(to: directory)
        guard let snapshot = experienceSnapshot else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let report = StorageExperienceBuilder.report(from: snapshot)
        try encoder.encode(report).write(to: directory.appendingPathComponent("p3_0_storage_experience.json"))
    }

    public func writeExplorerReports(to directory: URL) throws {
        guard let snapshot = explorerSnapshot else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(StorageExplorerBuilder.report(from: snapshot, falseGREEN: 0, duplicateEvaluations: 0))
            .write(to: directory.appendingPathComponent("p3_0_1_storage_explorer.json"))
        try encoder.encode(StorageExplorerBuilder.performanceReport(from: snapshot))
            .write(to: directory.appendingPathComponent("p3_0_1_explorer_performance.json"))
    }

    public func writeChangeReports(to directory: URL) throws {
        let report = changeReport ?? StorageChangeService.demoChangeReport()
        changeReport = report
        let status = historyStatus ?? P302HistoryStatusReport(
            historySnapshotCount: 2,
            oldestSnapshotAt: Date().addingTimeInterval(-7 * 24 * 3600),
            newestSnapshotAt: Date(),
            historyStoreLocationType: "fixture",
            snapshotWriteSuccess: true,
            privacyFieldsStored: StorageHistoryBuilder.privacyFieldsStored
        )
        historyStatus = status
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(P302StorageChangeExport(from: report))
            .write(to: directory.appendingPathComponent("p3_0_2_storage_change.json"))
        try encoder.encode(status)
            .write(to: directory.appendingPathComponent("p3_0_2_history_status.json"))
    }

    public func writeOptimizationReports(to directory: URL) throws {
        let plan = try optimizationPlan ?? OptimizationPlanService.demoPartialPlan()
        optimizationPlan = plan
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(P303OptimizationPlanReport(from: plan))
            .write(to: directory.appendingPathComponent("p3_0_3_optimization_plan.json"))
        try encoder.encode(plan.funnel)
            .write(to: directory.appendingPathComponent("p3_0_3_candidate_funnel.json"))
    }

    private func seedFixtures() {
        let item = UICandidateItem(
            id: fixtureEntityID,
            entityID: fixtureEntityID,
            displayName: "Xcode Derived Data",
            category: "Generated build data",
            pathSummary: "DerivedData/fixture",
            fullPath: fixturePath,
            byteLabel: "36 MB",
            expectedBytes: 36_000_000,
            recommendedAction: .moveToTrash,
            recommendedActionLabel: "Move to Trash",
            reasonSummary: "Generated by Xcode; can be recreated",
            readiness: .preflightRequired,
            group: .safeActions,
            safetyClass: .green,
            evidenceLines: [
                UIEvidenceLine(id: "r", satisfied: true, userText: "Xcode can regenerate this data.", technicalDetail: nil),
            ],
            executorAvailable: true
        )
        safeActions = [item]
        reviewNeeded = [
            UICandidateItem(
                id: "review.unknown", entityID: "review.unknown",
                displayName: "Unresolved Item", category: "Unknown",
                pathSummary: "…", fullPath: "/tmp/unknown",
                byteLabel: "1 MB", expectedBytes: 1_000_000,
                recommendedAction: nil, recommendedActionLabel: "Review needed",
                reasonSummary: "More evidence required",
                readiness: .verifyMore, group: .reviewNeeded,
                safetyClass: .unknown, evidenceLines: [], executorAvailable: false
            )
        ]
        protected = [
            UICandidateItem(
                id: "protected.voice", entityID: "protected.voice",
                displayName: "Voice Memos", category: "Protected",
                pathSummary: "…", fullPath: "/tmp/voice",
                byteLabel: "500 MB", expectedBytes: 500_000_000,
                recommendedAction: nil, recommendedActionLabel: "Protected",
                reasonSummary: "Source of truth protected",
                readiness: .unknown, group: .protected,
                safetyClass: .red, evidenceLines: [], executorAvailable: false
            )
        ]
        overview = StorageOverviewState(
            observedBytes: 98_000_000_000,
            observedBytesLabel: "98 GB",
            safeActionCount: 1,
            reviewCount: 1,
            protectedCount: 1,
            lastScanAt: Date(),
            scanRuntimeSeconds: 0.05
        )
        experienceSnapshot = fixtureExperienceSnapshot()
        explorerSnapshot = PreviewSnapshotFactory.explorerDemo(experience: experienceSnapshot)
        changeReport = StorageChangeService.demoChangeReport()
        historyStatus = P302HistoryStatusReport(
            historySnapshotCount: 2,
            oldestSnapshotAt: Date().addingTimeInterval(-7 * 24 * 3600),
            newestSnapshotAt: Date(),
            historyStoreLocationType: "fixture",
            snapshotWriteSuccess: true,
            privacyFieldsStored: StorageHistoryBuilder.privacyFieldsStored
        )
        optimizationPlan = try? OptimizationPlanService.demoPartialPlan()
        scanStage = .complete
    }

    private func fixtureExperienceSnapshot() -> StorageExperienceSnapshot {
        let disk = DiskCapacitySnapshot(
            volumeName: "Macintosh HD",
            volumeTotalBytes: 494_000_000_000,
            volumeAvailableBytes: 91_000_000_000,
            volumeUsedBytes: 403_000_000_000
        )
        let devNode = StorageMapNode(
            id: "category.developer",
            title: "Developer",
            bytes: 81_500_000_000,
            children: [
                StorageMapNode(
                    id: "entity.\(fixtureEntityID)",
                    entityID: fixtureEntityID,
                    title: "Xcode Build Data",
                    bytes: 36_000_000,
                    semanticCategory: .developer,
                    presentationState: .readyToOptimize,
                    isAggregate: false,
                    technicalEntityID: fixtureEntityID
                )
            ],
            semanticCategory: .developer,
            isAggregate: true,
            iconHint: "hammer"
        )
        let mapRoot = StorageMapNode(
            id: "map.root",
            title: "Macintosh HD",
            bytes: 98_000_000_000,
            children: [devNode],
            semanticCategory: .otherUnknown,
            isAggregate: true,
            iconHint: "internaldrive"
        )
        return StorageExperienceSnapshot(
            diskCapacity: disk,
            observedStorage: ObservedStorageSnapshot(
                scannedRootBytes: 98_000_000_000,
                classifiedUniqueBytes: 98_000_000_000,
                unclassifiedBytes: 0,
                selectedRootLabel: "Macintosh HD"
            ),
            mapRoot: mapRoot,
            categories: [devNode],
            insights: [],
            recommendations: [],
            needsReview: [],
            protected: [],
            recentActions: recentActions,
            readyActionCount: 1,
            readyPotentialBytes: 36_000_000,
            needsReviewCount: 1,
            needsReviewBytes: 1_000_000,
            protectedCount: 1,
            protectedBytes: 500_000_000,
            recoveryPendingBytes: 0,
            mapAccountingValid: true,
            mapRootBytes: 98_000_000_000,
            generatedAt: Date(),
            scanRuntimeSeconds: 0.05
        )
    }

    private func find(_ entityID: String) -> UICandidateItem? {
        safeActions.first { $0.entityID == entityID }
            ?? reviewNeeded.first { $0.entityID == entityID }
            ?? protected.first { $0.entityID == entityID }
    }

    private func fixtureFingerprint(entityID: String) -> ActionBindingFingerprint? {
        ActionBindingFingerprint(
            entityID: entityID,
            action: .moveToTrash,
            canonicalPath: fixturePath,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "test",
            transactionContractVersion: TransactionContractRegistry.trashVersion
        )
    }

    private func fixtureReceipt(entityID: String) -> PreflightReceipt? {
        guard let fp = fixtureFingerprint(entityID: entityID) else { return nil }
        return PreflightReceipt(
            receiptID: "fake-receipt",
            entityID: entityID,
            action: .moveToTrash,
            bindingFingerprint: fp,
            requiredClaims: [],
            satisfiedClaims: [],
            missingClaims: [],
            staleClaims: [],
            conflictedClaims: [],
            observedAt: Date(),
            freshnessValidity: [.runtimeFresh],
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            result: PreflightResultCode.satisfiedReadOnly.rawValue
        )
    }
}
