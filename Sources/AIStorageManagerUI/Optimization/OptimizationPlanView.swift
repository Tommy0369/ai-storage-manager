import SwiftUI
import AppServices
import SafetyCore

struct OptimizationGoalEntryPanel: View {
    var readyCount: Int = 0
    var onFree10: () -> Void
    var onFree20: () -> Void
    var onOpenCustom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProductCopy.needMoreSpace)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if readyCount == 0 {
                Text(ProductCopy.noSafeExecutablePlan)
                    .font(.subheadline)
                Text(L10n.t("plan.importantExcluded"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(ProductCopy.customGoal, action: onOpenCustom)
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
            } else {
                HStack(spacing: 8) {
                    Button(ProductCopy.free10GB, action: onFree10)
                        .buttonStyle(.bordered)
                    Button(ProductCopy.free20GB, action: onFree20)
                        .buttonStyle(.borderedProminent)
                    Button(ProductCopy.customGoal, action: onOpenCustom)
                        .buttonStyle(.borderless)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct OptimizationPlanView: View {
    @EnvironmentObject private var viewModel: StorageViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(ProductCopy.storageGoal)
                    .font(.largeTitle.bold())
                Text(ProductCopy.howMuchSpace)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                goalControls

                if let plan = viewModel.optimizationPlan {
                    OptimizationPlanCanvas(plan: plan, interactive: true) { entityID in
                        viewModel.openCandidate(entityID)
                    } onCheckSafety: { entityID in
                        viewModel.openCandidate(entityID)
                        Task { await viewModel.runPreflight(action: .moveToTrash) }
                    } onRemove: { entityID in
                        viewModel.removeFromOptimizationPlan(entityID: entityID)
                    }
                } else {
                    Text(ProductCopy.importantDataExcluded)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(ProductCopy.storageGoal)
    }

    private var goalControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("GB", text: $viewModel.goalGigabytesText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Text("GB")
                    .foregroundStyle(.secondary)
                Button(ProductCopy.buildSafePlan) {
                    viewModel.buildOptimizationPlan()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.experienceSnapshot == nil && viewModel.explorerSnapshot == nil)
                if viewModel.optimizationPlan != nil {
                    Button(ProductCopy.refreshPlan) {
                        viewModel.buildOptimizationPlan()
                    }
                    .buttonStyle(.bordered)
                }
            }
            HStack {
                Button(ProductCopy.free10GB) {
                    viewModel.goalGigabytesText = "10"
                    viewModel.buildOptimizationPlan()
                }
                Button(ProductCopy.free20GB) {
                    viewModel.goalGigabytesText = "20"
                    viewModel.buildOptimizationPlan()
                }
            }
            .font(.caption)
        }
    }
}

/// Deterministic plan canvas used by live UI and ImageRenderer screenshots.
struct OptimizationPlanCanvas: View {
    let plan: OptimizationPlan
    var interactive: Bool = false
    var onReview: ((String) -> Void)?
    var onCheckSafety: ((String) -> Void)?
    var onRemove: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if plan.freshness == .stale {
                Label(ProductCopy.planStale, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            summaryCard

            section(
                title: ProductCopy.readyNow,
                entries: plan.entries.filter {
                    $0.selected || $0.candidate.tier == .executableNow || $0.candidate.tier == .approvalRequired
                }.filter { $0.candidate.executionSupport == .implemented && $0.candidate.action == .moveToTrash },
                executable: true
            )

            section(
                title: ProductCopy.verifiedOpportunities,
                entries: plan.entries.filter { $0.candidate.tier == .verifiedButExecutorUnavailable },
                executable: false
            )

            section(
                title: ProductCopy.needsVerification,
                entries: Array(plan.entries.filter {
                    $0.candidate.tier == .verifyMore || $0.candidate.tier == .preflightRequired
                }.prefix(8)),
                executable: false
            )

            if !plan.excludedSummary.isEmpty {
                labeledBox(ProductCopy.whyNotChosen) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(plan.excludedSummary.prefix(6), id: \.entityID) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(item.displayName).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(UICandidateMapper.byteLabel(item.bytes)).monospacedDigit()
                                }
                                Text(item.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            ForEach(plan.warnings, id: \.self) { warning in
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(plan.contextNotes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCard: some View {
        labeledBox(nil) {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusLabel(plan.goalStatus))
                    .font(.headline)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ProductCopy.goalLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(UICandidateMapper.byteLabel(plan.requestedBytes))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ProductCopy.verifiedRecovered)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(UICandidateMapper.byteLabel(StorageProductPresentationBuilder.verifiedCompletedRecoveryTotal))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ProductCopy.remainingGoal)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(UICandidateMapper.byteLabel(max(0, plan.requestedBytes - StorageProductPresentationBuilder.verifiedCompletedRecoveryTotal)))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                }
                Text("\(ProductCopy.currentSafePlan): \(UICandidateMapper.byteLabel(selectedPotential))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(ProductCopy.diskRecoveryLater)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(ProductCopy.importantDataExcluded)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var selectedPotential: Int64 {
        guard plan.availableNowPotentialBytes > 0 else { return 0 }
        return plan.selectedEntries.reduce(Int64(0)) { $0 + $1.candidate.potentialRecoveryBytes }
    }

    private func section(title: String, entries: [OptimizationPlanEntry], executable: Bool) -> some View {
        Group {
            if !entries.isEmpty {
                labeledBox(title) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(entries) { entry in
                            planRow(entry, executable: executable)
                        }
                    }
                }
            }
        }
    }

    private func planRow(_ entry: OptimizationPlanEntry, executable: Bool) -> some View {
        let candidate = entry.candidate
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("\(UICandidateMapper.byteLabel(candidate.potentialRecoveryBytes)) potential · \(candidate.action == .moveToTrash ? ProductCopy.moveToTrashPotential : candidate.action.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !executable {
                        Text(candidate.tier == .verifiedButExecutorUnavailable
                             ? ProductCopy.notAvailableInThisVersion
                             : ProductCopy.checkSafety)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if let state = entry.completionState {
                        Text(state).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if interactive, executable, candidate.action == .moveToTrash {
                    Button(ProductCopy.reviewItem) {
                        onReview?(candidate.entityID)
                    }
                    .buttonStyle(.bordered)
                    if candidate.tier == .preflightRequired {
                        Button(ProductCopy.checkSafety) {
                            onCheckSafety?(candidate.entityID)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    Button(ProductCopy.removeFromPlan) {
                        onRemove?(candidate.entityID)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                } else if !executable || candidate.action != .moveToTrash {
                    Text(ProductCopy.notExecutable)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if entry.selected {
                ForEach(candidate.whyIncluded, id: \.self) { line in
                    Text("• \(line)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func labeledBox<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statusLabel(_ status: OptimizationGoalStatus) -> String {
        switch status {
        case .achievableNow: return "Goal is achievable with current ready actions."
        case .partiallyAchievable: return "Only part of the goal is currently available."
        case .achievableWithFutureCapabilities: return "More could become available when additional actions ship."
        case .needsMoreVerification: return "More verification is required before a safe plan exists."
        case .noSafeOptions: return ProductCopy.noSafeExecutablePlan
        }
    }
}
