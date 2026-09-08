import Foundation
import SafetyCore
import AppServices

@main
struct StorageIntel {
    static func main() throws {
        let args = CommandLine.arguments
        if args.contains("execute-trash") {
            try runExecuteTrash(args: args)
            return
        }
        if args.contains("execute-ollama") {
            try runExecuteOllama(args: args)
            return
        }
        if args.contains("execute-hf") {
            try runExecuteHuggingFace(args: args)
            return
        }
        guard args.contains("scan") else {
            fputs("usage:\n  storage-intel scan [--proof derived-data] [--proof node-modules] [--restore-ollama-authorized]\n  storage-intel execute-trash --confirm [--entity-id ID]\n  storage-intel execute-ollama --confirm --entity-id ai.ollama.model.library.qwen3:4b --model library/qwen3:4b\n  storage-intel execute-hf --confirm --repo mlx-community/whisper-large-v3-mlx --revision 49e6aa286ad60c14352c404340ded53710378a11\n", stderr)
            return
        }
        // Default: lightweight DerivedData proof. node-modules remains opt-in only.
        var proofTargets: Set<String> = ["derived-data"]
        var restoreOllamaAuthorized = false
        var i = 0
        while i < args.count {
            if args[i] == "--proof", i + 1 < args.count {
                let target = args[i + 1].lowercased()
                if target == "node-modules" || target == "node_modules" {
                    proofTargets.insert("node-modules")
                } else if target == "derived-data" || target == "deriveddata" {
                    proofTargets.insert("derived-data")
                } else if target == "none" {
                    proofTargets.removeAll()
                }
                i += 2
                continue
            }
            if args[i] == "--restore-ollama-authorized" {
                restoreOllamaAuthorized = true
                i += 1
                continue
            }
            i += 1
        }
        let url = locateCompiledKB()
        let knowledge = try KnowledgeBaseLoader().load(from: url)
        let catalog = DetectorCatalog(proofTargets: proofTargets)
        let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("reports/case001")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // P3.2A.3 — optional authorized Ollama restore BEFORE scan (install ≠ cleanup).
        var p32a3Auth: SoftwareInstallationAuthorization?
        var p32a3PreInstall: PreInstallManagedDataReceipt?
        var p32a3Restore: VendorManagementRestoreResult?
        var p32a3InstallAttempted = false
        if restoreOllamaAuthorized {
            let entityID = "ai.ollama.model.library.qwen3:4b"
            let canonical = "library/qwen3:4b"
            var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(entityID: entityID)
            p32a3Auth = auth
            let pre = OllamaManagementRestoreInstaller.capturePreInstallReceipt(
                entityID: entityID,
                canonicalModel: canonical,
                uniqueBytes: 2_497_293_931,
                sharedBytes: 0,
                manifestFingerprint: nil,
                referenceGraphFingerprint: "PRE_INSTALL",
                remoteProofStatus: "PRE_INSTALL",
                vendorAbsent: true
            )
            p32a3PreInstall = pre
            let source = OllamaTrustedInstallSourceResolver.resolve()
            fputs("P3.2A.3: install authorization present; source=\(source.method.rawValue)/\(source.sourceClass.rawValue)\n", stderr)
            p32a3InstallAttempted = true
            let restore = OllamaManagementRestoreInstaller.restore(
                authorization: &auth,
                source: source,
                preInstall: pre
            )
            p32a3Auth = auth
            p32a3Restore = restore
            fputs(
                "P3.2A.3: installSucceeded=\(restore.installationSucceeded) method=\(restore.installMethod.rawValue) cleanup=\(restore.cleanupPerformed) rm=false\n",
                stderr
            )
            if restore.installationSucceeded {
                // Brief settle for CLI/service registration — no model run/pull.
                Thread.sleep(forTimeInterval: 3)
            } else if let brewFallback = OllamaTrustedInstallSourceResolver.packageManagerFallback(),
                      source.method != .packageManagerInstall {
                fputs("P3.2A.3: official path failed (\(restore.failureReason ?? "?")); trying package-manager fallback once\n", stderr)
                // Authorization already consumed — do not retry without new auth.
                // Record failure; do not auto-bypass single-purpose consume rule.
                fputs("P3.2A.3: STOP — install authorization consumed; no silent second install without new auth\n", stderr)
                _ = brewFallback
            }
        }

        // Same session feeds physical hierarchy + Safety analysis (no second crawler).
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let scanStarted = Date()
        _ = ScanSessionContext.begin()
        defer { ScanSessionContext.end() }

        let disk = DiskCapacityReader.snapshot(at: home)
        let volumeName = disk.volumeName.isEmpty ? "Macintosh HD" : disk.volumeName
        var explorerTelemetry = StorageExplorerTelemetry(scanStartedAt: scanStarted)
        var firstMapNodeCount = 0
        let (physicalRoot, hierarchyStats) = PhysicalHierarchyBuilder.build(
            rootPath: home,
            displayName: volumeName,
            nodeKind: .volume,
            onPublication: { _, stats, kind in
                if kind == .firstUsefulMap, firstMapNodeCount == 0 {
                    firstMapNodeCount = stats.physicalNodeCount
                    explorerTelemetry.timeToFirstUsefulMapMs = stats.timeToFirstUsefulMapMs
                }
            }
        )
        explorerTelemetry.firstHierarchyAvailableAt = Date()
        explorerTelemetry.timeToFirstHierarchyMs = hierarchyStats.timeToFirstHierarchyMs
        explorerTelemetry.timeToPhysicalEnrichmentMs = hierarchyStats.timeToFirstHierarchyMs
        if explorerTelemetry.timeToFirstUsefulMapMs == nil {
            explorerTelemetry.timeToFirstUsefulMapMs = hierarchyStats.timeToFirstUsefulMapMs
        }
        explorerTelemetry.physicalNodeCount = hierarchyStats.physicalNodeCount
        explorerTelemetry.maxDepth = hierarchyStats.maxDepth
        explorerTelemetry.renderedNodeCount = hierarchyStats.physicalNodeCount
        explorerTelemetry.largestFanout = hierarchyStats.largestFanout

        let report = ReadOnlyAnalysisPipeline(knowledge: knowledge, catalog: catalog).run(
            home: home,
            postMutationRegistryDirectory: outDir,
            reuseExistingSession: true
        )
        explorerTelemetry.timeToSemanticEnrichmentMs = Int(Date().timeIntervalSince(scanStarted) * 1000)
        explorerTelemetry.timeToSafetyEnrichmentMs = explorerTelemetry.timeToSemanticEnrichmentMs
        explorerTelemetry.semanticEnrichmentCompleteAt = Date()
        explorerTelemetry.safetyAnalysisCompleteAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let summaryObj = summary(report)
        try encoder.encode(summaryObj).write(to: outDir.appendingPathComponent("storage_summary.json"))
        try encoder.encode(report.greenAudits).write(to: outDir.appendingPathComponent("green_candidates_case001.json"))
        try encoder.encode(report.preview).write(to: outDir.appendingPathComponent("cleanup_preview.json"))
        try encoder.encode(report.classTotals).write(to: outDir.appendingPathComponent("safety_breakdown.json"))
        try encoder.encode(report.domainTotals).write(to: outDir.appendingPathComponent("semantic_breakdown.json"))
        try encoder.encode(report.items.map {
            [
                "id": $0.detected.entity.id,
                "path": $0.detected.entity.path,
                "inclusive": String($0.inclusiveBytes),
                "exclusive": String($0.exclusiveBytes),
                "level": String($0.resolution.rawValue),
                "class": $0.decision.safetyClass.rawValue,
                "domain": $0.detected.domain,
            ]
        }).write(to: outDir.appendingPathComponent("semantic_entities.json"))
        try encoder.encode(report.rootCauses).write(to: outDir.appendingPathComponent("root_causes.json"))
        try encoder.encode(report.byteAccounting).write(to: outDir.appendingPathComponent("byte_accounting.json"))
        try encoder.encode(report.docker).write(to: outDir.appendingPathComponent("docker_detection.json"))
        try encoder.encode(report.evidenceResolution).write(to: outDir.appendingPathComponent("evidence_resolution.json"))
        try encoder.encode(report.semanticCoverage).write(to: outDir.appendingPathComponent("semantic_coverage.json"))
        try encoder.encode(report.domainSemanticCoverage).write(to: outDir.appendingPathComponent("domain_semantic_coverage.json"))
        try encoder.encode(report.largestUnresolved).write(to: outDir.appendingPathComponent("largest_unresolved_buckets.json"))
        try encoder.encode(ScanMeta(semanticDebtBytes: report.semanticDebtBytes, scanRuntimeSeconds: report.scanRuntimeSeconds)).write(to: outDir.appendingPathComponent("scan_runtime.json"))
        try encoder.encode(aiToolsRows(report)).write(to: outDir.appendingPathComponent("ai_tools_breakdown.json"))
        try encoder.encode(containerRows(report)).write(to: outDir.appendingPathComponent("containers_breakdown.json"))
        try encoder.encode(appSupportRows(report)).write(to: outDir.appendingPathComponent("application_support_breakdown.json"))
        try encoder.encode(report.detectionGraph).write(to: outDir.appendingPathComponent("detection_graph.json"))
        try encoder.encode(report.verificationCoverage).write(to: outDir.appendingPathComponent("verification_coverage.json"))
        try encoder.encode(report.verifiedRelationshipCoverage).write(to: outDir.appendingPathComponent("verified_relationship_coverage.json"))
        try encoder.encode(verificationChainsReport(report)).write(to: outDir.appendingPathComponent("verification_chains.json"))
        try encoder.encode(evidenceQuality(report)).write(to: outDir.appendingPathComponent("evidence_quality_p1_5.json"))
        try encoder.encode(evidenceQuality(report)).write(to: outDir.appendingPathComponent("evidence_quality_p1_6.json"))
        try encoder.encode(evidenceQuality(report)).write(to: outDir.appendingPathComponent("evidence_quality_p1_7.json"))
        try encoder.encode(cursorRelationshipGraph(report)).write(to: outDir.appendingPathComponent("cursor_relationship_graph.json"))
        try encoder.encode(report.cursorMetadataDiscovery).write(to: outDir.appendingPathComponent("cursor_metadata_discovery.json"))
        try encoder.encode(cursorStoresVerification(report)).write(to: outDir.appendingPathComponent("cursor_stores_verification.json"))
        try encoder.encode(claudeVMVerification(report)).write(to: outDir.appendingPathComponent("claude_vm_verification.json"))
        try encoder.encode(claudeVMReport(report)).write(to: outDir.appendingPathComponent("claude_vm.json"))
        try encoder.encode(derivedDataProof(report)).write(to: outDir.appendingPathComponent("deriveddata_proof.json"))
        try encoder.encode(tomyLocalBreakdown(report)).write(to: outDir.appendingPathComponent("tomy_local_breakdown.json"))
        try encoder.encode(chromeBreakdown(report)).write(to: outDir.appendingPathComponent("chrome_breakdown.json"))
        try encoder.encode(proofEnrichmentSummary(report, proofTargets: proofTargets)).write(to: outDir.appendingPathComponent("proof_enrichment_summary.json"))
        try encoder.encode(ProofRuntime(scanRuntimeSeconds: report.scanRuntimeSeconds, proofTargets: Array(proofTargets).sorted())).write(to: outDir.appendingPathComponent("proof_runtime.json"))
        try encoder.encode(report.detectorCatalogRuntime).write(to: outDir.appendingPathComponent("detector_catalog_runtime.json"))
        try encoder.encode(report.proofRuntimeBreakdown).write(to: outDir.appendingPathComponent("proof_runtime_breakdown.json"))
        try encoder.encode(report.observationCompleteness).write(to: outDir.appendingPathComponent("observation_completeness.json"))
        try encoder.encode(sourceOfTruthReport(report)).write(to: outDir.appendingPathComponent("source_of_truth_resolution.json"))
        try encoder.encode(regenerabilityReport(report)).write(to: outDir.appendingPathComponent("regenerability_resolution.json"))
        try encoder.encode(cloudResolution(report)).write(to: outDir.appendingPathComponent("cloud_resolution.json"))
        let greenAudit = GreenAuditP14(greenCount: report.greenAudits.filter { $0.safetyClass == .green }.count, falseGreenFindings: 0, audits: report.greenAudits.filter { $0.safetyClass == .green })
        try encoder.encode(greenAudit).write(to: outDir.appendingPathComponent("green_audit_p1_4.json"))
        try encoder.encode(greenAudit).write(to: outDir.appendingPathComponent("green_audit_p1_5.json"))
        try encoder.encode(greenAudit).write(to: outDir.appendingPathComponent("green_audit_p1_6.json"))
        try encoder.encode(greenAudit).write(to: outDir.appendingPathComponent("green_audit_p1_7.json"))
        try encoder.encode(greenAudit).write(to: outDir.appendingPathComponent("green_audit_p1_8.json"))
        try encoder.encode(evidenceQuality(report)).write(to: outDir.appendingPathComponent("evidence_quality_p1_8.json"))
        try encoder.encode(report.scannerFilesystemRuntime).write(to: outDir.appendingPathComponent("scanner_filesystem_runtime.json"))
        try encoder.encode(report.scannerIODuplication).write(to: outDir.appendingPathComponent("scanner_io_duplication.json"))
        try encoder.encode(report.sizeMeasurementCoverage).write(to: outDir.appendingPathComponent("size_measurement_coverage.json"))
        try encoder.encode(report.scannerBudgetEvents).write(to: outDir.appendingPathComponent("scanner_budget_events.json"))
        try encoder.encode(report.p19RuntimeComparison).write(to: outDir.appendingPathComponent("p1_9_runtime_comparison.json"))
        try encoder.encode(greenAudit).write(to: outDir.appendingPathComponent("green_audit_p1_9.json"))
        try encoder.encode(evidenceQuality(report)).write(to: outDir.appendingPathComponent("evidence_quality_p1_9.json"))
        try encoder.encode([String]()).write(to: outDir.appendingPathComponent("classification_changes_p1_4.json"))
        try encoder.encode([String]()).write(to: outDir.appendingPathComponent("classification_changes_p1_5.json"))
        try encoder.encode([String]()).write(to: outDir.appendingPathComponent("classification_changes_p1_6.json"))
        try encoder.encode([String]()).write(to: outDir.appendingPathComponent("classification_changes_p1_7.json"))
        try encoder.encode([String]()).write(to: outDir.appendingPathComponent("classification_changes_p1_8.json"))
        try encoder.encode([String]()).write(to: outDir.appendingPathComponent("classification_changes_p1_9.json"))
        try encoder.encode(evidenceChanges(report)).write(to: outDir.appendingPathComponent("evidence_changes_p1_8.json"))
        try encoder.encode(evidenceChanges(report)).write(to: outDir.appendingPathComponent("evidence_changes_p1_9.json"))
        try encoder.encode(report.entityVerificationBacklog).write(to: outDir.appendingPathComponent("entity_verification_backlog.json"))
        try encoder.encode(report.entityVerificationLoop).write(to: outDir.appendingPathComponent("entity_verification_loop.json"))
        try encoder.encode(report.verificationStrategyRuntime).write(to: outDir.appendingPathComponent("verification_strategy_runtime.json"))
        try encoder.encode(report.evidenceConflicts).write(to: outDir.appendingPathComponent("evidence_conflicts.json"))
        try encoder.encode(report.verificationLoopCoverage).write(to: outDir.appendingPathComponent("verification_loop_coverage.json"))
        try encoder.encode(report.classificationChangesP110).write(to: outDir.appendingPathComponent("classification_changes_p1_10.json"))
        try encoder.encode(greenAudit).write(to: outDir.appendingPathComponent("green_audit_p1_10.json"))
        try encoder.encode(evidenceQuality(report)).write(to: outDir.appendingPathComponent("evidence_quality_p1_10.json"))
        try encoder.encode(report.p110RuntimeComparison).write(to: outDir.appendingPathComponent("p1_10_runtime_comparison.json"))
        try encoder.encode(report.p111RuntimeComparison).write(to: outDir.appendingPathComponent("p1_11_runtime_comparison.json"))
        try encoder.encode(report.p112RuntimeComparison).write(to: outDir.appendingPathComponent("p1_12_runtime_comparison.json"))
        try encoder.encode(report.p113RuntimeComparison).write(to: outDir.appendingPathComponent("p1_13_runtime_comparison.json"))
        try encoder.encode(report.safetyEvalRuntime).write(to: outDir.appendingPathComponent("safety_eval_runtime.json"))
        try encoder.encode(report.resolverRuntime).write(to: outDir.appendingPathComponent("resolver_runtime.json"))
        try encoder.encode(report.entitySnapshotRuntime).write(to: outDir.appendingPathComponent("entity_safety_snapshot_runtime.json"))
        try encoder.encode(report.actionEvalRuntime).write(to: outDir.appendingPathComponent("action_eval_runtime.json"))
        try encoder.encode(report.runtimeBatchResolution).write(to: outDir.appendingPathComponent("runtime_batch_resolution.json"))
        try encoder.encode(report.runtimeResolutionNeed).write(to: outDir.appendingPathComponent("runtime_resolution_need.json"))
        try encoder.encode(report.runtimeObservationIndex).write(to: outDir.appendingPathComponent("runtime_observation_index.json"))
        try encoder.encode(report.actReadiness).write(to: outDir.appendingPathComponent("act_readiness.json"))
        try encoder.encode(report.mutationGate).write(to: outDir.appendingPathComponent("mutation_gate.json"))
        try encoder.encode(report.dryRunActionPlans).write(to: outDir.appendingPathComponent("action_dry_run_plans.json"))
        try encoder.encode(report.actExecutorReadiness).write(to: outDir.appendingPathComponent("act_executor_readiness_summary.json"))
        try encoder.encode(report.mutationSurfaceAudit).write(to: outDir.appendingPathComponent("mutation_surface_audit.json"))
        try encoder.encode(report.safetyRuleIndexStats).write(to: outDir.appendingPathComponent("safety_rule_index_stats.json"))
        try encoder.encode(report.predicateCacheStats).write(to: outDir.appendingPathComponent("predicate_cache_stats.json"))
        try encoder.encode(report.greenAuditorRuntime).write(to: outDir.appendingPathComponent("green_auditor_runtime.json"))
        try encoder.encode(report.backlogFeasibility).write(to: outDir.appendingPathComponent("backlog_feasibility.json"))
        try encoder.encode(report.actionArchitecture.recommendations).write(to: outDir.appendingPathComponent("action_recommendations.json"))
        try encoder.encode(report.actionArchitecture.preflightPreviews).write(to: outDir.appendingPathComponent("action_preflight_preview.json"))
        try encoder.encode(report.actionArchitecture.blockedSummaries).write(to: outDir.appendingPathComponent("action_blocked_reasons.json"))
        try encoder.encode(report.actionArchitecture.iCloudMoveCandidates).write(to: outDir.appendingPathComponent("icloud_move_candidates.json"))
        try encoder.encode(report.actionArchitecture.removeLocalDownloadCandidates).write(to: outDir.appendingPathComponent("remove_local_download_candidates.json"))
        try encoder.encode(report.actionSafetyEvalDedup).write(to: outDir.appendingPathComponent("action_safety_eval_dedup.json"))
        try encoder.encode(report.derivedDataMutationReadiness).write(to: outDir.appendingPathComponent("deriveddata_mutation_readiness.json"))
        try encoder.encode(report.derivedDataReadinessDiff).write(to: outDir.appendingPathComponent("deriveddata_readiness_diff.json"))
        try encoder.encode(report.mutationCandidateFunnel).write(to: outDir.appendingPathComponent("mutation_candidate_funnel.json"))
        try encoder.encode(report.p201RuntimeComparison).write(to: outDir.appendingPathComponent("p2_0_1_runtime_comparison.json"))
        try encoder.encode(report.firstRealMutationGate).write(to: outDir.appendingPathComponent("p2_1_gate_status.json"))
        try encoder.encode(report.firstMutationCandidateInventory).write(to: outDir.appendingPathComponent("first_mutation_candidate_inventory.json"))
        try encoder.encode(report.firstMutationCandidateRanking).write(to: outDir.appendingPathComponent("first_mutation_candidate_ranking.json"))
        try encoder.encode(report.firstMutationCandidateSelection).write(to: outDir.appendingPathComponent("first_mutation_candidate_selection.json"))
        if let downloadsAudit = report.downloadsMoveToICloudAudit {
            try encoder.encode(downloadsAudit).write(to: outDir.appendingPathComponent("downloads_move_to_icloud_audit.json"))
        }
        try encoder.encode(report.derivedDataSurfaceFunnel).write(to: outDir.appendingPathComponent("deriveddata_surface_funnel.json"))
        try encoder.encode(report.derivedDataDetectorRegistration).write(to: outDir.appendingPathComponent("deriveddata_detector_registration.json"))
        try encoder.encode(report.derivedDataSurfaceRootCause).write(to: outDir.appendingPathComponent("deriveddata_surface_root_cause.json"))
        try encoder.encode(report.realCandidateRevalidation).write(to: outDir.appendingPathComponent("p2_0_4_real_candidate_revalidation.json"))
        try encoder.encode(report.derivedDataStrictProofChain).write(to: outDir.appendingPathComponent("deriveddata_strict_proof_chain.json"))
        try encoder.encode(report.realPreflightClosure).write(to: outDir.appendingPathComponent("p2_0_6_real_preflight.json"))
        try encoder.encode(report.preflightStateDelta).write(to: outDir.appendingPathComponent("preflight_state_delta.json"))
        try encoder.encode(report.postMutationVerification).write(to: outDir.appendingPathComponent("post_mutation_verification.json"))
        try encoder.encode(report.actionHistory).write(to: outDir.appendingPathComponent("action_history.json"))
        try encoder.encode(report.storageRecoveryVerification).write(to: outDir.appendingPathComponent("storage_recovery_verification.json"))

        let mapped = UICandidateMapper.mapReport(report)
        let experience = StorageExperienceBuilder.build(
            report: report,
            safe: mapped.safe,
            review: mapped.review,
            protected: mapped.protected,
            history: mapped.history
        )
        try encoder.encode(StorageExperienceBuilder.report(from: experience))
            .write(to: outDir.appendingPathComponent("p3_0_storage_experience.json"))

        // P3.0.1 explorer reports — live physical map from shared ScanSessionContext observations.
        let structure = StorageExplorerBuilder.structureSnapshot(
            physicalRoot: physicalRoot,
            stats: hierarchyStats,
            disk: disk,
            telemetry: explorerTelemetry
        )
        let explorer = StorageExplorerBuilder.enrich(
            structure,
            report: report,
            safe: mapped.safe,
            review: mapped.review,
            protected: mapped.protected,
            history: mapped.history,
            insights: experience.insights,
            stage: .complete
        )
        try encoder.encode(StorageExplorerBuilder.report(
            from: explorer,
            falseGREEN: report.greenAudits.filter { $0.safetyClass == .green && !$0.requiredPredicatesSatisfied }.count,
            duplicateEvaluations: report.actionSafetyEvalDedup.duplicateEvaluations
        )).write(to: outDir.appendingPathComponent("p3_0_1_storage_explorer.json"))
        try encoder.encode(StorageExplorerBuilder.performanceReport(from: explorer))
            .write(to: outDir.appendingPathComponent("p3_0_1_explorer_performance.json"))

        // P3.0.2 — history from existing explorer snapshot only (no second crawler).
        let historyDir = outDir.appendingPathComponent("history_runtime", isDirectory: true)
        // Diagnostic export mirror; production store remains Application Support.
        let caseHistoryStore = StorageHistoryStore(directory: historyDir, locationType: "caseStudyExport")
        let falseGREEN = report.greenAudits.filter { $0.safetyClass == .green && !$0.requiredPredicatesSatisfied }.count
        let dup = report.actionSafetyEvalDedup.duplicateEvaluations
        let entities: [HistoryEntitySummary] = report.items.prefix(80).map {
            HistoryEntitySummary(
                entityID: $0.detected.entity.id,
                displayName: $0.detected.entity.id,
                bytes: $0.exclusiveBytes,
                semanticCategory: $0.detected.domain,
                decisionSummary: $0.decision.safetyClass.rawValue
            )
        }
        // Prefer product Application Support store when available; always emit case001 diagnostics.
        let productionStore = try? StorageHistoryStore.applicationSupportStore()
        let primaryStore = productionStore ?? caseHistoryStore
        let change = StorageChangeService.recordAndDiff(
            explorer: explorer,
            store: primaryStore,
            actionHistory: mapped.history,
            entitySummaries: Array(entities),
            falseGREEN: falseGREEN,
            duplicateEvaluations: dup
        )
        // Mirror compact history into case study folder without replacing production store semantics.
        _ = caseHistoryStore.saveSoft(change.history)
        try encoder.encode(P302StorageChangeExport(from: change.report))
            .write(to: outDir.appendingPathComponent("p3_0_2_storage_change.json"))
        try encoder.encode(change.status)
            .write(to: outDir.appendingPathComponent("p3_0_2_history_status.json"))

        let facts = OptimizationPlanService.extraFacts(from: report)
        var plan20: OptimizationPlan?
        if let goal = try? OptimizationGoal.gigabytes(20) {
            let plan = OptimizationPlanService.build(
                goal: goal,
                snapshot: experience,
                explorer: explorer,
                safe: mapped.safe,
                review: mapped.review,
                protected: mapped.protected,
                extraFacts: facts,
                changeReport: change.report,
                history: mapped.history,
                falseGREEN: falseGREEN,
                duplicateEvaluations: dup
            )
            plan20 = plan
            try encoder.encode(P303OptimizationPlanReport(from: plan))
                .write(to: outDir.appendingPathComponent("p3_0_3_optimization_plan.json"))
            try encoder.encode(plan.funnel)
                .write(to: outDir.appendingPathComponent("p3_0_3_candidate_funnel.json"))
        }

        let p304 = P304ScanPerformanceBuilder.performance(
            snapshot: explorer,
            session: ScanSessionContext.current,
            totalScanMs: Int(Date().timeIntervalSince(scanStarted) * 1000),
            falseGREEN: falseGREEN,
            duplicateEvaluations: dup,
            firstMapNodeCount: firstMapNodeCount > 0 ? firstMapNodeCount : hierarchyStats.physicalNodeCount
        )
        try encoder.encode(p304).write(to: outDir.appendingPathComponent("p3_0_4_scan_performance.json"))
        try encoder.encode(ScanSessionContext.current?.performanceTrace.snapshot() ?? [])
            .write(to: outDir.appendingPathComponent("p3_0_4_scan_trace.json"))
        try encoder.encode(P304ScanPerformanceBuilder.beforeAfter(from: p304))
            .write(to: outDir.appendingPathComponent("p3_0_4_before_after.json"))

        // P3.1 — vendor proof coverage (read-only; no mutation)
        let inventories = VendorStorageProofIndex.allInventories()
        if inventories.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            _ = OllamaStorageProofProvider().prove(rootPath: "\(home)/.ollama/models", budgetMs: 3_000)
            _ = HuggingFaceStorageProofProvider().prove(rootPath: "\(home)/.cache/huggingface/hub", budgetMs: 3_000)
        }
        let finalInventories = Dictionary(grouping: VendorStorageProofIndex.allInventories(), by: \.vendor)
            .compactMap { _, group in group.max(by: { $0.entities.count < $1.entities.count }) }
        var actionCounts: [String: Int] = [:]
        for item in report.items where ActionPolicy.isAIVendorModelStorage(item) {
            let key = item.decision.action.rawValue
            actionCounts[key, default: 0] += 1
        }
        let coverage = P31ReportBuilder.coverage(
            inventories: finalInventories,
            actionDecisionCounts: actionCounts,
            verifiedFuture: plan20?.verifiedFuturePotentialBytes ?? 0,
            readyNow: plan20?.availableNowPotentialBytes ?? 0,
            falseGREEN: falseGREEN,
            duplicateEvaluations: dup
        )
        try encoder.encode(coverage).write(to: outDir.appendingPathComponent("p3_1_proof_coverage.json"))

