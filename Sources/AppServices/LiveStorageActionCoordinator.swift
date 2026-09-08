import Foundation
import SafetyCore

/// P2.3 — UI-facing action boundary. UI calls this; never SafetyCore mutation APIs directly.
public protocol StorageActionCoordinating: AnyObject {
    var overview: StorageOverviewState { get }
    var safeActions: [UICandidateItem] { get }
    var reviewNeeded: [UICandidateItem] { get }
    var protected: [UICandidateItem] { get }
    var recentActions: [UIActionHistoryItem] { get }
    var isScanning: Bool { get }
    var selectedCandidateID: String? { get }
    var lastPreflight: UIPreflightResult? { get }
    var pendingApproval: UIApprovalState? { get }
    var lastExecution: UIExecutionOutcome? { get }
    var lastSurfaceReport: UIActionSurfaceReport? { get }
    var experienceSnapshot: StorageExperienceSnapshot? { get }
    var explorerSnapshot: StorageExplorerSnapshot? { get }
    var changeReport: StorageChangeReport? { get }
    var historyStatus: P302HistoryStatusReport? { get }
    var optimizationPlan: OptimizationPlan? { get }
    var optimizationFacts: [OptimizationActionFact] { get }
    var scanStage: StorageScanStage { get }
    var scanProgressHandler: (@Sendable (StorageScanStage) -> Void)? { get set }

    func scan() async throws
    func expandPhysicalNode(id: String)
    func candidateDetail(entityID: String) -> UICandidateDetail?
    func runFreshPreflight(entityID: String, action: StorageAction) async throws -> UIPreflightResult
    func submitApproval(entityID: String, action: StorageAction) throws -> UIApprovalState
    func executeApprovedAction(entityID: String, action: StorageAction) async throws -> UIExecutionOutcome
    func cancelApproval()
    func writeSurfaceReport(to directory: URL) throws
    func writeExperienceReport(to directory: URL) throws
    func writeExplorerReports(to directory: URL) throws
    func writeChangeReports(to directory: URL) throws
    func writeOptimizationReports(to directory: URL) throws
}

public enum StorageActionCoordinatorError: Error, Equatable, Sendable {
    case notScanned
    case candidateNotFound
    case preflightRequired
    case approvalRequired
    case bindingChanged
    case candidateDisappeared
    case unauthorizedAction
    case executionBlocked(String)
}

/// Live coordinator — invokes canonical SafetyCore pipeline only.
public final class LiveStorageActionCoordinator: StorageActionCoordinating, @unchecked Sendable {
    public private(set) var overview: StorageOverviewState = .empty
    public private(set) var safeActions: [UICandidateItem] = []
    public private(set) var reviewNeeded: [UICandidateItem] = []
    public private(set) var protected: [UICandidateItem] = []
    public private(set) var recentActions: [UIActionHistoryItem] = []
    public private(set) var isScanning = false
    public private(set) var selectedCandidateID: String?
    public private(set) var lastPreflight: UIPreflightResult?
    public private(set) var pendingApproval: UIApprovalState?
    public private(set) var lastExecution: UIExecutionOutcome?
    public private(set) var lastSurfaceReport: UIActionSurfaceReport?
    public private(set) var experienceSnapshot: StorageExperienceSnapshot?
    public private(set) var explorerSnapshot: StorageExplorerSnapshot?
    public private(set) var changeReport: StorageChangeReport?
    public private(set) var historyStatus: P302HistoryStatusReport?
    public private(set) var optimizationPlan: OptimizationPlan?
    public private(set) var optimizationFacts: [OptimizationActionFact] = []
    public private(set) var scanStage: StorageScanStage = .idle
    public var scanProgressHandler: (@Sendable (StorageScanStage) -> Void)?
    private let historyStore: StorageHistoryStore?

    private var lastReport: ReadOnlyAnalysisReport?
    private var lastP304: P304ScanPerformanceReport?
    private var lastTrace: [ScanPerformanceSpan] = []
    private var knowledge: KnowledgeBaseDocument?
    private var gateByEntity: [String: MutationGateResult] = [:]
    private var itemByEntity: [String: ClassifiedItem] = [:]
    private let reportsDirectory: URL
    private let executor: any StorageActionExecutor
    private let lock = NSLock()

