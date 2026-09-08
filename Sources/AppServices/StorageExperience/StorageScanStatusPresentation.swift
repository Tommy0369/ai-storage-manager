import Foundation
import SafetyCore

/// v0.2 UX FIX 001 — canonical scan status.
///
/// Presentation only. Never influences SafetyClass, ActionDecision,
/// MutationReadiness, candidateBytes or verifiedRecoveredBytes.
///
/// Before this type, the scan banner was composed from two independent strings:
/// a stage label plus a "scanning deeper" chip. Those could disagree, so a
/// failed scan could render as "Scan failed" next to "Scanning deeper…" with a
/// live spinner — three contradictory signals at once.
///
/// One state in, one sentence out.
public enum StorageScanStatus: String, Sendable, Equatable, CaseIterable {
    case idle = "IDLE"
    /// Scan running, structure still being mapped.
    case active = "ACTIVE"
    /// Scan running, now enriching meaning / safety.
    case deepening = "DEEPENING"
    /// Some areas could not be read AND the scan is still running.
    /// This is NOT a failure — the rest is still being scanned.
    case partialContinuing = "PARTIAL_CONTINUING"
    case complete = "COMPLETE"
    /// The scan itself could not complete. Distinct from partial coverage.
    case failed = "FAILED"

    /// Localization key for the single status sentence.
    public var localizationKey: String {
        switch self {
        case .idle: return "scan.ready"
        case .active: return "scan.status.active"
        case .deepening: return "scan.status.deepening"
        case .partialContinuing: return "scan.status.partialContinuing"
        case .complete: return "scan.status.complete"
        case .failed: return "scan.status.failed"
        }
    }

    /// True only while work is actually in flight. Drives the spinner.
    /// A failed scan is never "running", so it never shows progress.
    public var isRunning: Bool {
        switch self {
        case .active, .deepening, .partialContinuing: return true
        case .idle, .complete, .failed: return false
        }
    }

    /// Whether the banner should be shown at all.
    public var showsBanner: Bool {
        switch self {
        case .idle, .complete: return false
        case .active, .deepening, .partialContinuing, .failed: return true
        }
    }

    public var localizedText: String { L10n.t(localizationKey) }
}

public enum StorageScanStatusResolver {
    /// Resolve the one canonical status from scan stage + map coverage.
    ///
    /// Rules:
    /// - A thrown scan error (`.failed`) is the only true failure.
    /// - Partial coverage during a running scan is `partialContinuing`,
    ///   never `failed`.
    /// - Partial coverage after the scan finished is still `complete`;
    ///   the coverage caveat is surfaced separately by `partialCoverageNote`.
    public static func resolve(
        stage: StorageScanStage,
        coverage: PhysicalMapCoverage?
    ) -> StorageScanStatus {
        switch stage {
        case .failed:
            return .failed
        case .idle:
            return .idle
        case .complete:
            return .complete
        case .scanningFiles, .hierarchyAvailable:
            return coverage == .partial ? .partialContinuing : .active
        case .understandingStorage, .checkingSafety:
            return coverage == .partial ? .partialContinuing : .deepening
        }
    }

    /// Coverage caveat shown independently of progress.
    ///
    /// Returns nil unless coverage is genuinely partial. When the scan is still
    /// running the caveat is already part of the status sentence, so it is not
    /// repeated.
    public static func partialCoverageNote(
        stage: StorageScanStage,
        coverage: PhysicalMapCoverage?
    ) -> String? {
        guard coverage == .partial else { return nil }
        let status = resolve(stage: stage, coverage: coverage)
        if status == .partialContinuing { return nil }
        return L10n.t("scan.coverage.partial")
    }
}
