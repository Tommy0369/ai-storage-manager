import Foundation

public struct IdentifiedStorageCoverage: Codable, Sendable, Equatable {
    public var scannedBytes: Int64
    public var identifiedBytes: Int64
    public var unknownBytes: Int64

    public var ratio: Double {
        guard scannedBytes > 0 else { return 0 }
        return Double(identifiedBytes) / Double(scannedBytes)
    }

    public var percent: Double { min(100, ratio * 100) }
}

public struct RootCauseFinding: Codable, Sendable, Equatable {
    public var entityID: String
    public var what: String
    public var why: String
    public var canReduce: Bool
    public var ifYouDo: String
    public var potentialRecoveryBytes: Int64?
}

public struct ClassifiedItem: Codable, Sendable {
    public var detected: DetectedEntity
    public var decision: SafetyDecision
    public var semantic: SemanticResult
    public var allocatedBytes: Int64
    public var actionVariants: [String: String]
    public var inclusiveBytes: Int64
    public var exclusiveBytes: Int64
    public var resolution: ResolutionLevel
    public var unknownReason: UnknownReasonCode?
    public var verification: VerificationAnnotation?
}

public struct EvidenceResolutionReport: Codable, Sendable, Equatable {
    public var totals: [String: [String: Int]]
    public var knownRates: [String: Double]
    public var snapshotFailures: [String]
    public var unknownReasonCounts: [String: Int]
}

public struct PreviewTotals: Codable, Sendable, Equatable {
    public var greenPotentialRecovery: Int64
    public var yellowReview: Int64
    public var protectedRed: Int64
    public var unknown: Int64
    public var executable: Bool
}

public struct ReadOnlyAnalysisReport: Codable, Sendable {
    public var scannedRoots: [ScannedNode]
    public var items: [ClassifiedItem]
    public var coverage: IdentifiedStorageCoverage
    public var semanticCoverage: SemanticCoverage
    public var classTotals: [String: Int64]
    public var bucketTotals: [String: Int64]
    public var domainTotals: [String: Int64]
    public var rootCauses: [RootCauseFinding]
    public var greenAudits: [GreenAuditRecord]
    public var preview: PreviewTotals
    public var byteAccounting: ByteAccountingResult
    public var docker: DockerDetectionReport
    public var evidenceResolution: EvidenceResolutionReport
    public var domainSemanticCoverage: [DomainSemanticCoverage]
    public var largestUnresolved: [UnresolvedBucket]
    public var semanticDebtBytes: Int64
    public var scanRuntimeSeconds: Double
    public var detectionGraph: DetectionGraphReport
    public var verificationCoverage: VerificationCoverage
    public var verifiedRelationshipCoverage: VerifiedRelationshipCoverage
    public var verificationChains: [VerificationChain]
    public var knowledgeVersion: String
    public var knowledgeRuleCount: Int
    public var destructiveActionsExecuted: Bool
    public var proofRuntimeBreakdown: ProofRuntimeBreakdown
    public var cursorMetadataDiscovery: CursorMetadataDiscoveryReport
    public var observationCompleteness: ObservationCompletenessReport
    public var detectorCatalogRuntime: DetectorCatalogRuntimeReport
    public var scannerFilesystemRuntime: ScannerFilesystemRuntimeReport
    public var scannerIODuplication: ScannerIODuplicationReport
    public var sizeMeasurementCoverage: SizeMeasurementCoverageReport
    public var scannerBudgetEvents: [ScannerBudgetEvent]
    public var p19RuntimeComparison: P19RuntimeComparison
    public var entityVerificationLoop: EntityVerificationLoopReport
    public var entityVerificationBacklog: EntityVerificationBacklogReport
    public var verificationStrategyRuntime: VerificationStrategyRuntimeReport
    public var evidenceConflicts: [EvidenceConflictRecord]
    public var verificationLoopCoverage: VerificationLoopCoverageReport
    public var p110RuntimeComparison: P110RuntimeComparison
    public var classificationChangesP110: [[String: String]]
    public var actionArchitecture: ActionArchitectureReport
    public var safetyEvalRuntime: SafetyEvalRuntimeReport
    public var safetyRuleIndexStats: SafetyRuleIndexStats
    public var predicateCacheStats: PredicateCacheStats
    public var greenAuditorRuntime: GreenAuditorRuntimeReport
    public var backlogFeasibility: BacklogFeasibilityReport
    public var p111RuntimeComparison: P111RuntimeComparison
    public var p112RuntimeComparison: P112RuntimeComparison
    public var p113RuntimeComparison: P113RuntimeComparison
    public var resolverRuntime: ResolverRuntimeReport
    public var entitySnapshotRuntime: EntitySafetySnapshotRuntimeReport
    public var actionEvalRuntime: ActionEvalRuntimeReport
    public var runtimeBatchResolution: RuntimeBatchResolutionReport
    public var runtimeResolutionNeed: RuntimeResolutionNeedReport
    public var runtimeObservationIndex: RuntimeObservationIndexReport
    public var actReadiness: ActionReadinessReport
    public var mutationGate: MutationGateReport
    public var dryRunActionPlans: DryRunActionPlanReport
    public var actExecutorReadiness: ActExecutorReadinessSummary
    public var mutationSurfaceAudit: MutationSurfaceAuditReport
    public var actionSafetyEvalDedup: ActionSafetyEvalDedupReport
    public var derivedDataMutationReadiness: DerivedDataMutationReadinessReport
    public var derivedDataReadinessDiff: DerivedDataReadinessDiffReport
    public var mutationCandidateFunnel: MutationCandidateFunnelReport
    public var p201RuntimeComparison: P201RuntimeComparison
    public var p21GateStatus: P21GateStatusReport
    public var derivedDataSurfaceFunnel: DerivedDataSurfaceFunnelReport
    public var derivedDataDetectorRegistration: DerivedDataDetectorRegistrationReport
    public var derivedDataSurfaceRootCause: DerivedDataSurfaceRootCauseReport
    public var firstRealMutationGate: FirstRealMutationGateReport
    public var firstMutationCandidateInventory: FirstMutationCandidateInventoryReport
    public var firstMutationCandidateRanking: FirstMutationCandidateRankingReport
    public var firstMutationCandidateSelection: FirstMutationCandidateSelectionReport
    public var downloadsMoveToICloudAudit: DownloadsMoveToICloudAuditReport?
    public var realCandidateRevalidation: RealCandidateRevalidationReport
    public var derivedDataStrictProofChain: DerivedDataStrictProofChainReport
    public var realPreflightClosure: RealPreflightClosureReport
    public var preflightStateDelta: PreflightStateDeltaReport
    public var postMutationVerification: PostMutationVerificationReport
    public var actionHistory: ActionHistoryReport
    public var storageRecoveryVerification: StorageRecoveryVerificationReport
    public var postMutationScanSummary: PostMutationScanSummary
}