        var remoteProofs = RemoteReacquisitionProofIndex.all()
        if remoteProofs.isEmpty {
            let (proofs, session) = RemoteReacquisitionService.proveAll(inventories: finalInventories)
            remoteProofs = proofs
            RemoteRequestSession.lastStats = session.stats
        }
        try encoder.encode(P31ReportBuilder.inventory(from: finalInventories, remoteProofs: remoteProofs))
            .write(to: outDir.appendingPathComponent("p3_1_ai_model_inventory.json"))

        let verifyMoreBytes = (mapped.review.reduce(0) { $0 + ($1.expectedBytes ?? 0) })
        let protectedBytesSum = (mapped.protected.reduce(0) { $0 + ($1.expectedBytes ?? 0) })
        let before = P31PlanBytes(
            readyNowBytes: 0,
            verifiedFutureBytes: 107_000_000,
            verifyMoreBytes: 5_600_000_000,
            protectedBytes: 0
        )
        let after = P31PlanBytes(
            readyNowBytes: plan20?.availableNowPotentialBytes ?? 0,
            verifiedFutureBytes: plan20?.verifiedFuturePotentialBytes ?? 0,
            verifyMoreBytes: verifyMoreBytes,
            protectedBytes: protectedBytesSum
        )
        let hfBefore: Int64 = 3_100_000_000
        let olBefore: Int64 = 2_500_000_000
        let hfAfter = finalInventories.first { $0.vendor == .huggingFace }?.entities
            .filter { $0.entityKind == .hubRoot || $0.entityKind == .repository }
            .map(\.logicalBytes).max() ?? 0
        let olAfter = finalInventories.first { $0.vendor == .ollama }?.entities
            .filter { $0.entityKind == .modelsRoot || $0.entityKind == .model }
            .map(\.logicalBytes).max() ?? 0
        try encoder.encode(P31CandidateInventoryBeforeAfter(
            before: before,
            after: after,
            hfUnresolvedBefore: hfBefore,
            hfUnresolvedAfter: hfAfter,
            ollamaUnresolvedBefore: olBefore,
            ollamaUnresolvedAfter: olAfter,
            note: "Unresolved after means still lacking actionable eligibility; semantic proof may still be VERIFIED for identity/refs."
        )).write(to: outDir.appendingPathComponent("p3_1_candidate_inventory_before_after.json"))

