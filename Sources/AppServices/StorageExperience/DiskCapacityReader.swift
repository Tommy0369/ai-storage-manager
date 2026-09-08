import Foundation

public enum DiskCapacityReader {
    public static func snapshot(at path: String = NSHomeDirectory()) -> DiskCapacitySnapshot {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let total = values?.volumeTotalCapacity.map { Int64($0) }
        let available = values?.volumeAvailableCapacityForImportantUsage
            ?? values?.volumeAvailableCapacity.map { Int64($0) }
        let used: Int64?
        if let total, let available {
            used = max(0, total - available)
        } else {
            used = nil
        }
        return DiskCapacitySnapshot(
            volumeName: values?.volumeName ?? "Macintosh HD",
            volumeTotalBytes: total,
            volumeAvailableBytes: available,
            volumeUsedBytes: used
        )
    }
}