    public init(
        reportsDirectory: URL? = nil,
        executor: any StorageActionExecutor = StorageActionExecutorRouter(),
        historyStore: StorageHistoryStore? = nil
    ) {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.reportsDirectory = reportsDirectory ?? cwd.appendingPathComponent("reports/case001")
        self.executor = executor
        self.historyStore = historyStore ?? (try? StorageHistoryStore.applicationSupportStore())
    }

    public func scan() async throws {
        lock.lock()
        isScanning = true
        lock.unlock()
        defer {
            lock.lock()
            isScanning = false
            lock.unlock()
        }
        publishStage(.scanningFiles)

        let reportsDir = reportsDirectory
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        try await Task.detached { [self] in
            let started = Date()
            var telemetry = StorageExplorerTelemetry(scanStartedAt: started)
            _ = ScanSessionContext.begin()
            defer { ScanSessionContext.end() }

            let kb = try LiveStorageActionCoordinator.loadKnowledgeStatic()
            let disk = DiskCapacityReader.snapshot(at: home)
            let volumeName = disk.volumeName.isEmpty ? "Macintosh HD" : disk.volumeName
            let scanner = ReadOnlyStorageScanner()
            let snapshotID = UUID().uuidString
            let box = ProgressiveScanBox(telemetry: telemetry)
            let (physical, stats) = PhysicalHierarchyBuilder.build(
                rootPath: home,
                displayName: volumeName,
                nodeKind: .volume,
                scanner: scanner,
                onPublication: { node, pubStats, kind in
                    guard kind != .complete else { return }
                    box.telemetry.firstHierarchyAvailableAt = box.telemetry.firstHierarchyAvailableAt ?? Date()
                    if box.firstMapNodeCount == 0 {
                        box.firstMapNodeCount = pubStats.physicalNodeCount
                    }
                    box.telemetry.physicalNodeCount = pubStats.physicalNodeCount
                    box.telemetry.maxDepth = pubStats.maxDepth
                    box.telemetry.renderedNodeCount = min(pubStats.physicalNodeCount, 48)
                    box.telemetry.largestFanout = pubStats.largestFanout
                    let structure = StorageExplorerBuilder.structureSnapshot(
                        physicalRoot: node,
                        stats: pubStats,
                        disk: disk,
                        telemetry: box.telemetry,
                        snapshotID: snapshotID
                    )
                    self.publishExplorer(structure, stage: .hierarchyAvailable)
                }
            )
            telemetry = box.telemetry
            telemetry.timeToFirstHierarchyMs = stats.timeToFirstHierarchyMs
            telemetry.timeToPhysicalEnrichmentMs = stats.timeToFirstHierarchyMs
            telemetry.timeToFirstUsefulMapMs = stats.timeToFirstUsefulMapMs
            telemetry.physicalNodeCount = stats.physicalNodeCount
            telemetry.maxDepth = stats.maxDepth
            telemetry.renderedNodeCount = min(stats.physicalNodeCount, 48)
            telemetry.largestFanout = stats.largestFanout

            let structure = StorageExplorerBuilder.structureSnapshot(
                physicalRoot: physical,
                stats: stats,
                disk: disk,
                telemetry: telemetry,
                snapshotID: snapshotID
            )
            self.publishExplorer(structure, stage: .hierarchyAvailable)
            self.publishStage(.understandingStorage)

            let catalog = DetectorCatalog(proofTargets: ["derived-data"])
            self.publishStage(.checkingSafety)
            let report = ReadOnlyAnalysisPipeline(knowledge: kb, catalog: catalog).run(
                home: home,
                postMutationRegistryDirectory: reportsDir,
                reuseExistingSession: true
            )
            self.applyReport(report, knowledge: kb, structureSeed: structure, started: started)
            let falseGREEN = report.greenAudits.filter { $0.safetyClass == .green && !$0.requiredPredicatesSatisfied }.count
            let dup = report.actionSafetyEvalDedup.duplicateEvaluations
            let totalMs = Int(Date().timeIntervalSince(started) * 1000)
            self.lock.lock()
            self.lastP304 = P304ScanPerformanceBuilder.performance(
                snapshot: self.explorerSnapshot ?? structure,
                session: ScanSessionContext.current,
                totalScanMs: totalMs,
                falseGREEN: falseGREEN,
                duplicateEvaluations: dup,
                firstMapNodeCount: box.firstMapNodeCount
            )
            self.lastTrace = ScanSessionContext.current?.performanceTrace.snapshot() ?? []
            self.lock.unlock()
        }.value

        try writeSurfaceReport(to: reportsDirectory)
        try writeExperienceReport(to: reportsDirectory)
        try writeExplorerReports(to: reportsDirectory)
        try writeChangeReports(to: reportsDirectory)
        try writeOptimizationReports(to: reportsDirectory)
        publishStage(.complete)
    }