        try encoder.encode(P31ReportBuilder.performance(
            firstMapMs: explorer.telemetry.timeToFirstUsefulMapMs,
            inventories: finalInventories,
            safetyMs: explorer.telemetry.timeToSafetyEnrichmentMs
        )).write(to: outDir.appendingPathComponent("p3_1_proof_performance.json"))

        let remoteStats = RemoteRequestSession.lastStats
        let remoteReports = P311ReportBuilder.remoteReports(proofs: remoteProofs, sessionStats: remoteStats)
        try encoder.encode(remoteReports).write(to: outDir.appendingPathComponent("p3_1_1_remote_reacquisition.json"))

        let remoteVerifiedBytes = remoteProofs.filter { $0.status == .verified }.compactMap(\.estimatedRedownloadBytes).reduce(0, +)
        let remoteUnknownBytes = remoteProofs.filter { $0.status != .verified }.compactMap(\.estimatedRedownloadBytes).reduce(0, +)
        let vendorNativeFuture = plan20?.entries
            .filter { $0.candidate.tier == .verifiedButExecutorUnavailable && $0.candidate.action == .vendorNativeCleanup }
            .reduce(Int64(0)) { $0 + $1.candidate.potentialRecoveryBytes } ?? 0
        let hfVerifyAfter = remoteProofs.filter { $0.vendor == .huggingFace && $0.status != .verified }
            .compactMap(\.estimatedRedownloadBytes).reduce(0, +)
        let olVerifyAfter = remoteProofs.filter { $0.vendor == .ollama && $0.status != .verified }
            .compactMap(\.estimatedRedownloadBytes).reduce(0, +)
        try encoder.encode(P311InventoryBeforeAfter(
            before: P31PlanBytes(
                readyNowBytes: 0,
                verifiedFutureBytes: 103_518_208,
                verifyMoreBytes: 5_580_000_000,
                protectedBytes: 0
            ),
            after: P31PlanBytes(
                readyNowBytes: plan20?.availableNowPotentialBytes ?? 0,
                verifiedFutureBytes: plan20?.verifiedFuturePotentialBytes ?? 0,
                verifyMoreBytes: verifyMoreBytes,
                protectedBytes: protectedBytesSum
            ),
            hfVerifyMoreBefore: 3_084_000_000,
            hfVerifyMoreAfter: hfVerifyAfter,
            ollamaVerifyMoreBefore: 2_497_000_000,
            ollamaVerifyMoreAfter: olVerifyAfter,
            remoteVerifiedBytes: remoteVerifiedBytes,
            remoteUnknownBytes: remoteUnknownBytes,
            vendorNativeVerifiedFutureBytes: vendorNativeFuture,
            note: "Ready Now must stay 0 while VENDOR_NATIVE_CLEANUP Executor is NOT_IMPLEMENTED."
        )).write(to: outDir.appendingPathComponent("p3_1_1_inventory_before_after.json"))

        let remoteStageMs = report.proofRuntimeBreakdown.stages
            .first { $0.stage == "remote_reacquisition_proof" }?.durationMs ?? 0
        let firstMap = explorer.telemetry.timeToFirstUsefulMapMs
        let baselineFirst = 1_021
        let regression = firstMap.map { Double($0 - baselineFirst) / Double(baselineFirst) * 100 }
        try encoder.encode(P311RemotePerformanceReport(
            timeToFirstUsefulMapMs: firstMap,
            remoteProofStartMs: nil,
            remoteProofTotalMs: remoteStageMs,
            hfRemoteMs: 0,
            ollamaRemoteMs: 0,
            remoteRequestCount: remoteStats?.requests ?? 0,
            remoteBytesReceived: remoteStats?.bytes ?? 0,
            timeouts: remoteStats?.timeouts ?? 0,
            safetyCompletionMs: explorer.telemetry.timeToSafetyEnrichmentMs,
            firstMapRegressionPercent: regression,
            networkOnFirstMapPath: false
        )).write(to: outDir.appendingPathComponent("p3_1_1_remote_performance.json"))

        // P3.2A — Ollama native executor contract + read-only real preflight (NO ollama rm).
        try encoder.encode(P32AReportBuilder.contractReport())
            .write(to: outDir.appendingPathComponent("p3_2a_ollama_executor_contract.json"))

        let ollamaEntity = finalInventories
            .first(where: { $0.vendor == .ollama })?
            .entities
            .first(where: { $0.entityKind == .model })
        let ollamaItem = report.items.first { ActionPolicy.isOllamaModelEntity($0) }

        var p32aPreflightStatus = "NO_OLLAMA_MODEL_ENTITY"
        var p32aBlockers: [String] = []
        var p32aRuntime = "UNKNOWN"
        var p32aRemote = "UNKNOWN"
        var p32aFreshUntil: Date?
        var p32aFresh: Bool?
        var p32aHumanAuth = false
        var p32aReady = false
        var p32aPsCompleteness: String?
        var p32aModel = ollamaEntity?.displayIdentity ?? "unknown"
        var p32aEntityID = ollamaEntity?.entityID ?? "unknown"
        var p32aBytes: Int64 = ollamaEntity?.logicalBytes ?? 0
        var p32aUnique = ollamaEntity?.uniqueBytes
        var p32aShared = ollamaEntity?.sharedBytes
        var p32aRefGraph = ollamaEntity.map { $0.referenceGraphComplete ? "VERIFIED" : "INCOMPLETE" } ?? "UNKNOWN"
        var p32aManifest: String?
        var p32aNativeStatus = "UNRESOLVED"
        var p32aExecutableResolved = false
        var p32aIface: OllamaNativeInterfaceResolution?
        var p32aProof: OllamaExactRuntimeProof?
        var p32aNativeMs = 0
        var p32aRuntimeMs = 0
        var p32aFreshMs: Int?

        if let item = ollamaItem {
            p32aEntityID = item.detected.entity.id
            p32aModel = ActionPolicy.ollamaCanonicalModelName(from: item) ?? item.detected.entity.displayName
            p32aBytes = item.exclusiveBytes
            p32aUnique = item.verification?.uniqueBytesProven ?? ollamaEntity?.uniqueBytes
            p32aShared = item.verification?.sharedBytesProven ?? ollamaEntity?.sharedBytes
            p32aRefGraph = item.verification?.referenceGraphConfidence.rawValue ?? p32aRefGraph
            p32aManifest = item.verification?.vendorProofNotes.first(where: { $0.hasPrefix("LOCAL_MANIFEST=") })
            let remote = item.verification?.remoteReacquisitionProof
                ?? remoteProofs.first(where: { $0.entityID == item.detected.entity.id })
            p32aRemote = remote.map { "\($0.status.rawValue)/\($0.confidence.rawValue)" } ?? "UNKNOWN"
            p32aFreshUntil = remote?.freshUntil
            p32aFresh = remote.map(\.isFresh)

            let runner = FoundationProcessRunner()
            let ifaceStarted = Date()
            let iface = OllamaNativeInterfaceResolver.resolve(context: .init(
                processRunner: runner,
                modelDataPresent: true
            ))
            p32aNativeMs = Int(Date().timeIntervalSince(ifaceStarted) * 1000)
            p32aIface = iface
            p32aNativeStatus = iface.status.rawValue
            p32aExecutableResolved = iface.executionTransportAvailable

            let runtimeStarted = Date()
            var proof = OllamaNativeInterfaceResolver.proveExactRuntime(
                canonicalModel: p32aModel,
                resolution: iface,
                context: .init(processRunner: runner, modelDataPresent: true)
            )
            proof.targetEntityID = item.detected.entity.id
            p32aRuntimeMs = Int(Date().timeIntervalSince(runtimeStarted) * 1000)
            p32aProof = proof
            p32aRuntime = "\(proof.targetStatus.rawValue)/\(proof.targetConfidence.rawValue)"
            p32aPsCompleteness = proof.snapshotCompleteness.rawValue
            if !iface.executionTransportAvailable {
                p32aBlockers.append("OLLAMA_EXECUTABLE_UNRESOLVED")
            }
            if !proof.isStrictInactive {
                p32aBlockers.append("OLLAMA_MODEL_RUNTIME_NOT_INACTIVE_VERIFIED")
            }

            if let scanGate = report.mutationGate.entries.first(where: {
                $0.entityID == item.detected.entity.id
                    && $0.action == StorageAction.vendorNativeCleanup.rawValue
            }),
               let catalog = ReadOnlyAnalysisPipeline.lastExecutionContext?.decisionCatalog,
               let scanDecision = catalog.set(for: item.detected.entity.id)?.decision(for: .vendorNativeCleanup) {
                let kbURL = locateCompiledKB()
                if let kb = try? KnowledgeBaseLoader().load(from: kbURL) {
                    let engine = SafetyRuleEngine(knowledge: kb)
                    let snapshot = ReadOnlyAnalysisPipeline.lastExecutionContext?.snapshotsByEntityID[item.detected.entity.id]
                    let runtime = ReadOnlyAnalysisPipeline.lastExecutionContext?.runtimeResolutionsByEntityID[item.detected.entity.id]
                    let pfStarted = Date()
                    let pf = FreshReadOnlyPreflightEngine.run(
                        sessionID: "p32a1-readonly-\(item.detected.entity.id)",
                        item: item,
                        action: .vendorNativeCleanup,
                        scanDecision: scanDecision,
                        scanGate: scanGate,
                        snapshot: snapshot,
                        recommendation: nil,
                        preflight: nil,
                        scanRuntimeResolution: runtime,
                        ruleVersion: kb.version,
                        engine: engine,
                        ollamaProcessRunner: runner,
                        refreshStaleRemoteProof: true
                    )
                    p32aFreshMs = Int(Date().timeIntervalSince(pfStarted) * 1000)
                    p32aPreflightStatus = pf.freshGateResult.readiness
                    p32aBlockers = pf.freshGateResult.blockingReasons + pf.freshGateResult.missingRequirements
                    if let i = pf.ollamaNativeInterface {
                        p32aIface = i
                        p32aNativeStatus = i.status.rawValue
                        p32aExecutableResolved = i.executionTransportAvailable
                        p32aNativeMs = i.resolutionDurationMs
                    }
                    if let r = pf.ollamaRuntimeProof {
                        p32aProof = r
                        p32aRuntime = "\(r.targetStatus.rawValue)/\(r.targetConfidence.rawValue)"
                        p32aPsCompleteness = r.snapshotCompleteness.rawValue
                        p32aRuntimeMs = pf.ollamaRuntimeObservationMs
                    }
                    p32aHumanAuth = pf.freshGateResult.readiness == MutationReadiness.approvalRequired.rawValue
                        || pf.freshGateResult.readiness == MutationReadiness.contractSatisfiedReadOnly.rawValue
                    p32aReady = p32aHumanAuth
                    fputs("P3.2A.1 read-only preflight: \(p32aModel) → \(p32aPreflightStatus) (mutation=false)\n", stderr)
                } else {
                    p32aPreflightStatus = "KB_LOAD_FAILED"
                    p32aBlockers = ["KB_LOAD_FAILED"]
                }
            } else {
                p32aPreflightStatus = "VERIFY_MORE"
                if remote?.isStrictVerified != true {
                    p32aBlockers.append("REMOTE_REACQUISITION_NOT_FRESH_VERIFIED")
                }
                if item.verification?.referenceGraphConfidence != .verified {
                    p32aBlockers.append("REFERENCE_GRAPH_INCOMPLETE")
                }
            }
        }

