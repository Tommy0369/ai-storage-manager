import Foundation

public enum PathGlob {
    public static func matches(path: String, pattern: String) -> Bool {
        let expandedPattern = expandHome(pattern)
        let expandedPath = expandHome(path)
        let regex = globToRegex(expandedPattern)
        return expandedPath.range(of: regex, options: .regularExpression) != nil
    }

    public static func expandHome(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent(String(path.dropFirst(2)))
        }
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        return path
    }

    static func globToRegex(_ pattern: String) -> String {
        var result = "^"
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let ch = pattern[i]
            if ch == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex, pattern[next] == "*" {
                    let after = pattern.index(after: next)
                    if after < pattern.endIndex, pattern[after] == "/" {
                        result += "(?:.*/)?"
                        i = pattern.index(after: after)
                        continue
                    }
                    result += ".*"
                    i = after
                    continue
                }
                result += "[^/]*"
                i = next
                continue
            }
            if "\\.[]{}()+-^$|?".contains(ch) {
                result.append("\\")
            }
            result.append(ch)
            i = pattern.index(after: i)
        }
        result += "$"
        return result
    }
}

public struct HardSafetyGates {
    public static let blockedPrefixes: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/private/var/db",
        "/private/var/vm",
        "/Library/Keychains",
        "/private/var/db/dslocal",
        "/Library/Apple",
    ]

    public static func isHardBlocked(path: String) -> Bool {
        let p = PathGlob.expandHome(path)
        if blockedPrefixes.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) {
            return true
        }
        let lower = p.lowercased()
        if lower.contains("/library/keychains") { return true }
        if lower.hasSuffix(".keychain-db") { return true }
        return false
    }
}