    public func expandPhysicalNode(id: String) {
        lock.lock()
        guard let snap = explorerSnapshot,
              let target = PhysicalHierarchyBuilder.node(withID: id, in: snap.physicalRoot),
              target.isDirectory,
              !target.isPackage,
              !target.isSymlink,
              !target.isRestricted
        else {
            lock.unlock()
            return
        }
        let report = lastReport
        let safe = safeActions
        let review = reviewNeeded
        let protectedItems = protected
        let history = recentActions
        let insights = experienceSnapshot?.insights ?? []
        lock.unlock()

        let expandedRoot: PhysicalStorageNode
        if ScanSessionContext.current == nil {
            _ = ScanSessionContext.begin()
            expandedRoot = PhysicalHierarchyBuilder.expand(path: target.canonicalPath, in: snap.physicalRoot)
            ScanSessionContext.end()
        } else {
            expandedRoot = PhysicalHierarchyBuilder.expand(path: target.canonicalPath, in: snap.physicalRoot)
        }
        var next = snap
        next.physicalRoot = expandedRoot
        next = StorageExplorerBuilder.enrich(
            next,
            report: report,
            safe: safe,
            review: review,
            protected: protectedItems,
            history: history,
            insights: insights,
            stage: snap.scanStage
        )
        lock.lock()
        explorerSnapshot = next
        lock.unlock()
    }

    public func candidateDetail(entityID: String) -> UICandidateDetail? {
        lock.lock()
        defer { lock.unlock() }
        selectedCandidateID = entityID
        guard let item = itemByEntity[entityID] else { return nil }
        let uiItem = findCandidate(entityID) ?? UICandidateMapper.mapItem(item, gate: gateByEntity[entityID])
        return UICandidateMapper.mapDetail(uiItem, gate: gateByEntity[entityID])
    }

    public func runFreshPreflight(entityID: String, action: StorageAction) async throws -> UIPreflightResult {
        try await Task.detached { [self] in
            try self.runFreshPreflightSync(entityID: entityID, action: action)
        }.value
    }

    public func submitApproval(entityID: String, action: StorageAction) throws -> UIApprovalState {
        lock.lock()
        defer { lock.unlock() }
        guard let preflight = lastPreflight,
              preflight.entityID == entityID,
              preflight.action == action,
              preflight.canApprove,
              let receipt = preflight.receipt,
              let fp = preflight.bindingFingerprint else {
            throw StorageActionCoordinatorError.approvalRequired
        }
        let scope: String
        switch action {
        case .vendorNativeCleanup:
            scope = "ui_ollama_vendor_native:\(OllamaNativePostMutationProbe.authorizationTextFingerprint())"
        default:
            scope = "ui_move_to_trash"
        }
        let approval = UserActionApproval(
            approvalID: "ui-approval-\(entityID)-\(UUID().uuidString.prefix(8))",
            entityID: entityID,
            action: action,
            bindingFingerprint: fp,
            consequenceSummaryVersion: action == .vendorNativeCleanup ? "P3.2A.5_UI" : "P2.3_UI",
            expectedRecoveryBytes: itemByEntity[entityID]?.verification?.uniqueBytesProven
                ?? itemByEntity[entityID]?.exclusiveBytes,
            approvedAt: Date(),
            expiryPolicy: "single_use_immediate",
            scope: scope
        )
        let state = UIApprovalState(
            approval: approval,
            receipt: receipt,
            entityID: entityID,
            action: action,
            boundAt: Date()
        )
        pendingApproval = state
        refreshSurfaceReport()
        return state
    }