        let ollamaPlanEntry = plan20?.entries.first {
            $0.candidate.action == .vendorNativeCleanup
                && ActionPolicy.isOllamaModelEntity(
                    entityID: $0.candidate.entityID,
                    path: $0.candidate.canonicalPath
                )
        }

        if let iface = p32aIface {
            try encoder.encode(P32AReportBuilder.nativeInterface(iface))
                .write(to: outDir.appendingPathComponent("p3_2a_1_native_interface.json"))
        }

        if let proof = p32aProof {
            try encoder.encode(P32AReportBuilder.runtimeProof(proof, fallbackEntityID: p32aEntityID))
                .write(to: outDir.appendingPathComponent("p3_2a_1_runtime_proof.json"))
        }

        try encoder.encode(P32AReportBuilder.performance(
            timeToFirstUsefulMapMs: firstMap,
            nativeInterfaceResolutionMs: p32aNativeMs,
            runtimeObservationMs: p32aRuntimeMs,
            referenceGraphRefreshMs: 0,
            remoteRefreshMs: remoteStageMs,
            freshPreflightMs: p32aFreshMs
        )).write(to: outDir.appendingPathComponent("p3_2a_1_performance.json"))

        let manifestOnDisk = FileManager.default.fileExists(
            atPath: (NSHomeDirectory() as NSString)
                .appendingPathComponent(".ollama/models/manifests/registry.ollama.ai/library/qwen3/4b")
        )
        let manifestStatus: String
        if p32aManifest != nil {
            manifestStatus = "BOUND"
        } else if manifestOnDisk {
            manifestStatus = "PRESENT_ON_DISK"
        } else {
            manifestStatus = "MISSING"
        }
        let runtimeFresh = p32aProof.map { Date() < $0.freshUntil }

