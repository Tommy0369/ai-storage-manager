import Foundation

/// P1.7: bounded, read-only Cursor metadata discovery.
/// Never dump arbitrary DB values. Key-only probes + exact-key reads only.
public struct CursorMetadataDiscoveryReport: Codable, Sendable, Equatable {
    public var metadataSourcesFound: [String]
    public var dbsFound: [String]
    public var dbsQueried: [String]
    public var tablesInspected: [String]
    public var rowsScanned: Int
    public var queryBudgets: [String: Int]
    public var uuidsDiscovered: Int
    public var explicitURIMappings: Int
    public var verifiedMappings: Int
    public var inferredMappings: Int
    public var ambiguousMappings: Int
    public var unknownMappings: Int
    public var timeouts: Int
    public var budgetExceeded: Int
    public var sanitizedMappings: [CursorSanitizedMapping]

    public init(
        metadataSourcesFound: [String] = [],
        dbsFound: [String] = [],
        dbsQueried: [String] = [],
        tablesInspected: [String] = [],
        rowsScanned: Int = 0,
        queryBudgets: [String: Int] = [:],
        uuidsDiscovered: Int = 0,
        explicitURIMappings: Int = 0,
        verifiedMappings: Int = 0,
        inferredMappings: Int = 0,
        ambiguousMappings: Int = 0,
        unknownMappings: Int = 0,
        timeouts: Int = 0,
        budgetExceeded: Int = 0,
        sanitizedMappings: [CursorSanitizedMapping] = []
    ) {
        self.metadataSourcesFound = metadataSourcesFound
        self.dbsFound = dbsFound
        self.dbsQueried = dbsQueried
        self.tablesInspected = tablesInspected
        self.rowsScanned = rowsScanned
        self.queryBudgets = queryBudgets
        self.uuidsDiscovered = uuidsDiscovered
        self.explicitURIMappings = explicitURIMappings
        self.verifiedMappings = verifiedMappings
        self.inferredMappings = inferredMappings
        self.ambiguousMappings = ambiguousMappings
        self.unknownMappings = unknownMappings
        self.timeouts = timeouts
        self.budgetExceeded = budgetExceeded
        self.sanitizedMappings = sanitizedMappings
    }
}

public struct CursorSanitizedMapping: Codable, Sendable, Equatable {
    public var keyID: String
    public var workspacePath: String
    public var confidence: String
    public var evidenceSource: String
    public var reasonCode: String?
}

public enum CursorExplicitMetadataResolver {
    public static let maxDBs = 4
    public static let maxKeyRows = 80
    public static let maxValueBytes = 64_000
    public static let dbTimeoutMs = 800

    public struct DiscoveryResult: Sendable {
        public var explicitKeyToFolder: [String: String]
        public var ambiguousKeys: Set<String>
        public var report: CursorMetadataDiscoveryReport
    }