public struct StorageRecoveryVerificationReport: Codable, Sendable, Equatable {
    public var results: [StorageRecoveryResult]
    public var generatedAt: Date
}

public struct CleanupPreview: Codable, Sendable {
    public var item: SemanticResult
    public var action: ActionMode
    public var nativeHint: String?
    public var executable: Bool
}

public struct ScanExecutionContext: Sendable {
    public var snapshotsByEntityID: [String: EntitySafetySnapshot]
    public var runtimeResolutionsByEntityID: [String: RuntimeStateResolution]
    public var decisionCatalog: ActionDecisionCatalog
}

public struct ReadOnlyAnalysisPipeline {
    /// Populated after each `run()` — used by execute-trash in the same process.
    public static var lastExecutionContext: ScanExecutionContext?
    public var knowledge: KnowledgeBaseDocument
    public var scanner: ReadOnlyStorageScanner
    public var catalog: DetectorCatalog
    public var protection: UserProtectionStore
    public var processes: any ProcessRunningChecker
    public var handles: any OpenHandleChecker

    public init(
        knowledge: KnowledgeBaseDocument,
        scanner: ReadOnlyStorageScanner = ReadOnlyStorageScanner(),
        catalog: DetectorCatalog = DetectorCatalog(),
        protection: UserProtectionStore = UserProtectionStore(),
        processes: any ProcessRunningChecker = ProcessCheck(),
        handles: any OpenHandleChecker = LSOFHandleChecker()
    ) {
        self.knowledge = knowledge
        self.scanner = scanner
        self.catalog = catalog
        self.protection = protection
        self.processes = processes
        self.handles = handles
    }