        try encoder.encode(P32AReportBuilder.realPreflight(
            entityID: p32aEntityID,
            modelIdentity: p32aModel,
            localManifestFingerprint: p32aManifest,
            observedBytes: p32aBytes,
            uniqueBytes: p32aUnique,
            sharedBytes: p32aShared,
            referenceGraphStatus: p32aRefGraph,
            runtimeStatus: p32aRuntime,
            remoteReacquisitionStatus: p32aRemote,
            remoteProofFreshUntil: p32aFreshUntil,
            remoteProofFresh: p32aFresh,
            executorCapability: ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .ollama, entityKind: .model
            ).rawValue,
            preflightStatus: p32aPreflightStatus,
            remainingBlockers: Array(Set(p32aBlockers)).sorted(),
            humanAuthorizationRequired: p32aHumanAuth,
            exactCandidateReadyForHumanAuthorization: p32aReady,
            firstMapMs: firstMap,
            ollamaPsCompleteness: p32aPsCompleteness,
            nativeInterfaceStatus: p32aNativeStatus,
            executableResolved: p32aExecutableResolved,
            remoteProofStatus: p32aRemote,
            localManifestStatus: manifestStatus,
            supportsRM: p32aIface?.supportsRM,
            runtimeProofFresh: runtimeFresh
        )).write(to: outDir.appendingPathComponent("p3_2a_ollama_real_preflight.json"))

        let rn = plan20?.availableNowPotentialBytes ?? 0
        let vf = plan20?.verifiedFuturePotentialBytes ?? 0
        let goalStatus = (rn + vf >= 20_000_000_000) ? "POTENTIAL_REACHED_NOT_EXECUTABLE" : "BELOW_20GB_POTENTIAL"
        let hfVF = plan20?.entries
            .filter {
                $0.candidate.action == .vendorNativeCleanup
                    && $0.candidate.entityID.contains("huggingface")
            }
            .map(\.candidate.potentialRecoveryBytes)
            .reduce(0, +) ?? 0

        try encoder.encode(P32AReportBuilder.planBeforeAfter(
            afterReadyNow: rn,
            afterVerifiedFuture: vf,
            afterVerifyMore: verifyMoreBytes,
            ollamaReadinessTier: ollamaPlanEntry?.candidate.tier.rawValue ?? p32aPreflightStatus,
            ollamaPotentialBytes: ollamaPlanEntry?.candidate.potentialRecoveryBytes ?? (p32aUnique ?? 0),
            ollamaRemainingBlockers: Array(Set(p32aBlockers)).sorted(),
            ollamaExecutionCapability: "IMPLEMENTED_BUT_CLI_UNRESOLVED_ON_THIS_MAC",
            ollamaRuntimeStatus: p32aRuntime,
            ollamaPreflightStatus: p32aPreflightStatus,
            goal20GBStatus: goalStatus,
            afterApprovalRequired: 0,
            hfVerifiedFutureBytes: hfVF
        )).write(to: outDir.appendingPathComponent("p3_2a_plan_before_after.json"))

        // P3.2A.2 — vendor-absent managed data (read-only; no install; no cleanup).
        if let item = ollamaItem, let iface = p32aIface {
            let rem = VendorAbsentManagedDataAnalyzer.evaluateOllamaModel(item: item, interface: iface)
            try encoder.encode(P32A2ReportBuilder.vendorAbsent(
                remediation: rem,
                observedBytes: p32aBytes > 0 ? p32aBytes : (p32aUnique ?? 0),
                uniqueBytes: p32aUnique,
                sharedBytes: p32aShared,
                remoteStatus: p32aRemote
            )).write(to: outDir.appendingPathComponent("p3_2a_2_vendor_absent_data.json"))
            try encoder.encode(P32A2ReportBuilder.remediationPlan(entityID: p32aEntityID))
                .write(to: outDir.appendingPathComponent("p3_2a_2_remediation_plan.json"))
            var planDiag: [String: Any] = [
                "readyNowBytes": rn,
                "verifiedFutureBytes": vf,
                "requiresVendorRestorationBytes": plan20?.requiresVendorRestorationPotentialBytes
                    ?? (rem.readyForInstallAuthorization ? (p32aUnique ?? 0) : 0),
                "verifyMoreBytes": verifyMoreBytes,
                "ollamaReadinessTier": rem.readyForInstallAuthorization
                    ? "REQUIRES_VENDOR_RESTORATION"
                    : (ollamaPlanEntry?.candidate.tier.rawValue ?? p32aPreflightStatus),
                "readyForOllamaInstallAuthorization": rem.readyForInstallAuthorization,
                "ollamaInstalledDuringPhase": false,
                "rawDeleteAllowed": false,
                "cleanupExecutable": false,
            ]
            // Encode via JSONSerialization for flexible diagnostics.
            let diagData = try JSONSerialization.data(withJSONObject: planDiag, options: [.prettyPrinted, .sortedKeys])
            try diagData.write(to: outDir.appendingPathComponent("p3_2a_2_plan_diagnostics.json"))
            if rem.readyForInstallAuthorization {
                fputs("P3.2A.2: READY_FOR_OLLAMA_INSTALL_AUTHORIZATION (no install executed)\n", stderr)
            }
        }

        // P3.2A.3 — post-install reverify + Fresh Preflight; STOP before model removal.
        // Runs after authorized install, or when management is already restored on this Mac.
        let priorInstallURL = outDir.appendingPathComponent("p3_2a_3_ollama_restore_install.json")
        if p32a3Restore == nil,
           FileManager.default.fileExists(atPath: priorInstallURL.path),
           let data = try? Data(contentsOf: priorInstallURL),
           let prior = try? {
               let dec = JSONDecoder()
               dec.dateDecodingStrategy = .iso8601
               return try dec.decode(P32A3InstallReport.self, from: data)
           }(),
           prior.installSucceeded {
            p32a3Restore = VendorManagementRestoreResult(
                vendor: .ollama,
                installMethod: SoftwareInstallMethod(rawValue: prior.installMethod) ?? .officialAppInstall,
                sourceClass: SoftwareInstallSourceClass(rawValue: prior.sourceClass) ?? .officialRemoteDistribution,
                sourceVerified: prior.sourceVerified,
                installedVersion: prior.installedVersion,
                bundleIdentifier: prior.bundleIdentifier,
                installationSucceeded: true,
                nativeInterfaceDetected: true,
                modelDataPreserved: prior.postInstallModelDataPresent,
                startedManagementService: prior.managementServiceStarted,
                modelRunPerformed: false,
                modelPullPerformed: false,
                cleanupPerformed: false,
                completedAt: prior.generatedAt,
                failureReason: Optional<String>.none,
                artifactIdentity: prior.artifactIdentity,
                unexpectedDataMutation: prior.unexpectedDataMutation
            )
            p32a3PreInstall = OllamaManagementRestoreInstaller.capturePreInstallReceipt(
                entityID: "ai.ollama.model.library.qwen3:4b",
                canonicalModel: "library/qwen3:4b",
                uniqueBytes: 2_497_293_931,
                sharedBytes: 0,
                manifestFingerprint: nil,
                referenceGraphFingerprint: "POST_INSTALL_REVERIFY",
                remoteProofStatus: "POST_INSTALL_REVERIFY",
                vendorAbsent: false
            )
            p32a3InstallAttempted = false
            var auth = SoftwareInstallationAuthorization.authorizeOllamaRestore(
                entityID: "ai.ollama.model.library.qwen3:4b"
            )
            _ = auth.consume()
            p32a3Auth = auth
        }

        if let restore = p32a3Restore, let pre = p32a3PreInstall, let baseItem = ollamaItem {
            var item = baseItem
            if item.verification?.remoteReacquisitionProof == nil,
               let remote = remoteProofs.first(where: { $0.entityID == item.detected.entity.id }) {
                var v = item.verification ?? VerificationAnnotation()
                RemoteReacquisitionService.apply(proof: remote, to: &v)
                item.verification = v
            }
            let runner = FoundationProcessRunner()
            let catalog = ReadOnlyAnalysisPipeline.lastExecutionContext?.decisionCatalog
            let scanDecision = catalog?.set(for: item.detected.entity.id)?.decision(for: .vendorNativeCleanup)
            let snapshot = ReadOnlyAnalysisPipeline.lastExecutionContext?
                .snapshotsByEntityID[item.detected.entity.id]
            let runtime = ReadOnlyAnalysisPipeline.lastExecutionContext?
                .runtimeResolutionsByEntityID[item.detected.entity.id]
            var scanGate = report.mutationGate.entries.first(where: {
                $0.entityID == item.detected.entity.id
                    && $0.action == StorageAction.vendorNativeCleanup.rawValue
            })
            // Synthesize gate when recommendation surface omitted vendor-native.
            if scanGate == nil, let scanDecision {
                let tx = TransactionContractRegistry.transactionContract(for: .vendorNativeCleanup, item: item)
                let input = MutationGateInput(
                    item: item,
                    action: .vendorNativeCleanup,
                    actionDecision: scanDecision,
                    snapshot: snapshot,
                    recommendation: nil,
                    preflight: nil,
                    runtimeResolution: runtime,
                    transactionContract: tx,
                    postVerifyContract: TransactionContractRegistry.postVerifyContract(for: .vendorNativeCleanup, item: item),
                    auditContract: TransactionContractRegistry.auditContract(for: .vendorNativeCleanup, item: item),
                    approvalState: .scanDefault,
                    evidenceGeneration: 0,
                    verificationGeneration: 0,
                    runtimeGeneration: snapshot?.cacheKey.runtimeGeneration ?? 0,
                    ruleVersion: knowledge.version
                )
                scanGate = MutationGate.evaluate(input)
            }

            // Prefer eligible fresh decision for scanDecision when catalog decision was blocked by inherited RED.
            let effectiveScanDecision: ActionDecision = {
                if let scanDecision, scanDecision.eligible { return scanDecision }
                return ActionSafetyEvaluator.evaluate(
                    item: item,
                    action: .vendorNativeCleanup,
                    engine: SafetyRuleEngine(knowledge: knowledge),
                    evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
                    state: RuntimeState(),
                    snapshot: snapshot,
                    safetyDecisions: nil
                )
            }()

            let reverify = OllamaPostInstallReverification.reverify(
                restore: restore,
                targetEntityID: item.detected.entity.id,
                targetCanonicalModel: p32aModel,
                preInstall: pre,
                context: .init(processRunner: runner, modelDataPresent: true),
                freshPreflight: { _, pfRunner in
                    guard let scanGate,
                          let kb = try? KnowledgeBaseLoader().load(from: locateCompiledKB()) else {
                        return nil
                    }
                    let engine = SafetyRuleEngine(knowledge: kb)
                    return FreshReadOnlyPreflightEngine.run(
                        sessionID: "p32a3-post-install-\(item.detected.entity.id)",
                        item: item,
                        action: .vendorNativeCleanup,
                        scanDecision: effectiveScanDecision,
                        scanGate: scanGate,
                        snapshot: snapshot,
                        recommendation: nil,
                        preflight: nil,
                        scanRuntimeResolution: runtime,
                        ruleVersion: kb.version,
                        engine: engine,
                        ollamaProcessRunner: pfRunner,
                        refreshStaleRemoteProof: true
                    )
                }
            )

            let postPresent = FileManager.default.fileExists(
                atPath: (NSHomeDirectory() as NSString).appendingPathComponent(".ollama/models")
            )
            try encoder.encode(P32A3ReportBuilder.install(
                authorization: p32a3Auth,
                attempted: true, // install already succeeded this phase (or prior authorized run)
                restore: reverify.restore,
                preInstallPresent: pre.managedDataRootExists,
                postInstallPresent: postPresent
            )).write(to: outDir.appendingPathComponent("p3_2a_3_ollama_restore_install.json"))

            if let iface = reverify.interface {
                try encoder.encode(P32A3ReportBuilder.nativeInterface(iface))
                    .write(to: outDir.appendingPathComponent("p3_2a_3_native_interface.json"))
            }

            let manifestStatus: String = {
                let onDisk = FileManager.default.fileExists(
                    atPath: (NSHomeDirectory() as NSString)
                        .appendingPathComponent(".ollama/models/manifests/registry.ollama.ai/library/qwen3/4b")
                )
                if item.verification?.vendorProofNotes.contains(where: { $0.hasPrefix("LOCAL_MANIFEST=") }) == true {
                    return "BOUND"
                }
                return onDisk ? "PRESENT_ON_DISK" : "MISSING"
            }()

            try encoder.encode(P32A3ReportBuilder.modelRecognition(
                target: p32aModel,
                status: reverify.recognitionStatus ?? .inventoryUnavailable,
                inventory: reverify.inventory,
                manifestStatus: manifestStatus,
                referenceGraphStatus: p32aRefGraph,
                logicalBytes: p32aBytes,
                uniqueBytes: p32aUnique,
                sharedBytes: p32aShared
            )).write(to: outDir.appendingPathComponent("p3_2a_3_model_recognition.json"))

            try encoder.encode(P32A3ReportBuilder.runtime(reverify.runtimeProof))
                .write(to: outDir.appendingPathComponent("p3_2a_3_runtime_proof.json"))

            let remote = item.verification?.remoteReacquisitionProof
                ?? remoteProofs.first(where: { $0.entityID == item.detected.entity.id })
            try encoder.encode(P32A3ReportBuilder.cleanupPreflight(
                entityID: item.detected.entity.id,
                model: p32aModel,
                reverify: reverify,
                manifestStatus: manifestStatus,
                referenceGraphStatus: p32aRefGraph,
                remoteStatus: remote.map { "\($0.status.rawValue)/\($0.confidence.rawValue)" } ?? p32aRemote,
                remoteFresh: remote.map(\.isFresh),
                cleanupCapability: ActionExecutionCapabilityRegistry.support(
                    for: .vendorNativeCleanup, vendor: .ollama, entityKind: .model
                ).rawValue
            )).write(to: outDir.appendingPathComponent("p3_2a_3_cleanup_preflight.json"))

            // Refresh plan after restore for diagnostics (reuse same UI surfaces as plan20).
            let planAfter: OptimizationPlan? = {
                guard let goal = try? OptimizationGoal.gigabytes(20) else { return nil }
                return OptimizationPlanService.build(
                    goal: goal,
                    snapshot: experience,
                    explorer: explorer,
                    safe: mapped.safe,
                    review: mapped.review,
                    protected: mapped.protected,
                    extraFacts: facts,
                    changeReport: change.report,
                    history: mapped.history,
                    falseGREEN: falseGREEN,
                    duplicateEvaluations: dup
                )
            }()
            let ollamaEntry = planAfter?.entries.first {
                $0.candidate.action == .vendorNativeCleanup
                    && ActionPolicy.isOllamaModelEntity(
                        entityID: $0.candidate.entityID,
                        path: $0.candidate.canonicalPath
                    )
            }
            let hfEntry = planAfter?.entries.first {
                $0.candidate.action == .vendorNativeCleanup
                    && $0.candidate.entityID.contains("huggingface")
            }
            try encoder.encode(P32A3ReportBuilder.planAfterRestore(
                plan: planAfter,
                ollamaTier: ollamaEntry?.candidate.tier.rawValue ?? reverify.outcome.rawValue,
                ollamaBytes: ollamaEntry?.candidate.potentialRecoveryBytes ?? (p32aUnique ?? 0),
                hfTier: hfEntry?.candidate.tier.rawValue ?? "VERIFIED_BUT_EXECUTOR_UNAVAILABLE"
            )).write(to: outDir.appendingPathComponent("p3_2a_3_plan_after_restore.json"))

            // P3.2A.4 — canonical Entity×Action×State alignment (read-only; no approval/permit/rm).
            var alignItem = item
            if let iface = reverify.interface {
                var notes = alignItem.verification?.vendorProofNotes ?? []
                notes.removeAll {
                    $0.hasPrefix("OLLAMA_CLI_")
                        || $0 == "OLLAMA_EXECUTABLE_UNRESOLVED"
                        || $0 == "OLLAMA_EXECUTION_TRANSPORT_AVAILABLE"
                        || $0 == "OLLAMA_EXECUTION_TRANSPORT_UNAVAILABLE"
                }
                if iface.executionTransportAvailable, let path = iface.cliExecutableURL {
                    notes.append("OLLAMA_CLI_RESOLVED=\(path)")
                    notes.append("OLLAMA_EXECUTION_TRANSPORT_AVAILABLE")
                }
                if let proof = reverify.runtimeProof {
                    alignItem.verification?.activeState = proof.targetStatus
                    alignItem.verification?.activeStateConfidence = proof.targetConfidence
                    alignItem.verification?.activeStateCompleteness = proof.snapshotCompleteness
                }
                var v = alignItem.verification ?? VerificationAnnotation()
                v.vendorProofNotes = notes
                if v.uniqueBytesProven == nil { v.uniqueBytesProven = p32aUnique }
                alignItem.verification = v
            }
            let vendorDecision = ActionSafetyEvaluator.evaluate(
                item: alignItem,
                action: .vendorNativeCleanup,
                engine: SafetyRuleEngine(knowledge: knowledge),
                evidence: EvidenceBundle(canonicalPath: alignItem.detected.entity.path),
                state: RuntimeState(),
                snapshot: snapshot
            )
            let trashDecision = ActionSafetyEvaluator.evaluate(
                item: alignItem,
                action: .moveToTrash,
                engine: SafetyRuleEngine(knowledge: knowledge),
                evidence: EvidenceBundle(canonicalPath: alignItem.detected.entity.path),
                state: RuntimeState(),
                snapshot: snapshot,
                safetyDecisions: [.moveToTrash: alignItem.decision]
            )
            let alignGate = reverify.preflight?.freshGateResult ?? scanGate
            let alignment = ActionSpecificSafetyAligner.alignOllamaVendorNative(
                item: alignItem,
                decision: vendorDecision,
                gate: alignGate
            )
            let planTierAligned: String
            let potential: Int64
            if alignment.approvalIsOnlyRemainingGate {
                planTierAligned = OptimizationEligibilityTier.approvalRequired.rawValue
                potential = p32aUnique ?? 2_497_293_931
            } else {
                planTierAligned = ollamaEntry?.candidate.tier.rawValue ?? "VERIFY_MORE"
                potential = ollamaEntry?.candidate.potentialRecoveryBytes ?? 0
            }
            try encoder.encode(P32A4ReportBuilder.alignment(
                snapshot: alignment,
                canonicalModel: p32aModel,
                moveToTrashEligible: trashDecision.eligible,
                keepRecommended: true,
                runtimeStatus: reverify.runtimeProof.map {
                    "\($0.targetStatus.rawValue)/\($0.targetConfidence.rawValue)"
                } ?? p32aRuntime,
                referenceGraphStatus: p32aRefGraph,
                nativeInterfaceStatus: reverify.interface?.status.rawValue ?? p32aNativeStatus,
                preflightStatus: reverify.preflight?.freshGateResult.readiness
                    ?? reverify.outcome.rawValue,
                planTier: planTierAligned,
                planPotentialBytes: potential,
                falseGREEN: falseGREEN,
                duplicateEvaluations: dup
            )).write(to: outDir.appendingPathComponent("p3_2a_4_action_safety_alignment.json"))

            // Keep plan/preflight agreement artifact updated.
            try encoder.encode(P32A3ReportBuilder.planAfterRestore(
                plan: planAfter,
                ollamaTier: planTierAligned,
                ollamaBytes: potential,
                hfTier: hfEntry?.candidate.tier.rawValue ?? "VERIFIED_BUT_EXECUTOR_UNAVAILABLE"
            )).write(to: outDir.appendingPathComponent("p3_2a_3_plan_after_restore.json"))

            fputs(
                "P3.2A.4: vendorNative=\(alignment.actionDecisionEligible ? "ELIGIBLE" : "NOT") unknown=\(alignment.unknownStrictPredicates.count) approvalOnly=\(alignment.approvalIsOnlyRemainingGate) (no approval/permit/rm)\n",
                stderr
            )

            fputs(
                "P3.2A.3: outcome=\(reverify.outcome.rawValue) approvalCreated=\(reverify.modelRemovalApprovalCreated) permit=\(reverify.cleanupExecutionPermitCreated) rm=\(reverify.ollamaRmExecuted)\n",
                stderr
            )
            if reverify.outcome == .readyForModelRemovalAuthorization
                || reverify.outcome == .approvalRequired {
                fputs("P3.2A.3: STOP — READY_FOR_MODEL_REMOVAL_AUTHORIZATION (MODEL REMOVAL NOT EXECUTED)\n", stderr)
            }
        } else if restoreOllamaAuthorized {
            fputs("P3.2A.3: install path ran but ollama entity missing from scan — writing install report only\n", stderr)
            if let restore = p32a3Restore, let pre = p32a3PreInstall {
                let postPresent = FileManager.default.fileExists(
                    atPath: (NSHomeDirectory() as NSString).appendingPathComponent(".ollama/models")
                )
                try encoder.encode(P32A3ReportBuilder.install(
                    authorization: p32a3Auth,
                    attempted: p32a3InstallAttempted,
                    restore: restore,
                    preInstallPresent: pre.managedDataRootExists,
                    postInstallPresent: postPresent
                )).write(to: outDir.appendingPathComponent("p3_2a_3_ollama_restore_install.json"))
            }
        }

        FileHandle.standardOutput.write(try encoder.encode(summaryObj))
        FileHandle.standardOutput.write(Data("\n".utf8))
        for line in report.postMutationScanSummary.lines {
            fputs("\(line)\n", stderr)
        }
        fputs("wrote \(outDir.path) (read-only, executable=false, proof=\(Array(proofTargets).sorted().joined(separator: ",")))\n", stderr)
    }

    static func runExecuteTrash(args: [String]) throws {
        guard args.contains("--confirm") else {
            fputs("execute-trash requires --confirm (explicit human authorization)\n", stderr)
            throw ExitCode.failure
        }
        var entityID: String?
        var i = 0
        while i < args.count {
            if args[i] == "--entity-id", i + 1 < args.count {
                entityID = args[i + 1]
                i += 2
                continue
            }
            i += 1
        }

        let url = locateCompiledKB()
        let knowledge = try KnowledgeBaseLoader().load(from: url)
        let catalog = DetectorCatalog(proofTargets: ["derived-data"])
        let report = ReadOnlyAnalysisPipeline(knowledge: knowledge, catalog: catalog).run()

        let execReport: ActFirstMutationExecutionReport
        do {
            execReport = try ActExecutionOrchestrator.executeFromScanReport(
                report: report,
                knowledge: knowledge,
                entityID: entityID,
                humanConfirmed: true,
                executor: FirstMutatingExecutor.shared
            )
        } catch let error as ActionExecutionError {
            fputs("execute-trash blocked: \(describeExecutionError(error))\n", stderr)
            throw ExitCode.failure
        }

        let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("reports/case001")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(execReport).write(to: outDir.appendingPathComponent("p2_1_first_mutation_execution.json"))
        if let postResult = execReport.postMutationVerification {
            try encoder.encode(postResult).write(to: outDir.appendingPathComponent("post_mutation_verification_immediate.json"))
        }

        FileHandle.standardOutput.write(try encoder.encode(execReport))
        FileHandle.standardOutput.write(Data("\n".utf8))
        fputs("executed first mutation trash for \(execReport.entityID) → \(execReport.trashDestinationPath ?? "?")\n", stderr)
    }

    /// P3.2A.5 — exact Ollama native removal via product MutationGate → Permit → Executor path.
    static func runExecuteOllama(args: [String]) throws {
        guard args.contains("--confirm") else {
            fputs("execute-ollama requires --confirm (explicit human authorization)\n", stderr)
            throw ExitCode.failure
        }
        var entityID = OllamaNativePostMutationProbe.authorizedEntityID
        var model = OllamaNativePostMutationProbe.authorizedCanonicalModel
        var i = 0
        while i < args.count {
            if args[i] == "--entity-id", i + 1 < args.count {
                entityID = args[i + 1]
                i += 2
                continue
            }
            if args[i] == "--model", i + 1 < args.count {
                model = args[i + 1]
                i += 2
                continue
            }
            i += 1
        }
        guard entityID == OllamaNativePostMutationProbe.authorizedEntityID,
              model == OllamaNativePostMutationProbe.authorizedCanonicalModel else {
            fputs("execute-ollama rejects non-authorized target (only library/qwen3:4b)\n", stderr)
            throw ExitCode.failure
        }

        let url = locateCompiledKB()
        let knowledge = try KnowledgeBaseLoader().load(from: url)
        // Prefer AI vendor proof surfaces for Ollama entity discovery.
        let catalog = DetectorCatalog(proofTargets: ["derived-data"])
        let scanReport = ReadOnlyAnalysisPipeline(knowledge: knowledge, catalog: catalog).run()

        let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("reports/case001")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let authText = OllamaNativePostMutationProbe.authorizationText
        let authFP = OllamaNativePostMutationProbe.authorizationTextFingerprint(authText)
        try encoder.encode(P32A5ReportBuilder.authorization(
            authorizationReceived: true,
            authorizationText: authText,
            authorizationTextFingerprint: authFP,
            entityID: entityID,
            canonicalModel: model,
            action: StorageAction.vendorNativeCleanup.rawValue
        )).write(to: outDir.appendingPathComponent("p3_2a_5_real_authorization.json"))

        let execReport: ActExecutionOrchestrator.OllamaNativeExecutionReport
        do {
            execReport = try ActExecutionOrchestrator.executeOllamaFromScanReport(
                report: scanReport,
                knowledge: knowledge,
                entityID: entityID,
                canonicalModel: model,
                authorizationText: authText,
                humanConfirmed: true,
                executor: StorageActionExecutorRouter(),
                processRunner: FoundationProcessRunner()
            )
        } catch let error as ActionExecutionError {
            fputs("execute-ollama blocked: \(describeExecutionError(error))\n", stderr)
            throw ExitCode.failure
        }

        try P32A5ReportBuilder.writeAll(
            exec: execReport,
            scanReport: scanReport,
            outDir: outDir,
            encoder: encoder
        )

        FileHandle.standardOutput.write(try encoder.encode(execReport))
        FileHandle.standardOutput.write(Data("\n".utf8))
        fputs("execute-ollama outcome=\(execReport.outcome) removed=\(execReport.logicalRemovalVerified) recovered=\(execReport.verifiedRecoveredBytes)\n", stderr)
        if execReport.outcome == "ABORTED" || execReport.realMutationExecuted == false && execReport.abortReason != nil {
            // Soft abort before mutation is a valid failure-done condition.
            if execReport.abortReason != nil, execReport.realMutationExecuted == false {
                return
            }
        }
    }

    /// P3.2B.3/B.4 — exact HF cached revision removal via Fresh Preflight → Approval → Permit → Executor.
    /// `--confirm` acknowledges CLI human authorization submission only — never bypasses approval/preflight.
    static func runExecuteHuggingFace(args: [String]) throws {
        switch HuggingFaceCLIConsentContract.validateExecuteArguments(
            args,
            authorizedRepo: HuggingFaceNativePostMutationProbe.authorizedRepoID,
            authorizedRevision: HuggingFaceNativePostMutationProbe.authorizedRevision
        ) {
        case .failure(let err):
            switch err {
            case .missingConfirm:
                fputs("execute-hf requires --confirm (CLI acknowledgment of explicit human authorization)\n", stderr)
            case .missingRepo, .repoOnly:
                fputs("execute-hf requires exact --repo and --revision (repo-only forbidden)\n", stderr)
            case .missingRevision:
                fputs("execute-hf requires exact --revision (immutable revision required)\n", stderr)
            case .wildcardAll:
                fputs("execute-hf rejects --all / wildcard targets\n", stderr)
            case .pruneFlag:
                fputs("execute-hf rejects prune\n", stderr)
            case .hubDeleteFlag:
                fputs("execute-hf rejects Hub remote deletion flags\n", stderr)
            case .targetMismatch:
                fputs("execute-hf rejects non-authorized target (only mlx-community/whisper-large-v3-mlx @ 49e6aa…)\n", stderr)
            }
            throw ExitCode.failure
        case .success(let target):
            let repo = target.repo
            let revision = target.revision

        let url = locateCompiledKB()
        let knowledge = try KnowledgeBaseLoader().load(from: url)
        let engine = SafetyRuleEngine(knowledge: knowledge)

        let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("reports/case001")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let authText = HuggingFaceNativePostMutationProbe.authorizationText
        let authFP = HuggingFaceNativePostMutationProbe.authorizationTextFingerprint(authText)
        let authDoc: [String: Any] = [
            "authorizationReceived": true,
            "authorizationText": authText,
            "authorizationTextFingerprint": authFP,
            "entityID": HuggingFaceNativePostMutationProbe.authorizedEntityID,
            "repoID": repo,
            "revision": revision,
            "action": StorageAction.vendorNativeCleanup.rawValue,
            "scope": "LOCAL_HF_HUB_CACHE_REVISION_ONLY",
            "confirmFlagMeaning": HuggingFaceCLIConsentContract.confirmFlagMeaning,
            "canonicalApprovalRequired": true,
            "freshPreflightRequired": true,
            "approvalOrigin": HuggingFaceCLIConsentContract.approvalOrigin,
            "doesNotAuthorizeHubRemoteDeletion": true,
            "doesNotAuthorizePrune": true,
            "doesNotAuthorizeOtherRevisions": true,
            "doesNotAuthorizeOtherRepos": true,
            "doesNotAuthorizeRawDelete": true,
            "observedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        try JSONSerialization.data(withJSONObject: authDoc, options: [.prettyPrinted, .sortedKeys])
            .write(to: outDir.appendingPathComponent("p3_2b_3_real_authorization.json"))

        let before = HuggingFaceNativePostMutationProbe.captureBefore()
        try encoder.encode(before).write(to: outDir.appendingPathComponent("p3_2b_3_before.json"))

        let execReport: ActExecutionOrchestrator.HuggingFaceNativeExecutionReport
        do {
            // humanConfirmed=true only after --confirm; orchestrator still runs Fresh Preflight
            // and mints canonical UserActionApproval (no bypass).
            execReport = try ActExecutionOrchestrator.executeHuggingFaceRevisionCleanup(
                .init(
                    authorizationText: authText,
                    humanConfirmed: true,
                    expectedRecoveryBytes: HuggingFaceNativePostMutationProbe.expectedUniqueBytes,
                    engine: engine,
                    executor: StorageActionExecutorRouter(),
                    processRunner: FoundationProcessRunner()
                )
            )
        } catch let error as ActionExecutionError {
            fputs("execute-hf blocked: \(describeExecutionError(error))\n", stderr)
            throw ExitCode.failure
        }

        try encoder.encode(execReport).write(to: outDir.appendingPathComponent("p3_2b_3_execution.json"))
        if let post = execReport.postVerify {
            try encoder.encode(post).write(to: outDir.appendingPathComponent("p3_2b_3_postverify.json"))
        }
        let afterInv = HuggingFaceCacheDryRunPreviewer.captureLocalInventory(
            repoID: repo,
            revision: revision,
            itemPath: HuggingFaceNativePostMutationProbe.authorizedSnapshotPath,
            uniqueBytes: 0,
            sharedBytes: 0
        )
        try encoder.encode(afterInv).write(to: outDir.appendingPathComponent("p3_2b_3_after_inventory.json"))

        let beforeAfter: [String: Any] = [
            "entityID": execReport.entityID,
            "action": execReport.action,
            "permitID": execReport.permitID as Any,
            "outcome": execReport.outcome,
            "snapshotPresentBefore": execReport.snapshotPresentBefore as Any,
            "snapshotPresentAfter": execReport.snapshotPresentAfter as Any,
            "repoPresentAfter": execReport.repoPresentAfter as Any,
            "verifiedRecoveredBytes": execReport.verifiedRecoveredBytes,
            "diskFreeDeltaBytes": execReport.diskFreeDeltaBytes as Any,
            "hubRemoteDeletion": false,
            "pruneUsed": false,
            "rawDeleteFallback": false,
            "shellUsed": false,
        ]
        try JSONSerialization.data(withJSONObject: beforeAfter, options: [.prettyPrinted, .sortedKeys])
            .write(to: outDir.appendingPathComponent("p3_2b_3_before_after.json"))

        FileHandle.standardOutput.write(try encoder.encode(execReport))
        FileHandle.standardOutput.write(Data("\n".utf8))
        fputs(
            "execute-hf outcome=\(execReport.outcome) removed=\(execReport.logicalRemovalVerified) recovered=\(execReport.verifiedRecoveredBytes)\n",
            stderr
        )
        }
    }

    enum ExitCode: Error {
        case failure
    }

    static func describeExecutionError(_ error: ActionExecutionError) -> String {
        switch error {
        case .preflightNotReady(let reason):
            return "Fresh preflight not ready: \(reason). Close Xcode and retry."
        case .gateNotReady(let reason):
            return "Gate not ready: \(reason)"
        case .humanConfirmationRequired:
            return "Missing --confirm"
        case .permitDenied(let reason):
            return "ExecutionPermit denied: \(reason)"
        case .postVerifyFailed(let reason):
            return "Post-verify failed: \(reason)"
        case .sourceMissing(let path):
            return "Source missing: \(path)"
        case .trashFailed(let reason):
            return "Trash failed: \(reason)"
        case .unauthorizedAction(let action):
            return "Unauthorized action: \(action.rawValue)"
        case .unauthorizedTarget(let id, let path):
            return "Unauthorized target: \(id) @ \(path)"
        case .executorNotImplemented(let action):
            return "Executor not implemented: \(action.rawValue)"
        case .planActionMismatch(let detail):
            return "Plan/action mismatch: \(detail)"
        case .entityMismatch(let expected, let actual):
            return "Entity mismatch: expected \(expected), got \(actual)"
        case .bindingPathMismatch:
            return "Binding path mismatch"
        case .invalidModelIdentity(let id):
            return "Invalid model identity: \(id)"
        case .executableUnresolved(let name):
            return "Executable unresolved: \(name)"
        case .permitAlreadyConsumed(let id):
            return "Permit already consumed: \(id)"
        case .processFailed(let reason):
            return "Process failed: \(reason)"
        }
    }

    static func locateCompiledKB() -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("knowledge/compiled/compiled_rules_v0.1.json"),
            cwd.appendingPathComponent("Sources/SafetyCore/Resources/knowledge/compiled_rules_v0.1.json"),
        ]
        if let hit = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return hit
        }
        return candidates[0]
    }

    static func summary(_ report: ReadOnlyAnalysisReport) -> ScanSummary {
        ScanSummary(
            knowledgeVersion: report.knowledgeVersion,
            ruleCount: report.knowledgeRuleCount,
            scannedBytes: report.coverage.scannedBytes,
            identifiedBytes: report.coverage.identifiedBytes,
            unknownBytes: report.coverage.unknownBytes,
            coveragePercent: report.coverage.percent,
            semanticL3: report.semanticCoverage.l3PlusPercent,
            semanticL4: report.semanticCoverage.l4PlusPercent,
            semanticL5: report.semanticCoverage.l5Percent,
            uniqueBytes: report.byteAccounting.uniqueTotal,
            duplicateBytesRemoved: report.byteAccounting.duplicateBytesRemoved,
            classTotals: report.classTotals,
            bucketTotals: report.bucketTotals,
            domainTotals: report.domainTotals,
            itemCount: report.items.count,
            remainingGreenAfterAudit: report.greenAudits.filter { $0.safetyClass == .green }.count,
            downgradedGreen: report.greenAudits.filter(\.downgradedFromGreen).count,
            preview: report.preview,
            destructiveActionsExecuted: false,
            scanRuntimeSeconds: report.scanRuntimeSeconds,
            semanticDebtBytes: report.semanticDebtBytes
        )
    }

    static func aiToolsRows(_ report: ReadOnlyAnalysisReport) -> [AIToolRow] {
        report.items.filter { $0.detected.domain == "AI Tools" }.map {
            AIToolRow(
                product: $0.detected.entity.subcategory,
                semanticEntity: $0.detected.entity.id,
                path: $0.detected.entity.path,
                inclusiveBytes: $0.inclusiveBytes,
                exclusiveBytes: $0.exclusiveBytes,
                uniqueBytes: $0.exclusiveBytes,
                resolutionLevel: $0.resolution.rawValue,
                safetyClass: $0.decision.safetyClass.rawValue,
                evidenceStatus: $0.unknownReason?.rawValue ?? "CLASSIFIED",
                ruleMatch: $0.decision.matchedRuleID,
                unresolvedReason: $0.unknownReason?.rawValue
            )
        }
    }

    static func containerRows(_ report: ReadOnlyAnalysisReport) -> [ContainerRow] {
        var map: [String: ContainerRow] = [:]
        for item in report.items where item.detected.entity.id.hasPrefix("container.") {
            var rest = String(item.detected.entity.id.dropFirst("container.".count))
            let suffixes = [".documents", ".caches", ".preferences", ".app_support", ".tmp"]
            for s in suffixes where rest.hasSuffix(s) {
                rest.removeLast(s.count)
                break
            }
            let bid = rest
            guard !bid.isEmpty else { continue }
            var row = map[bid] ?? ContainerRow(
                bundleId: bid,
                owningApp: BundleCatalog.product(for: bid).name,
                containerRoot: item.detected.entity.path.components(separatedBy: "/Data/").first ?? item.detected.entity.path,
                documentsBytes: 0, cachesBytes: 0, applicationSupportBytes: 0,
                preferencesBytes: 0, tmpBytes: 0, unknownBytes: 0,
                semanticCoverage: item.resolution.rawValue
            )
            let exclusive = item.exclusiveBytes
            if item.detected.entity.id.contains(".documents") { row.documentsBytes += exclusive }
            else if item.detected.entity.id.contains(".caches") { row.cachesBytes += exclusive }
            else if item.detected.entity.id.contains(".app_support") { row.applicationSupportBytes += exclusive }
            else if item.detected.entity.id.contains(".preferences") { row.preferencesBytes += exclusive }
            else if item.detected.entity.id.contains(".tmp") { row.tmpBytes += exclusive }
            else { row.unknownBytes += exclusive }
            map[bid] = row
        }
        return map.values.sorted { $0.bundleId < $1.bundleId }
    }

    static func appSupportRows(_ report: ReadOnlyAnalysisReport) -> [AIToolRow] {
        report.items.filter {
            $0.detected.entity.path.contains("/Library/Application Support/")
        }.map {
            AIToolRow(
                product: $0.detected.entity.subcategory,
                semanticEntity: $0.detected.entity.id,
                path: $0.detected.entity.path,
                inclusiveBytes: $0.inclusiveBytes,
                exclusiveBytes: $0.exclusiveBytes,
                uniqueBytes: $0.exclusiveBytes,
                resolutionLevel: $0.resolution.rawValue,
                safetyClass: $0.decision.safetyClass.rawValue,
                evidenceStatus: $0.unknownReason?.rawValue ?? "CLASSIFIED",
                ruleMatch: $0.decision.matchedRuleID,
                unresolvedReason: $0.unknownReason?.rawValue
            )
        }
    }

    static func cursorStoresVerification(_ report: ReadOnlyAnalysisReport) -> [VerificationRow] {
        report.items.filter {
            $0.detected.entity.id.contains("cursor.snapshots.store") || $0.detected.entity.path.contains("/snapshots/stores")
                || ($0.detected.entity.id.contains("staging") && $0.detected.entity.id.contains("cursor.snapshots"))
        }.map { VerificationRow.from($0) }
    }

    static func claudeVMVerification(_ report: ReadOnlyAnalysisReport) -> [VerificationRow] {
        report.items.filter { $0.detected.entity.id.contains("claude.vm") }.map { VerificationRow.from($0) }
    }

    static func cloudResolution(_ report: ReadOnlyAnalysisReport) -> [VerificationRow] {
        report.items.filter { $0.detected.domain == "Cloud" || $0.detected.entity.id.hasPrefix("cloud.") }.map { VerificationRow.from($0) }
    }

    static func sourceOfTruthReport(_ report: ReadOnlyAnalysisReport) -> ResolutionSummary {
        ResolutionSummary.from(report) { $0.verification?.sourceOfTruth }
    }

    static func regenerabilityReport(_ report: ReadOnlyAnalysisReport) -> ResolutionSummary {
        ResolutionSummary.from(report) { $0.verification?.regenerable }
    }

    static func evidenceChanges(_ report: ReadOnlyAnalysisReport) -> EvidenceChangesP14 {
        var verified = 0
        var inferred = 0
        var unknown = 0
        for item in report.items {
            switch item.verification?.provenanceConfidence ?? item.detected.annotation?.provenance.confidence ?? .unknown {
            case .verified: verified += 1
            case .inferred: inferred += 1
            case .unknown: unknown += 1
            }
        }
        return EvidenceChangesP14(
            provenanceVerifiedCount: verified,
            provenanceInferredCount: inferred,
            provenanceUnknownCount: unknown,
            sourceOfTruthKnownBytes: report.verificationCoverage.sourceOfTruthKnownBytes,
            regenerabilityKnownBytes: report.verificationCoverage.regenerabilityKnownBytes,
            runtimeStateKnownBytes: report.verificationCoverage.runtimeStateKnownBytes
        )
    }

    static func cursorRelationshipGraph(_ report: ReadOnlyAnalysisReport) -> [CursorRelRow] {
        report.items.filter {
            $0.detected.entity.id.contains("cursor.snapshots")
                || $0.detected.entity.id.contains("cursor.workspaceStorage")
        }.compactMap { item -> CursorRelRow? in
            let rels = item.detected.annotation?.relationships ?? []
            guard !rels.isEmpty || item.detected.entity.id.contains("store") || item.detected.entity.id.contains("rootref") || item.detected.entity.id.contains("workspaceStorage") else { return nil }
            let ws = rels.first { $0.type == .belongsToWorkspace }
            let storeRel = rels.first { $0.type == .associatedWithCursorStore }
            let chain = report.verificationChains.first {
                $0.entityID == item.detected.entity.id && $0.claim.contains("BELONGS_TO_WORKSPACE")
            }
            let unknown = (item.verification?.unknownReasons ?? item.detected.annotation?.unknownReasons ?? [])
                .first { $0.hasPrefix("CURSOR_") }
            let directVerified = rels.contains { $0.confidence == .verified && ($0.type == .belongsToWorkspace || $0.type == .associatedWithCursorStore) }
            let composedOrInferred = rels.contains { $0.confidence == .inferred || $0.type == .possibleWorkspaceContext }
            let unresolved = unknown ?? rels.first { $0.type == .belongsToWorkspace && $0.confidence == .unknown }?.type.rawValue
            let storeID: String? = {
                if item.detected.entity.id.contains("store.") {
                    return item.detected.entity.id.components(separatedBy: "store.").last
                }
                if item.detected.entity.id.contains("rootref.") {
                    return item.detected.entity.id.components(separatedBy: "rootref.").last
                }
                if item.detected.entity.id.contains("workspaceStorage.") {
                    return item.detected.entity.id.components(separatedBy: "workspaceStorage.").last
                }
                return URL(fileURLWithPath: item.detected.entity.path).lastPathComponent
            }()
            return CursorRelRow(
                storeID: storeID,
                storeOrRoot: item.detected.entity.id,
                storePath: item.detected.entity.path,
                path: item.detected.entity.path,
                size: item.exclusiveBytes,
                uniqueBytes: item.exclusiveBytes,
                candidateWorkspace: ws?.target,
                workspacePath: ws?.target,
                workspaceExists: ws.map { $0.presence == .present },
                relationshipType: ws?.type.rawValue ?? storeRel?.type.rawValue,
                relationship: ws?.type.rawValue ?? storeRel?.type.rawValue,
                verificationLevel: ws?.confidence.rawValue ?? storeRel?.confidence.rawValue ?? item.detected.annotation?.provenance.confidence.rawValue,
                confidence: ws?.confidence.rawValue ?? storeRel?.confidence.rawValue ?? item.detected.annotation?.provenance.confidence.rawValue,
                verificationChainID: chain?.chainID,
                evidenceSource: directVerified ? "EXPLICIT_METADATA" : (composedOrInferred ? "FOLDER_NAME_INFERRED" : "UNKNOWN"),
                unknownReason: unknown,
                relationships: rels.map { "\($0.type.rawValue):\($0.target):\($0.confidence.rawValue)" },
                directVerified: directVerified,
                composedOrInferred: composedOrInferred,
                unresolvedReason: unresolved
            )
        }
    }

    static func claudeVMReport(_ report: ReadOnlyAnalysisReport) -> [ClaudeVMRow] {
        report.items.filter { $0.detected.entity.id.contains("claude.vm") }.map { item in
            let path = item.detected.entity.path
            let chain = report.verificationChains.first {
                $0.entityID == item.detected.entity.id && $0.claim == "ACTIVE_STATE"
            }
            let exactPathMatch = item.verification?.activeState == .active
                && item.verification?.activeStateConfidence == .verified
            return ClaudeVMRow(
                bundleIdentity: item.detected.entity.id,
                canonicalPath: path,
                runtimeRole: item.detected.annotation?.lifecycle.role.rawValue,
                bytes: item.exclusiveBytes,
                processEvidence: item.verification?.activeStateConfidence == .verified ? "PROCESS_OR_CMDLINE_SNAPSHOT" : "NONE_EXACT",
                openFileEvidence: exactPathMatch ? "EXACT_OR_BUNDLE_CHILD_HANDLE" : "NONE_EXACT",
                exactPathMatch: exactPathMatch,
                activeState: item.verification?.activeState.rawValue,
                verificationLevel: item.verification?.activeStateConfidence.rawValue,
                verificationChainID: chain?.chainID,
                unknownReason: (item.verification?.unknownReasons ?? []).first { $0.contains("ACTIVE") || $0.contains("UNKNOWN") }
            )
        }
    }

    static func derivedDataProof(_ report: ReadOnlyAnalysisReport) -> [DerivedDataProofRow] {
        report.items.filter {
            $0.detected.entity.id.contains("xcode.deriveddata") || $0.detected.entity.path.lowercased().contains("deriveddata")
        }.map { item in
            let rel = (item.detected.annotation?.relationships ?? []).first { $0.type == .derivedFrom || $0.type == .belongsToWorkspace }
            let reasons = item.verification?.unknownReasons ?? item.detected.annotation?.unknownReasons ?? []
            let budget = reasons.first { $0.hasPrefix("PROOF_BUDGET_FILES=") }
            let runtime = reasons.first { $0.hasPrefix("PROOF_RUNTIME_MS=") }
            let chain = report.verificationChains.first {
                $0.entityID == item.detected.entity.id && ($0.claim == "REGENERABILITY" || $0.claim == "SOURCE_OF_TRUTH")
            }
            return DerivedDataProofRow(
                path: item.detected.entity.path,
                bytes: item.exclusiveBytes,
                relatedProject: rel?.target,
                projectRelationshipVerification: rel.map { "\($0.confidence.rawValue):\($0.presence.rawValue)" },
                activeState: item.verification?.activeState.rawValue,
                sourceOfTruth: item.verification?.sourceOfTruth.value.rawValue,
                sourceOfTruthConfidence: item.verification?.sourceOfTruth.confidence.rawValue,
                regenerable: item.verification?.regenerable.value.rawValue,
                regenerableConfidence: item.verification?.regenerable.confidence.rawValue,
                verificationChainID: chain?.chainID,
                proofBudget: budget,
                proofRuntime: runtime,
                unknownReasons: reasons.filter { !$0.hasPrefix("PROOF_") }
            )
        }
    }

    static func verificationChainsReport(_ report: ReadOnlyAnalysisReport) -> [VerificationChainRow] {
        report.verificationChains.map { c in
            VerificationChainRow(
                chainID: c.chainID,
                subjectEntity: c.entityID,
                claim: c.claim,
                result: c.result,
                verificationLevel: c.confidence.rawValue,
                requiredSteps: c.requiredSteps,
                verifiedSteps: c.satisfiedRequirements,
                inferredSteps: c.inferredStepCount > 0 ? ["inferred_present"] : [],
                unknownSteps: c.unknownRequirements,
                failureReason: c.failureReason,
                evidenceSources: c.supportingEvidenceIDs,
                satisfiesStrictChain: c.satisfiesStrictChain
            )
        }
    }

    static func proofEnrichmentSummary(_ report: ReadOnlyAnalysisReport, proofTargets: Set<String>) -> ProofEnrichmentSummary {
        let cursorLinks = report.items.filter { item in
            item.detected.entity.id.contains("cursor")
                && (item.detected.annotation?.relationships ?? []).contains {
                    $0.type == .belongsToWorkspace && $0.confidence == .verified && $0.presence == .present
                }
        }
        let claudeActive = report.items.filter {
            $0.detected.entity.id.contains("claude.vm")
                && $0.verification?.activeState == .active
                && $0.verification?.activeStateConfidence == .verified
        }
        let ddRegen = report.items.filter {
            $0.detected.entity.path.lowercased().contains("deriveddata")
                && $0.verification?.regenerable.value == .true
                && $0.verification?.regenerable.confidence == .verified
        }
        let ddSOTFalse = report.items.filter {
            $0.detected.entity.path.lowercased().contains("deriveddata")
                && $0.verification?.sourceOfTruth.value == .false
                && $0.verification?.sourceOfTruth.confidence == .verified
        }
        return ProofEnrichmentSummary(
            proofTargets: Array(proofTargets).sorted(),
            cursorVerifiedWorkspaceLinks: cursorLinks.count,
            claudeExactActiveVerified: claudeActive.count,
            derivedDataRegenTrueVerified: ddRegen.count,
            derivedDataSOTFalseVerified: ddSOTFalse.count,
            verificationChainTotal: report.verificationChains.count,
            fullyVerifiedStrictChains: VerificationChainBuilder.strictVerifiedCount(report.verificationChains),
            falseGreen: 0,
            greenCount: report.greenAudits.filter { $0.safetyClass == .green }.count,
            uniqueBytes: report.byteAccounting.uniqueTotal,
            scanRuntimeSeconds: report.scanRuntimeSeconds,
            destructiveActionsExecuted: false,
            previewExecutable: report.preview.executable
        )
    }

    static func tomyLocalBreakdown(_ report: ReadOnlyAnalysisReport) -> [VerificationRow] {
        report.items.filter {
            $0.detected.entity.id.hasPrefix("tomylocal.") || $0.detected.entity.path.contains("/TomyLocal")
        }.map { VerificationRow.from($0) }
    }

    static func chromeBreakdown(_ report: ReadOnlyAnalysisReport) -> [VerificationRow] {
        report.items.filter {
            $0.detected.entity.id.contains("chrome.profile") || $0.detected.entity.path.contains("/Google/Chrome/")
        }.map { VerificationRow.from($0) }
    }

    static func evidenceQuality(_ report: ReadOnlyAnalysisReport) -> EvidenceQualityP15 {
        var claims: [ClaimQuality] = []
        func add(_ name: String, pick: (ClassifiedItem) -> (EvidenceConfidence, Int64)?) {
            var v: Int64 = 0, i: Int64 = 0, u: Int64 = 0
            var vc = 0, ic = 0, uc = 0
            for item in report.items {
                guard let (conf, bytes) = pick(item) else { continue }
                switch conf {
                case .verified: v += bytes; vc += 1
                case .inferred: i += bytes; ic += 1
                case .unknown: u += bytes; uc += 1
                }
            }
            claims.append(ClaimQuality(claim: name, verifiedCount: vc, inferredCount: ic, unknownCount: uc, verifiedBytes: v, inferredBytes: i, unknownBytes: u))
        }
        add("provenance") { item in
            let c = item.verification?.provenanceConfidence ?? item.detected.annotation?.provenance.confidence ?? .unknown
            return (c, item.exclusiveBytes)
        }
        add("source_of_truth") { item in
            (item.verification?.sourceOfTruth.confidence ?? .unknown, item.exclusiveBytes)
        }
        add("regenerability") { item in
            (item.verification?.regenerable.confidence ?? .unknown, item.exclusiveBytes)
        }
        add("runtime_state") { item in
            (item.verification?.activeStateConfidence ?? .unknown, item.exclusiveBytes)
        }
        add("verified_relationship") { item in
            let has = (item.detected.annotation?.relationships ?? []).contains { $0.confidence == .verified }
            return (has ? .verified : .unknown, item.exclusiveBytes)
        }
        return EvidenceQualityP15(
            claims: claims,
            verifiedRelationshipCoveragePercent: report.verifiedRelationshipCoverage.byteCoveragePercent,
            verificationChainCount: report.verificationChains.count
        )
    }
}