    /// Discover explicit UUID/key → workspace path links from safe metadata sources.
    public static func discover(home: String) -> DiscoveryResult {
        var explicit: [String: String] = [:]
        var ambiguous = Set<String>()
        var sources: [String] = []
        var dbsFound: [String] = []
        var dbsQueried: [String] = []
        var tables: [String] = []
        var rows = 0
        var timeouts = 0
        var budgetExceeded = 0
        var sanitized: [CursorSanitizedMapping] = []
        var uriCount = 0

        // 1) workspace.json (already primary; reaffirm)
        let wsRoot = "\(home)/Library/Application Support/Cursor/User/workspaceStorage"
        if FileManager.default.fileExists(atPath: wsRoot) {
            sources.append("workspaceStorage/workspace.json")
            for kid in ChildFolderEnumerator(maxChildren: 40).immediateDirectories(at: wsRoot) {
                let jsonPath = "\(kid.path)/workspace.json"
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                let folderURI = (obj["folder"] as? String) ?? ""
                let path = CursorWorkspaceIdentityResolver.decodeFileURI(folderURI)
                guard !path.isEmpty, path.hasPrefix("/") else { continue }
                uriCount += 1
                merge(key: kid.name, path: path, into: &explicit, ambiguous: &ambiguous, sanitized: &sanitized, source: "WORKSPACE_JSON")
            }
        }

        // 2) globalStorage/storage.json — profileAssociations.workspaces keys are file URIs
        let storageJSON = "\(home)/Library/Application Support/Cursor/User/globalStorage/storage.json"
        if FileManager.default.fileExists(atPath: storageJSON) {
            sources.append("globalStorage/storage.json")
            if let data = try? Data(contentsOf: URL(fileURLWithPath: storageJSON)),
               data.count <= maxValueBytes,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let profiles = obj["profileAssociations"] as? [String: Any],
               let workspaces = profiles["workspaces"] as? [String: Any] {
                for (uri, _) in workspaces {
                    let path = CursorWorkspaceIdentityResolver.decodeFileURI(uri)
                    guard path.hasPrefix("/") else { continue }
                    uriCount += 1
                    // URI alone is not a UUID bridge; record path existence only via report mapping id=uri-hash
                    let key = "storage.json:\(URL(fileURLWithPath: path).lastPathComponent)"
                    sanitized.append(CursorSanitizedMapping(
                        keyID: key,
                        workspacePath: path,
                        confidence: "INFERRED",
                        evidenceSource: "STORAGE_JSON_PROFILE",
                        reasonCode: UnknownReasonCode.sourceRelationUnknown.rawValue
                    ))
                }
            }
        }

        // 3) globalStorage/state.vscdb — exact key + key-prefix only (never value LIKE)
        let globalDB = "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        if FileManager.default.fileExists(atPath: globalDB) {
            dbsFound.append(globalDB)
            sources.append("globalStorage/state.vscdb")
            if dbsQueried.count < maxDBs {
                dbsQueried.append(globalDB)
                let meta = queryExactValue(db: globalDB, key: "workspaceMetadata.entries", timeoutMs: dbTimeoutMs)
                rows += 1
                if meta.timedOut { timeouts += 1 }
                if let text = meta.value, text.count <= maxValueBytes {
                    tables.append("ItemTable")
                    parseWorkspaceMetadataEntries(text, explicit: &explicit, ambiguous: &ambiguous, sanitized: &sanitized, uriCount: &uriCount)
                }
                let glassKeys = queryKeysLike(
                    db: globalDB,
                    like: "cursor/glass.fileTab.viewState/%",
                    limit: maxKeyRows,
                    timeoutMs: dbTimeoutMs
                )
                if glassKeys.timedOut { timeouts += 1 }
                if glassKeys.budgetExceeded { budgetExceeded += 1 }
                rows += glassKeys.keys.count
                parseGlassFileTabKeys(glassKeys.keys, explicit: &explicit, ambiguous: &ambiguous, sanitized: &sanitized, uriCount: &uriCount)
            }
        }

        // 4) Sample workspaceStorage state.vscdb — schema/tables only + debug.selectedroot if present
        let wsKids = ChildFolderEnumerator(maxChildren: 6).immediateDirectories(at: wsRoot)
        for kid in wsKids {
            if dbsQueried.count >= maxDBs { budgetExceeded += 1; break }
            let db = "\(kid.path)/state.vscdb"
            guard FileManager.default.fileExists(atPath: db) else { continue }
            dbsFound.append(db)
            dbsQueried.append(db)
            let tableList = queryTables(db: db, timeoutMs: dbTimeoutMs)
            if tableList.timedOut { timeouts += 1 }
            tables.append(contentsOf: tableList.tables.map { "\(kid.name):\($0)" })
            let selected = queryExactValue(db: db, key: "debug.selectedroot", timeoutMs: dbTimeoutMs)
            rows += 1
            if selected.timedOut { timeouts += 1 }
            if let text = selected.value, text.count <= 2000, text.contains("file://") {
                let path = CursorWorkspaceIdentityResolver.decodeFileURI(text.trimmingCharacters(in: .whitespacesAndNewlines))
                if path.hasPrefix("/") {
                    uriCount += 1
                    merge(key: kid.name, path: path, into: &explicit, ambiguous: &ambiguous, sanitized: &sanitized, source: "DEBUG_SELECTEDROOT")
                }
            }
        }

