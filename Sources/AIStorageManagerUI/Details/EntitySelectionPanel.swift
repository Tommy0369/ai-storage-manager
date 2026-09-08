import SwiftUI
import AppServices

struct EntitySelectionPanel: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    var node: StorageMapNode?
    var entityID: String?
    var detail: UICandidateDetail?

    init(node: StorageMapNode) {
        self.node = node
        self.entityID = node.entityID
        self.detail = nil
    }

    init(entityID: String, detail: UICandidateDetail) {
        self.node = nil
        self.entityID = entityID
        self.detail = detail
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                whatSection
                recommendationSection
                if let detail {
                    actionSection(detail: detail)
                } else if let entityID {
                    reviewButton(entityID: entityID)
                }
                technicalSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if let entityID, detail == nil {
                viewModel.openCandidate(entityID)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayTitle)
                .font(.largeTitle.bold())
            if let subtitle = node?.subtitle ?? detail?.item.category {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text(displayBytes)
                .font(.title2.monospacedDigit())
            if let state = node?.presentationState {
                Label(presentationLabel(state), systemImage: presentationIcon(state))
                    .font(.callout)
            }
        }
    }

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProductCopy.whatIsThis)
                .font(.headline)
            Text(whatDescription)
                .font(.body)
                .foregroundStyle(.secondary)
            if let why = whyLarge {
                Text(ProductCopy.whyLarge)
                    .font(.headline)
                    .padding(.top, 4)
                Text(why)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recommendationSection: some View {
        GroupBox(ProductCopy.whatShouldIDo) {
            VStack(alignment: .leading, spacing: 8) {
                Text(recommendationLabel)
                    .font(.headline)
                if let action = node?.actionSummary ?? detail?.item.recommendedActionLabel {
                    Text(action)
                        .font(.callout)
                }
                if let detail {
                    Text(detail.recoverySemantics)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func actionSection(detail: UICandidateDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if detail.item.group == .safeActions {
                Button(ProductCopy.checkCurrentSafety) {
                    Task { await viewModel.runPreflight() }
                }
                .disabled(viewModel.isPreflighting)

                if viewModel.preflight?.canApprove == true {
                    Button(ProductCopy.reviewAndApprove) {
                        viewModel.presentApproval()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if let outcome = viewModel.executionOutcome {
                ExecutionResultView(outcome: outcome)
            }
        }
        .sheet(isPresented: $viewModel.showApprovalSheet) {
            ApprovalView(detail: detail)
                .environmentObject(viewModel)
        }
    }

    private func reviewButton(entityID: String) -> some View {
        Button(ProductCopy.openFullReview) {
            viewModel.openCandidate(entityID)
        }
    }

    private var technicalSection: some View {
        DisclosureGroup(ProductCopy.technicalDetails) {
            VStack(alignment: .leading, spacing: 4) {
                if let tech = node?.technicalEntityID ?? detail?.technicalDetails.entityID {
                    detailRow("Entity ID", tech)
                }
                if let path = node?.pathSummary ?? detail?.technicalDetails.canonicalPath {
                    detailRow("Path", path)
                }
                if let detail {
                    detailRow("Safety Class", detail.technicalDetails.safetyClass)
                    detailRow("Readiness", detail.technicalDetails.readiness)
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .frame(width: 100, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private var displayTitle: String {
        node?.title ?? detail?.item.displayName ?? ProductCopy.storageItem
    }

    private var displayBytes: String {
        if let node { return ByteFormat.label(node.bytes) }
        return detail?.item.byteLabel ?? "—"
    }

    private var whatDescription: String {
        if let detail {
            if detail.item.entityID.contains("ollama") || detail.item.fullPath.contains(".ollama") {
                return L10n.t("detail.ollamaLocal")
            }
            if detail.item.entityID.contains("ai.hf") || detail.item.fullPath.contains("huggingface") {
                return L10n.t("detail.hfLocal")
            }
            return detail.item.reasonSummary
        }
        return node?.subtitle ?? L10n.t("detail.categoryOnMac")
    }

    private var whyLarge: String? {
        guard let detail else { return nil }
        let lines = detail.item.evidenceLines
        let unique = lines.first { $0.id == "unique" }?.userText
        let shared = lines.first { $0.id == "shared" }?.userText
        if unique != nil || shared != nil {
            return [unique, shared].compactMap { $0 }.joined(separator: "\n")
        }
        if detail.item.entityID.contains("ollama") {
            return L10n.t("detail.ollamaSharedNote")
        }
        if detail.item.entityID.contains("ai.hf") || detail.item.fullPath.contains("huggingface") {
            return L10n.t("detail.hfRedownloadNote")
        }
        return nil
    }

    private var recommendationLabel: String {
        switch node?.presentationState {
        case .readyToOptimize: return L10n.t("presentation.readyToOptimize")
        case .verificationNeeded: return L10n.t("presentation.verificationNeeded")
        case .protected: return ProductCopy.protectedLabel
        case .recoveryPending: return L10n.t("presentation.recoveryPending")
        default:
            if detail?.item.group == .safeActions { return L10n.t("presentation.readyToOptimize") }
            if detail?.item.group == .reviewNeeded { return L10n.t("presentation.verificationNeeded") }
            if detail?.item.group == .protected { return ProductCopy.protectedLabel }
            return L10n.t("presentation.noRecommendationYet")
        }
    }

    private func presentationLabel(_ state: StoragePresentationState) -> String {
        switch state {
        case .readyToOptimize: return L10n.t("presentation.readyToOptimize")
        case .verificationNeeded: return L10n.t("presentation.verificationNeeded")
        case .protected: return ProductCopy.protectedLabel
        case .keep: return L10n.t("decision.keep.title")
        case .recoveryPending: return L10n.t("presentation.diskRecoveryPending")
        case .noRecommendation: return L10n.t("presentation.noRecommendationYet")
        case .informational: return L10n.t("presentation.informational")
        }
    }

    private func presentationIcon(_ state: StoragePresentationState) -> String {
        switch state {
        case .readyToOptimize: return "checkmark.circle"
        case .verificationNeeded: return "eye"
        case .protected: return "lock.shield"
        case .recoveryPending: return "exclamationmark.triangle"
        default: return "info.circle"
        }
    }
}

struct TechnicalDebugView: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(ProductCopy.technicalDebugTitle)
                    .font(.title2.bold())
                Spacer()
                TextField(ProductCopy.debugSearchPlaceholder, text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }
            .padding()
            List(selection: $viewModel.selectedCandidateID) {
                candidateSection(title: ProductCopy.safeActions, items: filtered(viewModel.safeActions))
                candidateSection(title: ProductCopy.needsReview, items: filtered(viewModel.reviewNeeded))
                candidateSection(title: ProductCopy.protectedItems, items: filtered(viewModel.protected))
            }
            .listStyle(.inset)
        }
    }

    private func filtered(_ items: [UICandidateItem]) -> [UICandidateItem] {
        guard !search.isEmpty else { return items }
        let q = search.lowercased()
        return items.filter {
            $0.displayName.lowercased().contains(q)
                || $0.category.lowercased().contains(q)
                || $0.entityID.lowercased().contains(q)
                || $0.fullPath.lowercased().contains(q)
        }
    }

    @ViewBuilder
    private func candidateSection(title: String, items: [UICandidateItem]) -> some View {
        Section(title) {
            ForEach(items) { item in
                CandidateRow(item: item)
                    .tag(item.entityID)
                    .onTapGesture { viewModel.openCandidate(item.entityID) }
            }
        }
    }
}
