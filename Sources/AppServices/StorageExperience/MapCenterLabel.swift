import Foundation
import SafetyCore

/// Center-label presentation for physical map. Pure formatting — no Safety inference.
public struct MapCenterLabel: Equatable, Sendable {
    public var primary: String
    public var footnote: String
    public var showsNumericZero: Bool

    public init(primary: String, footnote: String, showsNumericZero: Bool) {
        self.primary = primary
        self.footnote = footnote
        self.showsNumericZero = showsNumericZero
    }

    public static func make(
        focus: StorageNodePresentation,
        accounting: PhysicalMapAccounting
    ) -> MapCenterLabel {
        // Focused child with authoritative measurement keeps its own value.
        if focus.physical.bytesKnown {
            return MapCenterLabel(
                primary: UICandidateMapper.byteLabel(focus.bytes),
                footnote: footnote(for: focus, fallbackMapped: focus.physical.nodeKind == .volume),
                showsNumericZero: focus.bytes == 0
            )
        }

        // Focus measurement unknown — use accounting geometry for this node.
        let local = PhysicalMapAccountingResolver.resolve(for: focus.physical)
        if let mapped = local.mappedBytes {
            let useMapped = local.fallbackUsed || focus.physical.nodeKind == .volume
            return MapCenterLabel(
                primary: UICandidateMapper.byteLabel(mapped),
                footnote: footnote(for: focus, fallbackMapped: useMapped),
                showsNumericZero: mapped == 0 && local.basis == .rootMeasured
            )
        }

        return MapCenterLabel(
            primary: "—",
            footnote: L10n.t("map.footnote.unavailable"),
            showsNumericZero: false
        )
    }

    private static func footnote(for focus: StorageNodePresentation, fallbackMapped: Bool) -> String {
        if fallbackMapped || focus.physical.nodeKind == .volume {
            return L10n.t("map.footnote.mapped")
        }
        return focus.physical.isDirectory ? L10n.t("map.footnote.folder") : L10n.t("map.footnote.item")
    }
}