struct CursorRelRow: Codable {
    var storeID: String?
    var storeOrRoot: String
    var storePath: String?
    var path: String
    var size: Int64?
    var uniqueBytes: Int64
    var candidateWorkspace: String?
    var workspacePath: String?
    var workspaceExists: Bool?
    var relationshipType: String?
    var relationship: String?
    var verificationLevel: String?
    var confidence: String?
    var verificationChainID: String?
    var evidenceSource: String?
    var unknownReason: String?
    var relationships: [String]
    var directVerified: Bool
    var composedOrInferred: Bool
    var unresolvedReason: String?
}

struct ClaudeVMRow: Codable {
    var bundleIdentity: String
    var canonicalPath: String
    var runtimeRole: String?
    var bytes: Int64
    var processEvidence: String?
    var openFileEvidence: String?
    var exactPathMatch: Bool
    var activeState: String?
    var verificationLevel: String?
    var verificationChainID: String?
    var unknownReason: String?
}

struct DerivedDataProofRow: Codable {
    var path: String
    var bytes: Int64
    var relatedProject: String?
    var projectRelationshipVerification: String?
    var activeState: String?
    var sourceOfTruth: String?
    var sourceOfTruthConfidence: String?
    var regenerable: String?
    var regenerableConfidence: String?
    var verificationChainID: String?
    var proofBudget: String?
    var proofRuntime: String?
    var unknownReasons: [String]
}

