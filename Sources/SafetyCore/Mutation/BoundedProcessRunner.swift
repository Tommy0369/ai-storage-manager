import Foundation

/// Direct argv process runner. Never uses a shell.
public protocol BoundedProcessRunner: Sendable {
    func run(_ request: BoundedProcessRequest) -> BoundedProcessResult
}

public struct BoundedProcessRequest: Sendable, Equatable {
    public var executableURL: URL
    public var arguments: [String]
    public var timeoutSeconds: TimeInterval
    public var currentDirectoryURL: URL?

    public init(
        executableURL: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval = 30,
        currentDirectoryURL: URL? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
        self.currentDirectoryURL = currentDirectoryURL
    }
}

public enum BoundedProcessOutcome: String, Codable, Sendable, Equatable {
    case commandAccepted = "COMMAND_ACCEPTED"
    case startFailed = "START_FAILED"
    case timedOut = "TIMED_OUT"
    case nonzeroExit = "NONZERO_EXIT"
    case terminated = "TERMINATED"
    case unknownOutcome = "UNKNOWN_OUTCOME"
}

public struct BoundedProcessResult: Sendable, Equatable {
    public var outcome: BoundedProcessOutcome
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String
    public var durationMs: Int

    public init(
        outcome: BoundedProcessOutcome,
        exitCode: Int32? = nil,
        stdout: String = "",
        stderr: String = "",
        durationMs: Int = 0
    ) {
        self.outcome = outcome
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
    }
}

/// Records invocations for tests. Never touches the real machine beyond what the test configures.
public final class FakeProcessRunner: BoundedProcessRunner, @unchecked Sendable {
    public struct Invocation: Sendable, Equatable {
        public var executablePath: String
        public var arguments: [String]
        public var timeoutSeconds: TimeInterval
    }

    public var invocations: [Invocation] = []
    public var nextResult: BoundedProcessResult
    public var resultsByInvocationIndex: [Int: BoundedProcessResult] = [:]
    /// Prefer exact argv match when configured (tests).
    public var resultsByArguments: [[String]: BoundedProcessResult] = [:]

    public init(nextResult: BoundedProcessResult = BoundedProcessResult(outcome: .commandAccepted, exitCode: 0)) {
        self.nextResult = nextResult
    }

    public func run(_ request: BoundedProcessRequest) -> BoundedProcessResult {
        let inv = Invocation(
            executablePath: request.executableURL.path,
            arguments: request.arguments,
            timeoutSeconds: request.timeoutSeconds
        )
        let index = invocations.count
        invocations.append(inv)
        if let byArgs = resultsByArguments[request.arguments] {
            return byArgs
        }
        return resultsByInvocationIndex[index] ?? nextResult
    }
}

/// Real Process-based runner. Direct executable URL + argv only.
public struct FoundationProcessRunner: BoundedProcessRunner {
    public init() {}

    public func run(_ request: BoundedProcessRequest) -> BoundedProcessResult {
        let started = Date()
        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.currentDirectoryURL = request.currentDirectoryURL
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return BoundedProcessResult(
                outcome: .startFailed,
                stderr: error.localizedDescription,
                durationMs: Int(Date().timeIntervalSince(started) * 1000)
            )
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }
        let wait = group.wait(timeout: .now() + request.timeoutSeconds)
        if wait == .timedOut {
            process.terminate()
            return BoundedProcessResult(
                outcome: .timedOut,
                exitCode: process.terminationStatus,
                stdout: String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                stderr: String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                durationMs: Int(Date().timeIntervalSince(started) * 1000)
            )
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let code = process.terminationStatus
        let outcome: BoundedProcessOutcome
        switch process.terminationReason {
        case .exit:
            outcome = code == 0 ? .commandAccepted : .nonzeroExit
        case .uncaughtSignal:
            outcome = .terminated
        @unknown default:
            outcome = .unknownOutcome
        }
        return BoundedProcessResult(
            outcome: outcome,
            exitCode: code,
            stdout: stdout,
            stderr: stderr,
            durationMs: Int(Date().timeIntervalSince(started) * 1000)
        )
    }
}
