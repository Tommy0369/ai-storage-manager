import Foundation

/// P3.3D — state.vscdb.backup retention & recovery contract (read-only).
/// BACKUP ≠ DISPOSABLE. Duplicate ≠ unnecessary. Age ≠ cleanup permission.

public enum CursorBackupFileType: String, Codable, Sendable, Equatable {
    case fullSqliteDatabase = "FULL_SQLITE_DATABASE"
    case sqliteSnapshot = "SQLITE_SNAPSHOT"
    case copyArtifact = "COPY_ARTIFACT"
    case migrationBackup = "MIGRATION_BACKUP"
    case recoveryBackup = "RECOVERY_BACKUP"
    case partialBackup = "PARTIAL_BACKUP"
    case opaqueCursorBackup = "OPAQUE_CURSOR_BACKUP"
    case unknown = "UNKNOWN"
}

public enum CursorBackupLifecycleClassification: String, Codable, Sendable, Equatable {
    case currentRecoveryBackup = "CURRENT_RECOVERY_BACKUP"
    case supersededRecoveryBackup = "SUPERSEDED_RECOVERY_BACKUP"
    case migrationBackupRemains = "MIGRATION_BACKUP_REMAINS"
    case legacyRecoveryBackup = "LEGACY_RECOVERY_BACKUP"
    case unknownBackup = "UNKNOWN_BACKUP"
}

public enum CursorBackupSourceOfTruthRole: String, Codable, Sendable, Equatable {
    case primarySource = "PRIMARY_SOURCE"
    case recoverySource = "RECOVERY_SOURCE"
    case secondaryRecoveryCopy = "SECONDARY_RECOVERY_COPY"
    case migrationRollbackCopy = "MIGRATION_ROLLBACK_COPY"
    case unknown = "UNKNOWN"
}

public enum CursorBackupCreationTrigger: String, Codable, Sendable, Equatable {
    case appUpdate = "APP_UPDATE"
    case schemaMigration = "SCHEMA_MIGRATION"
    case databaseMigration = "DATABASE_MIGRATION"
    case startupRecovery = "STARTUP_RECOVERY"
    case corruptionRecovery = "CORRUPTION_RECOVERY"
    case manualReset = "MANUAL_RESET"
    case periodicBackup = "PERIODIC_BACKUP"
    case storageCloseSnapshot = "STORAGE_CLOSE_SNAPSHOT"
    case unknown = "UNKNOWN"
}

public enum CursorBackupFutureActionUnit: String, Codable, Sendable, Equatable {
    case exactBackupFile = "EXACT_BACKUP_FILE"
    case supersededBackupSet = "SUPERSEDED_BACKUP_SET"
    case migrationBackup = "MIGRATION_BACKUP"
    case recoveryGeneration = "RECOVERY_GENERATION"
    case none = "NONE"
    case unknown = "UNKNOWN"
}

public struct CursorBackupRelationship: Codable, Sendable, Equatable {
    public var backupEntity: String
    public var sourceEntity: String
    public var structuralSimilarity: String
    public var logicalCoverage: String
    public var uniqueToBackupEstimate: Int64
    public var missingFromBackupEstimate: Int64
    public var createdByVendor: Bool
    public var restoreRelationship: String
    public var currentUse: String
    public var recoveryRole: CursorBackupSourceOfTruthRole
    public var confidence: String
}

public struct CursorDatabaseRecoveryContract: Codable, Sendable, Equatable {
    public var backupKind: CursorBackupFileType
    public var creationTrigger: CursorBackupCreationTrigger
    public var sourceDB: String
    public var backupPath: String
    public var restoreTrigger: String
    public var restoreOperation: String
    public var backupRetentionCount: Int
    public var replacementSemantics: String
    public var cleanupSemantics: String
    public var corruptionUse: String
    public var migrationUse: String
    public var rollbackUse: String
    public var confidence: String
    public var contractFound: Bool
    public var restorePathFound: Bool
    public var restoreReachable: Bool
}

public enum CursorDatabaseBackupAnalyzer {
    public static let relativeBackup = "state.vscdb.backup"
    public static let relativeMain = "state.vscdb"
    public static let storageNameLiteral = "state.vscdb"
    public static let disableBackupStorageKey = "cursor.storage.disableSqliteStorageBackup"

    /// Filename alone never authorizes cleanup.
    public static func filenameAloneIsNotSafe() -> Bool { true }

