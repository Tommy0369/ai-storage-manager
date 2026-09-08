import Foundation

/// P3.3B — read-only SQLite inspection contract for Cursor state.vscdb.
/// Forbidden: DELETE/UPDATE/INSERT/VACUUM/wal_checkpoint/REINDEX/schema mutation.
public enum CursorSQLiteReadOnlyContract {
    public static let allowedPragmaPrefixes: [String] = [
        "PRAGMA query_only",
        "PRAGMA page_size",
        "PRAGMA page_count",
        "PRAGMA freelist_count",
        "PRAGMA journal_mode",
        "PRAGMA auto_vacuum",
        "PRAGMA encoding",
        "PRAGMA user_version",
        "PRAGMA schema_version",
        "PRAGMA table_list",
        "PRAGMA table_info",
    ]

    public static let deniedSQLTokens: [String] = [
        "DELETE ", "UPDATE ", "INSERT ",
        "WAL_CHECKPOINT", "REINDEX", "ALTER TABLE", "DROP ", "CREATE TABLE",
        "CREATE INDEX", "CREATE TRIGGER", "ATTACH ", "DETACH ",
        "REPLACE INTO", "TRUNCATE", "PRAGMA JOURNAL_MODE=", "PRAGMA AUTO_VACUUM=",
        "PRAGMA WRITABLE_SCHEMA", "PRAGMA USER_VERSION=",
    ]

    public static func isMutatingSQL(_ sql: String) -> Bool {
        let upper = sql.uppercased()
        // Standalone VACUUM statement only — never confuse with PRAGMA auto_vacuum
        let withoutAutoVacuum = upper.replacingOccurrences(of: "AUTO_VACUUM", with: "AUTO_X")
        if withoutAutoVacuum.range(of: #"\bVACUUM\b"#, options: .regularExpression) != nil {
            return true
        }
        for token in deniedSQLTokens {
            if upper.contains(token) { return true }
        }
        let trimmed = upper.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("SELECT") || trimmed.hasPrefix("WITH") || trimmed.hasPrefix("PRAGMA") {
            return false
        }
        return true
    }

    public static func assertReadOnlyOrThrow(_ sql: String) throws {
        if isMutatingSQL(sql) {
            throw CursorSQLiteInspectionError.mutatingSQLDenied(sql.prefix(80).description)
        }
    }
}

public enum CursorSQLiteInspectionError: Error, Equatable {
    case mutatingSQLDenied(String)
    case databaseMissing(String)
    case queryFailed(String)
}

public struct DatabaseStorageAccounting: Codable, Sendable, Equatable {
    public var databaseFileBytes: Int64
    public var walBytes: Int64
    public var shmBytes: Int64
    public var pageSize: Int64
    public var pageCount: Int64
    public var freePageCount: Int64
    public var freePageBytes: Int64
    public var estimatedAllocatedPayloadBytes: Int64
    public var journalMode: String
    public var autoVacuumMode: String
    public var dbOpen: Bool
    public var inspectionMethod: String
    public var inspectionMutationDetected: Bool
    public var accountingConfidence: String
    public var inspectionSafety: String
    public var largestObjectName: String?
    public var largestObjectBytes: Int64?
    public var freelistSignificant: Bool
    public var walSignificant: Bool

    public static let significanceBytes: Int64 = 1_000_000_000
    public static let significanceFraction: Double = 0.10

