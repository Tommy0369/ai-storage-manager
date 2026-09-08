import SwiftUI
import AppServices

struct CandidateRow: View {
    let item: UICandidateItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayName)
                .font(.headline)
            HStack {
                Text(item.byteLabel)
                Text("·")
                Text(item.readiness.userLabel)
                    .foregroundStyle(readinessColor)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityLabel("\(item.displayName), \(item.byteLabel), \(item.readiness.userLabel)")
    }

    private var readinessColor: Color {
        switch item.readiness {
        case .approvalRequired, .completed: return .primary
        case .verifyMore, .preflightRequired, .storageRecoveryPending: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }
}

struct RecentActionRow: View {
    let item: UIActionHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayName)
                .font(.subheadline.weight(.medium))
            Text(item.actionLabel)
                .font(.caption)
            ForEach(item.summaryLines, id: \.self) { line in
                Label(line, systemImage: line.contains("pending") ? "exclamationmark.triangle" : "checkmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
