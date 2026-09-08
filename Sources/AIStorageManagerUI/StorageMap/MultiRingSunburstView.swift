import SwiftUI
import AppServices
import SafetyCore

enum StructurePalette {
    static let colors: [Color] = [
        Color(red: 0.30, green: 0.72, blue: 0.45),
        Color(red: 0.95, green: 0.72, blue: 0.22),
        Color(red: 0.35, green: 0.55, blue: 0.95),
        Color(red: 0.85, green: 0.45, blue: 0.30),
        Color(red: 0.55, green: 0.40, blue: 0.90),
        Color(red: 0.25, green: 0.70, blue: 0.80),
        Color(red: 0.70, green: 0.55, blue: 0.35),
        Color(red: 0.50, green: 0.60, blue: 0.40),
    ]

    static func color(for key: String) -> Color {
        let hash = abs(key.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
        return colors[hash % colors.count]
    }
}

enum DecisionChrome {
    static func badge(for state: StoragePresentationState) -> (icon: String, tint: Color)? {
        switch state {
        case .readyToOptimize: return ("checkmark.circle.fill", Color(red: 0.20, green: 0.65, blue: 0.55))
        case .verificationNeeded: return ("ellipsis.circle.fill", Color(red: 0.70, green: 0.55, blue: 0.25))
        case .protected: return ("shield.fill", Color(red: 0.40, green: 0.55, blue: 0.75))
        case .recoveryPending: return ("clock.fill", Color(red: 0.40, green: 0.55, blue: 0.80))
        case .keep: return ("checkmark.seal.fill", Color(red: 0.35, green: 0.55, blue: 0.50))
        default: return nil
        }
    }
}

struct MultiRingSunburstView: View {
    let focus: StorageNodePresentation
    let lens: StorageMapLens
    @Binding var selectedID: String?
    @Binding var hoveredID: String?
    var ringCount: Int = 3
    var prominence: SunburstProminence = .hero
    var onSelect: (StorageNodePresentation) -> Void
    var onDrill: (StorageNodePresentation) -> Void

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let outerRadius = prominence == .hero ? max(120, side * 0.48) : max(80, side * 0.42)
            let hole = outerRadius * 0.30
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let arcs = StorageExplorerBuilder.layoutArcs(focus: focus, rings: ringCount)
            let ringThickness = (outerRadius - hole) / CGFloat(max(ringCount, 1))

            Canvas { context, _ in
                for arc in arcs.sorted(by: { $0.ringIndex < $1.ringIndex }) {
                    let inner = hole + CGFloat(arc.ringIndex) * ringThickness
                    let outer = inner + ringThickness * 0.96
                    var path = Path()
                    path.addArc(
                        center: center,
                        radius: outer,
                        startAngle: .degrees(arc.startDegrees),
                        endAngle: .degrees(arc.endDegrees),
                        clockwise: false
                    )
                    path.addArc(
                        center: center,
                        radius: inner,
                        startAngle: .degrees(arc.endDegrees),
                        endAngle: .degrees(arc.startDegrees),
                        clockwise: true
                    )
                    path.closeSubpath()

                    let node = StorageExplorerBuilder.node(withID: arc.nodeID, in: focus)
                        ?? focus
                    let base = fillColor(for: node, lens: lens)
                    let selected = selectedID == arc.nodeID
                    let hovered = hoveredID == arc.nodeID
                    let dimmed = hoveredID != nil && !selected && !hovered && !isRelated(arc.nodeID, hovered: hoveredID)
                    context.fill(path, with: .color(base.opacity(dimmed ? 0.28 : selected ? 1 : hovered ? 0.92 : 0.78)))
                    if selected {
                        context.stroke(path, with: .color(.primary.opacity(0.8)), lineWidth: 1.5)
                    } else if lens == .decision, let badge = DecisionChrome.badge(for: node.decision.state) {
                        context.stroke(path, with: .color(badge.tint.opacity(0.85)), lineWidth: 1.2)
                    }
                }

                let holeRect = CGRect(
                    x: center.x - hole + 3,
                    y: center.y - hole + 3,
                    width: (hole - 3) * 2,
                    height: (hole - 3) * 2
                )
                context.fill(Path(ellipseIn: holeRect), with: .color(Color(nsColor: .windowBackgroundColor)))
            }
            .overlay {
                let accounting = PhysicalMapAccountingResolver.resolve(for: focus.physical)
                let label = MapCenterLabel.make(focus: focus, accounting: accounting)
                VStack(spacing: 2) {
                    Text(label.primary)
                        .font(.system(size: min(30, hole * 0.42), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(focus.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(label.footnote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if accounting.coverage == .partial {
                        Text(ProductCopy.partialMap)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    } else if accounting.coverage == .unknown {
                        Text(ProductCopy.mappingUnavailable)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: hole * 1.7)
                .position(center)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hoveredID = hitTest(
                            at: value.location,
                            center: center,
                            hole: hole,
                            thickness: ringThickness,
                            arcs: arcs
                        )
                    }
                    .onEnded { value in
                        guard let id = hitTest(
                            at: value.location,
                            center: center,
                            hole: hole,
                            thickness: ringThickness,
                            arcs: arcs
                        ) else { return }
                        if let node = find(id) {
                            selectedID = id
                            onSelect(node)
                            if node.physical.isDirectory || node.physical.isAggregate {
                                onDrill(node)
                            }
                        }
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(ProductCopy.mapAccessibilityHint)
        }
    }

    private var centerFootnote: String {
        ProductCopy.mappedScope
    }

    private func fillColor(for node: StorageNodePresentation, lens: StorageMapLens) -> Color {
        switch lens {
        case .structure:
            return StructurePalette.color(for: structureKey(for: node))
        case .meaning:
            return CategoryMapColors.color(for: node.semanticCategory)
        case .decision:
            return StructurePalette.color(for: structureKey(for: node)).opacity(0.55)
        }
    }

    private func structureKey(for node: StorageNodePresentation) -> String {
        if focus.children.contains(where: { $0.id == node.id }) {
            return node.id
        }
        for child in focus.children {
            if StorageExplorerBuilder.node(withID: node.id, in: child) != nil {
                return child.id
            }
        }
        return node.id
    }

    private func isRelated(_ id: String, hovered: String?) -> Bool {
        guard let hovered else { return false }
        return id == hovered || id.hasPrefix(hovered) || hovered.hasPrefix(id)
    }

    private func find(_ id: String) -> StorageNodePresentation? {
        if focus.id == id { return focus }
        return StorageExplorerBuilder.node(withID: id, in: focus)
            ?? StorageExplorerBuilder.flatten(focus).first { $0.id == id }
    }

    private func hitTest(
        at point: CGPoint,
        center: CGPoint,
        hole: CGFloat,
        thickness: CGFloat,
        arcs: [SunburstArc]
    ) -> String? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance >= hole, distance <= hole + thickness * CGFloat(ringCount) else { return nil }
        let ring = Int((distance - hole) / thickness)
        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < -90 { degrees += 360 }
        for arc in arcs.reversed() where arc.ringIndex == ring {
            if degrees >= arc.startDegrees && degrees <= arc.endDegrees {
                return arc.nodeID
            }
        }
        for arc in arcs.reversed() {
            let inner = hole + CGFloat(arc.ringIndex) * thickness
            let outer = inner + thickness
            guard distance >= inner, distance <= outer else { continue }
            if degrees >= arc.startDegrees && degrees <= arc.endDegrees {
                return arc.nodeID
            }
        }
        return nil
    }
}
