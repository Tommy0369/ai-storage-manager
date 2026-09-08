import SwiftUI
import AppServices

struct StorageMapView: View {
    @EnvironmentObject private var viewModel: StorageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !viewModel.mapFocusPath.isEmpty {
                BreadcrumbBar(path: viewModel.mapFocusPath, onNavigate: viewModel.focusMapPath)
            }
            if let root = viewModel.mapFocusNode ?? viewModel.experienceSnapshot?.mapRoot {
                SunburstChartView(
                    root: root,
                    selectedID: $viewModel.selectedMapNodeID,
                    onSelect: { viewModel.selectMapNode($0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(ProductCopy.mapAccessibilityHint)

                MapListAlternative(root: root, onSelect: { viewModel.selectMapNode($0) })
                    .frame(maxHeight: 180)
            } else {
                ProgressView(ProductCopy.scanning)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
    }
}

struct BreadcrumbBar: View {
    let path: [StorageMapNode]
    let onNavigate: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.offset) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button(node.title) {
                        onNavigate(index)
                    }
                    .buttonStyle(.plain)
                    .font(index == path.count - 1 ? .headline : .subheadline)
                }
            }
        }
    }
}

struct MapListAlternative: View {
    let root: StorageMapNode
    let onSelect: (StorageMapNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ProductCopy.listView)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            List(root.children) { child in
                Button {
                    onSelect(child)
                } label: {
                    HStack {
                        Text(child.title)
                        Spacer()
                        Text(ByteFormat.label(child.bytes))
                            .foregroundStyle(.secondary)
                        if child.bytes > 0, root.bytes > 0 {
                            Text(String(format: "%.0f%%", Double(child.bytes) / Double(root.bytes) * 100))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ProductCopy.mapListAlternativeA11y)
    }
}

enum SunburstProminence {
    case standard
    case hero
}

struct SunburstChartView: View {
    let root: StorageMapNode
    @Binding var selectedID: String?
    let onSelect: (StorageMapNode) -> Void
    var prominence: SunburstProminence = .standard
    var centerTitle: String? = nil
    var centerFootnote: String? = nil

    @State private var hoveredID: String?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let outerRadius = prominence == .hero
                ? max(100, side * 0.47)
                : max(60, side * 0.42)
            let innerRadius = outerRadius * (prominence == .hero ? 0.52 : 0.38)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            Canvas { context, _ in
                let segments = layoutSegments(for: root.children, total: max(root.bytes, 1))
                for segment in segments {
                    var path = Path()
                    path.addArc(
                        center: center,
                        radius: outerRadius,
                        startAngle: segment.start,
                        endAngle: segment.end,
                        clockwise: false
                    )
                    path.addArc(
                        center: center,
                        radius: innerRadius,
                        startAngle: segment.end,
                        endAngle: segment.start,
                        clockwise: true
                    )
                    path.closeSubpath()
                    let isSelected = selectedID == segment.node.id
                    let isHovered = hoveredID == segment.node.id
                    context.fill(
                        path,
                        with: .color(CategoryMapColors.color(for: segment.node.semanticCategory)
                            .opacity(isSelected ? 1 : isHovered ? 0.9 : 0.75))
                    )
                    if isSelected {
                        context.stroke(path, with: .color(.primary), lineWidth: 2)
                    }
                }
                let inner = Path(ellipseIn: CGRect(
                    x: center.x - innerRadius + 4,
                    y: center.y - innerRadius + 4,
                    width: (innerRadius - 4) * 2,
                    height: (innerRadius - 4) * 2
                ))
                context.fill(inner, with: .color(Color(nsColor: .windowBackgroundColor)))
            }
            .overlay {
                Group {
                    if prominence == .hero {
                        Text(ByteFormat.label(root.bytes))
                            .font(.system(size: min(28, innerRadius * 0.38), weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    } else {
                        VStack(spacing: 3) {
                            if let centerTitle {
                                Text(centerTitle)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(ByteFormat.label(root.bytes))
                                .font(.title3.monospacedDigit().weight(.semibold))
                            Text(root.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            if let centerFootnote {
                                Text(centerFootnote)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: innerRadius * 1.6)
                    }
                }
                .position(center)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hoveredID = hitTest(
                            at: value.location,
                            center: center,
                            outerRadius: outerRadius,
                            innerRadius: innerRadius,
                            segments: layoutSegments(for: root.children, total: max(root.bytes, 1))
                        )
                    }
                    .onEnded { value in
                        if let id = hitTest(
                            at: value.location,
                            center: center,
                            outerRadius: outerRadius,
                            innerRadius: innerRadius,
                            segments: layoutSegments(for: root.children, total: max(root.bytes, 1))
                        ),
                           let node = root.children.first(where: { $0.id == id }) {
                            selectedID = node.id
                            onSelect(node)
                        }
                    }
            )
        }
    }

    private struct SegmentLayout {
        var node: StorageMapNode
        var start: Angle
        var end: Angle
    }

    private func layoutSegments(for nodes: [StorageMapNode], total: Int64) -> [SegmentLayout] {
        var result: [SegmentLayout] = []
        var cursor = Angle.degrees(-90)
        for node in nodes where node.bytes > 0 {
            let fraction = Double(node.bytes) / Double(total)
            let sweep = Angle.degrees(360 * fraction)
            result.append(SegmentLayout(node: node, start: cursor, end: cursor + sweep))
            cursor += sweep
        }
        return result
    }

    private func hitTest(
        at point: CGPoint,
        center: CGPoint,
        outerRadius: CGFloat,
        innerRadius: CGFloat,
        segments: [SegmentLayout]
    ) -> String? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }
        var degrees = atan2(dy, dx) * 180 / .pi + 90
        if degrees < 0 { degrees += 360 }
        let angle = Angle.degrees(degrees)
        for segment in segments {
            if angle >= segment.start && angle <= segment.end {
                return segment.node.id
            }
        }
        return nil
    }
}
