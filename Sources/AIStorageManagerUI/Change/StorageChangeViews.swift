import SwiftUI
import AppServices

/// Compact secondary panel — never steals hero from the sunburst.
struct StorageChangeCompactPanel: View {
    let report: StorageChangeReport?
    var isScanning: Bool = false
    var scanStage: StorageScanStage = .idle
    var onSeeDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProductCopy.storageChange)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isScanning, report == nil || scanStage != .complete {
                Text(ProductCopy.checkingChanges)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let report {
                if report.comparisonQuality == .noComparisonYet {
                    Text(ProductCopy.storageHistoryStartsNow)
                        .font(.subheadline.weight(.medium))
                    Text(ProductCopy.runAnotherScanForChanges)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if report.comparisonQuality == .notComparable {
                    Text(ProductCopy.storageHistoryUnavailable)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ProductCopy.sinceLastScan)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(usedDeltaLabel(report))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        if let top = report.topGrowing.first {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ProductCopy.largestChange)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(top.displayName) \(signedLabel(top.deltaBytes ?? 0))")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button(ProductCopy.seeWhatChanged, action: onSeeDetails)
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                    }
                }
            } else {
                Text(ProductCopy.storageHistoryUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func usedDeltaLabel(_ report: StorageChangeReport) -> String {
        guard let delta = report.diskUsedDelta else { return "—" }
        return L10n.t("history.usedDelta", "\(signedLabel(delta))")
    }

    private func signedLabel(_ bytes: Int64) -> String {
        let sign = bytes > 0 ? "+" : ""
        return "\(sign)\(UICandidateMapper.byteLabel(bytes))"
    }
}

struct StorageChangeDetailView: View {
    let report: StorageChangeReport?

    var body: some View {
        List {
            if let report {
                Section {
                    Text(report.explanation.headline)
                        .font(.title3.weight(.semibold))
                    ForEach(Array(report.explanation.bodyLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(ProductCopy.whatChanged)
                }

                changeSection(title: ProductCopy.growing, items: report.topGrowing, positive: true)
                changeSection(title: ProductCopy.shrinking, items: report.topShrinking, positive: false)
                changeSection(title: ProductCopy.newItems, items: report.newLargeItems, positive: true)
                changeSection(title: ProductCopy.removedItems, items: report.removedLargeItems, positive: false)

                if !report.categoryDeltas.isEmpty {
                    Section(ProductCopy.categoryChanges) {
                        ForEach(report.categoryDeltas.prefix(8), id: \.category) { delta in
                            HStack {
                                Text(delta.category)
                                Spacer()
                                Text(signed(delta.deltaBytes))
                                    .foregroundStyle(delta.deltaBytes >= 0 ? Color.primary : Color.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                if !report.relatedVerifiedActions.isEmpty {
                    Section(ProductCopy.relatedVerifiedActions) {
                        ForEach(report.relatedVerifiedActions, id: \.actionID) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.entityID)
                                    .font(.subheadline.weight(.medium))
                                Text(item.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let unexplained = report.unexplainedDeltaBytes, unexplained > 0 {
                    Section(ProductCopy.unexplainedChange) {
                        Text(UICandidateMapper.byteLabel(unexplained))
                            .monospacedDigit()
                        Text(ProductCopy.unexplainedNotMappedGrowth)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableCompat(
                    title: ProductCopy.noComparisonYet,
                    systemImage: "clock",
                    description: ProductCopy.runAnotherScanForChanges
                )
            }
        }
        .navigationTitle(ProductCopy.storageChange)
    }

    @ViewBuilder
    private func changeSection(title: String, items: [StorageChangeItem], positive: Bool) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items.prefix(8)) { item in
                    HStack {
                        Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                            if let category = item.semanticCategory {
                                Text(category)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(signed(item.deltaBytes ?? item.currentBytes ?? item.previousBytes ?? 0))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func signed(_ bytes: Int64) -> String {
        let sign = bytes > 0 ? "+" : ""
        return "\(sign)\(UICandidateMapper.byteLabel(bytes))"
    }
}
