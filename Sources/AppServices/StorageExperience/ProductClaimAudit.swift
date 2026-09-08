import Foundation

/// P5.0 — user-facing claim audit helpers (presentation/docs, not Safety authority).
public enum ProductClaimAudit {
    public static let riskyFragments: [String] = [
        "always safe",
        "safe to delete",
        "automatic cleanup",
        "one-click clean",
        "100% recoverable",
        "free 14gb",
        "junk",
    ]

    public static func containsRiskyUnqualifiedClaim(_ text: String) -> Bool {
        let lower = text.lowercased()
        return riskyFragments.contains { lower.contains($0) }
    }
}