        let verified = sanitized.filter { $0.confidence == "VERIFIED" }.count
        let inferred = sanitized.filter { $0.confidence == "INFERRED" }.count
        let amb = sanitized.filter { $0.confidence == "UNKNOWN" && $0.reasonCode == UnknownReasonCode.cursorRelationshipAmbiguous.rawValue }.count
        let unk = sanitized.filter { $0.confidence == "UNKNOWN" }.count

        let report = CursorMetadataDiscoveryReport(
            metadataSourcesFound: sources,
            dbsFound: dbsFound,
            dbsQueried: dbsQueried,
            tablesInspected: Array(Set(tables)).sorted(),
            rowsScanned: rows,
            queryBudgets: [
                "max_dbs": maxDBs,
                "max_key_rows": maxKeyRows,
                "max_value_bytes": maxValueBytes,
                "db_timeout_ms": dbTimeoutMs
            ],
            uuidsDiscovered: Set(explicit.keys).union(ambiguous).count,
            explicitURIMappings: uriCount,
            verifiedMappings: verified,
            inferredMappings: inferred,
            ambiguousMappings: amb,
            unknownMappings: unk,
            timeouts: timeouts,
            budgetExceeded: budgetExceeded,
            sanitizedMappings: Array(sanitized.prefix(40))
        )
        return DiscoveryResult(explicitKeyToFolder: explicit, ambiguousKeys: ambiguous, report: report)
    }

    static func merge(
        key: String,
        path: String,
        into explicit: inout [String: String],
        ambiguous: inout Set<String>,
        sanitized: inout [CursorSanitizedMapping],
        source: String
    ) {
        if ambiguous.contains(key) {
            sanitized.append(.init(keyID: key, workspacePath: path, confidence: "UNKNOWN", evidenceSource: source, reasonCode: UnknownReasonCode.cursorRelationshipAmbiguous.rawValue))
            return
        }
        if let existing = explicit[key], existing != path {
            explicit.removeValue(forKey: key)
            ambiguous.insert(key)
            sanitized.append(.init(keyID: key, workspacePath: path, confidence: "UNKNOWN", evidenceSource: source, reasonCode: UnknownReasonCode.cursorRelationshipAmbiguous.rawValue))
            return
        }
        explicit[key] = path
        let exists = FileManager.default.fileExists(atPath: path)
        sanitized.append(.init(
            keyID: key,
            workspacePath: path,
            confidence: exists ? "VERIFIED" : "UNKNOWN",
            evidenceSource: source,
            reasonCode: exists ? nil : UnknownReasonCode.cursorWorkspaceTargetNotFound.rawValue
        ))
    }

    static func parseWorkspaceMetadataEntries(
        _ text: String,
        explicit: inout [String: String],
        ambiguous: inout Set<String>,
        sanitized: inout [CursorSanitizedMapping],
        uriCount: inout Int
    ) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = obj["entries"] as? [[String: Any]]
        else { return }
        for entry in entries.prefix(40) {
            let wid = (entry["workspaceId"] as? String) ?? ""
            let folderURI = (entry["folderUri"] as? String) ?? ""
            let path = CursorWorkspaceIdentityResolver.decodeFileURI(folderURI)
            guard !wid.isEmpty, path.hasPrefix("/") else { continue }
            uriCount += 1
            merge(key: wid, path: path, into: &explicit, ambiguous: &ambiguous, sanitized: &sanitized, source: "WORKSPACE_METADATA_ENTRIES")
        }
    }

    /// Keys shaped: cursor/glass.fileTab.viewState/{workspaceStorageId}/file://...
    static func parseGlassFileTabKeys(
        _ keys: [String],
        explicit: inout [String: String],
        ambiguous: inout Set<String>,
        sanitized: inout [CursorSanitizedMapping],
        uriCount: inout Int
    ) {
        let prefix = "cursor/glass.fileTab.viewState/"
        var seen = Set<String>()
        for key in keys {
            guard key.hasPrefix(prefix) else { continue }
            let rest = String(key.dropFirst(prefix.count))
            guard let slash = rest.firstIndex(of: "/") else { continue }
            let wid = String(rest[..<slash])
            let uri = String(rest[rest.index(after: slash)...])
            guard uri.hasPrefix("file://") else { continue }
            uriCount += 1
            guard !seen.contains(wid) else { continue }
            seen.insert(wid)
            if explicit[wid] != nil { continue }
            let filePath = CursorWorkspaceIdentityResolver.decodeFileURI(uri)
            sanitized.append(.init(
                keyID: wid,
                workspacePath: filePath,
                confidence: "UNKNOWN",
                evidenceSource: "GLASS_FILETAB_KEY",
                reasonCode: UnknownReasonCode.cursorWorkspaceURIMissing.rawValue
            ))
        }
        _ = ambiguous
    }

    // MARK: - Bounded sqlite3 CLI

    struct QueryResult {
        var value: String?
        var timedOut: Bool = false
    }
    struct KeysResult {
        var keys: [String]
        var timedOut: Bool = false
        var budgetExceeded: Bool = false
    }
    struct TablesResult {
        var tables: [String]
        var timedOut: Bool = false
    }

    static func queryExactValue(db: String, key: String, timeoutMs: Int) -> QueryResult {
        // Escape single quotes for SQL literal
        let escaped = key.replacingOccurrences(of: "'", with: "''")
        let sql = "SELECT substr(value,1,\(maxValueBytes)) FROM ItemTable WHERE key='\(escaped)' LIMIT 1;"
        let out = runSQLite(db: db, sql: sql, timeoutMs: timeoutMs)
        if out.timedOut { return QueryResult(value: nil, timedOut: true) }
        let text = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return QueryResult(value: text.isEmpty ? nil : text, timedOut: false)
    }

    static func queryKeysLike(db: String, like: String, limit: Int, timeoutMs: Int) -> KeysResult {
        let escaped = like.replacingOccurrences(of: "'", with: "''")
        let sql = "SELECT key FROM ItemTable WHERE key LIKE '\(escaped)' LIMIT \(limit);"
        let out = runSQLite(db: db, sql: sql, timeoutMs: timeoutMs)
        if out.timedOut { return KeysResult(keys: [], timedOut: true) }
        let keys = out.stdout.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        return KeysResult(keys: keys, timedOut: false, budgetExceeded: keys.count >= limit)
    }

    static func queryTables(db: String, timeoutMs: Int) -> TablesResult {
        let out = runSQLite(db: db, sql: ".tables", timeoutMs: timeoutMs)
        if out.timedOut { return TablesResult(tables: [], timedOut: true) }
        let tables = out.stdout.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        return TablesResult(tables: tables, timedOut: false)
    }

    struct SQLiteRun {
        var stdout: String
        var timedOut: Bool
    }

    static func runSQLite(db: String, sql: String, timeoutMs: Int) -> SQLiteRun {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [db, sql]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
            while proc.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if proc.isRunning {
                proc.terminate()
                return SQLiteRun(stdout: "", timedOut: true)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return SQLiteRun(stdout: String(data: data, encoding: .utf8) ?? "", timedOut: false)
        } catch {
            return SQLiteRun(stdout: "", timedOut: false)
        }
    }
}