    public func run(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        postMutationRegistryDirectory: URL? = nil,
        reuseExistingSession: Bool = false
    ) -> ReadOnlyAnalysisReport {
        let started = Date()
        let createdSession: Bool
        let scanSession: ScanSessionContext
        if reuseExistingSession, let existing = ScanSessionContext.current {
            scanSession = existing
            createdSession = false
        } else {
            scanSession = ScanSessionContext.begin()
            createdSession = true
        }
        defer {
            if createdSession {
                ScanSessionContext.end()
            }
        }
        _ = scanSession
        let telemetry = ProofRuntimeTelemetry()
        CursorWorkspaceIdentityResolver.lastDiscovery = nil
        VendorStorageProofIndex.reset()

        let (procCaptured, fileCaptured): (any ProcessRunningChecker, any OpenHandleChecker) = telemetry.measure("runtime_snapshots", spawn: 4) {
            if processes is ProcessCheck, handles is LSOFHandleChecker {
                // P1.7: bounded dual snapshot window (max 2) for Claude exact ACTIVE chance.
                let (p, f) = RuntimeObservationWindow.capture(snapshots: 2, gapMs: RuntimeObservationWindow.gapMs)
                return (p, f)
            }
            return (processes, handles)
        }
        let proc = procCaptured
        let file = fileCaptured
        var snapshotFailures: [String] = []
        if let p = proc as? ProcessTableSnapshot, p.snapshotFailed {
            snapshotFailures.append(p.failureReason ?? "PROCESS_SNAPSHOT_FAILED")
        }
        if let f = file as? OpenFileSnapshot, f.snapshotFailed {
            snapshotFailures.append(f.failureReason ?? "OPEN_FILE_SNAPSHOT_FAILED")
        }
        let procCompleteness = (proc as? ProcessTableSnapshot)?.completeness ?? .unknown
        let handleCompleteness = (file as? OpenFileSnapshot)?.completeness ?? .unknown
        let processFailure = (proc as? ProcessTableSnapshot)?.failureReason
        let handleFailure = (file as? OpenFileSnapshot)?.failureReason
        let resolver = EvidenceResolver(processes: proc, handles: file)
        let catalogTelemetry = DetectorCatalogTelemetry()
        let roots = telemetry.measure("scanner_filesystem_walk") { scanner.scanRoots() }
        let scannerWalkMs = telemetry.snapshot().first { $0.stage == "scanner_filesystem_walk" }?.durationMs ?? 0
        let detected = telemetry.measure("detector_catalog") {
            catalog.detectAll(home: home, scanner: scanner, telemetry: catalogTelemetry, resetCaches: false)
        }
        let detectorCatalogRuntime = DetectorCatalog.lastCatalogTelemetry ?? catalogTelemetry.snapshot()
        let sizeStats = DirectorySizeCache.stats()
        telemetry.record(ProofRuntimeStage(
            stage: "directory_measurement_cache",
            durationMs: 0,
            entityCount: detected.count,
            processSpawnCount: sizeStats.spawns,
            timeoutCount: sizeStats.timeouts,
            cacheHits: sizeStats.hits,
            note: "du cache across lightweight detectors"
        ))
        // Cursor metadata discovery already ran inside detectors via buildIndex; capture report.
        let cursorDiscovery = CursorWorkspaceIdentityResolver.lastDiscovery ?? CursorExplicitMetadataResolver.discover(home: home).report
        telemetry.record(ProofRuntimeStage(
            stage: "cursor_metadata_proof",
            durationMs: 0,
            entityCount: cursorDiscovery.verifiedMappings,
            timeoutCount: cursorDiscovery.timeouts,
            budgetExceeded: cursorDiscovery.budgetExceeded > 0,
            note: "sources=\(cursorDiscovery.metadataSourcesFound.count)"
        ))

        var draft: [(DetectedEntity, SafetyDecision, [String: String], EvidenceBundle, RuntimeState, VerificationAnnotation)] = []
        var greenAudits: [GreenAuditRecord] = []
        var evidenceTotals: [String: [String: Int]] = [:]

        let loopContext = VerificationLoopContext(
            resolver: resolver,
            processes: proc,
            handles: file,
            processCompleteness: procCompleteness,
            handleCompleteness: handleCompleteness,
            proofTargets: catalog.proofTargets
        )
        let verificationLoop = EntityVerificationLoop(
            knowledge: knowledge,
            protection: protection,
            proofTargets: catalog.proofTargets
        )
        let loopResult = telemetry.measure("entity_verification_loop", entityCount: detected.count) {
            verificationLoop.run(detected: detected, context: loopContext, telemetry: telemetry)
        }
        draft = loopResult.draft
        greenAudits = loopResult.greenAudits
        evidenceTotals = loopResult.evidenceTotals

        // P3.1.1 — late remote reacquisition proof (never on first-map critical path).
        RemoteReacquisitionProofIndex.reset()
        let remoteStage = telemetry.measure("remote_reacquisition_proof", entityCount: VendorStorageProofIndex.allInventories().reduce(0) { $0 + $1.entities.count }) { () -> Int in
            let result = RemoteReacquisitionService.proveAll(inventories: VendorStorageProofIndex.allInventories())
            RemoteRequestSession.lastStats = result.session.stats
            return result.proofs.count
        }
        _ = remoteStage
        draft = draft.map { d, decision, variants, evidence, state, verification in
            var v = verification
            if let proof = RemoteReacquisitionProofIndex.proof(for: d.entity.id) {
                RemoteReacquisitionService.apply(proof: proof, to: &v)
            } else if let semantic = VendorStorageProofIndex.lookup(pathOrID: d.entity.id)
                ?? VendorStorageProofIndex.lookup(pathOrID: d.entity.path),
                      let proof = RemoteReacquisitionProofIndex.proof(for: semantic.entityID) {
                RemoteReacquisitionService.apply(proof: proof, to: &v)
            }
            return (d, decision, variants, evidence, state, v)
        }

        telemetry.record(ProofRuntimeStage(
            stage: "entity_verification_candidate_build",
            durationMs: loopResult.loopReport.candidateBuildingMs,
            entityCount: loopResult.loopReport.candidatesDiscovered
        ))
        telemetry.record(ProofRuntimeStage(
            stage: "entity_verification_proof_execution",
            durationMs: loopResult.loopReport.proofExecutionMs,
            entityCount: loopResult.loopReport.candidatesAttempted,
            note: "yield=\(String(format: "%.2f", loopResult.loopReport.verificationYield))"
        ))
        telemetry.record(ProofRuntimeStage(
            stage: "entity_verification_safety_eval",
            durationMs: loopResult.loopReport.safetyEvaluationMs,
            entityCount: detected.count
        ))

        let inputs = draft.map { d, decision, _, evidence, _, _ in
            let predsOK = knowledge.rules.first { $0.id == decision.matchedRuleID }?.requiredPredicates
                .allSatisfy { evidence.satisfiesStrictPredicate($0) } ?? false
            let m = scanSession.measurement(for: d.entity.path)
                ?? (d.entity.logicalBytes > 0
                    ? SizeMeasurement.partial(bytes: d.entity.logicalBytes, reason: "ENTITY_LOGICAL_BYTES", method: "entity_fallback")
                    : SizeMeasurement.unknown(reason: "MEASUREMENT_NOT_RECORDED", method: "entity_fallback"))
            return AccountingInput(
                id: d.entity.id,
                path: d.entity.path,
                inclusiveBytes: m.accountingBytes,
                safetyClass: decision.safetyClass,
                resolution: ResolutionLevel.assign(entityID: d.entity.id, path: d.entity.path, predicatesAllTrue: predsOK, safetyClass: decision.safetyClass),
                measurementKnown: m.isKnown,
                measurementQuality: m.quality
            )
        }
        let accounting = telemetry.measure("byte_accounting") { ByteAccountant.account(inputs) }
        let exclusiveByPath = Dictionary(uniqueKeysWithValues: accounting.nodes.map { ($0.path, $0) })

        var items: [ClassifiedItem] = []
        var causes: [RootCauseFinding] = []
        var bucketTotals: [String: Int64] = [:]
        var domainTotals: [String: Int64] = [:]
        var unknownReasonCounts: [String: Int] = [:]
        for (d, decision, variants, evidence, _, verification) in draft {
            let node = exclusiveByPath[(d.entity.path as NSString).standardizingPath]
            let exclusive = node?.exclusiveBytes ?? 0
            let resolution = node?.resolution ?? .l2Domain
            let reason = UnknownReasonCode.classify(decision: decision, evidence: evidence, entity: d.entity)
            if let reason {
                unknownReasonCounts[reason.rawValue, default: 0] += 1
            }
            items.append(ClassifiedItem(
                detected: d,
                decision: decision,
                semantic: LLMBoundary.freeze(decision),
                allocatedBytes: exclusive,
                actionVariants: variants,
                inclusiveBytes: d.entity.logicalBytes,
                exclusiveBytes: exclusive,
                resolution: resolution,
                unknownReason: reason,
                verification: verification
            ))
            bucketTotals[d.bucket.rawValue, default: 0] += exclusive
            domainTotals[d.domain, default: 0] += exclusive
            causes.append(RootCauseFinding(
                entityID: d.entity.id,
                what: d.entity.displayName,
                why: decision.growthCauses.first ?? decision.userExplanationJA,
                canReduce: decision.safetyClass == .green || decision.safetyClass == .yellow,
                ifYouDo: decision.sideEffects.joined(separator: ", "),
                potentialRecoveryBytes: (decision.safetyClass == .green || decision.safetyClass == .yellow) ? exclusive : 0
            ))
        }

        let scannedBytes = roots.reduce(Int64(0)) { $0 + $1.logicalBytes }
        let unique = accounting.uniqueTotal
        let identified = min(unique, scannedBytes == 0 ? unique : max(unique, 0))
        let coverage = IdentifiedStorageCoverage(
            scannedBytes: scannedBytes,
            identifiedBytes: min(identified, scannedBytes),
            unknownBytes: max(0, scannedBytes - min(identified, scannedBytes))
        )
        let semantic = ByteAccountant.semanticCoverage(nodes: accounting.nodes, scannedBytes: max(scannedBytes, unique))
        let classTotals = accounting.classUnique
        let preview = PreviewTotals(
            greenPotentialRecovery: classTotals[SafetyClass.green.rawValue] ?? 0,
            yellowReview: classTotals[SafetyClass.yellow.rawValue] ?? 0,
            protectedRed: classTotals[SafetyClass.red.rawValue] ?? 0,
            unknown: classTotals[SafetyClass.unknown.rawValue] ?? 0,
            executable: false
        )

        let domainSemantic = SemanticReports.domainCoverage(items: items)
        let unresolved = SemanticReports.largestUnresolved(items: items)
        let debt = SemanticDebt.bytes(nodes: accounting.nodes)
        var knownRates: [String: Double] = [:]
        for (key, counts) in evidenceTotals {
            let total = counts.values.reduce(0, +)
            let known = (counts["true"] ?? 0) + (counts["false"] ?? 0)
            knownRates[key] = total == 0 ? 0 : Double(known) / Double(total)
        }

        let totalMs = Int(Date().timeIntervalSince(started) * 1000)
        let breakdown = ProofRuntimeBreakdown.build(stages: telemetry.snapshot(), totalMs: totalMs)
        let completeness = ObservationCompletenessReport.build(
            items: items,
            processCompleteness: procCompleteness,
            handleCompleteness: handleCompleteness,
            processFailure: processFailure,
            handleFailure: handleFailure,
            cursorDiscovery: cursorDiscovery
        )

        let scannerFilesystemRuntime = scanSession.filesystemRuntimeReport(totalMs: scannerWalkMs)
        let scannerIODuplication = scanSession.duplicationReport()
        let sizeMeasurementCoverage = ByteAccountant.measurementCoverage(
            result: accounting,
            denominatorBytes: max(scannedBytes, accounting.uniqueTotal)
        )
        let scannerBudgetEvents = scanSession.budgetEventsReport()
        let detectorMs = breakdown.stages.first { $0.stage == "detector_catalog" }?.durationMs ?? detectorCatalogRuntime.totalDurationMs
        let p19Comparison = P19RuntimeComparison(
            p18TotalSeconds: ScanSessionContext.p18Baseline.p18TotalSeconds,
            p19TotalSeconds: Date().timeIntervalSince(started),
            scannerFilesystemWalkP18Ms: ScanSessionContext.p18Baseline.scannerFilesystemWalkP18Ms,
            scannerFilesystemWalkP19Ms: scannerWalkMs,
            detectorCatalogP18Ms: ScanSessionContext.p18Baseline.detectorCatalogP18Ms,
            detectorCatalogP19Ms: detectorMs,
            duSpawnsP19: scanSession.duSpawnCount(),
            duTimeoutsP19: scanSession.duTimeoutCount(),
            duplicateMeasurementCountP19: scannerIODuplication.totalDuplicatedOperations
        )
        let loopMs = breakdown.stages.first { $0.stage == "entity_verification_loop" }?.durationMs ?? loopResult.loopReport.totalRuntimeMs
        let p111Comparison = P111RuntimeComparison(
            p110TotalSeconds: P111RuntimeComparison.p110Baseline.p110TotalSeconds,
            p111TotalSeconds: P112RuntimeComparison.p111Baseline.p111TotalSeconds,
            safetyEvalP110Ms: P111RuntimeComparison.p110Baseline.safetyEvalP110Ms,
            safetyEvalP111Ms: P112RuntimeComparison.p111Baseline.safetyEvalP111Ms,
            entityVerificationLoopP110Ms: P111RuntimeComparison.p110Baseline.entityVerificationLoopP110Ms,
            entityVerificationLoopP111Ms: P112RuntimeComparison.p111Baseline.entityVerificationLoopP111Ms
        )
        let proofMs = breakdown.stages.first { $0.stage == "entity_verification_proof_execution" }?.durationMs ?? loopResult.loopReport.proofExecutionMs
        let p112Comparison = P112RuntimeComparison(
            p111TotalSeconds: P112RuntimeComparison.p111Baseline.p111TotalSeconds,
            p112TotalSeconds: Date().timeIntervalSince(started),
            safetyEvalP111Ms: P112RuntimeComparison.p111Baseline.safetyEvalP111Ms,
            safetyEvalP112Ms: loopResult.safetyEvalRuntime.totalSafetyEvalMs,
            entityVerificationLoopP111Ms: P112RuntimeComparison.p111Baseline.entityVerificationLoopP111Ms,
            entityVerificationLoopP112Ms: loopMs,
            proofExecutionP112Ms: proofMs,
            snapshotFinalizationP112Ms: loopResult.safetyEvalRuntime.snapshotFinalizationMs,
            resolverTimeP112Ms: loopResult.resolverRuntime.resolvers.reduce(0) { $0 + $1.totalRuntimeMs },
            actionPredicateP112Ms: loopResult.safetyEvalRuntime.predicateEvaluationMs,
            greenAuditorP112Ms: loopResult.greenAuditorRuntime.totalMs,
            reportGenerationP112Ms: 0
        )
        let p110Comparison = P110RuntimeComparison(
            p19TotalSeconds: EntityVerificationLoopReport.p19Baseline.p19TotalSeconds,
            p110TotalSeconds: Date().timeIntervalSince(started),
            entityVerificationLoopP19Ms: EntityVerificationLoopReport.p19Baseline.entityVerificationLoopP19Ms,
            entityVerificationLoopP110Ms: loopMs,
            scannerFilesystemWalkP110Ms: scannerWalkMs,
            detectorCatalogP110Ms: detectorMs
        )
        let verificationLoopCoverage = VerificationLoopCoverageBuilder.build(
            items: items,
            loopReport: loopResult.loopReport,
            measurementCoverage: sizeMeasurementCoverage,
            semanticCoverage: semantic
        )
        let classificationChangesP110: [[String: String]] = []

        let actionEngine = SafetyRuleEngine(knowledge: knowledge, protection: protection)
        let userContext = ActionUserContext(wantsMoreFreeSpace: true, iCloudEnabled: nil, allowManualReview: true)
        let decisionBuildStarted = Date()
        var decisionCatalog = ActionDecisionBuilder.buildCatalog(
            items: items,
            engine: actionEngine,
            snapshotsByEntityID: loopResult.entitySnapshotsByID,
            safetyDecisionsByEntityID: loopResult.safetyDecisionsByEntityID,
            userContext: userContext
        )
        let decisionBuildMs = Int(Date().timeIntervalSince(decisionBuildStarted) * 1000)
        let actionDecisionMap = decisionCatalog.decisionMapByEntityID

        let recommendStarted = Date()
        let recommendations = ActionRecommendationEngine.recommend(items: items, decisionCatalog: decisionCatalog)
        ActionDecisionBuilder.recordReuse(&decisionCatalog.telemetry, count: items.count)
        let recommendMs = Int(Date().timeIntervalSince(recommendStarted) * 1000)

        let preflightStarted = Date()
        let preflights = ActionPreflightEngine.preview(
            items: items,
            recommendations: recommendations,
            decisionCatalog: decisionCatalog
        )
        ActionDecisionBuilder.recordReuse(&decisionCatalog.telemetry, count: items.count)
        let preflightMs = Int(Date().timeIntervalSince(preflightStarted) * 1000)

        let blocked = ActionPreflightEngine.blockedSummaries(from: recommendations)
        let iCloud = recommendations.filter {
            if case .actionable(.moveToICloud) = $0.disposition { return true }
            return $0.recommendedAction == .moveToICloud
        }
        let evict = recommendations.filter {
            if case .actionable(.removeLocalDownload) = $0.disposition { return true }
            return $0.recommendedAction == .removeLocalDownload
        }
        let actionArchitecture = ActionArchitectureReport(
            recommendations: recommendations,
            preflightPreviews: preflights,
            blockedSummaries: blocked,
            iCloudMoveCandidates: iCloud,
            removeLocalDownloadCandidates: evict,
            previewExecutable: false,
            destructiveActionsExecuted: false
        )

        let readinessStarted = Date()
        let actReadiness = ActionReadinessEngine.buildReport(
            items: items,
            recommendations: recommendations,
            snapshotsByEntityID: loopResult.entitySnapshotsByID,
            runtimeResolutions: loopResult.runtimeResolutionsByEntityID,
            preflights: preflights,
            actionDecisions: actionDecisionMap,
            ruleVersion: knowledge.version,
            runtimeGeneration: loopResult.runtimeObservationIndex.runtimeGeneration
        )
        ActionDecisionBuilder.recordReuse(&decisionCatalog.telemetry, count: items.count)
        let readinessMs = Int(Date().timeIntervalSince(readinessStarted) * 1000)

        let mutationGateStarted = Date()
        let mutationGate = MutationGate.buildReport(
            items: items,
            recommendations: recommendations,
            preflights: preflights,
            actionDecisions: actionDecisionMap,
            snapshotsByEntityID: loopResult.entitySnapshotsByID,
            runtimeResolutions: loopResult.runtimeResolutionsByEntityID,
            ruleVersion: knowledge.version,
            runtimeGeneration: loopResult.runtimeObservationIndex.runtimeGeneration
        )
        ActionDecisionBuilder.recordReuse(&decisionCatalog.telemetry, count: items.count)
        let mutationGateMs = Int(Date().timeIntervalSince(mutationGateStarted) * 1000)

        let derivedDataReadiness = DerivedDataMutationReadinessAnalyzer.analyze(
            items: items,
            decisionCatalog: decisionCatalog,
            recommendations: recommendations,
            preflights: preflights,
            snapshotsByEntityID: loopResult.entitySnapshotsByID,
            runtimeResolutions: loopResult.runtimeResolutionsByEntityID,
            runtimeIndex: loopResult.runtimeIndexHandle,
            ruleVersion: knowledge.version
        )
        let derivedDataDiff = DerivedDataMutationReadinessAnalyzer.diff(report: derivedDataReadiness, items: items)
        let candidateFunnel = MutationCandidateFunnel.build(
            items: items,
            decisionCatalog: decisionCatalog,
            recommendations: recommendations,
            preflights: preflights,
            actReadiness: actReadiness,
            mutationGate: mutationGate,
            derivedDataReport: derivedDataReadiness
        )
        let dryRunPlans = DryRunActionPlanBuilder.build(from: mutationGate)
        let actExecutorReadiness = MutationGate.summarize(mutationGate)
        let mutationSurfaceAudit = MutationSurfaceAudit.audit(repositoryRoot: FileManager.default.currentDirectoryPath)
        let surfaceAnalysis = DerivedDataSurfaceAnalyzer.analyze(
            home: home,
            items: items,
            proofTargets: catalog.proofTargets,
            catalogRuntime: detectorCatalogRuntime,
            verificationBacklog: loopResult.backlog,
            scanner: scanner
        )
        var rootCause = surfaceAnalysis.rootCause
        rootCause.architecturalFixMade = false
        let firstMutation = FirstMutationCandidateAnalyzer.analyze(
            items: items,
            decisionCatalog: decisionCatalog,
            recommendations: recommendations,
            preflights: preflights,
            snapshotsByEntityID: loopResult.entitySnapshotsByID,
            runtimeResolutions: loopResult.runtimeResolutionsByEntityID,
            mutationGate: mutationGate,
            ruleVersion: knowledge.version,
            runtimeGeneration: loopResult.runtimeObservationIndex.runtimeGeneration
        )
        let firstRealMutationGate: FirstRealMutationGateReport
        if decisionCatalog.telemetry.duplicateEvaluations > 0 || !mutationSurfaceAudit.auditPassed {
            var blocked = firstMutation.gate
            blocked.status = P21GateStatusValue.blockedByArchitecture.rawValue
            blocked.reason.append("Architecture integrity check failed")
            firstRealMutationGate = blocked
        } else {
            firstRealMutationGate = firstMutation.gate
        }
        let p21GateStatus = firstRealMutationGate.asLegacyP21
        let realCandidateRevalidation = RealCandidateRevalidationAnalyzer.analyze(
            home: home,
            funnel: surfaceAnalysis.funnel,
            readiness: derivedDataReadiness,
            gate: firstRealMutationGate,
            dedup: decisionCatalog.telemetry,
            surfaceAudit: mutationSurfaceAudit,
            scanTimestamp: Date()
        )
        let derivedDataStrictProofChain = DerivedDataStrictProofChainAnalyzer.analyze(
            items: items,
            snapshotsByEntityID: loopResult.entitySnapshotsByID,
            decisionCatalog: decisionCatalog,
            recommendations: recommendations,
            preflights: preflights,
            mutationGate: mutationGate,
            readiness: derivedDataReadiness,
            gate: firstRealMutationGate
        )
        let preflightClosure = RealPreflightClosureAnalyzer.analyze(
            items: items,
            decisionCatalog: decisionCatalog,
            recommendations: recommendations,
            preflights: preflights,
            snapshotsByEntityID: loopResult.entitySnapshotsByID,
            runtimeResolutions: loopResult.runtimeResolutionsByEntityID,
            mutationGate: mutationGate,
            inventory: firstMutation.inventory,
            ranking: firstMutation.ranking,
            selection: firstMutation.selection,
            gate: firstRealMutationGate,
            engine: actionEngine,
            ruleVersion: knowledge.version,
            processes: proc,
            handles: file
        )
        var finalMutationGate = mutationGate
        if let freshEntry = preflightClosure.freshGateEntry {
            finalMutationGate.entries.removeAll { $0.entityID == freshEntry.entityID && $0.action == freshEntry.action }
            finalMutationGate.entries.append(freshEntry)
            finalMutationGate.entries.sort { $0.entityID < $1.entityID }
        }
        let finalFirstRealMutationGate = preflightClosure.updatedGate
        let finalSelection = preflightClosure.updatedSelection
        let finalP21GateStatus = finalFirstRealMutationGate.asLegacyP21
        let totalSeconds = Date().timeIntervalSince(started)
        let p201Comparison = P201RuntimeComparison(
            p113TotalSeconds: 70.5,
            p20TotalSeconds: 117.0,
            p201TotalSeconds: totalSeconds,
            p113SafetyEvalMs: 11_300,
            p20SafetyEvalMs: 25_000,
            p201SafetyEvalMs: loopResult.safetyEvalRuntime.totalSafetyEvalMs,
            actionDecisionBuildMs: decisionBuildMs,
            recommendationMs: recommendMs,
            preflightMs: preflightMs,
            readinessMs: readinessMs,
            mutationGateMs: mutationGateMs,
            reportGenerationMs: 0,
            runtimeBatchMs: loopResult.runtimeBatchResolution.totalRuntimeResolutionMs,
            duplicateEvaluations: decisionCatalog.telemetry.duplicateEvaluations,
            decisionReuseCount: decisionCatalog.telemetry.decisionReuseCount
        )
        let activeResolverMs = loopResult.resolverRuntime.resolvers.first { $0.resolver == "active_state" }?.totalRuntimeMs ?? 0
        let p113Comparison = P113RuntimeComparison(
            p112TotalSeconds: P113RuntimeComparison.p112Baseline.p112TotalSeconds,
            p113TotalSeconds: Date().timeIntervalSince(started),
            safetyEvalP112Ms: P113RuntimeComparison.p112Baseline.safetyEvalP112Ms,
            safetyEvalP113Ms: loopResult.safetyEvalRuntime.totalSafetyEvalMs,
            snapshotFinalizationP112Ms: P113RuntimeComparison.p112Baseline.snapshotFinalizationP112Ms,
            snapshotFinalizationP113Ms: loopResult.safetyEvalRuntime.snapshotFinalizationMs,
            activeStateP112Ms: P113RuntimeComparison.p112Baseline.activeStateP112Ms,
            runtimeBatchP113Ms: loopResult.runtimeBatchResolution.totalRuntimeResolutionMs,
            runtimeIndexBuildP113Ms: loopResult.runtimeBatchResolution.indexBuildRuntimeMs,
            runtimeBatchLookupP113Ms: loopResult.runtimeBatchResolution.batchLookupRuntimeMs,
            deferPlannerP113Ms: loopResult.runtimeBatchResolution.deferPlannerMs,
            entitiesRuntimeRequiredP113: loopResult.runtimeBatchResolution.runtimeResolutionRequired,
            entitiesDeferredP113: loopResult.runtimeBatchResolution.runtimeResolutionDeferred
        )
        _ = activeResolverMs

        ReadOnlyAnalysisPipeline.lastExecutionContext = ScanExecutionContext(
            snapshotsByEntityID: loopResult.entitySnapshotsByID,
            runtimeResolutionsByEntityID: loopResult.runtimeResolutionsByEntityID,
            decisionCatalog: decisionCatalog
        )

        let postMutationBundle = PostMutationScanIntegration.reconcile(
            scanItems: items,
            registryDirectory: postMutationRegistryDirectory
        )

        return ReadOnlyAnalysisReport(
            scannedRoots: roots,
            items: items,
            coverage: coverage,
            semanticCoverage: semantic,
            classTotals: classTotals,
            bucketTotals: bucketTotals,
            domainTotals: domainTotals,
            rootCauses: causes,
            greenAudits: greenAudits,
            preview: preview,
            byteAccounting: accounting,
            docker: DockerProbe().probe(home: home),
            evidenceResolution: EvidenceResolutionReport(
                totals: evidenceTotals,
                knownRates: knownRates,
                snapshotFailures: snapshotFailures,
                unknownReasonCounts: unknownReasonCounts
            ),
            domainSemanticCoverage: domainSemantic,
            largestUnresolved: unresolved,
            semanticDebtBytes: debt,
            scanRuntimeSeconds: Date().timeIntervalSince(started),
            detectionGraph: DetectionGraphReport.build(items),
            verificationCoverage: VerificationCoverageBuilder.build(items),
            verifiedRelationshipCoverage: VerifiedRelationshipCoverage.build(items),
            verificationChains: VerificationChainBuilder.buildAll(items),
            knowledgeVersion: knowledge.version,
            knowledgeRuleCount: knowledge.rules.count,
            destructiveActionsExecuted: false,
            proofRuntimeBreakdown: breakdown,
            cursorMetadataDiscovery: cursorDiscovery,
            observationCompleteness: completeness,
            detectorCatalogRuntime: detectorCatalogRuntime,
            scannerFilesystemRuntime: scannerFilesystemRuntime,
            scannerIODuplication: scannerIODuplication,
            sizeMeasurementCoverage: sizeMeasurementCoverage,
            scannerBudgetEvents: scannerBudgetEvents,
            p19RuntimeComparison: p19Comparison,
            entityVerificationLoop: loopResult.loopReport,
            entityVerificationBacklog: loopResult.backlog,
            verificationStrategyRuntime: loopResult.strategyRuntime,
            evidenceConflicts: loopResult.conflicts,
            verificationLoopCoverage: verificationLoopCoverage,
            p110RuntimeComparison: p110Comparison,
            classificationChangesP110: classificationChangesP110,
            actionArchitecture: actionArchitecture,
            safetyEvalRuntime: loopResult.safetyEvalRuntime,
            safetyRuleIndexStats: loopResult.ruleIndexStats,
            predicateCacheStats: loopResult.predicateCacheStats,
            greenAuditorRuntime: loopResult.greenAuditorRuntime,
            backlogFeasibility: loopResult.backlogFeasibility,
            p111RuntimeComparison: p111Comparison,
            p112RuntimeComparison: p112Comparison,
            p113RuntimeComparison: p113Comparison,
            resolverRuntime: loopResult.resolverRuntime,
            entitySnapshotRuntime: loopResult.entitySnapshotRuntime,
            actionEvalRuntime: loopResult.actionEvalRuntime,
            runtimeBatchResolution: loopResult.runtimeBatchResolution,
            runtimeResolutionNeed: loopResult.runtimeResolutionNeed,
            runtimeObservationIndex: loopResult.runtimeObservationIndex,
            actReadiness: actReadiness,
            mutationGate: finalMutationGate,
            dryRunActionPlans: dryRunPlans,
            actExecutorReadiness: MutationGate.summarize(finalMutationGate),
            mutationSurfaceAudit: mutationSurfaceAudit,
            actionSafetyEvalDedup: decisionCatalog.telemetry,
            derivedDataMutationReadiness: derivedDataReadiness,
            derivedDataReadinessDiff: derivedDataDiff,
            mutationCandidateFunnel: candidateFunnel,
            p201RuntimeComparison: p201Comparison,
            p21GateStatus: finalP21GateStatus,
            derivedDataSurfaceFunnel: surfaceAnalysis.funnel,
            derivedDataDetectorRegistration: surfaceAnalysis.registration,
            derivedDataSurfaceRootCause: rootCause,
            firstRealMutationGate: finalFirstRealMutationGate,
            firstMutationCandidateInventory: firstMutation.inventory,
            firstMutationCandidateRanking: firstMutation.ranking,
            firstMutationCandidateSelection: finalSelection,
            downloadsMoveToICloudAudit: firstMutation.downloadsAudit,
            realCandidateRevalidation: realCandidateRevalidation,
            derivedDataStrictProofChain: derivedDataStrictProofChain,
            realPreflightClosure: preflightClosure.report,
            preflightStateDelta: preflightClosure.delta,
            postMutationVerification: postMutationBundle.verificationReport,
            actionHistory: postMutationBundle.actionHistory,
            storageRecoveryVerification: StorageRecoveryVerificationReport(
                results: postMutationBundle.storageRecoveryResults,
                generatedAt: postMutationBundle.verificationReport.generatedAt
            ),
            postMutationScanSummary: postMutationBundle.summary
        )
    }

