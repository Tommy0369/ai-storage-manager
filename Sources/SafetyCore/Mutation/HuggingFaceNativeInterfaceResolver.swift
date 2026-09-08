import Foundation

/// Deterministic Hugging Face `hf` CLI discovery. No PATH shell. No home crawl.
public enum HuggingFaceNativeInterfaceResolver {
    public static let fixedCLICandidates: [String] = [
        "/opt/homebrew/bin/hf",
        "/usr/local/bin/hf",
        "\(NSHomeDirectory())/.local/bin/hf",
        "\(NSHomeDirectory())/.local/share/uv/tools/hf/bin/hf",
        "/usr/bin/hf",
        "\(NSHomeDirectory())/.pyenv/shims/hf",
    ]

    /// Additional candidates derived from known package-manager roots (still exact paths — no PATH scan).
    public static func packageManagerDerivedCandidates(
        brewPrefixes: [String] = ["/opt/homebrew", "/usr/local"],
        home: String = NSHomeDirectory()
    ) -> [String] {
        brewPrefixes.map { "\($0)/bin/hf" }
            + ["\(home)/.local/share/uv/tools/hf/bin/hf"]
    }

    public struct Context: Sendable {
        public var fileManager: FileManager
        public var processRunner: any BoundedProcessRunner
        public var processExecutablePaths: [String]
        public var fixedCLICandidatePaths: [String]?
        public var now: Date

        public init(
            fileManager: FileManager = .default,
            processRunner: any BoundedProcessRunner = FoundationProcessRunner(),
            processExecutablePaths: [String] = [],
            fixedCLICandidatePaths: [String]? = nil,
            now: Date = Date()
        ) {
            self.fileManager = fileManager
            self.processRunner = processRunner
            self.processExecutablePaths = processExecutablePaths
            self.fixedCLICandidatePaths = fixedCLICandidatePaths
            self.now = now
        }
    }

    public static func resolve(context: Context = Context()) -> HuggingFaceNativeInterfaceResolution {
        var evidence: [String] = []
        let candidates = (context.fixedCLICandidatePaths
            ?? (fixedCLICandidates + packageManagerDerivedCandidates()))
            + context.processExecutablePaths.filter {
                ($0 as NSString).lastPathComponent.lowercased() == "hf"
            }

        var exe: URL?
        var method = "NONE"
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            guard context.fileManager.isExecutableFile(atPath: url.path) else { continue }
            guard (url.lastPathComponent as NSString).lastPathComponent == "hf"
                || url.lastPathComponent.lowercased() == "hf" else { continue }
            // Reject lookalike directories / non-files
            var isDir: ObjCBool = false
            guard context.fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            exe = url
            method = context.processExecutablePaths.contains(path) ? "PROCESS_METADATA" : "FIXED_CANDIDATE"
            evidence.append("CLI_CANDIDATE=\(url.path)")
            break
        }

        guard let exe else {
            return HuggingFaceNativeInterfaceResolution(
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
                resolutionMethod: method,
                resolvedAt: context.now,
                failureReason: "HF_CLI_UNRESOLVED",
                evidence: evidence + ["NO_EXECUTABLE"]
            )
        }

        let versionOut = context.processRunner.run(BoundedProcessRequest(
            executableURL: exe, arguments: ["--version"], timeoutSeconds: 8
        ))
        let version = parseVersion(versionOut.stdout + versionOut.stderr)
        evidence.append("VERSION_PROBE=\(versionOut.outcome.rawValue)")

        let help = context.processRunner.run(BoundedProcessRequest(
            executableURL: exe, arguments: ["--help"], timeoutSeconds: 8
        ))
        let cacheHelp = context.processRunner.run(BoundedProcessRequest(
            executableURL: exe, arguments: ["cache", "--help"], timeoutSeconds: 8
        ))
        let rmHelp = context.processRunner.run(BoundedProcessRequest(
            executableURL: exe, arguments: ["cache", "rm", "--help"], timeoutSeconds: 8
        ))
        let lsHelp = context.processRunner.run(BoundedProcessRequest(
            executableURL: exe, arguments: ["cache", "ls", "--help"], timeoutSeconds: 8
        ))
        let verifyHelp = context.processRunner.run(BoundedProcessRequest(
            executableURL: exe, arguments: ["cache", "verify", "--help"], timeoutSeconds: 8
        ))

        let cacheText = (cacheHelp.stdout + cacheHelp.stderr + rmHelp.stdout + rmHelp.stderr).lowercased()
        let lsOK = (lsHelp.outcome == .commandAccepted || lsHelp.outcome == .nonzeroExit)
            && !(lsHelp.stdout + lsHelp.stderr).lowercased().contains("unknown")
            || cacheText.contains("cache ls") || cacheText.contains("ls ")
        let verifyOK = (verifyHelp.outcome == .commandAccepted || verifyHelp.outcome == .nonzeroExit)
            && ((verifyHelp.stdout + verifyHelp.stderr).lowercased().contains("verify")
                || cacheText.contains("verify"))
        let rmOK = (rmHelp.outcome == .commandAccepted || rmHelp.outcome == .nonzeroExit)
            && (cacheText.contains("rm") || (rmHelp.stdout + rmHelp.stderr).lowercased().contains("rm"))
        let dryOK = cacheText.contains("dry-run") || cacheText.contains("dry_run")
            || (rmHelp.stdout + rmHelp.stderr).lowercased().contains("dry-run")
        let cacheDirOK = cacheText.contains("cache-dir") || cacheText.contains("cache_dir")
            || (rmHelp.stdout + rmHelp.stderr).lowercased().contains("cache-dir")
        let yesOK = cacheText.contains("--yes") || (rmHelp.stdout + rmHelp.stderr).lowercased().contains("--yes")

        let fp = binaryFingerprint(exe, fm: context.fileManager)
        let contractOK = rmOK && dryOK && cacheDirOK
        let status: HuggingFaceNativeInterfaceStatus = contractOK ? .resolvedCLI : .contractIncomplete

        return HuggingFaceNativeInterfaceResolution(
            status: status,
            cliResolved: true,
            cliExecutableURL: exe.path,
            cliVersion: version,
            supportsCacheLS: lsOK || cacheText.contains("ls"),
            supportsCacheVerify: verifyOK,
            supportsCacheRM: rmOK,
            supportsDryRun: dryOK,
            supportsCacheDir: cacheDirOK,
            supportsYes: yesOK,
            binaryFingerprint: fp,
            resolutionMethod: method,
            resolvedAt: context.now,
            failureReason: contractOK ? nil : "HF_CLI_CONTRACT_INCOMPLETE",
            evidence: evidence + [
                "HELP=\(help.outcome.rawValue)",
                "CACHE_HELP=\(cacheHelp.outcome.rawValue)",
                "RM_HELP=\(rmHelp.outcome.rawValue)",
            ]
        )
    }

    private static func parseVersion(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).map(String.init).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return line.map { String($0.prefix(120)) }
    }

    private static func binaryFingerprint(_ url: URL, fm: FileManager) -> String? {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        return "path=\(url.path);size=\(size.int64Value);mtime=\(Int(mtime.timeIntervalSince1970))"
    }
}
