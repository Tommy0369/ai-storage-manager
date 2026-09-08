import Foundation

/// Canonical Ollama model identity helpers. Never accept free-form UI/shell text.
public enum OllamaModelIdentity {
    /// Allowed: namespace/name:tag  or  name:tag  (alphanumeric, ., _, -, / and one :)
    private static let pattern = #"^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?:[A-Za-z0-9._-]+$"#

    public static func isValidCanonical(_ identity: String) -> Bool {
        guard !identity.isEmpty, identity.count <= 256 else { return false }
        if identity.contains("\n") || identity.contains("\r") || identity.contains("\0") { return false }
        if identity.contains(";") || identity.contains("|") || identity.contains("&")
            || identity.contains("`") || identity.contains("$") || identity.contains("(")
            || identity.contains(")") || identity.contains("<") || identity.contains(">")
            || identity.contains("*") || identity.contains("?") || identity.contains("!")
            || identity.contains("\\") || identity.contains(" ") {
            return false
        }
        if identity.hasPrefix("/") || identity.hasPrefix("-") || identity.hasPrefix("~") {
            return false
        }
        guard identity.range(of: pattern, options: .regularExpression) != nil else { return false }
        return true
    }

    public static func validateOrThrow(_ identity: String) throws {
        guard isValidCanonical(identity) else {
            throw ActionExecutionError.invalidModelIdentity(identity)
        }
    }

    public static func rmArguments(canonicalModel: String) throws -> [String] {
        try validateOrThrow(canonicalModel)
        return ["rm", canonicalModel]
    }

    /// Prefer bound Fresh Preflight executable, then deterministic resolver. Never PATH/env.
    public static func resolveExecutableURL(
        fileManager: FileManager = .default,
        boundExecutablePath: String? = nil,
        processExecutablePaths: [String] = [],
        processRunner: any BoundedProcessRunner = FoundationProcessRunner()
    ) -> URL? {
        if let bound = boundExecutablePath, fileManager.isExecutableFile(atPath: bound) {
            return URL(fileURLWithPath: bound)
        }
        let resolution = OllamaNativeInterfaceResolver.resolve(
            context: .init(
                fileManager: fileManager,
                processRunner: processRunner,
                processExecutablePaths: processExecutablePaths,
                modelDataPresent: fileManager.fileExists(
                    atPath: (NSHomeDirectory() as NSString).appendingPathComponent(".ollama/models")
                )
            )
        )
        guard resolution.executionTransportAvailable, let path = resolution.cliExecutableURL else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}

/// Single-use permit ledger. Prevents double-submit / replay.
public enum ExecutionPermitLedger {
    private static let lock = NSLock()
    private static var consumed: Set<String> = []

    public static func reset() {
        lock.lock(); defer { lock.unlock() }
        consumed.removeAll()
    }

    public static func isConsumed(_ permitID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return consumed.contains(permitID)
    }

    public static func consume(_ permitID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if consumed.contains(permitID) { return false }
        consumed.insert(permitID)
        return true
    }
}