    public init(
        databaseFileBytes: Int64,
        walBytes: Int64,
        shmBytes: Int64,
        pageSize: Int64,
        pageCount: Int64,
        freePageCount: Int64,
        freePageBytes: Int64,
        estimatedAllocatedPayloadBytes: Int64,
        journalMode: String,
        autoVacuumMode: String,
        dbOpen: Bool,
        inspectionMethod: String,
        inspectionMutationDetected: Bool,
        accountingConfidence: String,
        inspectionSafety: String,
        largestObjectName: String? = nil,
        largestObjectBytes: Int64? = nil,
        freelistSignificant: Bool,
        walSignificant: Bool
    ) {
        self.databaseFileBytes = databaseFileBytes
        self.walBytes = walBytes
        self.shmBytes = shmBytes
        self.pageSize = pageSize
        self.pageCount = pageCount
        self.freePageCount = freePageCount
        self.freePageBytes = freePageBytes
        self.estimatedAllocatedPayloadBytes = estimatedAllocatedPayloadBytes
        self.journalMode = journalMode
        self.autoVacuumMode = autoVacuumMode
        self.dbOpen = dbOpen
        self.inspectionMethod = inspectionMethod
        self.inspectionMutationDetected = inspectionMutationDetected
        self.accountingConfidence = accountingConfidence
        self.inspectionSafety = inspectionSafety
        self.largestObjectName = largestObjectName
        self.largestObjectBytes = largestObjectBytes
        self.freelistSignificant = freelistSignificant
        self.walSignificant = walSignificant
    }
}

public struct CursorDiskKVClassStats: Codable, Sendable, Equatable {
    public var keyClass: String
    public var entryCount: Int
    public var logicalValueBytes: Int64
    public var averageValueBytes: Double
    public var medianValueBytes: Int64
    public var p95ValueBytes: Int64
    public var p99ValueBytes: Int64
    public var maxValueBytes: Int64
    public var percentageOfKV: Double
    public var activeRelationshipState: String
    public var retentionSemantics: String
    public var sourceOfTruthState: String
    public var userStateLikelihood: String
    public var evidenceLevel: String
    public var recommendation: String
    public var semanticLabel: String
}

public enum CursorDatabaseGrowthRootCause: String, Codable, Sendable, Equatable {
    case liveUserAgentStateDominant = "LIVE_USER_AGENT_STATE_DOMINANT"
    case databaseFreelistBloatSignificant = "DATABASE_FREELIST_BLOAT_SIGNIFICANT"
    case walAccumulationSignificant = "WAL_ACCUMULATION_SIGNIFICANT"
    case backupRetentionSignificant = "BACKUP_RETENTION_SIGNIFICANT"
    case duplicateLogicalStateSignificant = "DUPLICATE_LOGICAL_STATE_SIGNIFICANT"
    case vendorRetentionGapSuspected = "VENDOR_RETENTION_GAP_SUSPECTED"
    case unknownGrowthSource = "UNKNOWN_GROWTH_SOURCE"
}

public enum CursorDatabaseRootCauseAnalyzer {
    public static func isSignificant(bytes: Int64, ofTotal total: Int64) -> Bool {
        if bytes >= DatabaseStorageAccounting.significanceBytes { return true }
        guard total > 0 else { return false }
        return Double(bytes) / Double(total) >= DatabaseStorageAccounting.significanceFraction
    }

    public static func classify(
        dbBytes: Int64,
        freePageBytes: Int64,
        walBytes: Int64,
        logicalKVBytes: Int64,
        backupBytes: Int64,
        vendorRetentionFound: Bool
    ) -> (primary: CursorDatabaseGrowthRootCause, secondary: [CursorDatabaseGrowthRootCause]) {
        var secondary: [CursorDatabaseGrowthRootCause] = []
        let liveDominant = logicalKVBytes >= dbBytes / 2
            || isSignificant(bytes: logicalKVBytes, ofTotal: dbBytes)
        if isSignificant(bytes: freePageBytes, ofTotal: dbBytes) {
            secondary.append(.databaseFreelistBloatSignificant)
        }
        if isSignificant(bytes: walBytes, ofTotal: dbBytes) {
            secondary.append(.walAccumulationSignificant)
        }
        if isSignificant(bytes: backupBytes, ofTotal: dbBytes + backupBytes) {
            secondary.append(.backupRetentionSignificant)
        }
        if !vendorRetentionFound {
            secondary.append(.vendorRetentionGapSuspected)
        }
        let primary: CursorDatabaseGrowthRootCause = liveDominant
            ? .liveUserAgentStateDominant
            : (secondary.first ?? .unknownGrowthSource)
        return (primary, secondary.filter { $0 != primary })
    }

    /// Open DB must never become low-level executable.
    public static func rawDatabaseExecutable(dbOpen: Bool) -> Bool {
        _ = dbOpen
        return false
    }
}
