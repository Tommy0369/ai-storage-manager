import Foundation

public enum StorageHistoryStoreError: Error, Equatable {
    case unsupportedSchema(Int)
    case corruptSnapshot
    case writeFailed
    case notFound
}

/// Product-owned local history. Not iCloud / Downloads / Documents / repo.
public final class StorageHistoryStore: @unchecked Sendable {
    public let directory: URL
    public let retentionLimit: Int
    public let locationType: String

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(
        directory: URL,
        retentionLimit: Int = storageHistoryRetentionLimit,
        locationType: String = "applicationSupport"
    ) {
        self.directory = directory
        self.retentionLimit = retentionLimit
        self.locationType = locationType
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func applicationSupportStore(
        fileManager: FileManager = .default
    ) throws -> StorageHistoryStore {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base
            .appendingPathComponent("AIStorageManager", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return StorageHistoryStore(directory: dir, locationType: "applicationSupport")
    }

    public func save(_ snapshot: StorageHistorySnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(snapshot.snapshotID).json")
        do {
            let data = try encoder.encode(snapshot)
            // Atomic replace of product-owned history JSON only — no FileManager move/remove APIs
            // (those are reserved for the authorized storage mutation executor surface).
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw StorageHistoryStoreError.writeFailed
        }
        // Soft retention: loaders expose at most `retentionLimit` newest snapshots.
        // Physical file pruning is intentionally deferred to keep mutation surface = MOVE_TO_TRASH executor only.
    }

    /// Save without throwing into Safety path — returns success flag.
    public func saveSoft(_ snapshot: StorageHistorySnapshot) -> Bool {
        do {
            try save(snapshot)
            return true
        } catch {
            return false
        }
    }

    public func loadAll() -> [StorageHistorySnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return loadAllLocked()
    }

    public func load(id: String) throws -> StorageHistorySnapshot {
        lock.lock()
        defer { lock.unlock() }
        let url = directory.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StorageHistoryStoreError.notFound
        }
        return try decodeFile(url)
    }

    public func newest() -> StorageHistorySnapshot? {
        loadAll().first
    }

    /// Closest valid snapshot at or before target time. No interpolation.
    public func snapshot(atOrBefore target: Date) -> StorageHistorySnapshot? {
        loadAll().first { $0.generatedAt <= target }
    }

    public func status(writeSuccess: Bool) -> P302HistoryStatusReport {
        let all = loadAll()
        return P302HistoryStatusReport(
            historySnapshotCount: all.count,
            oldestSnapshotAt: all.last?.generatedAt,
            newestSnapshotAt: all.first?.generatedAt,
            retentionLimit: retentionLimit,
            historyStoreLocationType: locationType,
            snapshotWriteSuccess: writeSuccess,
            secondCrawlerAdded: false,
            privacyFieldsStored: StorageHistoryBuilder.privacyFieldsStored
        )
    }

    private func loadAllLocked() -> [StorageHistorySnapshot] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var snaps: [StorageHistorySnapshot] = []
        for url in urls where url.pathExtension == "json" {
            if let snap = try? decodeFile(url) {
                snaps.append(snap)
            }
            // corrupt / unsupported schema → skip safely
        }
        return Array(snaps.sorted { $0.generatedAt > $1.generatedAt }.prefix(retentionLimit))
    }

    private func decodeFile(_ url: URL) throws -> StorageHistorySnapshot {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StorageHistoryStoreError.corruptSnapshot
        }
        let snap: StorageHistorySnapshot
        do {
            snap = try decoder.decode(StorageHistorySnapshot.self, from: data)
        } catch {
            throw StorageHistoryStoreError.corruptSnapshot
        }
        guard snap.schemaVersion == storageHistorySchemaVersion else {
            throw StorageHistoryStoreError.unsupportedSchema(snap.schemaVersion)
        }
        return snap
    }
}
