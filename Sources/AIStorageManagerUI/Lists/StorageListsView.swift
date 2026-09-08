import SwiftUI
import AppServices

struct RecommendationsListView: View {
    @EnvironmentObject private var viewModel: StorageViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(ProductCopy.recommendations)
                    .font(.largeTitle.bold())
                if let cards = viewModel.experienceSnapshot?.recommendations, !cards.isEmpty {
                    ForEach(cards) { card in
                        RecommendationCardView(card: card) {
                            viewModel.openCandidate(card.entityID)
                        }
                    }
                } else {
                    emptyState
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProductCopy.noActionsReady)
                .foregroundStyle(.secondary)
            if let count = viewModel.experienceSnapshot?.needsReviewCount, count > 0 {
                Text(ProductCopy.verificationAreas(count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RecommendationCardView: View {
    let card: RecommendationCard
    let onReview: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.title)
                            .font(.title3.bold())
                        Text(card.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(card.byteLabel)
                        .font(.title3.monospacedDigit())
                }
                Text(card.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(card.evidenceLines, id: \.self) { line in
                    Label(line, systemImage: "checkmark.circle")
                        .font(.caption)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text(ProductCopy.recommendation)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(card.recommendedActionLabel)
                            .font(.headline)
                    }
                    Spacer()
                    if let recovery = card.potentialRecoveryLabel {
                        Text(recovery)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(ProductCopy.review, action: onReview)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ReviewListView: View {
    @EnvironmentObject private var viewModel: StorageViewModel

    var body: some View {
        itemList(
            title: ProductCopy.needsReview,
            items: viewModel.experienceSnapshot?.needsReview ?? [],
            empty: ProductCopy.needsReviewEmpty
        ) { item in
            viewModel.openCandidate(item.entityID)
        } row: { item in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                    Spacer()
                    Text(item.byteLabel)
                        .monospacedDigit()
                }
                Text(item.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(item.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct ProtectedListView: View {
    @EnvironmentObject private var viewModel: StorageViewModel

    var body: some View {
        itemList(
            title: ProductCopy.protectedItems,
            items: viewModel.experienceSnapshot?.protected ?? [],
            empty: ProductCopy.protectedEmpty
        ) { item in
            viewModel.openCandidate(item.entityID)
        } row: { item in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(ProductCopy.protectedLabel, systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(item.byteLabel)
                        .monospacedDigit()
                }
                Text(item.title)
                    .font(.headline)
                Text(item.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RecentActionsView: View {
    @EnvironmentObject private var viewModel: StorageViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(ProductCopy.recentActionsTitle)
                    .font(.largeTitle.bold())
                if viewModel.recentActions.isEmpty {
                    Text(ProductCopy.noActionsYet)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.recentActions) { action in
                        RecentActionRow(item: action)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ItemList<Item: Identifiable, Row: View>: View {
    let title: String
    let items: [Item]
    let empty: String
    let onSelect: (Item) -> Void
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.largeTitle.bold())
                if items.isEmpty {
                    Text(empty)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            row(item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func itemList<Item: Identifiable, Row: View>(
    title: String,
    items: [Item],
    empty: String,
    onSelect: @escaping (Item) -> Void,
    @ViewBuilder row: @escaping (Item) -> Row
) -> some View {
    ItemList(title: title, items: items, empty: empty, onSelect: onSelect, row: row)
}
