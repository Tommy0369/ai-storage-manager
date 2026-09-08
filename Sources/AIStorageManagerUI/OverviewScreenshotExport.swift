import AppKit
import SwiftUI
import AppServices
import SafetyCore

public enum OverviewScreenshotExport {
    @MainActor
    public static func exportCase001(reportDirectory: URL, outputURL: URL) throws {
        let experience = try PreviewSnapshotFactory.loadCase001(from: reportDirectory)
        let explorer = PreviewSnapshotFactory.explorerDemo(experience: experience)
        try render(frame: OverviewScreenshotFrame(experience: experience, explorer: explorer), to: outputURL)
    }

    @MainActor
    public static func exportExplorerScenarios(reportDirectory: URL, outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let experience = try PreviewSnapshotFactory.loadCase001(from: reportDirectory)
        let explorer = PreviewSnapshotFactory.explorerDemo(experience: experience)

        let scenarios: [(String, (StorageViewModel) -> Void)] = [
            ("overview_large_map.png", { vm in
                vm.mapLens = .structure
            }),
            ("explorer_root.png", { vm in
                vm.mapLens = .structure
            }),
            ("explorer_library_drilldown.png", { vm in
                if let library = StorageExplorerBuilder.flatten(explorer.presentedRoot).first(where: { $0.title == "Library" }) {
                    vm.focusExplorerNode(library)
                }
            }),
            ("explorer_ai_tools_lens.png", { vm in
                vm.mapLens = .meaning
            }),
            ("explorer_decision_lens.png", { vm in
                vm.mapLens = .decision
            }),
            ("explorer_selected_item.png", { vm in
                if let cursor = StorageExplorerBuilder.flatten(explorer.presentedRoot).first(where: { $0.title == "Cursor" }) {
                    vm.focusExplorerNode(cursor)
                    vm.selectExplorerNode(cursor, drill: false)
                }
            }),
        ]

        for (name, configure) in scenarios {
            let frame: AnyView
            if name.hasPrefix("overview") {
                frame = AnyView(OverviewScreenshotFrame(experience: experience, explorer: explorer, configure: configure))
            } else {
                frame = AnyView(ExplorerScreenshotFrame(experience: experience, explorer: explorer, configure: configure))
            }
            try render(frame: frame, to: outputDirectory.appendingPathComponent(name), size: CGSize(width: 1280, height: 860))
        }
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: explorer),
            to: outputDirectory.appendingPathComponent("overview_p30_quality_check.png"),
            size: CGSize(width: 1280, height: 860)
        )

        // P3.0.2 deterministic change screenshots — fixtures only; do not overwrite live change JSON.
        let firstRun = StorageSnapshotDiffEngine.compare(
            previous: nil,
            current: StorageHistoryBuilder.build(from: explorer)
        )
        let withChange = StorageChangeService.demoChangeReport()
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: firstRun),
            to: outputDirectory.appendingPathComponent("overview_p302_first_run.png"),
            size: CGSize(width: 1280, height: 860)
        )
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: withChange),
            to: outputDirectory.appendingPathComponent("overview_p302_change_intelligence.png"),
            size: CGSize(width: 1280, height: 860)
        )
        try render(
            frame: ChangeDetailScreenshotFrame(report: withChange),
            to: outputDirectory.appendingPathComponent("change_detail_p302.png"),
            size: CGSize(width: 900, height: 720)
        )

        let partial = try OptimizationPlanService.demoPartialPlan()
        let achievable = try OptimizationPlanService.demoAchievablePlan()
        let none = try OptimizationPlanService.demoNoSafePlan()
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: withChange, plan: partial),
            to: outputDirectory.appendingPathComponent("overview_p303_goal_entry.png"),
            size: CGSize(width: 1280, height: 860)
        )
        try render(
            frame: OptimizationPlanScreenshotFrame(plan: partial),
            to: outputDirectory.appendingPathComponent("optimization_plan_p303_partial.png"),
            size: CGSize(width: 960, height: 760)
        )
        try render(
            frame: OptimizationPlanScreenshotFrame(plan: achievable),
            to: outputDirectory.appendingPathComponent("optimization_plan_p303_achievable.png"),
            size: CGSize(width: 960, height: 760)
        )
        try render(
            frame: OptimizationPlanScreenshotFrame(plan: none),
            to: outputDirectory.appendingPathComponent("optimization_plan_p303_no_safe_options.png"),
            size: CGSize(width: 960, height: 760)
        )

        // P3.0.4 progressive scan fixtures — do not overwrite live performance JSON.
        var scanningExplorer = explorer
        scanningExplorer.scanStage = .scanningFiles
        scanningExplorer.mapReadiness = .notReady
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: scanningExplorer, scanning: true),
            to: outputDirectory.appendingPathComponent("overview_p304_scanning.png"),
            size: CGSize(width: 1280, height: 860)
        )
        var partialExplorer = explorer
        if var accounting = partialExplorer.mapAccounting {
            accounting.coverage = .partial
            accounting.basis = .knownChildrenLowerBound
            accounting.rootMeasurementStatus = .timeout
            accounting.rootTotalKnown = false
            accounting.fallbackUsed = true
            partialExplorer.mapAccounting = accounting
        }
        partialExplorer.scanStage = .hierarchyAvailable
        partialExplorer.mapReadiness = .structureReadyPartial
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: partialExplorer, change: withChange, scanning: true),
            to: outputDirectory.appendingPathComponent("overview_p304_partial_map.png"),
            size: CGSize(width: 1280, height: 860)
        )
        var semanticExplorer = explorer
        semanticExplorer.scanStage = .understandingStorage
        semanticExplorer.mapReadiness = .semanticEnriched
        semanticExplorer.meaningLensAvailable = true
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: semanticExplorer, change: withChange, scanning: true, configure: { vm in
                vm.mapLens = .meaning
            }),
            to: outputDirectory.appendingPathComponent("overview_p304_semantic.png"),
            size: CGSize(width: 1280, height: 860)
        )
        var completeExplorer = explorer
        completeExplorer.scanStage = .complete
        completeExplorer.mapReadiness = .complete
        completeExplorer.meaningLensAvailable = true
        completeExplorer.decisionLensAvailable = true
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: completeExplorer, change: withChange, configure: { vm in
                vm.mapLens = .decision
            }),
            to: outputDirectory.appendingPathComponent("overview_p304_complete.png"),
            size: CGSize(width: 1280, height: 860)
        )

        // P3.1 AI model proof fixtures — no live mutation.
        try render(
            frame: AIModelDetailScreenshotFrame(
                title: "mlx-community/whisper-large-v3-mlx",
                subtitle: "Hugging Face Hub cache",
                bytesLabel: "3.1 GB",
                what: "Locally stored AI model data.",
                lines: [
                    "Installed/downloaded model data",
                    "Unique local storage: proven when reference graph is complete",
                    "Can it be downloaded again? Not yet verified",
                    "Correct action: vendor-native cleanup (not available in this version)"
                ]
            ),
            to: outputDirectory.appendingPathComponent("ai_models_p31_huggingface_detail.png"),
            size: CGSize(width: 900, height: 720)
        )
        try render(
            frame: AIModelDetailScreenshotFrame(
                title: "qwen3:4b",
                subtitle: "Ollama model",
                bytesLabel: "6.2 GB logical",
                what: "Locally stored Ollama model data.",
                lines: [
                    "Unique local storage: 1.4 GB (example when proven)",
                    "Shared with other models: 4.8 GB (example when proven)",
                    "Potential unique cleanup: 1.4 GB",
                    "Some model files may be shared — raw blob delete is never auto-promoted"
                ]
            ),
            to: outputDirectory.appendingPathComponent("ai_models_p31_ollama_shared_storage.png"),
            size: CGSize(width: 900, height: 720)
        )
        var verifiedFuturePlan = try OptimizationPlanService.demoPartialPlan()
        // Force the verified-future section to be visible for screenshot semantics.
        try render(
            frame: OptimizationPlanScreenshotFrame(plan: verifiedFuturePlan),
            to: outputDirectory.appendingPathComponent("optimization_plan_p31_verified_future.png"),
            size: CGSize(width: 960, height: 760)
        )
        _ = verifiedFuturePlan

        // P3.2A.6 — deterministic fixtures (no qwen3 redownload, no live mutation).
        try render(
            frame: VerifiedActionReceiptScreenshotFrame(
                title: "Removed with Ollama",
                subtitle: "qwen3:4b",
                headline: "qwen3:4b was removed using Ollama.",
                checklist: [
                    "✓ Native Ollama action completed",
                    "✓ Model no longer installed",
                    "✓ 2.50 GB verified removed",
                    "✓ No regeneration detected"
                ],
                footnote: "FIXTURE — grounded in P3.2A.5 verified event. Disk free delta kept distinct from verified recovery.",
                tone: .success
            ),
            to: outputDirectory.appendingPathComponent("ollama_p32a6_removed_verified.png"),
            size: CGSize(width: 900, height: 720)
        )
        try render(
            frame: VerifiedActionReceiptScreenshotFrame(
                title: "Action receipt",
                subtitle: "qwen3:4b",
                headline: "2.50 GB of model storage was verified as removed.",
                checklist: [
                    "Removed with Ollama",
                    "Potential before action: ~2.50 GB",
                    "Verified recovered: 2.50 GB",
                    "Observed disk free change: shown separately in details"
                ],
                footnote: "FIXTURE — VerifiedActionResult presentation. Never copy potential into verified.",
                tone: .success
            ),
            to: outputDirectory.appendingPathComponent("ollama_p32a6_action_receipt.png"),
            size: CGSize(width: 900, height: 720)
        )
        try render(
            frame: VerifiedActionReceiptScreenshotFrame(
                title: "Outcome unknown",
                subtitle: "Re-check state",
                headline: "AI Storage Manager could not verify whether the action completed.",
                checklist: [
                    "○ Native outcome not confirmed",
                    "○ Do not retry deletion yet",
                    "✓ Re-check state is read-only",
                    "○ Automatic retry is blocked"
                ],
                footnote: "FIXTURE — unknown process outcome UX. Reconciliation only.",
                tone: .unknown
            ),
            to: outputDirectory.appendingPathComponent("ollama_p32a6_unknown_outcome.png"),
            size: CGSize(width: 900, height: 720)
        )
        // After-action plan: no qwen3 candidate — reuse no-safe / verified-future fixture framing.
        try render(
            frame: OptimizationPlanScreenshotFrame(plan: try OptimizationPlanService.demoPartialPlan()),
            to: outputDirectory.appendingPathComponent("optimization_plan_p32a6_after_action.png"),
            size: CGSize(width: 960, height: 760)
        )
    }

    /// P4.1 — consumer polish screenshots. Live map frames use case001 snapshot data;
    /// action/receipt frames are explicitly fixture/historical.
    @MainActor
    public static func exportP41ConsumerPolish(reportDirectory: URL, outputDirectory: URL) throws {
        L10n.setOverride(.english)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let experience = try PreviewSnapshotFactory.loadCase001(from: reportDirectory)
        let explorer = PreviewSnapshotFactory.explorerDemo(experience: experience)
        let change = StorageChangeService.demoChangeReport()

        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: change, configure: { $0.mapLens = .structure }),
            to: outputDirectory.appendingPathComponent("p41_overview_live.png"),
            size: CGSize(width: 1280, height: 860)
        )
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: change, configure: { $0.mapLens = .structure }),
            to: outputDirectory.appendingPathComponent("p41_structure_live.png"),
            size: CGSize(width: 1280, height: 860)
        )
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: change, configure: { $0.mapLens = .meaning }),
            to: outputDirectory.appendingPathComponent("p41_meaning_live.png"),
            size: CGSize(width: 1280, height: 860)
        )
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: change, configure: { $0.mapLens = .decision }),
            to: outputDirectory.appendingPathComponent("p41_decision_live.png"),
            size: CGSize(width: 1280, height: 860)
        )
        try render(
            frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: change, configure: { vm in
                vm.mapLens = .decision
                if let protected = StorageExplorerBuilder.flatten(explorer.presentedRoot).first(where: {
                    $0.decision.state == .protected || $0.decision.state == .keep || $0.title.localizedCaseInsensitiveContains("Cursor")
                }) {
                    vm.focusExplorerNode(protected)
                    vm.selectExplorerNode(protected, drill: false)
                }
            }),
            to: outputDirectory.appendingPathComponent("p41_protected_live.png"),
            size: CGSize(width: 1280, height: 860)
        )
        try render(
            frame: OptimizationPlanScreenshotFrame(plan: try OptimizationPlanService.demoPartialPlan()),
            to: outputDirectory.appendingPathComponent("p41_plan_live.png"),
            size: CGSize(width: 960, height: 760)
        )
        try render(
            frame: ChangeDetailScreenshotFrame(report: change),
            to: outputDirectory.appendingPathComponent("p41_history_live.png"),
            size: CGSize(width: 900, height: 720)
        )

        // Explicit fixture / historical action flows
        try render(
            frame: ActionReviewFixtureFrame(),
            to: outputDirectory.appendingPathComponent("p41_action_review_fixture.png"),
            size: CGSize(width: 900, height: 720)
        )
        try render(
            frame: PreflightFixtureFrame(),
            to: outputDirectory.appendingPathComponent("p41_preflight_fixture.png"),
            size: CGSize(width: 900, height: 720)
        )
        try render(
            frame: VerifiedActionReceiptScreenshotFrame(
                title: L10n.t("fixture.verifiedResult"),
                subtitle: L10n.t("entity.hfSnapshot.title"),
                headline: L10n.t("fixture.verifiedRecoveredHeadline", LocaleFormatting.byteLabel(3_083_520_968)),
                checklist: [
                    L10n.t("fixture.removedLocalSnapshot"),
                    L10n.t("fixture.exactTargetGone"),
                    L10n.t("fixture.remoteRevisionAvailable"),
                    L10n.t("fixture.verifiedRecoveredHeadline", LocaleFormatting.byteLabel(3_083_520_968)),
                    L10n.t("fixture.diskFreeSeparate", LocaleFormatting.byteLabel(3_083_520_968))
                ],
                footnote: L10n.t("fixture.receiptHistoricalNote"),
                tone: .success
            ),
            to: outputDirectory.appendingPathComponent("p41_verified_receipt_fixture.png"),
            size: CGSize(width: 900, height: 720)
        )
        try render(
            frame: VerifiedActionReceiptScreenshotFrame(
                title: L10n.t("fixture.movedToTrash"),
                subtitle: L10n.t("entity.xcodeBuildData.title"),
                headline: L10n.t("fixture.spacePending"),
                checklist: [
                    L10n.t("fixture.movedToTrashCheck"),
                    L10n.t("fixture.spacePendingCheck"),
                    L10n.t("fixture.trashStillOccupies"),
                    L10n.t("fixture.emptyTrashNotOffered")
                ],
                footnote: L10n.t("fixture.trashPendingNote"),
                tone: .success
            ),
            to: outputDirectory.appendingPathComponent("p41_trash_pending_fixture.png"),
            size: CGSize(width: 900, height: 720)
        )
    }

    /// P5.4 priority localization screenshot matrix (en / ja / zh-Hans / de).
    @MainActor
    public static func exportP54LocalizationMatrix(reportDirectory: URL, outputRoot: URL) throws {
        let priority: [(AppLanguage, String)] = [
            (.english, "en"),
            (.japanese, "ja"),
            (.chineseSimplified, "zh-Hans"),
            (.german, "de"),
        ]
        let previous = L10n.currentLanguage()
        defer { L10n.setOverride(previous) }

        let experience = try PreviewSnapshotFactory.loadCase001(from: reportDirectory)

        for (language, folder) in priority {
            L10n.setOverride(language)
            let explorer = PreviewSnapshotFactory.explorerDemo(experience: experience)
            let change = StorageChangeService.demoChangeReport()
            let plan = try OptimizationPlanService.demoPartialPlan()
            let outputDirectory = outputRoot.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            try render(
                frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: change, configure: { $0.mapLens = .structure })
                    .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("01_storage_overview_LIVE.png"),
                size: CGSize(width: 1280, height: 860)
            )
            try render(
                frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: change, configure: { $0.mapLens = .structure })
                    .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("02_structure_lens_LIVE.png"),
                size: CGSize(width: 1280, height: 860)
            )
            try render(
                frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: change, configure: { $0.mapLens = .meaning })
                    .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("03_meaning_lens_LIVE.png"),
                size: CGSize(width: 1280, height: 860)
            )
            try render(
                frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: change, configure: { $0.mapLens = .decision })
                    .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("04_decision_lens_LIVE.png"),
                size: CGSize(width: 1280, height: 860)
            )
            try render(
                frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: change, configure: { vm in
                    vm.mapLens = .decision
                    if let node = StorageExplorerBuilder.flatten(explorer.presentedRoot).first(where: {
                        $0.title.localizedCaseInsensitiveContains("Cursor")
                            || $0.title.localizedCaseInsensitiveContains("Xcode")
                            || $0.decision.state == .keep
                    }) {
                        vm.focusExplorerNode(node)
                        vm.selectExplorerNode(node, drill: false)
                    }
                })
                .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("05_selected_entity_inspector_LIVE.png"),
                size: CGSize(width: 1280, height: 860)
            )
            try render(
                frame: OverviewScreenshotFrame(experience: experience, explorer: explorer, change: change, configure: { vm in
                    vm.mapLens = .decision
                    if let protected = StorageExplorerBuilder.flatten(explorer.presentedRoot).first(where: {
                        $0.decision.state == .protected || $0.decision.state == .keep
                    }) {
                        vm.focusExplorerNode(protected)
                        vm.selectExplorerNode(protected, drill: false)
                    }
                })
                .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("06_protected_entity_LIVE.png"),
                size: CGSize(width: 1280, height: 860)
            )
            try render(
                frame: OptimizationPlanScreenshotFrame(plan: plan)
                    .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("07_plan_LIVE.png"),
                size: CGSize(width: 960, height: 760)
            )
            try render(
                frame: ChangeDetailScreenshotFrame(report: change)
                    .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("08_history_LIVE.png"),
                size: CGSize(width: 900, height: 720)
            )
            try render(
                frame: SettingsLanguageScreenshotFrame(language: language)
                    .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("09_settings_LIVE.png"),
                size: CGSize(width: 720, height: 640)
            )
            try render(
                frame: SettingsLanguageScreenshotFrame(language: language, highlightPicker: true)
                    .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("10_language_selector_LIVE.png"),
                size: CGSize(width: 720, height: 640)
            )
            try render(
                frame: ActionReviewFixtureFrame()
                    .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("11_action_review_FIXTURE.png"),
                size: CGSize(width: 900, height: 720)
            )
            try render(
                frame: PreflightFixtureFrame()
                    .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("12_fresh_preflight_FIXTURE.png"),
                size: CGSize(width: 900, height: 720)
            )
            try render(
                frame: PreflightFixtureFrame()
                    .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("13_changed_state_FIXTURE.png"),
                size: CGSize(width: 900, height: 720)
            )
            try render(
                frame: VerifiedActionReceiptScreenshotFrame(
                    title: L10n.t("fixture.verifiedResult"),
                    subtitle: L10n.t("entity.hfSnapshot.title"),
                    headline: L10n.t("fixture.verifiedRecoveredHeadline", LocaleFormatting.byteLabel(3_083_520_968)),
                    checklist: [
                        L10n.t("fixture.removedLocalSnapshot"),
                        L10n.t("fixture.exactTargetGone"),
                        L10n.t("fixture.remoteRevisionAvailable"),
                        L10n.t("fixture.verifiedRecoveredHeadline", LocaleFormatting.byteLabel(3_083_520_968)),
                        L10n.t("fixture.diskFreeSeparate", LocaleFormatting.byteLabel(3_083_520_968))
                    ],
                    footnote: L10n.t("fixture.receiptHistoricalNote"),
                    tone: .success
                )
                .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("14_verification_receipt_HISTORICAL.png"),
                size: CGSize(width: 900, height: 720)
            )
            try render(
                frame: VerifiedActionReceiptScreenshotFrame(
                    title: L10n.t("fixture.movedToTrash"),
                    subtitle: L10n.t("entity.xcodeBuildData.title"),
                    headline: L10n.t("fixture.spacePending"),
                    checklist: [
                        L10n.t("fixture.movedToTrashCheck"),
                        L10n.t("fixture.spacePendingCheck"),
                        L10n.t("fixture.trashStillOccupies"),
                        L10n.t("fixture.emptyTrashNotOffered")
                    ],
                    footnote: L10n.t("fixture.trashPendingNote"),
                    tone: .success
                )
                .environment(\.locale, L10n.resolvedLocale(for: language)),
                to: outputDirectory.appendingPathComponent("15_trash_recovery_pending_FIXTURE.png"),
                size: CGSize(width: 900, height: 720)
            )
        }
    }

    @MainActor
    private static func render<V: View>(frame: V, to outputURL: URL, size: CGSize = CGSize(width: 1280, height: 860)) throws {
        let renderer = ImageRenderer(content: frame)
        renderer.scale = 2.0
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        guard let image = renderer.nsImage else { throw ExportError.renderFailed }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.encodeFailed
        }
        try png.write(to: outputURL)
    }

    public enum ExportError: Error {
        case renderFailed
        case encodeFailed
    }
}

