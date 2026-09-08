import Foundation

/// P3.4A — bounded semantic inspection (evidence acquisition only).
/// Broad recursive app-bundle scans are NOT the default.
/// Prefer: exact resource → literal → narrow class → expand only when required.
/// Does NOT affect SafetyClass / actionability.

public struct SemanticInspectionScope: Codable, Sendable, Equatable {
    public var root: String
    public var resourceClasses: [String]
    public var literalTargets: [String]
    public var maxFiles: Int
    public var maxBytes: Int64
    public var maxDurationMs: Int
    public var expansionReason: String?

    public init(
        root: String,
        resourceClasses: [String],
        literalTargets: [String],
        maxFiles: Int = 32,
        maxBytes: Int64 = 64 * 1024 * 1024,
        maxDurationMs: Int = 5_000,
        expansionReason: String? = nil
    ) {
        self.root = root
        self.resourceClasses = resourceClasses
        self.literalTargets = literalTargets
        self.maxFiles = maxFiles
        self.maxBytes = maxBytes
        self.maxDurationMs = maxDurationMs
        self.expansionReason = expansionReason
    }
}

public enum BoundedSemanticInspection {
    public static let principle =
        "BROAD_BUNDLE_SEARCH_IS_NOT_DEFAULT"

    public static let preferredOrder: [String] = [
        "exact_known_resource",
        "exact_literal",
        "narrow_source_class",
        "bounded_surrounding_implementation",
        "expand_only_when_evidence_requires",
    ]

    /// Default scope for Cursor storage DB backup/restore questions.
    public static func cursorStorageMainJSScope(
        appResourcesRoot: String = "/Applications/Cursor.app/Contents/Resources/app/out"
    ) -> SemanticInspectionScope {
        SemanticInspectionScope(
            root: appResourcesRoot,
            resourceClasses: ["main.js", "SQLiteStorageDatabase"],
            literalTargets: [
                "state.vscdb",
                "toBackupPath",
                "backup()",
                ".backup",
                "open_backup_reconnect_succeeded",
            ],
            maxFiles: 4,
            maxBytes: 8 * 1024 * 1024,
            maxDurationMs: 3_000,
            expansionReason: nil
        )
    }

    public static func shouldExpand(
        currentHits: Int,
        questionAnswered: Bool,
        scope: SemanticInspectionScope
    ) -> Bool {
        _ = scope
        if questionAnswered { return false }
        return currentHits == 0
    }

    /// Size alone must not reopen a closed protected investigation.
    public static func sizeAloneDoesNotReopenClosedInvestigation() -> Bool { true }
}
