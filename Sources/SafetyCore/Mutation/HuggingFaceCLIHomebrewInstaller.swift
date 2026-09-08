import Foundation

/// Installs Hugging Face `hf` CLI via Homebrew under exact install authorization.
/// Never runs `hf cache rm`. Never deletes Hub data. Never mints cleanup permits.
public enum HuggingFaceCLIHomebrewInstaller {
    public static let expectedPackageIdentity = "hf"
    public static let entityID = "ai.hf.snapshot.mlx-community.whisper-large-v3-mlx.49e6aa286ad6"

    public struct InstallResult: Codable, Sendable, Equatable {
        public var installationSucceeded: Bool
        public var brewExecutableURL: String?
        public var argv: [String]
        public var installedVersion: String?
        public var executableURL: String?
        public var binaryFingerprint: String?
        public var contractProven: Bool
        public var supportsCacheLS: Bool
        public var supportsCacheVerify: Bool
        public var supportsCacheRM: Bool
        public var supportsDryRun: Bool
        public var supportsCacheDir: Bool
        public var cacheModified: Bool
        public var cacheRmExecuted: Bool
        public var cleanupPermitCreated: Bool
        public var authorizationConsumed: Bool
        public var processOutcome: String?
        public var exitCode: Int32?
        public var durationMs: Int
        public var failureReason: String?
        public var completedAt: Date
    }

    public struct Context: Sendable {
        public var fileManager: FileManager
        public var processRunner: any BoundedProcessRunner
        public var brewExecutableURL: URL?
        public var now: Date

        public init(
            fileManager: FileManager = .default,
            processRunner: any BoundedProcessRunner = FoundationProcessRunner(),
            brewExecutableURL: URL? = nil,
            now: Date = Date()
        ) {
            self.fileManager = fileManager
            self.processRunner = processRunner
            self.brewExecutableURL = brewExecutableURL
            self.now = now
        }
    }

    public static func resolveBrewExecutable(
        fileManager: FileManager = .default,
        processRunner: any BoundedProcessRunner = FoundationProcessRunner()
    ) -> URL? {
        let resolution = HomebrewArchitectureResolver.resolve(
            context: .init(fileManager: fileManager, processRunner: processRunner)
        )
        guard let path = resolution.selectedExecutable,
              resolution.architectureMatchesHost else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Production gate: HF CLI install scope only. Consumes auth once.
    public static func install(
        authorization: inout SoftwareInstallationAuthorization,
        context: Context = Context()
    ) -> InstallResult {
        let started = Date()
        func fail(_ reason: String, consumed: Bool = false) -> InstallResult {
            InstallResult(
                installationSucceeded: false,
                brewExecutableURL: context.brewExecutableURL?.path,
                argv: [],
                installedVersion: nil,
                executableURL: nil,
                binaryFingerprint: nil,
                contractProven: false,
                supportsCacheLS: false,
                supportsCacheVerify: false,
                supportsCacheRM: false,
                supportsDryRun: false,
                supportsCacheDir: false,
                cacheModified: false,
                cacheRmExecuted: false,
                cleanupPermitCreated: false,
                authorizationConsumed: consumed,
                processOutcome: nil,
                exitCode: nil,
                durationMs: Int(Date().timeIntervalSince(started) * 1000),
                failureReason: reason,
                completedAt: Date()
            )
        }

        guard authorization.allowsHuggingFaceCLIInstall else {
            return fail(authorization.isConsumed
                ? "INSTALL_AUTHORIZATION_CONSUMED"
                : "INSTALL_AUTHORIZATION_MISSING_OR_OUT_OF_SCOPE")
        }
        guard authorization.vendor == .huggingFace,
              authorization.scope == .huggingFaceCLIInstallationOnly,
              authorization.doesNotAuthorizeCleanup,
              authorization.doesNotAuthorizeModelRemoval,
              authorization.doesNotAuthorizeRawDelete else {
            return fail("AUTHORIZATION_SCOPE_NOT_HF_CLI_INSTALL")
        }

        guard let brew = context.brewExecutableURL ?? resolveBrewExecutable(fileManager: context.fileManager) else {
            return fail("BREW_EXECUTABLE_UNRESOLVED")
        }

        // Consume before mutation — single-purpose install only.
        guard authorization.consume(at: context.now) else {
            return fail("INSTALL_AUTHORIZATION_CONSUME_FAILED")
        }

        let argv = ["install", expectedPackageIdentity]
        // Hard forbid prune/rm/cache mutation via brew argv.
        guard !argv.contains(where: { $0.contains("cache") || $0 == "rm" || $0 == "prune" }) else {
            return fail("FORBIDDEN_ARGV", consumed: true)
        }

        let result = context.processRunner.run(BoundedProcessRequest(
            executableURL: brew,
            arguments: argv,
            timeoutSeconds: 600
        ))

        let prefixOut = context.processRunner.run(BoundedProcessRequest(
            executableURL: brew, arguments: ["--prefix"], timeoutSeconds: 8
        ))
        let prefix = prefixOut.stdout.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "/usr/local"
        let expectedHF = "\(prefix)/bin/hf"

        var version: String?
        var contract = HuggingFaceNativeInterfaceResolution(
            status: .unresolved,
            cliResolved: false,
            cliExecutableURL: nil,
            cliVersion: nil,
            supportsCacheLS: false,
            supportsCacheVerify: false,
            supportsCacheRM: false,
            supportsDryRun: false,
            supportsCacheDir: false,
            supportsYes: false,
            binaryFingerprint: nil,
            resolutionMethod: "POST_INSTALL",
            resolvedAt: Date(),
            failureReason: "NOT_PROBED",
            evidence: []
        )

        let installOK = result.outcome == .commandAccepted
            || (result.outcome == .nonzeroExit && context.fileManager.isExecutableFile(atPath: expectedHF))
        // brew may return nonzero if already installed — still accept if executable appears.

        if context.fileManager.isExecutableFile(atPath: expectedHF) {
            contract = HuggingFaceNativeInterfaceResolver.resolve(
                context: .init(
                    fileManager: context.fileManager,
                    processRunner: context.processRunner,
                    fixedCLICandidatePaths: [expectedHF],
                    now: Date()
                )
            )
            version = contract.cliVersion
        }

        let success = installOK && contract.cliResolved && contract.executionTransportAvailable
        return InstallResult(
            installationSucceeded: success,
            brewExecutableURL: brew.path,
            argv: argv,
            installedVersion: version,
            executableURL: contract.cliExecutableURL ?? (context.fileManager.isExecutableFile(atPath: expectedHF) ? expectedHF : nil),
            binaryFingerprint: contract.binaryFingerprint,
            contractProven: contract.executionTransportAvailable,
            supportsCacheLS: contract.supportsCacheLS,
            supportsCacheVerify: contract.supportsCacheVerify,
            supportsCacheRM: contract.supportsCacheRM,
            supportsDryRun: contract.supportsDryRun,
            supportsCacheDir: contract.supportsCacheDir,
            cacheModified: false,
            cacheRmExecuted: false,
            cleanupPermitCreated: false,
            authorizationConsumed: true,
            processOutcome: result.outcome.rawValue,
            exitCode: result.exitCode,
            durationMs: Int(Date().timeIntervalSince(started) * 1000),
            failureReason: success ? nil : (contract.failureReason ?? "INSTALL_OR_CONTRACT_FAILED:\(result.outcome.rawValue)"),
            completedAt: Date()
        )
    }
}