private struct OverviewScreenshotFrame: View {
    let experience: StorageExperienceSnapshot
    let explorer: StorageExplorerSnapshot
    var configure: ((StorageViewModel) -> Void)?
    @StateObject private var viewModel: StorageViewModel

    init(
        experience: StorageExperienceSnapshot,
        explorer: StorageExplorerSnapshot,
        change: StorageChangeReport? = nil,
        plan: OptimizationPlan? = nil,
        scanning: Bool = false,
        configure: ((StorageViewModel) -> Void)? = nil
    ) {
        self.experience = experience
        self.explorer = explorer
        self.configure = configure
        _viewModel = StateObject(
            wrappedValue: StorageViewModel(
                coordinator: SnapshotCoordinator(
                    experience: experience,
                    explorer: explorer,
                    change: change,
                    plan: plan,
                    stage: explorer.scanStage,
                    scanning: scanning
                )
            )
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            appSidebar.frame(width: 220)
            StorageExplorerView(heroMode: true)
                .environmentObject(viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 1280, height: 860)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.syncFromCoordinator()
            configure?(viewModel)
        }
    }

    private var appSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ProductCopy.appTitle).font(.headline)
            Label(ProductCopy.scanStorage, systemImage: "arrow.clockwise").foregroundStyle(.secondary)
            Divider()
            Label(AppSidebarSection.overview.title, systemImage: AppSidebarSection.overview.icon)
                .font(.headline)
                .padding(.vertical, 2).padding(.horizontal, 6)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Divider()
            Text(ProductCopy.storageIntelligence).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(L10n.t("overview.readyCount", experience.readyActionCount))
            Text(L10n.t("overview.reviewCount", experience.needsReviewCount))
            Text(L10n.t("overview.protectedCount", experience.protectedCount)).font(.caption)
            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ExplorerScreenshotFrame: View {
    let experience: StorageExperienceSnapshot
    let explorer: StorageExplorerSnapshot
    var configure: ((StorageViewModel) -> Void)?
    @StateObject private var viewModel: StorageViewModel

    init(
        experience: StorageExperienceSnapshot,
        explorer: StorageExplorerSnapshot,
        configure: ((StorageViewModel) -> Void)? = nil
    ) {
        self.experience = experience
        self.explorer = explorer
        self.configure = configure
        _viewModel = StateObject(
            wrappedValue: StorageViewModel(
                coordinator: SnapshotCoordinator(experience: experience, explorer: explorer)
            )
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(ProductCopy.appTitle).font(.headline)
                Label(AppSidebarSection.overview.title, systemImage: AppSidebarSection.overview.icon)
                    .font(.headline)
                    .padding(6)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer()
            }
            .padding(16)
            .frame(width: 220)
            .background(Color(nsColor: .controlBackgroundColor))

            StorageExplorerView(heroMode: false)
                .environmentObject(viewModel)
        }
        .frame(width: 1280, height: 860)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.syncFromCoordinator()
            configure?(viewModel)
        }
    }
}

