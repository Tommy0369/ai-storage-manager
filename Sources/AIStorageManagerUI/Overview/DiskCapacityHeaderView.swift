import SwiftUI
import AppServices

struct DiskCapacityHeaderView: View {
    let snapshot: StorageExperienceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.diskCapacity.volumeName)
                .font(.largeTitle.bold())

            HStack(spacing: 12) {
                metricCard(label: ProductCopy.diskTotal, value: ByteFormat.label(snapshot.diskCapacity.volumeTotalBytes))
                metricCard(label: ProductCopy.diskUsed, value: ByteFormat.label(snapshot.diskCapacity.volumeUsedBytes))
                metricCard(label: ProductCopy.diskFree, value: ByteFormat.label(snapshot.diskCapacity.volumeAvailableBytes))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 16) {
                    scanMetric(
                        label: ProductCopy.observedScope,
                        value: ByteFormat.label(snapshot.observedStorage.scannedRootBytes)
                    )
                    scanMetric(
                        label: ProductCopy.uniqueClassified,
                        value: ByteFormat.label(snapshot.observedStorage.classifiedUniqueBytes)
                    )
                }
                Text(ProductCopy.scanScopeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metricCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func scanMetric(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
        }
    }
}