    static func buildActionDecisionMap(
        items: [ClassifiedItem],
        engine: SafetyRuleEngine,
        snapshotsByEntityID: [String: EntitySafetySnapshot],
        safetyDecisionsByEntityID: [String: [ActionMode: SafetyDecision]]
    ) -> [String: [StorageAction: ActionDecision]] {
        ActionDecisionBuilder.buildCatalog(
            items: items,
            engine: engine,
            snapshotsByEntityID: snapshotsByEntityID,
            safetyDecisionsByEntityID: safetyDecisionsByEntityID
        ).decisionMapByEntityID
    }

    public func preview(for decision: SafetyDecision) -> CleanupPreview {
        let plan = ActionPlanner().plan(decision)
        return CleanupPreview(
            item: LLMBoundary.freeze(decision),
            action: decision.action,
            nativeHint: plan.nativeCommand,
            executable: false
        )
    }

    func tally(_ totals: inout [String: [String: Int]], _ evidence: EvidenceBundle) {
        func add(_ key: String, _ value: PredicateValue) {
            totals[key, default: [:]][value.rawValue, default: 0] += 1
        }
        add("canonical_path", evidence.canonicalPath.isEmpty ? .unknown : .true)
        add("symlink", evidence.isSymlink)
        add("owner", evidence.ownerIsCurrentUser)
        add("open_file", evidence.openFileHandle)
        add("process", evidence.owningProcessRunning)
        add("source_of_truth", evidence.sourceOfTruth)
        add("regenerable", evidence.regenerable)
        add("manifest", evidence.manifestExists)
        add("lockfile", evidence.lockfileExists)
        add("cloud", evidence.cloudFileProvider)
    }
}