    /// Old mtime never promotes SafetyClass / actionability.
    public static func oldMtimeDoesNotPromoteSafety() -> Bool { true }

    /// Structural near-duplicate without lifecycle proof stays protected.
    public static func structuralDuplicateWithoutLifecycleStaysProtected() -> Bool { true }

    public static func potentialRecoveryBytes(
        vendorRetentionCleanupFound: Bool,
        contractAligned: Bool,
        exactTargetBytes: Int64
    ) -> Int64 {
        guard vendorRetentionCleanupFound, contractAligned else { return 0 }
        return exactTargetBytes
    }

    public static func classifyLifecycle(
        restorePathReachable: Bool,
        isSoleRecoveryGeneration: Bool,
        migrationSpecificProven: Bool,
        supersededByNewerVendorGeneration: Bool,
        uniqueRecoveryStatePresent: Bool
    ) -> CursorBackupLifecycleClassification {
        if supersededByNewerVendorGeneration {
            return .supersededRecoveryBackup
        }
        if migrationSpecificProven && !restorePathReachable {
            return .migrationBackupRemains
        }
        if restorePathReachable || isSoleRecoveryGeneration || uniqueRecoveryStatePresent {
            return .currentRecoveryBackup
        }
        return .unknownBackup
    }

    public static func classifyFileType(
        validSQLite: Bool,
        isPathPlusBackupSuffixCopy: Bool,
        usedAsOpenFailureRestore: Bool
    ) -> CursorBackupFileType {
        guard validSQLite else { return .opaqueCursorBackup }
        if usedAsOpenFailureRestore && isPathPlusBackupSuffixCopy {
            return .recoveryBackup
        }
        if isPathPlusBackupSuffixCopy {
            return .fullSqliteDatabase
        }
        return .unknown
    }

    /// Agent-cli / HF / conversation cleanup contracts must not cover DB backup.
    public static func wrongCleanupContractAgainstBackup(
        contractVendor: String,
        contractStorageClass: String,
        backupStoreCanonical: String,
        contractResolvedRoot: String
    ) -> VendorCleanupAlignmentStatus {
        let rel = CursorAgentCLIPathAlignment.relationship(
            actualCanonical: backupStoreCanonical,
            cleanupCanonical: contractResolvedRoot
        )
        if contractVendor != "CURSOR" { return .blocked }
        if contractStorageClass != "DATABASE_BACKUP_STORE" {
            return .semanticClassMismatch
        }
        if rel != .exactRootMatch {
            return .storeMismatch
        }
        return .verifyMore
    }

    /// Evidence-backed recovery contract from installed Cursor `main.js` (SQLiteStorageDatabase).
    public static func knownVendorRecoveryContract() -> CursorDatabaseRecoveryContract {
        CursorDatabaseRecoveryContract(
            backupKind: .recoveryBackup,
            creationTrigger: .storageCloseSnapshot,
            sourceDB: "state.vscdb (SQLiteStorageDatabase path)",
            backupPath: "${path}.backup  →  state.vscdb.backup",
            restoreTrigger: "connect/open failure after SQLITE error (not SQLITE_BUSY retry exhaustion path uses backup rename)",
            restoreOperation: "rename main→.corrupted.<ts>; rename .backup→main; reconnect",
            backupRetentionCount: 1,
            replacementSemantics: "single-file overwrite via copy(path, path.backup) on successful close when backup enabled",
            cleanupSemantics: "NONE_FOUND — no delete/rotate of .backup beyond overwrite; disable flag skips create but does not remove existing",
            corruptionUse: "LIVE — open failure recovery",
            migrationUse: "NOT_SPECIFIC — not a schema-migration-only artifact",
            rollbackUse: "IMPLICIT — restores last successful close snapshot",
            confidence: "VERIFIED_CALL_PATH",
            contractFound: true,
            restorePathFound: true,
            restoreReachable: true
        )
    }

    public static func planTier(
        lifecycle: CursorBackupLifecycleClassification,
        cleanupContractFound: Bool
    ) -> String {
        if cleanupContractFound { return "VERIFY_MORE" }
        switch lifecycle {
        case .currentRecoveryBackup:
            return "KEEP"
        case .supersededRecoveryBackup, .migrationBackupRemains:
            return "VERIFY_MORE"
        case .legacyRecoveryBackup, .unknownBackup:
            return "VERIFY_MORE"
        }
    }

    public static func rootExecutable() -> Bool { false }
}
