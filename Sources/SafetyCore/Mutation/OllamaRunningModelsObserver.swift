import Foundation

/// Bounded read-only observation of currently loaded Ollama models (`ollama ps`).
/// Service running alone never implies a specific model is ACTIVE.
public struct OllamaRunningModelsSnapshot: Sendable, Equatable {
    public var completeness: ObservationCompleteness
    public var runningModelIdentities: Set<String>
    public var observedAt: Date
    public var rawStdoutSummary: String
    public var failureReason: String?

    public init(
        completeness: ObservationCompleteness,
        runningModelIdentities: Set<String>,
        observedAt: Date = Date(),
        rawStdoutSummary: String = "",
        failureReason: String? = nil
    ) {
        self.completeness = completeness
        self.runningModelIdentities = runningModelIdentities
        self.observedAt = observedAt
        self.rawStdoutSummary = rawStdoutSummary
        self.failureReason = failureReason
    }

    /// Exact target inactivity is VERIFIED only when the snapshot is COMPLETE
    /// and the canonical identity is absent.
    public func inactivity(for canonicalModel: String) -> (state: ObservedActiveState, confidence: EvidenceConfidence) {
        guard completeness == .complete else {
            return (.unknown, .unknown)
        }
        if runningModelIdentities.contains(canonicalModel)
            || runningModelIdentities.contains(where: { OllamaModelIdentityNormalization.matches($0, canonical: canonicalModel) }) {
            return (.active, .verified)
        }
        return (.inactive, .verified)
    }

    private static func matches(_ running: String, canonical: String) -> Bool {
        OllamaModelIdentityNormalization.matches(running, canonical: canonical)
    }
}

public enum OllamaRunningModelsObserver {
    public static func capture(
        runner: any BoundedProcessRunner,
        executableURL: URL?,
        timeoutSeconds: TimeInterval = 8
    ) -> OllamaRunningModelsSnapshot {
        guard let exe = executableURL else {
            return OllamaRunningModelsSnapshot(
                completeness: .unknown,
                runningModelIdentities: [],
                failureReason: "OLLAMA_EXECUTABLE_UNRESOLVED"
            )
        }
        let result = runner.run(BoundedProcessRequest(
            executableURL: exe,
            arguments: ["ps"],
            timeoutSeconds: timeoutSeconds
        ))
        switch result.outcome {
        case .timedOut:
            return OllamaRunningModelsSnapshot(
                completeness: .partial,
                runningModelIdentities: [],
                rawStdoutSummary: truncate(result.stdout),
                failureReason: "OLLAMA_PS_TIMEOUT"
            )
        case .startFailed, .terminated, .unknownOutcome:
            return OllamaRunningModelsSnapshot(
                completeness: .unknown,
                runningModelIdentities: [],
                rawStdoutSummary: truncate(result.stderr),
                failureReason: result.outcome.rawValue
            )
        case .nonzeroExit:
            // Nonzero may mean daemon down — not authoritative inactivity.
            return OllamaRunningModelsSnapshot(
                completeness: .partial,
                runningModelIdentities: [],
                rawStdoutSummary: truncate(result.stderr.isEmpty ? result.stdout : result.stderr),
                failureReason: "OLLAMA_PS_NONZERO"
            )
        case .commandAccepted:
            let names = parsePS(result.stdout)
            return OllamaRunningModelsSnapshot(
                completeness: .complete,
                runningModelIdentities: names,
                rawStdoutSummary: truncate(result.stdout)
            )
        }
    }

    /// Parse `ollama ps` table: NAME column.
    public static func parsePS(_ stdout: String) -> Set<String> {
        var out: Set<String> = []
        let lines = stdout.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return out }
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if idx == 0, trimmed.uppercased().hasPrefix("NAME") { continue }
            let cols = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let name = cols.first, !name.isEmpty else { continue }
            out.insert(name)
        }
        return out
    }

    private static func truncate(_ s: String, max: Int = 400) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max))
    }
}
