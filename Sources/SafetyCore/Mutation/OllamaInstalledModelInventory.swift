import Foundation

/// Read-only installed-model inventory via `ollama list` (never rm/run/pull/create).
public enum OllamaInstalledModelInventory {
    public struct Snapshot: Codable, Sendable, Equatable {
        public var models: [String]
        public var rawLineCount: Int
        public var source: String
        public var observedAt: Date
        public var failureReason: String?
    }

    public static func capture(
        cliURL: URL,
        runner: any BoundedProcessRunner,
        now: Date = Date()
    ) -> Snapshot {
        let result = runner.run(BoundedProcessRequest(
            executableURL: cliURL,
            arguments: ["list"],
            timeoutSeconds: 20
        ))
        guard result.outcome == .commandAccepted || result.outcome == .nonzeroExit else {
            return Snapshot(
                models: [],
                rawLineCount: 0,
                source: "ollama list",
                observedAt: now,
                failureReason: "LIST_\(result.outcome.rawValue)"
            )
        }
        let models = parseListOutput(result.stdout)
        return Snapshot(
            models: models,
            rawLineCount: result.stdout.split(whereSeparator: \.isNewline).count,
            source: "ollama list",
            observedAt: now,
            failureReason: models.isEmpty && result.outcome != .commandAccepted
                ? "LIST_EMPTY_OR_FAILED"
                : nil
        )
    }

    public static func recognition(
        targetCanonical: String,
        inventory: Snapshot
    ) -> InstalledModelRecognitionStatus {
        if inventory.failureReason != nil && inventory.models.isEmpty {
            return .inventoryUnavailable
        }
        let hits = inventory.models.filter {
            OllamaModelIdentityNormalization.matches($0, canonical: targetCanonical)
        }
        if hits.count == 1 { return .recognizedExact }
        if hits.count > 1 { return .identityAmbiguous }
        return .dataRemainsUnrecognized
    }

    /// Parse `ollama list` NAME column. Tolerates header + SIZE/MODIFIED columns.
    public static func parseListOutput(_ stdout: String) -> [String] {
        var out: [String] = []
        for (idx, raw) in stdout.split(whereSeparator: \.isNewline).enumerated() {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lower = line.lowercased()
            if idx == 0, lower.hasPrefix("name") || lower.contains("name") && lower.contains("id") {
                continue
            }
            let cols = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let name = cols.first, !name.isEmpty else { continue }
            if name.lowercased() == "name" { continue }
            out.append(name)
        }
        return out
    }
}
