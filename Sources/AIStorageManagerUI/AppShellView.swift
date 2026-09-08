import SwiftUI
import AppServices
import SafetyCore

public struct AppShellView: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    @EnvironmentObject private var languageStore: LanguageStore
    /// `ASM_START_SECTION=settings` opens Settings for packaging QA without AX clicks.
    @State private var section: AppSidebarSection = AppShellView.initialSection()
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var showTechnicalDebug = false
#if DEBUG
    @State private var debugMenuEnabled = true
#else
    @State private var debugMenuEnabled = false
#endif

    public init() {}

    private static func initialSection() -> AppSidebarSection {
        switch ProcessInfo.processInfo.environment["ASM_START_SECTION"]?.lowercased() {
        case "settings": return .settings
        case "storagegoal", "plan": return .storageGoal
        case "recentactions", "history": return .recentActions
        default: return .overview
        }
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            mainContent
        } detail: {
            detailPane
        }
        .navigationTitle(ProductCopy.appTitle)
        .id(languageStore.language) // force shell refresh on language change
        .environment(\.locale, languageStore.resolvedLocale)
        .task {
            if viewModel.experienceSnapshot == nil {
                await viewModel.scan()
            }
            syncColumnVisibility()
        }
        .onChange(of: section) { _ in syncColumnVisibility() }
        .onChange(of: viewModel.selectedMapNodeID) { _ in syncColumnVisibility() }
        .onChange(of: viewModel.selectedExplorerNodeID) { _ in syncColumnVisibility() }
        .onChange(of: viewModel.selectedCandidateID) { _ in syncColumnVisibility() }
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                scanButton
            }
            Section(L10n.t("sidebar.navigate")) {
                ForEach(AppSidebarSection.allCases) { item in
                    Label(item.title, systemImage: item.icon)
                        .tag(item)
                }
            }
            if let snapshot = viewModel.experienceSnapshot {
                Section(L10n.t("sidebar.ataGlance")) {
                    glanceRow(ProductCopy.readyActions, value: "\(snapshot.readyActionCount)")
                    glanceRow(ProductCopy.needsReview, value: "\(snapshot.needsReviewCount)")
                    glanceRow(ProductCopy.protectedItems, value: "\(snapshot.protectedCount)")
                    glanceRow(
                        ProductCopy.verifiedRecovered,
                        value: ByteFormat.label(StorageProductPresentationBuilder.verifiedCompletedRecoveryTotal)
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200, idealWidth: 220)
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isScanning && viewModel.experienceSnapshot == nil && viewModel.explorerSnapshot == nil {
            ProgressView(ProductCopy.scanning)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch section {
            case .overview:
                OverviewView()
            case .storageGoal:
                OptimizationPlanView()
            case .recentActions:
                RecentActionsView()
            case .settings:
                SettingsDebugGateView(
                    debugEnabled: $debugMenuEnabled,
                    showTechnical: $showTechnicalDebug
                )
                .environmentObject(languageStore)
                .sheet(isPresented: $showTechnicalDebug) {
                    NavigationStack {
                        TechnicalDebugView()
                            .environmentObject(viewModel)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button(L10n.t("common.done")) { showTechnicalDebug = false }
                                }
                            }
                    }
                    .frame(minWidth: 720, minHeight: 520)
                }
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if showTechnicalDebug, viewModel.selectedCandidateID != nil, let detail = viewModel.candidateDetail {
            CandidateDetailView(detail: detail)
        } else if let node = viewModel.selectedMapNode {
            EntitySelectionPanel(node: node)
        } else if viewModel.selectedCandidateID != nil, let detail = viewModel.candidateDetail {
            EntitySelectionPanel(entityID: detail.item.entityID, detail: detail)
        } else {
            detailSelectionHint
        }
    }

    private var detailSelectionHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(ProductCopy.detailPaneHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanButton: some View {
        Button {
            Task { await viewModel.scan() }
        } label: {
            Label(viewModel.isScanning ? ProductCopy.scanning : ProductCopy.scanStorage, systemImage: "arrow.clockwise")
        }
        .disabled(viewModel.isScanning)
    }

    private func glanceRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func syncColumnVisibility() {
        columnVisibility = shouldShowDetailColumn ? .all : .doubleColumn
    }

    private var shouldShowDetailColumn: Bool {
        if section == .overview {
            return viewModel.selectedCandidateID != nil && viewModel.candidateDetail != nil
        }
        if viewModel.selectedMapNode != nil { return true }
        if section == .storageGoal {
            return viewModel.selectedCandidateID != nil
        }
        return false
    }
}

private struct SettingsDebugGateView: View {
    @EnvironmentObject private var languageStore: LanguageStore
    @Binding var debugEnabled: Bool
    @Binding var showTechnical: Bool

    var body: some View {
        // Do NOT use Form + maxHeight:.infinity here.
        // On macOS NavigationSplitView content columns, that combo collapses to a blank pane
        // (title still updates). Same class of bug fixed for ImageRenderer in P5.4 screenshots.
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsSection(L10n.t("settings.about")) {
                    settingsRow(L10n.t("settings.product"), ProductReleaseIdentity.productName)
                    settingsRow(L10n.t("settings.version"), ProductReleaseIdentity.marketingVersionDisplay)
                    settingsRow(L10n.t("settings.bundleID"), ProductReleaseIdentity.bundleIdentifier)
                    settingsRow(L10n.t("settings.minimumMacOS"), ProductReleaseIdentity.minimumMacOSVersion)
                    settingsRow(L10n.t("settings.productLoop"), L10n.t("settings.productLoop.value"))
                    settingsRow(
                        L10n.t("settings.research"),
                        ProductizationInvariants.researchFrozen ? L10n.t("settings.research.frozen") : "Open"
                    )
                    settingsRow(
                        L10n.t("verification.recovered.title"),
                        ByteFormat.label(StorageProductPresentationBuilder.verifiedCompletedRecoveryTotal)
                    )
                }

                settingsSection(ProductCopy.permissionBenefitTitle) {
                    Text(ProductCopy.permissionBenefitBody)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ProductCopy.permissionDeniedSafeNote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsSection(L10n.t("settings.language")) {
                    Picker(L10n.t("settings.language"), selection: $languageStore.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.pickerLabel).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320, alignment: .leading)
                    Text(L10n.t("settings.language.restartNote"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsSection(L10n.t("settings.developer")) {
                    Toggle(L10n.t("settings.enableDiagnostics"), isOn: $debugEnabled)
                    Button(L10n.t("settings.openTechnical")) {
                        showTechnical = true
                    }
                    .disabled(!debugEnabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(ProductCopy.settingsNav)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
    }

    private func settingsRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(minWidth: 140, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
