import SwiftUI
import AppServices

/// Calm compact disk summary — DaisyDisk-class top bar.
struct CompactDiskSummaryBar: View {
    let snapshot: StorageExperienceSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ProductCopy.disksBreadcrumb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(snapshot.diskCapacity.volumeName)
                    .font(.subheadline.weight(.semibold))
            }

            Spacer(minLength: 12)

            HStack(spacing: 18) {
                inlineStat(label: ProductCopy.usedCapacity, bytes: snapshot.diskCapacity.volumeUsedBytes)
                inlineStat(label: ProductCopy.freeCapacity, bytes: snapshot.diskCapacity.volumeAvailableBytes)
                inlineStat(label: ProductCopy.totalCapacity, bytes: snapshot.diskCapacity.volumeTotalBytes)
                verifiedRecovered
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ProductCopy.diskSummaryA11y)
    }

    private var verifiedRecovered: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 6) {
                Text(ProductCopy.verifiedRecovered)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ByteFormat.label(StorageProductPresentationBuilder.verifiedCompletedRecoveryTotal))
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            Text(ConsumerPresentationCopy.verifiedRecoveredHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func inlineStat(label: String, bytes: Int64?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ByteFormat.label(bytes))
                .font(.caption.monospacedDigit().weight(.semibold))
        }
    }
}
