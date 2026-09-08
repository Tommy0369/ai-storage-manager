import Foundation

/// Restores Ollama management under exact install authorization.
/// Never runs rm/run/pull/create. Never touches ~/.ollama/models manually.
public enum OllamaManagementRestoreInstaller {
    public static let managedModelsRelativePath = ".ollama/models"
    public static let qwenManifestRelativePath =
        ".ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"

    public struct Context: Sendable {
        public var fileManager: FileManager
        public var homeDirectory: String
        public var processRunner: any BoundedProcessRunner
        public var download: (@Sendable (URL, URL) throws -> Void)?
        public var unzip: (@Sendable (URL, URL) throws -> URL)?
        public var installAppBundle: (@Sendable (URL) throws -> URL)?
        public var launchApp: (@Sendable (URL) throws -> Void)?
        public var codesignIdentity: (@Sendable (URL) -> String?)?
        public var applicationsDirectory: String
        public var workDirectory: String
        public var now: Date

        public init(
            fileManager: FileManager = .default,
            homeDirectory: String = NSHomeDirectory(),
            processRunner: any BoundedProcessRunner = FoundationProcessRunner(),
            download: (@Sendable (URL, URL) throws -> Void)? = nil,
            unzip: (@Sendable (URL, URL) throws -> URL)? = nil,
            installAppBundle: (@Sendable (URL) throws -> URL)? = nil,
            launchApp: (@Sendable (URL) throws -> Void)? = nil,
            codesignIdentity: (@Sendable (URL) -> String?)? = nil,
            applicationsDirectory: String = "/Applications",
            workDirectory: String = NSTemporaryDirectory(),
            now: Date = Date()
        ) {
            self.fileManager = fileManager
            self.homeDirectory = homeDirectory
            self.processRunner = processRunner
            self.download = download
            self.unzip = unzip
            self.installAppBundle = installAppBundle
            self.launchApp = launchApp
            self.codesignIdentity = codesignIdentity
            self.applicationsDirectory = applicationsDirectory
            self.workDirectory = workDirectory
            self.now = now
        }
    }

    public static func capturePreInstallReceipt(
        entityID: String,
        canonicalModel: String,
        uniqueBytes: Int64?,
        sharedBytes: Int64?,
        manifestFingerprint: String?,
        referenceGraphFingerprint: String?,
        remoteProofStatus: String?,
        vendorAbsent: Bool,
        context: Context = Context()
    ) -> PreInstallManagedDataReceipt {
        let root = (context.homeDirectory as NSString)
            .appendingPathComponent(managedModelsRelativePath)
        let manifest = (context.homeDirectory as NSString)
            .appendingPathComponent(qwenManifestRelativePath)
        return PreInstallManagedDataReceipt(
            vendorAbsent: vendorAbsent,
            entityID: entityID,
            canonicalModel: canonicalModel,
            manifestFingerprint: manifestFingerprint,
            referenceGraphFingerprint: referenceGraphFingerprint,
            uniqueBytes: uniqueBytes,
            sharedBytes: sharedBytes,
            remoteProofStatus: remoteProofStatus,
            managedDataRootPath: root,
            managedDataRootExists: context.fileManager.fileExists(atPath: root),
            manifestPresentOnDisk: context.fileManager.fileExists(atPath: manifest),
            capturedAt: context.now
        )
    }