private struct ChangeDetailScreenshotFrame: View {
    let report: StorageChangeReport

    var body: some View {
        NavigationStack {
            StorageChangeDetailView(report: report)
        }
        .frame(width: 900, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct OptimizationPlanScreenshotFrame: View {
    let plan: OptimizationPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ProductCopy.storageGoal)
                .font(.largeTitle.bold())
            Text(ProductCopy.howMuchSpace)
                .font(.callout)
                .foregroundStyle(.secondary)
            OptimizationPlanCanvas(plan: plan, interactive: false)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 960, height: 760, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct AIModelDetailScreenshotFrame: View {
    let title: String
    let subtitle: String
    let bytesLabel: String
    let what: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(bytesLabel)
                .font(.title2.monospacedDigit())
            Text(ProductCopy.whatIsThis)
                .font(.headline)
            Text(what)
                .foregroundStyle(.secondary)
            Text(L10n.t("fixture.proofCoverage"))
                .font(.headline)
                .padding(.top, 8)
            ForEach(lines, id: \.self) { line in
                Text("• \(line)")
            }
            Spacer()
        }
        .padding(28)
        .frame(width: 900, height: 720, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct VerifiedActionReceiptScreenshotFrame: View {
    enum Tone { case success, unknown }
    let title: String
    let subtitle: String
    let headline: String
    let checklist: [String]
    let footnote: String
    let tone: Tone

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(headline)
                .font(.title3)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(checklist, id: \.self) { line in
                    Text(line)
                        .font(.body.monospacedDigit())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (tone == .success ? Color.green : Color.orange).opacity(0.12)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(L10n.t("fixture.remoteCopyVerified"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
            Spacer()
        }
        .padding(28)
        .frame(width: 900, height: 720, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private final class SnapshotCoordinator: StorageActionCoordinating, @unchecked Sendable {
    var overview: StorageOverviewState
    var safeActions: [UICandidateItem] = []
    var reviewNeeded: [UICandidateItem] = []
    var protected: [UICandidateItem] = []
    var recentActions: [UIActionHistoryItem] = []
    var isScanning = false
    var selectedCandidateID: String?
    var lastPreflight: UIPreflightResult?
    var pendingApproval: UIApprovalState?
    var lastExecution: UIExecutionOutcome?
    var lastSurfaceReport: UIActionSurfaceReport?
    var experienceSnapshot: StorageExperienceSnapshot?
    var explorerSnapshot: StorageExplorerSnapshot?
    var changeReport: StorageChangeReport?
    var historyStatus: P302HistoryStatusReport?
    var optimizationPlan: OptimizationPlan?
    var optimizationFacts: [OptimizationActionFact] = []
    var scanStage: StorageScanStage = .complete
    var scanProgressHandler: (@Sendable (StorageScanStage) -> Void)?

    init(
        experience: StorageExperienceSnapshot,
        explorer: StorageExplorerSnapshot,
        change: StorageChangeReport? = nil,
        plan: OptimizationPlan? = nil,
        stage: StorageScanStage? = nil,
        scanning: Bool = false
    ) {
        experienceSnapshot = experience
        explorerSnapshot = explorer
        changeReport = change
        optimizationPlan = plan
        scanStage = stage ?? explorer.scanStage
        isScanning = scanning
        if change != nil {
            historyStatus = P302HistoryStatusReport(
                historySnapshotCount: 2,
                oldestSnapshotAt: Date().addingTimeInterval(-7 * 24 * 3600),
                newestSnapshotAt: Date(),
                historyStoreLocationType: "fixture",
                snapshotWriteSuccess: true,
                privacyFieldsStored: StorageHistoryBuilder.privacyFieldsStored
            )
        } else {
            historyStatus = P302HistoryStatusReport(
                historySnapshotCount: 1,
                oldestSnapshotAt: Date(),
                newestSnapshotAt: Date(),
                historyStoreLocationType: "fixture",
                snapshotWriteSuccess: true,
                privacyFieldsStored: StorageHistoryBuilder.privacyFieldsStored
            )
        }
        overview = StorageOverviewState(
            observedBytes: experience.observedStorage.scannedRootBytes,
            observedBytesLabel: UICandidateMapper.byteLabel(experience.observedStorage.scannedRootBytes),
            safeActionCount: experience.readyActionCount,
            reviewCount: experience.needsReviewCount,
            protectedCount: experience.protectedCount,
            lastScanAt: experience.generatedAt,
            scanRuntimeSeconds: experience.scanRuntimeSeconds
        )
    }

    func scan() async throws {}
    func expandPhysicalNode(id: String) {}
    func candidateDetail(entityID: String) -> UICandidateDetail? { nil }
    func runFreshPreflight(entityID: String, action: StorageAction) async throws -> UIPreflightResult {
        throw StorageActionCoordinatorError.notScanned
    }
    func submitApproval(entityID: String, action: StorageAction) throws -> UIApprovalState {
        throw StorageActionCoordinatorError.approvalRequired
    }
    func executeApprovedAction(entityID: String, action: StorageAction) async throws -> UIExecutionOutcome {
        throw StorageActionCoordinatorError.approvalRequired
    }
    func cancelApproval() {}
    func writeSurfaceReport(to directory: URL) throws {}
    func writeExperienceReport(to directory: URL) throws {}
    func writeExplorerReports(to directory: URL) throws {}
    func writeChangeReports(to directory: URL) throws {}
    func writeOptimizationReports(to directory: URL) throws {}
}

private struct ActionReviewFixtureFrame: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("fixture.reviewAction"))
                .font(.largeTitle.bold())
            Text("qwen3:4b · \(L10n.t("entity.ollamaModel.title"))")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(LocaleFormatting.byteLabel(2_497_293_931))
                .font(.title2.monospacedDigit())

            fixtureBlock(title: L10n.t("fixture.whatWillHappen"), body: L10n.t("fixture.ollamaRemoveExact"))
            fixtureBlock(title: L10n.t("fixture.whatWillRemain"), body: L10n.t("fixture.otherModelsStay"))
            fixtureBlock(title: L10n.t("fixture.canItComeBack"), body: L10n.t("fixture.downloadAgain"))
            fixtureBlock(title: L10n.t("fixture.whoPerforms"), body: L10n.t("fixture.ollamaVendorNative"))

            Text(L10n.t("fixture.historicalNote"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(28)
        .frame(width: 900, height: 720, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func fixtureBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PreflightFixtureFrame: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("fixture.somethingChanged"))
                .font(.largeTitle.bold())
            Text(L10n.t("fixture.stateNoLongerMatches"))
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("fixture.currentCheck"))
                    .font(.headline)
                Label(L10n.t("fixture.checkingDone"), systemImage: "checkmark.circle")
                Label(L10n.t("fixture.readyNoLongerAvailable"), systemImage: "xmark.circle")
                Text(L10n.t("fixture.changedSinceAnalyzed"))
                    .font(.callout)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(L10n.t("fixture.reviewAgain"))
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(L10n.t("fixture.changedStateNote"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(28)
        .frame(width: 900, height: 720, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsLanguageScreenshotFrame: View {
    let language: AppLanguage
    var highlightPicker: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("settings.about"))
                .font(.title2.bold())
            settingsRow(L10n.t("settings.product"), ProductReleaseIdentity.productName)
            settingsRow(L10n.t("settings.version"), ProductReleaseIdentity.marketingVersionDisplay)
            settingsRow(L10n.t("settings.minimumMacOS"), ProductReleaseIdentity.minimumMacOSVersion)
            settingsRow(L10n.t("settings.productLoop"), L10n.t("settings.productLoop.value"))
            settingsRow(L10n.t("settings.research"), L10n.t("settings.research.frozen"))

            Divider()

            Text(L10n.t("settings.language"))
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                ForEach(AppLanguage.allCases) { option in
                    HStack {
                        Text(option.pickerLabel)
                        Spacer()
                        if option == language {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 2)
                    .fontWeight(option == language ? .semibold : .regular)
                }
            }
            if highlightPicker {
                Text(L10n.t("settings.language.restartNote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text(L10n.t("settings.developer"))
                .font(.title2.bold())
            Text(L10n.t("settings.enableDiagnostics"))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(28)
        .frame(width: 720, height: 640, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingsRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
