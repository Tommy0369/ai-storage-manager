import Foundation

/// Read-only volume free-space measurement for post-mutation recovery observation.
public enum StorageCapacityMeasurer {
    public static func freeBytes(at path: String = NSHomeDirectory()) -> Int64? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]) else { return nil }
        if let important = values.volumeAvailableCapacityForImportantUsage {
            return important
        }
        if let available = values.volumeAvailableCapacity {
            return Int64(available)
        }
        return nil
    }

    public static func itemBytes(at path: String) -> Int64? {
        let canonical = (path as NSString).standardizingPath
        guard FileManager.default.fileExists(atPath: canonical) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical, isDirectory: &isDir) else { return nil }
        if isDir.boolValue {
            return directoryBytes(at: canonical)
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: canonical),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }

    private static func directoryBytes(at path: String) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
