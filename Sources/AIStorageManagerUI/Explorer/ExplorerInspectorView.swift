import SwiftUI
import AppServices

struct ExplorerInspectorView: View {
    let node: StorageNodePresentation?
    let focus: StorageNodePresentation
    let selectedID: String?
    var compact: Bool = false
    var onSelectChild: (StorageNodePresentation) -> Void
    var onReveal: (StorageNodePresentation) -> Void
    var onPreview: (StorageNodePresentation) -> Void
    var onReview: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            childList
            Divider()
            if let node {
                detail(node)
            } else {
                Text(ProductCopy.selectItemHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
                Spacer(minLength: 0)
            }
        }
    }

    private var childList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProductCopy.largestChildren)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            VStack(spacing: 2) {
                ForEach(focus.children) { child in
                    Button {
                        onSelectChild(child)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CategoryMapColors.color(for: child.semanticCategory))
                                .frame(width: 8, height: 8)
                            Image(systemName: icon(for: child))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            Text(child.title)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            if child.bytesKnown {
                                Text(ByteFormat.label(child.bytes))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } else if child.physical.isRestricted {
                                Text(ProductCopy.notScanned)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text(ProductCopy.measuring)
                                    .foregroundStyle(.tertiary)
                            }
                            if let badge = DecisionChrome.badge(for: child.decision.state) {
                                Image(systemName: badge.icon)
                                    .font(.caption2)
                                    .foregroundStyle(badge.tint)
                                    .accessibilityLabel(ConsumerPresentationCopy.humanDecisionLabel(state: child.decision.state))
                            }
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedID == child.id ? Color.accentColor.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: child))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .frame(maxHeight: compact ? 240 : .infinity, alignment: .top)
        }
    }

    private func detail(_ node: StorageNodePresentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1–2 NAME / SIZE
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.title)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(ByteFormat.label(node.bytes))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.primary)
                }

                // 3 WHAT
                labeled(ProductCopy.whatIsThis, node.whatIsThis)

                // 4 WHY LARGE
                if let why = node.whyLarge {
                    labeled(ProductCopy.whyLarge, why)
                }

                // 5–6 RECOMMENDATION / WHY
                VStack(alignment: .leading, spacing: 6) {
                    Text(ProductCopy.doINeedIt)
                        .font(.headline)
                    Label(
                        ConsumerPresentationCopy.humanDecisionLabel(state: node.decision.state),
                        systemImage: node.decision.iconHint
                    )
                    .font(.body.weight(.medium))
                    Text(node.decision.label)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(node.semanticCategory.displayName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // 7 WHAT YOU CAN DO / WHY CAN'T
                VStack(alignment: .leading, spacing: 8) {
                    if node.decision.state == .readyToOptimize, let entityID = node.decision.entityID {
                        Button(ProductCopy.reviewItem) { onReview(entityID) }
                            .buttonStyle(.borderedProminent)
                    } else if node.decision.state == .protected || node.decision.state == .keep || node.decision.state == .verificationNeeded {
                        Text(ProductCopy.whyCantAct)
                            .font(.headline)
                        Text(actionBlockCopy(for: node))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                // Actions (secondary)
                HStack(spacing: 8) {
                    Button(ProductCopy.revealInFinder) { onReveal(node) }
                    if node.physical.isFile {
                        Button(ProductCopy.preview) { onPreview(node) }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Technical last, collapsed
                DisclosureGroup(ProductCopy.technicalDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        techRow("Location", node.location)
                        techRow("Path", node.physical.canonicalPath)
                        techRow("ID", node.technicalEntityID ?? "—")
                        techRow("Kind", node.physical.nodeKind.rawValue)
                    }
                    .padding(.top, 4)
                }
                .font(.callout)
            }
            .padding(16)
        }
    }

    private func actionBlockCopy(for node: StorageNodePresentation) -> String {
        let id = (node.technicalEntityID ?? node.id).lowercased()
        let title = node.title.lowercased()
        if id.contains("voicememo") || title.contains("recording") {
            return "Apple does not provide a verified local-only removal action for these recordings."
        }
        if id.contains("cursor") || title.contains("cursor") {
            return "Cursor uses this to restore its state."
        }
        if id.contains("chrome") || title.contains("chrome") || title.contains("website") {
            return "This contains website state, not just cache."
        }
        if id.contains("claude") || title.contains("claude") {
            return "Claude is currently using this."
        }
        if node.decision.state == .verificationNeeded {
            return "We haven't verified enough yet."
        }
        return node.decision.label
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func techRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    private func icon(for node: StorageNodePresentation) -> String {
        if node.physical.isRestricted { return "lock.slash" }
        if node.physical.isPackage { return "shippingbox" }
        if node.physical.isSymlink { return "link" }
        if node.physical.isFile { return "doc" }
        if node.physical.isAggregate { return "ellipsis.circle" }
        return "folder"
    }

    private func accessibilityLabel(for node: StorageNodePresentation) -> String {
        let size = node.bytesKnown ? ByteFormat.label(node.bytes) : ProductCopy.notScanned
        let decision = ConsumerPresentationCopy.humanDecisionLabel(state: node.decision.state)
        return "\(node.title), \(size), \(decision)"
    }
}
