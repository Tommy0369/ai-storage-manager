import Foundation

/// P3.3B — bounded read-only physical accounting for Cursor state.vscdb.
/// Never copies the 10GB DB. Never VACUUM/checkpoint/mutate.
public enum CursorStateDatabaseInspector {
    public static let relativeDB = "state.vscdb"
    public static let relativeWAL = "state.vscdb-wal"
    public static let relativeSHM = "state.vscdb-shm"
    public static let relativeBackup = "state.vscdb.backup"

    public struct FileFingerprint: Codable, Sendable, Equatable {
        public var bytes: Int64
        public var mtime: TimeInterval
    }

    public static func globalStorageRoot(home: String) -> String {
        "\(home)/Library/Application Support/Cursor/User/globalStorage"
    }

    public static func fingerprint(_ path: String) -> FileFingerprint? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber,
              let date = attrs[.modificationDate] as? Date else { return nil }
        return FileFingerprint(bytes: size.int64Value, mtime: date.timeIntervalSince1970)
    }

    public static func inspectPhysical(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        dbOpenHint: Bool? = nil
    ) throws -> DatabaseStorageAccounting {
        let root = globalStorageRoot(home: home)
        let dbPath = "\(root)/\(relativeDB)"
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw CursorSQLiteInspectionError.databaseMissing(dbPath)
        }
        let beforeDB = fingerprint(dbPath)
        let beforeWAL = fingerprint("\(root)/\(relativeWAL)")
        let beforeSHM = fingerprint("\(root)/\(relativeSHM)")

        let pageSize = try readPragmaInt(dbPath, "PRAGMA query_only=ON; PRAGMA page_size;")
        let pageCount = try readPragmaInt(dbPath, "PRAGMA query_only=ON; PRAGMA page_count;")
        let freeCount = try readPragmaInt(dbPath, "PRAGMA query_only=ON; PRAGMA freelist_count;")
        let journal = try readPragmaString(dbPath, "PRAGMA query_only=ON; PRAGMA journal_mode;")
        let autoVac = try readPragmaString(dbPath, "PRAGMA query_only=ON; PRAGMA auto_vacuum;")

        let afterPragmaDB = fingerprint(dbPath)
        let afterWAL = fingerprint("\(root)/\(relativeWAL)")
        let afterSHM = fingerprint("\(root)/\(relativeSHM)")

        let open = dbOpenHint ?? isPathOpen(dbPath)
        // RO PRAGMA/query_only cannot mutate. Concurrent Cursor may rewrite DB/WAL while open.
        // inspectionMutationDetected = our process issued mutating SQL (always false after assertReadOnly).
        // File growth during an OPEN DB is concurrentWriterChange, not our mutation.
        let concurrentDBChange =
            (beforeDB?.bytes != afterPragmaDB?.bytes) || (beforeDB?.mtime != afterPragmaDB?.mtime)
        let mutationByUs = false

        let freeBytes = freeCount * pageSize
        let allocated = max(0, (pageCount - freeCount) * pageSize)
        let dbBytes = afterPragmaDB?.bytes ?? beforeDB?.bytes ?? 0
        let walBytes = afterWAL?.bytes ?? beforeWAL?.bytes ?? 0
        let shmBytes = afterSHM?.bytes ?? beforeSHM?.bytes ?? 0

        // dbstat is optional / best-effort — may take long while Cursor writes concurrently.
        let largest = try? largestDBStatObject(dbPath)

        let safety: String
        if mutationByUs {
            safety = "MUTATION_DETECTED"
        } else if concurrentDBChange && open {
            safety = "READ_ONLY_OK_CONCURRENT_WRITER"
        } else if concurrentDBChange {
            safety = "READ_ONLY_OK_FILE_CHANGED_EXTERNAL"
        } else {
            safety = "READ_ONLY_OK"
        }

        return DatabaseStorageAccounting(
            databaseFileBytes: dbBytes,
            walBytes: walBytes,
            shmBytes: shmBytes,
            pageSize: pageSize,
            pageCount: pageCount,
            freePageCount: freeCount,
            freePageBytes: freeBytes,
            estimatedAllocatedPayloadBytes: allocated,
            journalMode: journal,
            autoVacuumMode: autoVac,
            dbOpen: open,
            inspectionMethod: "sqlite3_CLI_PRAGMA_query_only_RO_URI_mode_ro",
            inspectionMutationDetected: mutationByUs,
            accountingConfidence: "VERIFIED_PRAGMA_DBSTAT_OPTIONAL",
            inspectionSafety: safety,
            largestObjectName: largest?.name,
            largestObjectBytes: largest?.bytes,
            freelistSignificant: CursorDatabaseRootCauseAnalyzer.isSignificant(
                bytes: freeBytes, ofTotal: dbBytes
            ),
            walSignificant: CursorDatabaseRootCauseAnalyzer.isSignificant(
                bytes: walBytes, ofTotal: dbBytes
            )
        )
    }

    public static func cursorVendorStorageClassLabels() -> [String: String] {
        // From Cursor's own storageSizeScanMain.js (VERIFIED_LITERAL_REFERENCE).
        [
            "bubbleId": "Chat messages — per-bubble message bodies (bubbleId:*)",
            "agentKv": "Agent blobs/checkpoints/artifacts under agentKv:*",
            "agentKv:blob": "Conversation-state blobs (agentKv:blob:*)",
            "checkpointId": "Composer file checkpoints (checkpointId:*)",
            "composerData": "Per-chat composerData payloads",
            "composer.content": "Composer content payloads",
        ]
    }

    // MARK: - helpers

    static func isPathOpen(_ path: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-nP", path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run(); proc.waitUntilExit() } catch { return false }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.split(separator: "\n").count > 1
    }

    static func readPragmaInt(_ db: String, _ sql: String) throws -> Int64 {
        try CursorSQLiteReadOnlyContract.assertReadOnlyOrThrow(sql)
        let text = try runSQLite(db: db, sql: sql)
        guard let v = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? "") else {
            throw CursorSQLiteInspectionError.queryFailed(sql)
        }
        return v
    }

    static func readPragmaString(_ db: String, _ sql: String) throws -> String {
        try CursorSQLiteReadOnlyContract.assertReadOnlyOrThrow(sql)
        let text = try runSQLite(db: db, sql: sql)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
    }

    static func largestDBStatObject(_ db: String) throws -> (name: String, bytes: Int64)? {
        let sql = "PRAGMA query_only=ON; SELECT name, SUM(pgsize) FROM dbstat GROUP BY name ORDER BY SUM(pgsize) DESC LIMIT 1;"
        try CursorSQLiteReadOnlyContract.assertReadOnlyOrThrow(sql)
        let text = try runSQLite(db: db, sql: sql)
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
        guard parts.count >= 2, let bytes = Int64(parts[1]) else { return nil }
        return (String(parts[0]), bytes)
    }

    static func runSQLite(db: String, sql: String) throws -> String {
        try CursorSQLiteReadOnlyContract.assertReadOnlyOrThrow(sql)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        // Prefer mode=ro URI — still avoid immutable=1 against live WAL.
        proc.arguments = ["file:\(db)?mode=ro", sql]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do { try proc.run() } catch {
            throw CursorSQLiteInspectionError.queryFailed(String(describing: error))
        }
        proc.waitUntilExit()
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            // Fallback: plain path + query_only (still RO contract)
            let p2 = Process()
            p2.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            p2.arguments = [db, sql]
            let o2 = Pipe()
            p2.standardOutput = o2
            p2.standardError = Pipe()
            try p2.run()
            p2.waitUntilExit()
            if p2.terminationStatus != 0 {
                throw CursorSQLiteInspectionError.queryFailed(stderr)
            }
            return String(data: o2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
