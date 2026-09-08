import SwiftUI
import AppServices

struct CategoryLegendView: View {
    let categories: [StorageMapNode]
    let totalBytes: Int64
    let selectedID: String?
    let onSelect: (StorageMapNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ProductCopy.storageByCategory)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            VStack(spacing: 2) {
                ForEach(categories) { category in
                    legendRow(category)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func legendRow(_ node: StorageMapNode) -> some View {
        let selected = selectedID == node.id
        return Button {
            onSelect(node)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(CategoryMapColors.color(for: node.semanticCategory))
                    .frame(width: 10, height: 10)
                Text(node.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(ByteFormat.label(node.bytes))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(selected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(node.title), \(ByteFormat.label(node.bytes))")
    }
}
