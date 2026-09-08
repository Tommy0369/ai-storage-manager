import SwiftUI
import AppServices

struct StorageExplorerView: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    var heroMode: Bool = false

    var body: some View {
        Group {
            if let explorer = viewModel.explorerSnapshot {
                explorerBody(explorer)
            } else if viewModel.isScanning {
                progressiveEmpty
            } else {
                ContentUnavailableCompat(
                    title: ProductCopy.noScanTitle,
                    systemImage: "externaldrive",
                    description: ProductCopy.noScanDescription
                )
            }
        }
        .navigationTitle(heroMode ? ProductCopy.overviewTitle : ProductCopy.exploreStorage)
    }

    private func explorerBody(_ explorer: StorageExplorerSnapshot) -> some View {
        VStack(spacing: 0) {
            if !heroMode {
                toolbar
                Divider()
            } else {
                CompactDiskSummaryBar(snapshot: viewModel.experienceSnapshot ?? experienceFallback(explorer))
                Divider()
                storyBar(explorer)
                Divider()
            }

            if scanStatus.showsBanner {
                stageBanner
                Divider()
            }

            if viewModel.explorerMode == .largestItems {
                largestList(explorer)
            } else {
                mapSplit(explorer)
            }

            if heroMode {
                Divider()
                StorageChangeCompactPanel(
                    report: viewModel.changeReport,
                    isScanning: viewModel.isScanning,
                    scanStage: viewModel.scanStage,
                    onSeeDetails: { viewModel.showChangeDetail = true }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                OptimizationGoalEntryPanel(
                    readyCount: viewModel.experienceSnapshot?.readyActionCount ?? 0,
                    onFree10: {
                        viewModel.buildOptimizationPlan(gigabytes: 10)
                    },
                    onFree20: {
                        viewModel.buildOptimizationPlan(gigabytes: 20)
                    },
                    onOpenCustom: {
                        viewModel.showOptimizationPlan = true
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                Divider()
                if let experience = viewModel.experienceSnapshot {
                    OverviewIntelligenceFooter(snapshot: experience)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .onExitCommand { viewModel.explorerGoUp() }
        .sheet(isPresented: $viewModel.showChangeDetail) {
            NavigationStack {
                StorageChangeDetailView(report: viewModel.changeReport)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.t("common.done")) { viewModel.showChangeDetail = false }
                        }
                    }
            }
            .frame(minWidth: 640, minHeight: 520)
        }
        .sheet(isPresented: $viewModel.showOptimizationPlan) {
            NavigationStack {
                OptimizationPlanView()
                    .environmentObject(viewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.t("common.done")) { viewModel.showOptimizationPlan = false }
                        }
                    }
            }
            .frame(minWidth: 720, minHeight: 560)
        }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { viewModel.explorerBack() } label: { Image(systemName: "chevron.backward") }
                    .disabled(!viewModel.canExplorerBack)
                Button { viewModel.explorerForward() } label: { Image(systemName: "chevron.forward") }
                    .disabled(!viewModel.canExplorerForward)
                ExplorerBreadcrumbBar(
                    path: viewModel.explorerFocusPath,
                    onNavigate: viewModel.focusExplorerPath
                )
                Spacer()
                Picker("", selection: Binding(
                    get: { viewModel.mapLens },
                    set: { viewModel.mapLens = $0 }
                )) {
                    ForEach(StorageMapLens.allCases) { lens in
                        Text(lens.title).tag(lens)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Picker("", selection: Binding(
                    get: { viewModel.explorerMode },
                    set: { viewModel.explorerMode = $0 }
                )) {
                    Text(ProductCopy.mapMode).tag(ExplorerViewMode.map)
                    Text(ProductCopy.largestItems).tag(ExplorerViewMode.largestItems)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(ProductCopy.searchPlaceholder, text: Binding(
                    get: { viewModel.explorerSearch },
                    set: { viewModel.explorerSearch = $0 }
                ))
                .textFieldStyle(.plain)
                if !viewModel.explorerSearch.isEmpty {
                    Button(ProductCopy.clearSearch) { viewModel.explorerSearch = "" }
                        .font(.caption)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !viewModel.explorerSearch.isEmpty {
                searchResults
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func storyBar(_ explorer: StorageExplorerSnapshot) -> some View {
        HStack(spacing: 16) {
            Picker("", selection: Binding(
                get: { viewModel.mapLens },
                set: { viewModel.mapLens = $0 }
            )) {
                ForEach(StorageMapLens.allCases) { lens in
                    Text(lens.title).tag(lens)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if let note = StorageScanStatusResolver.partialCoverageNote(
                        stage: viewModel.scanStage,
                        coverage: explorer.mapAccounting?.coverage
                    ) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    ForEach(StorageExplorerBuilder.stories(from: explorer), id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// v0.2 UX FIX 001 — one canonical status sentence.
    ///
    /// Previously this stacked a stage label and a "scanning deeper" chip next to
    /// an always-on spinner, so a failed scan could read
    /// "Scan failed" + "Scanning deeper…" at the same time.
    private var scanStatus: StorageScanStatus {
        StorageScanStatusResolver.resolve(
            stage: viewModel.scanStage,
            coverage: viewModel.explorerSnapshot?.mapAccounting?.coverage
        )
    }

    private var stageBanner: some View {
        let status = scanStatus
        return HStack(spacing: 8) {
            if status.isRunning {
                ProgressView()
                    .controlSize(.small)
            } else if status == .failed {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            Text(status.localizedText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    /// v0.2 UX FIX 001 — the map/inspector boundary is a real, native split.
    ///
    /// This used to be `HStack { map; Divider(); inspector.frame(width: 320) }`.
    /// That drew a separator identical to the window's NavigationSplitView
    /// divider, but it was inert: the boundary lived in a hardcoded 320pt frame,
    /// not in the divider. Two identical-looking vertical rules, only one of them
    /// draggable — so after dragging the real one, the inert twin read as a
    /// stale line left behind at the old position.
    ///
    /// `HSplitView` gives the separator and the boundary a single owner
    /// (AppKit's NSSplitView), so the line the user sees *is* the line they drag,
    /// through drag, resize, fullscreen and restore.
    private func mapSplit(_ explorer: StorageExplorerSnapshot) -> some View {
        let focus = viewModel.explorerFocusNode ?? explorer.presentedRoot
        return HSplitView {
            VStack(spacing: 0) {
                if heroMode {
                    ExplorerBreadcrumbBar(
                        path: viewModel.explorerFocusPath.isEmpty ? [explorer.presentedRoot] : viewModel.explorerFocusPath,
                        onNavigate: viewModel.focusExplorerPath
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                MultiRingSunburstView(
                    focus: focus,
                    lens: viewModel.mapLens,
                    selectedID: $viewModel.selectedExplorerNodeID,
                    hoveredID: $viewModel.hoveredExplorerNodeID,
                    ringCount: 3,
                    prominence: .hero,
                    onSelect: { viewModel.selectExplorerNode($0, drill: false) },
                    onDrill: { viewModel.selectExplorerNode($0, drill: true) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .padding(8)

                if let hovered = viewModel.hoveredExplorerNode {
                    hoverCard(hovered, focus: focus)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            // The map is the hero: it takes the slack so the inspector settles
            // near its ideal width instead of an even 50/50 split.
            .layoutPriority(1)

            ExplorerInspectorView(
                node: viewModel.selectedExplorerNode ?? focus,
                focus: focus,
                selectedID: viewModel.selectedExplorerNodeID,
                compact: heroMode,
                onSelectChild: { viewModel.selectExplorerNode($0, drill: true) },
                onReveal: { QuickLookSupport.revealInFinder(path: $0.physical.canonicalPath) },
                onPreview: { _ = QuickLookController.shared.present(path: $0.physical.canonicalPath) },
                onReview: { viewModel.openCandidate($0) }
            )
            // Default width matches v0.1 exactly (the map takes the slack), but the
            // boundary is now a real splitter, so the inspector can be widened.
            .frame(
                minWidth: heroMode ? 320 : 360,
                idealWidth: heroMode ? 320 : 360,
                maxWidth: 560,
                maxHeight: .infinity
            )
        }
        .frame(minHeight: heroMode ? 520 : 560)
    }

    private func largestList(_ explorer: StorageExplorerSnapshot) -> some View {
        let items = StorageExplorerBuilder.largestItems(root: explorer.presentedRoot)
        return List(items) { item in
            Button {
                viewModel.focusExplorerNode(item)
                viewModel.explorerMode = .map
            } label: {
                HStack {
                    Image(systemName: item.physical.isFile ? "doc" : "folder")
                    Text(item.title)
                    Spacer()
                    Text(ByteFormat.label(item.bytes)).monospacedDigit().foregroundStyle(.secondary)
                    Text(item.decision.label).font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var searchResults: some View {
        let hits: [StorageNodePresentation] = {
            guard let root = viewModel.explorerSnapshot?.presentedRoot else { return [] }
            return StorageExplorerBuilder.search(root: root, query: viewModel.explorerSearch)
        }()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                if hits.isEmpty {
                    Text(ProductCopy.noMatchesYet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(hits.prefix(12)) { hit in
                    Button(hit.title) {
                        viewModel.focusExplorerNode(hit)
                        viewModel.explorerSearch = ""
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func hoverCard(_ node: StorageNodePresentation, focus: StorageNodePresentation) -> some View {
        let percent = focus.bytes > 0 ? Double(node.bytes) / Double(focus.bytes) * 100 : 0
        return HStack(spacing: 12) {
            Text(node.title).font(.subheadline.weight(.semibold))
            Text(ByteFormat.label(node.bytes)).monospacedDigit()
            Text(String(format: "%.1f%%", percent)).foregroundStyle(.secondary)
            Text(node.semanticCategory.displayName).foregroundStyle(.secondary)
            Text(node.decision.label).foregroundStyle(.secondary)
            Spacer()
        }
        .font(.caption)
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var progressiveEmpty: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(scanStatus.localizedText)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(ProductCopy.analysisStillRunning)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func experienceFallback(_ explorer: StorageExplorerSnapshot) -> StorageExperienceSnapshot {
        StorageExperienceSnapshot(
            diskCapacity: explorer.diskCapacity,
            observedStorage: ObservedStorageSnapshot(
                scannedRootBytes: explorer.physicalMapBytes,
                classifiedUniqueBytes: explorer.uniqueClassifiedBytes,
                unclassifiedBytes: explorer.unclassifiedBytes,
                selectedRootLabel: explorer.presentedRoot.title
            ),
            mapRoot: StorageMapNode(
                id: "fallback",
                title: explorer.presentedRoot.title,
                bytes: explorer.physicalMapBytes,
                semanticCategory: .otherUnknown
            ),
            categories: [],
            insights: explorer.insights,
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
            mapAccountingValid: explorer.accountingValid,
            mapRootBytes: explorer.physicalMapBytes,
            generatedAt: explorer.generatedAt
        )
    }
}

struct ExplorerBreadcrumbBar: View {
    let path: [StorageNodePresentation]
    let onNavigate: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text(ProductCopy.disksBreadcrumb)
                    .foregroundStyle(.secondary)
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Button(node.title) { onNavigate(index) }
                        .buttonStyle(.plain)
                        .font(index == path.count - 1 ? .subheadline.weight(.semibold) : .subheadline)
                }
            }
        }
    }
}

struct ContentUnavailableCompat: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum ExplorerViewMode: String, CaseIterable, Identifiable {
    case map
    case largestItems
    var id: String { rawValue }
}

struct OverviewIntelligenceFooter: View {
    let snapshot: StorageExperienceSnapshot
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text(ProductCopy.intelligenceSectionTitle)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(ProductCopy.readyActions) \(snapshot.readyActionCount)")
                        .font(.caption)
                    Text("\(ProductCopy.needsReview) \(snapshot.needsReviewCount)")
                        .font(.caption)
                        .foregroundStyle(snapshot.needsReviewCount > 0 ? .orange : .secondary)
                    Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDetails {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        IntelligenceCardView(
                            title: ProductCopy.readyActions,
                            value: "\(snapshot.readyActionCount)",
                            subtitle: ProductCopy.readyActionsHint,
                            tint: .green
                        )
                        IntelligenceCardView(
                            title: ProductCopy.needsReview,
                            value: "\(snapshot.needsReviewCount)",
                            subtitle: ProductCopy.needsReviewHint,
                            tint: .orange
                        )
                        IntelligenceCardView(
                            title: ProductCopy.protectedItems,
                            value: "\(snapshot.protectedCount)",
                            subtitle: ProductCopy.protectedHint,
                            tint: .blue
                        )
                    }
                    .padding(16)
                }
                .frame(height: 120)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
}