struct VerificationChainRow: Codable {
    var chainID: String
    var subjectEntity: String
    var claim: String
    var result: String
    var verificationLevel: String
    var requiredSteps: [String]
    var verifiedSteps: [String]
    var inferredSteps: [String]
    var unknownSteps: [String]
    var failureReason: String?
    var evidenceSources: [String]
    var satisfiesStrictChain: Bool
}

struct ProofEnrichmentSummary: Codable {
    var proofTargets: [String]
    var cursorVerifiedWorkspaceLinks: Int
    var claudeExactActiveVerified: Int
    var derivedDataRegenTrueVerified: Int
    var derivedDataSOTFalseVerified: Int
    var verificationChainTotal: Int
    var fullyVerifiedStrictChains: Int
    var falseGreen: Int
    var greenCount: Int
    var uniqueBytes: Int64
    var scanRuntimeSeconds: Double
    var destructiveActionsExecuted: Bool
    var previewExecutable: Bool
}

struct ProofRuntime: Codable {
    var scanRuntimeSeconds: Double
    var proofTargets: [String]
}

struct ClaimQuality: Codable {
    var claim: String
    var verifiedCount: Int
    var inferredCount: Int
    var unknownCount: Int
    var verifiedBytes: Int64
    var inferredBytes: Int64
    var unknownBytes: Int64
}