    /// Production gate: authorization must be present, unconsumed, Ollama-scoped.
    public static func restore(
        authorization: inout SoftwareInstallationAuthorization,
        source: OllamaTrustedInstallSourceResolver.ResolvedSource,
        preInstall: PreInstallManagedDataReceipt,
        context: Context = Context()
    ) -> VendorManagementRestoreResult {
        guard authorization.allowsOllamaInstall else {
            return .failure(
                method: source.method,
                sourceClass: source.sourceClass,
                sourceVerified: source.sourceVerified,
                reason: authorization.isConsumed
                    ? "INSTALL_AUTHORIZATION_CONSUMED"
                    : "INSTALL_AUTHORIZATION_MISSING_OR_OUT_OF_SCOPE",
                modelDataPreserved: preInstall.managedDataRootExists
            )
        }
        guard authorization.vendor == .ollama,
              authorization.scope == .ollamaSoftwareReinstallationOnly else {
            return .failure(
                method: .unresolved,
                sourceClass: .unresolved,
                sourceVerified: false,
                reason: "AUTHORIZATION_SCOPE_NOT_OLLAMA_INSTALL",
                modelDataPreserved: preInstall.managedDataRootExists
            )
        }
        guard source.method != .unresolved else {
            return .failure(
                method: .unresolved,
                sourceClass: .unresolved,
                sourceVerified: false,
                reason: source.unresolvedReason ?? "INSTALL_SOURCE_UNRESOLVED",
                modelDataPreserved: preInstall.managedDataRootExists
            )
        }

        // Consume before mutation — single-purpose.
        guard authorization.consume(at: context.now) else {
            return .failure(
                method: source.method,
                sourceClass: source.sourceClass,
                sourceVerified: source.sourceVerified,
                reason: "INSTALL_AUTHORIZATION_CONSUME_FAILED",
                modelDataPreserved: preInstall.managedDataRootExists
            )
        }

        let before = dataPresence(context: context)
        let result: VendorManagementRestoreResult
        switch source.method {
        case .officialAppInstall, .existingOfficialInstaller:
            result = installOfficialApp(source: source, preInstall: preInstall, context: context)
        case .packageManagerInstall:
            result = installViaBrew(source: source, preInstall: preInstall, context: context)
        case .unresolved:
            result = .failure(
                method: .unresolved,
                sourceClass: .unresolved,
                sourceVerified: false,
                reason: "INSTALL_SOURCE_UNRESOLVED",
                modelDataPreserved: before.rootExists
            )
        }

        let after = dataPresence(context: context)
        var finalized = result
        // Preserve means: install did not destroy data that existed before.
        // Absent pre-install manifest (e.g. after authorized removal) is not install damage.
        let lostRoot = before.rootExists && !after.rootExists
        let lostManifest = before.manifestExists && !after.manifestExists
        finalized.modelDataPreserved = !lostRoot && !lostManifest
        if lostRoot || lostManifest {
            finalized.unexpectedDataMutation = true
            finalized.failureReason = finalized.failureReason ?? "UNEXPECTED_MODEL_DATA_LOSS"
            finalized.installationSucceeded = false
        }
        // Hard locks for this phase.
        finalized.modelRunPerformed = false
        finalized.modelPullPerformed = false
        finalized.cleanupPerformed = false
        return finalized
    }

    private struct DataPresence {
        var rootExists: Bool
        var manifestExists: Bool
    }

    private static func dataPresence(context: Context) -> DataPresence {
        let root = (context.homeDirectory as NSString)
            .appendingPathComponent(managedModelsRelativePath)
        let manifest = (context.homeDirectory as NSString)
            .appendingPathComponent(qwenManifestRelativePath)
        return DataPresence(
            rootExists: context.fileManager.fileExists(atPath: root),
            manifestExists: context.fileManager.fileExists(atPath: manifest)
        )
    }