    public func executeApprovedAction(entityID: String, action: StorageAction) async throws -> UIExecutionOutcome {
        try await Task.detached { [self] in
            try self.executeApprovedSync(entityID: entityID, action: action)
        }.value
    }

    public func cancelApproval() {
        lock.lock()
        pendingApproval = nil
        lastPreflight = nil
        refreshSurfaceReport()
        lock.unlock()
    }

    public func writeSurfaceReport(to directory: URL) throws {
        lock.lock()
        let report = lastSurfaceReport
        lock.unlock()
        guard let report else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: directory.appendingPathComponent("ui_action_surface.json"))
    }

    public func writeExperienceReport(to directory: URL) throws {
        lock.lock()
        let snapshot = experienceSnapshot
        lock.unlock()
        guard let snapshot else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let report = StorageExperienceBuilder.report(from: snapshot)
        try encoder.encode(report).write(to: directory.appendingPathComponent("p3_0_storage_experience.json"))
    }

    public func writeExplorerReports(to directory: URL) throws {
        lock.lock()
        let snapshot = explorerSnapshot
        let last = lastReport
        lock.unlock()
        guard let snapshot else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let falseGREEN = last?.greenAudits.filter { $0.safetyClass == .green && !$0.requiredPredicatesSatisfied }.count ?? 0
        let dup = last?.actionSafetyEvalDedup.duplicateEvaluations ?? 0
        try encoder.encode(StorageExplorerBuilder.report(from: snapshot, falseGREEN: falseGREEN, duplicateEvaluations: dup))
            .write(to: directory.appendingPathComponent("p3_0_1_storage_explorer.json"))
        try encoder.encode(StorageExplorerBuilder.performanceReport(from: snapshot))
            .write(to: directory.appendingPathComponent("p3_0_1_explorer_performance.json"))
        if let lastP304 {
            try encoder.encode(lastP304)
                .write(to: directory.appendingPathComponent("p3_0_4_scan_performance.json"))
            try encoder.encode(P304ScanPerformanceBuilder.beforeAfter(from: lastP304))
                .write(to: directory.appendingPathComponent("p3_0_4_before_after.json"))
        }
        if !lastTrace.isEmpty {
            try encoder.encode(lastTrace)
                .write(to: directory.appendingPathComponent("p3_0_4_scan_trace.json"))
        }
    }

    public func writeChangeReports(to directory: URL) throws {
        lock.lock()
        let snapshot = explorerSnapshot
        let history = recentActions
        let last = lastReport
        let store = historyStore
        lock.unlock()
        guard let snapshot else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let falseGREEN = last?.greenAudits.filter { $0.safetyClass == .green && !$0.requiredPredicatesSatisfied }.count ?? 0
        let dup = last?.actionSafetyEvalDedup.duplicateEvaluations ?? 0

        let entities: [HistoryEntitySummary] = (last?.items ?? []).prefix(80).map { item in
            HistoryEntitySummary(
                entityID: item.detected.entity.id,
                displayName: item.detected.entity.id,
                bytes: item.exclusiveBytes,
                semanticCategory: item.detected.domain,
                decisionSummary: item.decision.safetyClass.rawValue
            )
        }

        let report: StorageChangeReport
        let status: P302HistoryStatusReport
        if let store {
            let result = StorageChangeService.recordAndDiff(
                explorer: snapshot,
                store: store,
                actionHistory: history,
                entitySummaries: Array(entities),
                falseGREEN: falseGREEN,
                duplicateEvaluations: dup
            )
            report = result.report
            status = result.status
        } else {
            let hist = StorageHistoryBuilder.build(from: snapshot, actionHistory: history, entitySummaries: Array(entities))
            report = StorageSnapshotDiffEngine.compare(
                previous: nil,
                current: hist,
                falseGREEN: falseGREEN,
                duplicateEvaluations: dup
            )
            status = P302HistoryStatusReport(
                historySnapshotCount: 0,
                oldestSnapshotAt: nil,
                newestSnapshotAt: nil,
                historyStoreLocationType: "unavailable",
                snapshotWriteSuccess: false,
                privacyFieldsStored: StorageHistoryBuilder.privacyFieldsStored
            )
        }

        lock.lock()
        changeReport = report
        historyStatus = status
        lock.unlock()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(P302StorageChangeExport(from: report))
            .write(to: directory.appendingPathComponent("p3_0_2_storage_change.json"))
        try encoder.encode(status)
            .write(to: directory.appendingPathComponent("p3_0_2_history_status.json"))
    }

    public func writeOptimizationReports(to directory: URL) throws {
        lock.lock()
        let experience = experienceSnapshot
        let explorer = explorerSnapshot
        let safe = safeActions
        let review = reviewNeeded
        let protectedItems = protected
        let history = recentActions
        let change = changeReport
        let last = lastReport
        lock.unlock()

        let facts = last.map { OptimizationPlanService.extraFacts(from: $0) } ?? []
        let falseGREEN = last?.greenAudits.filter { $0.safetyClass == .green && !$0.requiredPredicatesSatisfied }.count ?? 0
        let dup = last?.actionSafetyEvalDedup.duplicateEvaluations ?? 0
        guard let goal = try? OptimizationGoal.gigabytes(20) else { return }
        let plan = OptimizationPlanService.build(
            goal: goal,
            snapshot: experience,
            explorer: explorer,
            safe: safe,
            review: review,
            protected: protectedItems,
            extraFacts: facts,
            changeReport: change,
            history: history,
            falseGREEN: falseGREEN,
            duplicateEvaluations: dup
        )
        lock.lock()
        optimizationFacts = facts
        optimizationPlan = plan
        lock.unlock()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(P303OptimizationPlanReport(from: plan))
            .write(to: directory.appendingPathComponent("p3_0_3_optimization_plan.json"))
        try encoder.encode(plan.funnel)
            .write(to: directory.appendingPathComponent("p3_0_3_candidate_funnel.json"))
    }

    // MARK: - Sync internals

    private func runFreshPreflightSync(entityID: String, action: StorageAction) throws -> UIPreflightResult {
        lock.lock()
        guard let report = lastReport, let kb = knowledge else {
            lock.unlock()
            throw StorageActionCoordinatorError.notScanned
        }
        guard let item = itemByEntity[entityID] else {
            lock.unlock()
            throw StorageActionCoordinatorError.candidateNotFound
        }
        guard action == .moveToTrash || action == .vendorNativeCleanup else {
            lock.unlock()
            throw StorageActionCoordinatorError.unauthorizedAction
        }
        if action == .vendorNativeCleanup,
           !ActionPolicy.isOllamaModelEntity(item) {
            lock.unlock()
            throw StorageActionCoordinatorError.unauthorizedAction
        }
        let gate = gateByEntity[entityID]
        let snapshot = ReadOnlyAnalysisPipeline.lastExecutionContext?.snapshotsByEntityID[entityID]
        let runtime = ReadOnlyAnalysisPipeline.lastExecutionContext?.runtimeResolutionsByEntityID[entityID]
        let decision = ReadOnlyAnalysisPipeline.lastExecutionContext?.decisionCatalog.set(for: entityID)?
            .decision(for: action)
        lock.unlock()

        guard let gate, let decision else { throw StorageActionCoordinatorError.candidateNotFound }

        let engine = SafetyRuleEngine(knowledge: kb)
        let sessionID = "ui-preflight-\(entityID)-\(Int(Date().timeIntervalSince1970))"
        let result = FreshReadOnlyPreflightEngine.run(
            sessionID: sessionID,
            item: item,
            action: action,
            scanDecision: decision,
            scanGate: gate,
            snapshot: snapshot,
            recommendation: nil,
            preflight: nil,
            scanRuntimeResolution: runtime,
            ruleVersion: kb.version,
            engine: engine
        )
        let mapped = UICandidateMapper.mapPreflight(result, action: action)
        lock.lock()
        lastPreflight = mapped
        selectedCandidateID = entityID
        refreshSurfaceReport()
        lock.unlock()
        return mapped
    }

    private func executeApprovedSync(entityID: String, action: StorageAction) throws -> UIExecutionOutcome {
        lock.lock()
        guard let report = lastReport, let kb = knowledge else {
            lock.unlock()
            throw StorageActionCoordinatorError.notScanned
        }
        guard let approvalState = pendingApproval,
              approvalState.entityID == entityID,
              approvalState.action == action else {
            lock.unlock()
            throw StorageActionCoordinatorError.approvalRequired
        }
        guard let preflight = lastPreflight,
              preflight.canApprove,
              let receipt = preflight.receipt else {
            lock.unlock()
            throw StorageActionCoordinatorError.preflightRequired
        }
        if receipt.bindingFingerprint != approvalState.approval.bindingFingerprint {
            lock.unlock()
            pendingApproval = nil
            throw StorageActionCoordinatorError.bindingChanged
        }
        guard itemByEntity[entityID] != nil else {
            lock.unlock()
            pendingApproval = nil
            lastPreflight = nil
            throw StorageActionCoordinatorError.candidateDisappeared
        }
        lock.unlock()

        // Re-run fresh preflight immediately before execution (pre-execution recheck).
        let fresh = try runFreshPreflightSync(entityID: entityID, action: action)
        guard fresh.canApprove,
              fresh.receipt?.bindingFingerprint == approvalState.approval.bindingFingerprint else {
            lock.lock()
            pendingApproval = nil
            lock.unlock()
            throw StorageActionCoordinatorError.bindingChanged
        }

        lock.lock()
        guard let item = itemByEntity[entityID],
              let gate = gateByEntity[entityID] else {
            lock.unlock()
            throw StorageActionCoordinatorError.candidateDisappeared
        }
        let snapshot = ReadOnlyAnalysisPipeline.lastExecutionContext?.snapshotsByEntityID[entityID]
        let runtime = ReadOnlyAnalysisPipeline.lastExecutionContext?.runtimeResolutionsByEntityID[entityID]
        let decision = ReadOnlyAnalysisPipeline.lastExecutionContext?.decisionCatalog.set(for: entityID)?
            .decision(for: action)
        lock.unlock()
        guard let decision else { throw StorageActionCoordinatorError.candidateDisappeared }

        let engine = SafetyRuleEngine(knowledge: kb)
        do {
            if action == .vendorNativeCleanup {
                guard ActionPolicy.isOllamaModelEntity(item) else {
                    throw ActionExecutionError.unauthorizedTarget(
                        entityID: entityID,
                        path: item.detected.entity.path
                    )
                }
                let model = ActionPolicy.ollamaCanonicalModelName(from: item)
                    ?? item.detected.entity.displayName
                let plan = DryRunActionPlanBuilder.plan(for: gate, action: .vendorNativeCleanup)
                // Re-bind permit from existing approval + fresh receipt
                guard let receipt = fresh.receipt,
                      let permit = ExecutionPermit.generate(
                        receipt: receipt,
                        approval: approvalState.approval,
                        decision: decision
                      ) else {
                    throw ActionExecutionError.permitDenied("Ollama native permit validation failed")
                }
                let cliPath = item.verification?.vendorProofNotes
                    .first(where: { $0.hasPrefix("OLLAMA_CLI_RESOLVED=") })?
                    .replacingOccurrences(of: "OLLAMA_CLI_RESOLVED=", with: "")
                let exe = OllamaModelIdentity.resolveExecutableURL(boundExecutablePath: cliPath)
                    ?? OllamaModelIdentity.resolveExecutableURL()
                guard let exe else {
                    throw ActionExecutionError.executableUnresolved("ollama")
                }
                let runner = FoundationProcessRunner()
                let before = OllamaNativePostMutationProbe.captureBefore(
                    entityID: entityID,
                    canonicalModel: model,
                    item: item,
                    cliURL: exe,
                    runner: runner
                )
                let boundRouter = StorageActionExecutorRouter(
                    trashExecutor: .shared,
                    ollamaExecutor: OllamaNativeCleanupExecutor(
                        processRunner: runner,
                        resolveExecutable: { exe }
                    )
                )
                let audit = try boundRouter.executeVendorNativeCleanup(
                    plan: plan,
                    permit: permit,
                    canonicalModel: model
                )
                let after = OllamaNativePostMutationProbe.observeAfter(
                    before: before,
                    cliURL: exe,
                    runner: runner
                )
                let post = OllamaNativePostMutationProbe.verify(
                    before: before,
                    after: after,
                    processFailed: audit.failureReason != nil,
                    contract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item)
                )
                let execReport = ActFirstMutationExecutionReport(
                    phase: "P3.2A.5",
                    outcome: post.logical == .modelRemoved ? "MODEL_REMOVED" : "MODEL_REMOVAL_NOT_VERIFIED",
                    entityID: entityID,
                    action: StorageAction.vendorNativeCleanup.rawValue,
                    path: item.detected.entity.path,
                    preflightSessionID: fresh.receipt?.receiptID,
                    approvalID: approvalState.approval.approvalID,
                    permitID: permit.permitID,
                    auditRecord: audit,
                    postVerifySteps: post.steps,
                    measuredRecoveryBytes: post.verifiedRecoveredBytes,
                    trashDestinationPath: nil,
                    executionMs: 0,
                    humanConfirmed: true,
                    executorImplemented: true,
                    destructiveActionsExecuted: audit.failureReason == nil,
                    explanation: "Ollama native cleanup via StorageActionExecutorRouter; storage=\(post.storage.rawValue)",
                    postMutationVerification: nil
                )
                let outcome = UICandidateMapper.mapExecutionOutcome(
                    report: execReport,
                    postResult: nil as PostMutationVerificationResult?,
                    error: audit.failureReason
                )
                lock.lock()
                lastExecution = outcome
                pendingApproval = nil
                lastPreflight = nil
                lock.unlock()
                return outcome
            }

            let execReport = try ActExecutionOrchestrator.executeFirstMutationTrash(
                ActExecutionOrchestrator.ExecuteInput(
                    entityID: entityID,
                    action: action,
                    item: item,
                    snapshot: snapshot,
                    scanDecision: decision,
                    scanGate: gate,
                    scanRuntimeResolution: runtime,
                    postVerifyContract: TransactionContractRegistry.postVerifyContract(for: action, item: item),
                    ruleVersion: kb.version,
                    humanConfirmed: true,
                    expectedRecoveryBytes: item.exclusiveBytes,
                    engine: engine,
                    executor: executor
                )
            )
            let outcome = UICandidateMapper.mapExecutionOutcome(
                report: execReport,
                postResult: execReport.postMutationVerification,
                error: nil
            )
            lock.lock()
            lastExecution = outcome
            pendingApproval = nil
            lastPreflight = nil
            lock.unlock()
            return outcome
        } catch let error as ActionExecutionError {
            let message = describe(error)
            let outcome = UICandidateMapper.mapExecutionOutcome(report: nil, postResult: nil, error: message)
            lock.lock()
            lastExecution = outcome
            pendingApproval = nil
            lock.unlock()
            return outcome
        }
    }

    private func applyReport(
        _ report: ReadOnlyAnalysisReport,
        knowledge: KnowledgeBaseDocument,
        structureSeed: StorageExplorerSnapshot? = nil,
        started: Date? = nil
    ) {
        let mapped = UICandidateMapper.mapReport(report)
        var items: [String: ClassifiedItem] = [:]
        for item in report.items {
            items[item.detected.entity.id] = item
        }
        itemByEntity = items
        gateByEntity = Dictionary(
            report.mutationGate.entries
                .filter {
                    $0.action == StorageAction.moveToTrash.rawValue
                        || $0.action == StorageAction.vendorNativeCleanup.rawValue
                }
                .map { ($0.entityID, $0) },
            uniquingKeysWith: { prev, latest in
                // Prefer vendor-native entry for Ollama models when both exist.
                if latest.action == StorageAction.vendorNativeCleanup.rawValue { return latest }
                if prev.action == StorageAction.vendorNativeCleanup.rawValue { return prev }
                return latest
            }
        )
        overview = mapped.overview
        safeActions = mapped.safe
        reviewNeeded = mapped.review
        protected = mapped.protected
        recentActions = mapped.history
        experienceSnapshot = StorageExperienceBuilder.build(
            report: report,
            safe: mapped.safe,
            review: mapped.review,
            protected: mapped.protected,
            history: mapped.history
        )
        lastReport = report
        self.knowledge = knowledge
        if var seed = structureSeed ?? explorerSnapshot {
            var telemetry = seed.telemetry
            let now = Date()
            telemetry.semanticEnrichmentCompleteAt = now
            telemetry.safetyAnalysisCompleteAt = now
            if let started {
                let ms = Int(now.timeIntervalSince(started) * 1000)
                telemetry.timeToSemanticEnrichmentMs = ms
                telemetry.timeToSafetyEnrichmentMs = ms
            }
            seed.telemetry = telemetry
            explorerSnapshot = StorageExplorerBuilder.enrich(
                seed,
                report: report,
                safe: mapped.safe,
                review: mapped.review,
                protected: mapped.protected,
                history: mapped.history,
                insights: experienceSnapshot?.insights ?? [],
                stage: .checkingSafety
            )
        }
        refreshSurfaceReport()
    }

    private func publishExplorer(_ snapshot: StorageExplorerSnapshot, stage: StorageScanStage) {
        lock.lock()
        explorerSnapshot = snapshot
        scanStage = stage
        let handler = scanProgressHandler
        lock.unlock()
        handler?(stage)
    }

    private func publishStage(_ stage: StorageScanStage) {
        lock.lock()
        scanStage = stage
        if var snap = explorerSnapshot {
            snap.scanStage = stage
            explorerSnapshot = snap
        }
        let handler = scanProgressHandler
        lock.unlock()
        handler?(stage)
    }

    private func refreshSurfaceReport() {
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
    }

    private func findCandidate(_ entityID: String) -> UICandidateItem? {
        safeActions.first { $0.entityID == entityID }
            ?? reviewNeeded.first { $0.entityID == entityID }
            ?? protected.first { $0.entityID == entityID }
    }

    private func loadKnowledge() throws -> KnowledgeBaseDocument {
        if let knowledge { return knowledge }
        return try Self.loadKnowledgeStatic()
    }

    private static func loadKnowledgeStatic() throws -> KnowledgeBaseDocument {
        let loader = KnowledgeBaseLoader()
        do {
            return try loader.loadBundled()
        } catch {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let candidates = [
                cwd.appendingPathComponent("knowledge/compiled/compiled_rules_v0.1.json"),
                cwd.appendingPathComponent("Sources/SafetyCore/Resources/knowledge/compiled_rules_v0.1.json"),
            ]
            guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                throw error
            }
            return try loader.load(from: url)
        }
    }

    private func describe(_ error: ActionExecutionError) -> String {
        switch error {
        case .preflightNotReady(let r): return "Safety check no longer valid: \(r)"
        case .gateNotReady(let r): return "Action not ready: \(r)"
        case .bindingPathMismatch, .entityMismatch: return "This item changed after your safety check. Nothing was moved."
        case .postVerifyFailed: return "Verification failed after move."
        case .humanConfirmationRequired: return "Explicit approval required."
        case .permitDenied(let r): return "Execution permit denied: \(r)"
        case .sourceMissing: return "This item no longer exists."
        case .trashFailed(let r): return "Trash operation failed: \(r)"
        case .unauthorizedAction, .unauthorizedTarget: return "This action is not authorized for this item."
        case .executorNotImplemented: return "Executor not implemented."
        case .planActionMismatch: return "Internal action mismatch."
        case .invalidModelIdentity: return "Model identity is invalid."
        case .executableUnresolved: return "Ollama executable could not be resolved."
        case .permitAlreadyConsumed: return "This approval was already used."
        case .processFailed(let r): return "Native process failed: \(r)"
        }
    }
}