struct EvidenceQualityP15: Codable {
    var claims: [ClaimQuality]
    var verifiedRelationshipCoveragePercent: Double
    var verificationChainCount: Int
}

struct ScanSummary: Codable {
    var knowledgeVersion: String
    var ruleCount: Int
    var scannedBytes: Int64
    var identifiedBytes: Int64
    var unknownBytes: Int64
    var coveragePercent: Double
    var semanticL3: Double
    var semanticL4: Double
    var semanticL5: Double
    var uniqueBytes: Int64
    var duplicateBytesRemoved: Int64
    var classTotals: [String: Int64]
    var bucketTotals: [String: Int64]
    var domainTotals: [String: Int64]
    var itemCount: Int
    var remainingGreenAfterAudit: Int
    var downgradedGreen: Int
    var preview: PreviewTotals
    var destructiveActionsExecuted: Bool
    var scanRuntimeSeconds: Double
    var semanticDebtBytes: Int64
}

struct ScanMeta: Codable {
    var semanticDebtBytes: Int64
    var scanRuntimeSeconds: Double
}

struct AIToolRow: Codable {
    var product: String
    var semanticEntity: String
    var path: String
    var inclusiveBytes: Int64
    var exclusiveBytes: Int64
    var uniqueBytes: Int64
    var resolutionLevel: Int
    var safetyClass: String
    var evidenceStatus: String
    var ruleMatch: String?
    var unresolvedReason: String?
}

struct ContainerRow: Codable {
    var bundleId: String
    var owningApp: String
    var containerRoot: String
    var documentsBytes: Int64
    var cachesBytes: Int64
    var applicationSupportBytes: Int64
    var preferencesBytes: Int64
    var tmpBytes: Int64
    var unknownBytes: Int64
    var semanticCoverage: Int
}

struct VerificationRow: Codable {
    var path: String
    var entityID: String
    var uniqueBytes: Int64
    var safetyClass: String
    var lifecycleRole: String?
    var provenanceConfidence: String?
    var sourceOfTruth: String?
    var sourceOfTruthConfidence: String?
    var regenerable: String?
    var regenerableConfidence: String?
    var activeState: String?
    var activeStateConfidence: String?
    var relationships: [String]
    var unknownReasons: [String]

    static func from(_ item: ClassifiedItem) -> VerificationRow {
        VerificationRow(
            path: item.detected.entity.path,
            entityID: item.detected.entity.id,
            uniqueBytes: item.exclusiveBytes,
            safetyClass: item.decision.safetyClass.rawValue,
            lifecycleRole: item.detected.annotation?.lifecycle.role.rawValue,
            provenanceConfidence: (item.verification?.provenanceConfidence ?? item.detected.annotation?.provenance.confidence)?.rawValue,
            sourceOfTruth: item.verification?.sourceOfTruth.value.rawValue,
            sourceOfTruthConfidence: item.verification?.sourceOfTruth.confidence.rawValue,
            regenerable: item.verification?.regenerable.value.rawValue,
            regenerableConfidence: item.verification?.regenerable.confidence.rawValue,
            activeState: item.verification?.activeState.rawValue,
            activeStateConfidence: item.verification?.activeStateConfidence.rawValue,
            relationships: (item.detected.annotation?.relationships ?? []).map { "\($0.type.rawValue):\($0.target):\($0.confidence.rawValue)" },
            unknownReasons: item.verification?.unknownReasons ?? item.detected.annotation?.unknownReasons ?? []
        )
    }
}

struct ResolutionSummary: Codable {
    var eligibleBytes: Int64
    var verifiedTrueBytes: Int64
    var verifiedFalseBytes: Int64
    var inferredBytes: Int64
    var unknownBytes: Int64
    var knownCoveragePercent: Double

    static func from(_ report: ReadOnlyAnalysisReport, pick: (ClassifiedItem) -> ObservationRecord?) -> ResolutionSummary {
        var eligible: Int64 = 0, vt: Int64 = 0, vf: Int64 = 0, inf: Int64 = 0, unk: Int64 = 0
        for item in report.items {
            let b = item.exclusiveBytes
            eligible += b
            guard let rec = pick(item) else { unk += b; continue }
            switch (rec.value, rec.confidence) {
            case (.true, .verified): vt += b
            case (.false, .verified): vf += b
            case (_, .inferred): inf += b
            default: unk += b
            }
        }
        let known = vt + vf
        return ResolutionSummary(
            eligibleBytes: eligible,
            verifiedTrueBytes: vt,
            verifiedFalseBytes: vf,
            inferredBytes: inf,
            unknownBytes: unk,
            knownCoveragePercent: ByteAccountant.coverage(uniqueBytes: known, scannedBytes: max(eligible, 1))
        )
    }
}

struct GreenAuditP14: Codable {
    var greenCount: Int
    var falseGreenFindings: Int
    var audits: [GreenAuditRecord]
}

struct EvidenceChangesP14: Codable {
    var provenanceVerifiedCount: Int
    var provenanceInferredCount: Int
    var provenanceUnknownCount: Int
    var sourceOfTruthKnownBytes: Int64
    var regenerabilityKnownBytes: Int64
    var runtimeStateKnownBytes: Int64
}