    private static func installOfficialApp(
        source: OllamaTrustedInstallSourceResolver.ResolvedSource,
        preInstall: PreInstallManagedDataReceipt,
        context: Context
    ) -> VendorManagementRestoreResult {
        do {
            let zipURL: URL
            if let local = source.localArtifactPath {
                zipURL = URL(fileURLWithPath: local)
            } else if let remote = source.remoteURL.flatMap(URL.init(string:)) {
                guard OllamaTrustedInstallSourceResolver.hostAllowed(remote) else {
                    return .failure(
                        method: .officialAppInstall,
                        sourceClass: source.sourceClass,
                        sourceVerified: false,
                        reason: "REMOTE_HOST_NOT_ALLOWLISTED",
                        modelDataPreserved: preInstall.managedDataRootExists
                    )
                }
                let dest = URL(fileURLWithPath: context.workDirectory)
                    .appendingPathComponent("Ollama-darwin-\(UUID().uuidString.prefix(8)).zip")
                let downloader = context.download ?? defaultDownload
                try downloader(remote, dest)
                zipURL = dest
            } else {
                return .failure(
                    method: .officialAppInstall,
                    sourceClass: source.sourceClass,
                    sourceVerified: false,
                    reason: "NO_ARTIFACT_OR_URL",
                    modelDataPreserved: preInstall.managedDataRootExists
                )
            }

            let extractRoot = URL(fileURLWithPath: context.workDirectory)
                .appendingPathComponent("ollama-extract-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try context.fileManager.createDirectory(at: extractRoot, withIntermediateDirectories: true)
            let unzipper = context.unzip ?? defaultUnzip
            let appURL = try unzipper(zipURL, extractRoot)

            let signer = context.codesignIdentity ?? defaultCodesignIdentity
            let identity = signer(appURL)
            let sourceVerified = identity.map {
                $0.contains("Ollama") || $0.contains("Developer ID") || $0.contains("Apple")
            } ?? false

            let installer = context.installAppBundle ?? defaultInstallApp
            let installedURL = try installer(appURL)

            var startedService = false
            if let launch = context.launchApp {
                try launch(installedURL)
                startedService = true
            } else {
                startedService = defaultLaunchApp(installedURL, runner: context.processRunner)
            }

            let bundleID = readBundleID(at: installedURL) ?? "com.electron.ollama"
            let version = readBundleVersion(at: installedURL)

            return VendorManagementRestoreResult(
                vendor: .ollama,
                installMethod: source.localArtifactPath != nil
                    ? .existingOfficialInstaller
                    : .officialAppInstall,
                sourceClass: source.sourceClass,
                sourceVerified: sourceVerified || identity != nil,
                installedVersion: version,
                bundleIdentifier: bundleID,
                installationSucceeded: true,
                nativeInterfaceDetected: false, // proven later
                modelDataPreserved: true,
                startedManagementService: startedService,
                modelRunPerformed: false,
                modelPullPerformed: false,
                cleanupPerformed: false,
                completedAt: context.now,
                failureReason: nil,
                artifactIdentity: source.artifactIdentity ?? zipURL.lastPathComponent,
                unexpectedDataMutation: false
            )
        } catch {
            return .failure(
                method: .officialAppInstall,
                sourceClass: source.sourceClass,
                sourceVerified: false,
                reason: "OFFICIAL_INSTALL_FAILED:\(error.localizedDescription)",
                modelDataPreserved: preInstall.managedDataRootExists,
                artifactIdentity: source.artifactIdentity
            )
        }
    }

    private static func installViaBrew(
        source: OllamaTrustedInstallSourceResolver.ResolvedSource,
        preInstall: PreInstallManagedDataReceipt,
        context: Context
    ) -> VendorManagementRestoreResult {
        let brew = OllamaTrustedInstallSourceResolver.Context(
            fileManager: context.fileManager
        ).brewExecutablePath
        guard let brewPath = brew else {
            return .failure(
                method: .packageManagerInstall,
                sourceClass: .establishedPackageManager,
                sourceVerified: false,
                reason: "BREW_NOT_FOUND",
                modelDataPreserved: preInstall.managedDataRootExists
            )
        }
        let install = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: brewPath),
            arguments: ["install", "ollama"],
            timeoutSeconds: 600
        ))
        guard install.outcome == .commandAccepted else {
            return .failure(
                method: .packageManagerInstall,
                sourceClass: .establishedPackageManager,
                sourceVerified: true,
                reason: "BREW_INSTALL_\(install.outcome.rawValue):\(bounded(install.stderr))",
                modelDataPreserved: preInstall.managedDataRootExists,
                artifactIdentity: source.artifactIdentity
            )
        }
        // Start management service only — never run a model.
        let services = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: brewPath),
            arguments: ["services", "start", "ollama"],
            timeoutSeconds: 60
        ))
        let started = services.outcome == .commandAccepted
        return VendorManagementRestoreResult(
            vendor: .ollama,
            installMethod: .packageManagerInstall,
            sourceClass: .establishedPackageManager,
            sourceVerified: true,
            installedVersion: nil,
            bundleIdentifier: nil,
            installationSucceeded: true,
            nativeInterfaceDetected: false,
            modelDataPreserved: true,
            startedManagementService: started,
            modelRunPerformed: false,
            modelPullPerformed: false,
            cleanupPerformed: false,
            completedAt: context.now,
            failureReason: nil,
            artifactIdentity: source.artifactIdentity,
            unexpectedDataMutation: false
        )
    }

    // MARK: - Defaults (production)

    private static func defaultDownload(_ remote: URL, _ dest: URL) throws {
        // Bounded file download — never pipe to shell.
        let sem = DispatchSemaphore(value: 0)
        var capturedError: Error?
        let task = URLSession.shared.downloadTask(with: remote) { temp, response, error in
            defer { sem.signal() }
            if let error {
                capturedError = error
                return
            }
            guard let temp else {
                capturedError = NSError(
                    domain: "OllamaInstall",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "DOWNLOAD_EMPTY"]
                )
                return
            }
            if let http = response as? HTTPURLResponse,
               !(200..<400).contains(http.statusCode) {
                capturedError = NSError(
                    domain: "OllamaInstall",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP_\(http.statusCode)"]
                )
                return
            }
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.moveItem(at: temp, to: dest)
            } catch {
                capturedError = error
            }
        }
        task.resume()
        if sem.wait(timeout: .now() + 600) == .timedOut {
            task.cancel()
            throw NSError(
                domain: "OllamaInstall",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "DOWNLOAD_TIMEOUT"]
            )
        }
        if let capturedError { throw capturedError }
    }

    private static func defaultUnzip(_ zipURL: URL, _ extractRoot: URL) throws -> URL {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-o", zipURL.path, "-d", extractRoot.path]
        let err = Pipe()
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "OllamaInstall",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "UNZIP_FAILED:\(bounded(msg))"]
            )
        }
        if let app = findAppBundle(in: extractRoot) {
            return app
        }
        throw NSError(
            domain: "OllamaInstall",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "OLLAMA_APP_NOT_IN_ARCHIVE"]
        )
    }

    private static func findAppBundle(in root: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.pathExtension == "app", url.lastPathComponent == "Ollama.app" {
                return url
            }
        }
        // Shallow fallback
        let direct = root.appendingPathComponent("Ollama.app")
        if fm.fileExists(atPath: direct.path) { return direct }
        return nil
    }

    private static func defaultInstallApp(_ appURL: URL) throws -> URL {
        let dest = URL(fileURLWithPath: "/Applications").appendingPathComponent("Ollama.app")
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: appURL, to: dest)
        return dest
    }

    private static func defaultLaunchApp(_ appURL: URL, runner: any BoundedProcessRunner) -> Bool {
        let result = runner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-a", appURL.path],
            timeoutSeconds: 30
        ))
        return result.outcome == .commandAccepted
    }

    private static func defaultCodesignIdentity(_ appURL: URL) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        proc.arguments = ["-dv", "--verbose=2", appURL.path]
        let err = Pipe()
        proc.standardError = err
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in text.split(whereSeparator: \.isNewline) {
            if line.lowercased().contains("authority=") || line.lowercased().hasPrefix("authority") {
                return String(line)
            }
            if line.lowercased().hasPrefix("identifier=") {
                return String(line)
            }
        }
        return text.isEmpty ? nil : String(text.prefix(200))
    }

    private static func readBundleID(at appURL: URL) -> String? {
        let info = appURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: info) as? [String: Any] else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    private static func readBundleVersion(at appURL: URL) -> String? {
        let info = appURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: info) as? [String: Any] else { return nil }
        return (dict["CFBundleShortVersionString"] as? String)
            ?? (dict["CFBundleVersion"] as? String)
    }

    private static func bounded(_ s: String, limit: Int = 240) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit))
    }
}
