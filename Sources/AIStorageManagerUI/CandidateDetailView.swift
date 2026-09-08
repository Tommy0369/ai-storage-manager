import SwiftUI
import AppServices

struct CandidateDetailView: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    let detail: UICandidateDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                evidenceSection
                recommendationSection
                preflightSection
                executionSection
                technicalSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $viewModel.showApprovalSheet) {
            ApprovalView(detail: detail)
                .environmentObject(viewModel)
        }
        .onAppear {
            viewModel.openCandidate(detail.item.entityID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.item.displayName)
                .font(.largeTitle.bold())
            Text(detail.item.category)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(detail.item.pathSummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(detail.item.byteLabel)
                .font(.title2.monospacedDigit())
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProductCopy.whyRemovable)
                .font(.headline)
            ForEach(detail.item.evidenceLines) { line in
                Label(line.userText, systemImage: line.satisfied ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(line.satisfied ? Color.primary : Color.red)
                    .font(.body)
            }
        }
    }

    private var recommendationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(ProductCopy.recommended)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detail.item.recommendedActionLabel)
                    .font(.title3.weight(.semibold))
                Text(detail.item.reasonSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var preflightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isPreflighting {
                HStack {
                    ProgressView()
                    Text(ProductCopy.checkingCurrentSafety)
                }
            } else if let preflight = viewModel.preflight {
                GroupBox(ProductCopy.freshSafetyCheck) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(preflight.userMessage)
                            .font(.headline)
                        ForEach(preflight.satisfiedLines) { line in
                            Label(line.userText, systemImage: "checkmark.circle.fill")
                        }
                        ForEach(preflight.blockingLines) { line in
                            Label(line.userText, systemImage: "xmark.circle.fill")
                                .foregroundStyle(Color.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if viewModel.actionFlowPhase == .needsReviewAgain {
                GroupBox(ProductCopy.somethingChanged) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.errorMessage ?? ProductCopy.somethingChanged)
                            .font(.callout)
                        Button(ProductCopy.reviewAgain) {
                            Task { await viewModel.runPreflight() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Button(ProductCopy.runSafetyCheck) {
                    Task { await viewModel.runPreflight() }
                }
                .disabled(viewModel.isPreflighting || viewModel.isExecuting)

                if viewModel.preflight?.canApprove == true && viewModel.pendingApproval == nil {
                    Button(ProductCopy.reviewAndApprove) {
                        viewModel.presentApproval()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if viewModel.canMoveToTrash {
                    Button(ProductCopy.moveToTrash) {
                        Task { await viewModel.execute() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(viewModel.isExecuting)
                    .accessibilityHint(viewModel.moveButtonDisabledReason ?? "")
                }
            }

            if viewModel.isExecuting {
                Label(ProductCopy.movingToTrash, systemImage: "arrow.triangle.2.circlepath")
            }

            if let error = viewModel.errorMessage, viewModel.actionFlowPhase != .needsReviewAgain {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.red)
                    .font(.callout)
                Button(ProductCopy.runSafetyCheckAgain) {
                    Task { await viewModel.runPreflight() }
                }
            }
        }
    }

    @ViewBuilder
    private var executionSection: some View {
        if let outcome = viewModel.executionOutcome {
            ExecutionResultView(outcome: outcome)
        }
    }

    private var technicalSection: some View {
        DisclosureGroup(ProductCopy.technicalDetails) {
            VStack(alignment: .leading, spacing: 4) {
                detailRow("Entity ID", detail.technicalDetails.entityID)
                detailRow("Path", detail.technicalDetails.canonicalPath)
                detailRow("Safety Class", detail.technicalDetails.safetyClass)
                detailRow("Readiness", detail.technicalDetails.readiness)
                if let gate = detail.technicalDetails.gateReadiness {
                    detailRow("Gate", gate)
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
}

struct ExecutionResultView: View {
    let outcome: UIExecutionOutcome

    var body: some View {
        GroupBox(outcome.readiness.userLabel) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(outcome.userLines, id: \.self) { line in
                    Label(line, systemImage: icon(for: line))
                }
                if let potential = outcome.potentialRecoveryLabel {
                    Text(potential)
                        .font(.callout)
                }
                Text(outcome.recoveryLabel)
                    .font(.headline)
                    .foregroundStyle(outcome.storageRecoveryState == .recoveryVerified ? Color.primary : Color.orange)
                if let warning = outcome.trashWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func icon(for line: String) -> String {
        if line.contains("pending") || line.contains("remains") { return "exclamationmark.triangle" }
        if outcome.readiness == .failed { return "xmark.circle" }
        return "checkmark.circle.fill"
    }
}

struct ApprovalView: View {
    @EnvironmentObject private var viewModel: StorageViewModel
    @Environment(\.dismiss) private var dismiss
    let detail: UICandidateDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(ProductCopy.approveAction)
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text(detail.item.displayName)
                    .font(.headline)
                Text(detail.item.fullPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ProductCopy.actionMoveToTrash)
                    .font(.body.weight(.semibold))
                Text(ProductCopy.expectedSize(detail.item.byteLabel))
            }

            GroupBox(ProductCopy.whatWillHappen) {
                Text(detail.consequenceCopy)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox(ProductCopy.diskRecovery) {
                Text(detail.recoverySemantics)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(detail.reversibilityCopy)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(ProductCopy.cancel) {
                    viewModel.cancelApproval()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(ProductCopy.moveToTrash) {
                    viewModel.confirmApproval()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480)
    }
}
