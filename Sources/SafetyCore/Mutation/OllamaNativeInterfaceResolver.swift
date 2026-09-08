import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Deterministic Ollama native interface discovery. No PATH shell lookup. No disk crawl.
public enum OllamaNativeInterfaceResolver {
    public static let knownBundleIDs = [
        "com.electron.ollama",
        "com.ollama.app",
        "ai.ollama.ollama",
        "com.jmorganca.ollama",
    ]

    public static let fixedCLICandidates: [String] = [
        "/usr/local/bin/ollama",
        "/opt/homebrew/bin/ollama",
        "\(NSHomeDirectory())/.local/bin/ollama",
        "/usr/bin/ollama",
    ]

    public static let localAPIBase = "http://127.0.0.1:11434"

    /// Injectables for tests.
    public struct Context: Sendable {
        public var fileManager: FileManager
        public var processRunner: any BoundedProcessRunner
        public var processExecutablePaths: [String]
        public var modelDataPresent: Bool
        public var httpGET: (@Sendable (URL) -> (status: Int, body: Data)?)?
        public var bundleLookup: (@Sendable ([String]) -> (id: String, url: URL, version: String?)?)?
        public var now: Date
        /// When non-nil, replaces `fixedCLICandidates` (tests pass `[]` to isolate from host install).
        public var fixedCLICandidatePaths: [String]?

        public init(
            fileManager: FileManager = .default,
            processRunner: any BoundedProcessRunner = FoundationProcessRunner(),
            processExecutablePaths: [String] = [],
            modelDataPresent: Bool = false,
            httpGET: (@Sendable (URL) -> (status: Int, body: Data)?)? = nil,
            bundleLookup: (@Sendable ([String]) -> (id: String, url: URL, version: String?)?)? = nil,
            now: Date = Date(),
            fixedCLICandidatePaths: [String]? = nil
        ) {
            self.fileManager = fileManager
            self.processRunner = processRunner
            self.processExecutablePaths = processExecutablePaths
            self.modelDataPresent = modelDataPresent
            self.httpGET = httpGET
            self.bundleLookup = bundleLookup
            self.now = now
            self.fixedCLICandidatePaths = fixedCLICandidatePaths
        }
    }

    public static func resolve(context: Context = Context()) -> OllamaNativeInterfaceResolution {
        let started = Date()
        var evidence: [String] = []
        var guiRejected = false

        // 1) Native app discovery (NSWorkspace / injected)
        let bundle = context.bundleLookup.map { $0(knownBundleIDs) } ?? lookupBundleViaWorkspace()
        let appFound = bundle != nil
        if let bundle {
            evidence.append("BUNDLE_RESOLVED=\(bundle.id)")
        } else {
            evidence.append("BUNDLE_NOT_FOUND")
        }

        // 2) Embedded CLI candidates under resolved bundle (bounded paths only)
        var cliURL: URL?
        var locationClass: String?
        var method = "NONE"
        if let bundle {
            let embedded = [
                bundle.url.appendingPathComponent("Contents/Resources/ollama"),
                bundle.url.appendingPathComponent("Contents/MacOS/ollama"),
            ]
            for u in embedded {
                // Case-insensitive APFS: Contents/MacOS/ollama may resolve to GUI "Ollama".
                if isExactBasenameExecutable(u, expectedBasename: "ollama", fm: context.fileManager) {
                    cliURL = u
                    locationClass = "APP_BUNDLE_EMBEDDED"
                    method = "BUNDLE_EMBEDDED_CLI"
                    evidence.append("EMBEDDED_CLI=\(u.lastPathComponent)")
                    break
                }
            }
            let guiExe = bundle.url.appendingPathComponent("Contents/MacOS/Ollama")
            if isExactBasenameExecutable(guiExe, expectedBasename: "Ollama", fm: context.fileManager)
                || (cliURL == nil && isExecutableFile(guiExe.path, fm: context.fileManager)
                    && actualBasename(guiExe, fm: context.fileManager)?.lowercased() == "ollama") {
                // If the only MacOS binary is the GUI app executable, reject as CLI.
                if cliURL != nil,
                   actualBasename(cliURL!, fm: context.fileManager) == "Ollama"
                    || (cliURL!.path.lowercased().contains("/contents/macos/")
                        && actualBasename(cliURL!, fm: context.fileManager) != "ollama") {
                    guiRejected = true
                    evidence.append("GUI_EXECUTABLE_REJECTED_AS_CLI")
                    cliURL = nil
                    locationClass = nil
                    method = "GUI_REJECTED"
                } else if cliURL == nil {
                    guiRejected = true
                    evidence.append("GUI_EXECUTABLE_REJECTED_AS_CLI")
                }
            }
        }

        // 3) Fixed vendor CLI locations
        if cliURL == nil {
            for path in context.fixedCLICandidatePaths ?? fixedCLICandidates {
                if isExecutableFile(path, fm: context.fileManager) {
                    cliURL = URL(fileURLWithPath: path)
                    locationClass = locationClassForFixed(path)
                    method = "FIXED_VENDOR_PATH"
                    evidence.append("FIXED_CLI=\(locationClass ?? path)")
                    break
                }
            }
        }

        // 4) Running process executable — candidate only; still needs CLI contract
        if cliURL == nil {
            for path in context.processExecutablePaths {
                let lower = path.lowercased()
                guard lower.contains("ollama") else { continue }
                // Reject GUI app main executable masquerading as CLI without contract proof.
                if lower.hasSuffix("/ollama.app/contents/macos/ollama") {
                    // Could be CLI named Ollama — still require contract.
                }
                if isExecutableFile(path, fm: context.fileManager) {
                    let candidate = URL(fileURLWithPath: path)
                    let contract = proveCLIContract(candidate, runner: context.processRunner)
                    if contract.supportsPS || contract.supportsRM {
                        cliURL = candidate
                        locationClass = "RUNNING_PROCESS_EXECUTABLE"
                        method = "PROCESS_EXECUTABLE"
                        evidence.append("PROCESS_EXE_ACCEPTED")
                        break
                    } else if path.lowercased().contains(".app/contents/macos/") {
                        guiRejected = true
                        evidence.append("PROCESS_GUI_EXE_REJECTED")
                    }
                }
            }
        }

        var supportsPS = false
        var supportsRM = false
        var cliVersion: String?
        var fingerprint: String?
        if let candidate = cliURL {
            let contract = proveCLIContract(candidate, runner: context.processRunner)
            supportsPS = contract.supportsPS
            supportsRM = contract.supportsRM
            cliVersion = contract.version
            fingerprint = binaryFingerprint(candidate, fm: context.fileManager)
            if !supportsPS && !supportsRM {
                evidence.append("CLI_CONTRACT_FAILED")
                cliURL = nil
                locationClass = nil
                method = "CONTRACT_REJECTED"
            } else {
                evidence.append("CLI_CONTRACT_OK")
            }
        }

        // 5) Local API read-only identity
        let api = probeLocalAPI(context: context)
        if api.reachable {
            evidence.append(api.identityVerified ? "LOCAL_API_IDENTITY_VERIFIED" : "LOCAL_API_REACHABLE_UNVERIFIED")
        } else {
            evidence.append("LOCAL_API_UNREACHABLE")
        }

        let modelData = context.modelDataPresent || defaultModelDataPresent(fm: context.fileManager)
        if modelData { evidence.append("MODEL_DATA_PRESENT") }

        let (kind, status, reality) = classify(
            cliResolved: cliURL != nil && (supportsPS || supportsRM),
            supportsRM: supportsRM,
            appFound: appFound,
            guiRejected: guiRejected,
            apiReachable: api.reachable && api.identityVerified,
            modelData: modelData
        )

        return OllamaNativeInterfaceResolution(
            interfaceKind: kind,
            status: status,
            installReality: reality,
            ollamaAppFound: appFound,
            bundleIdentifier: bundle?.id,
            bundleVersion: bundle?.version,
            bundleLocationClass: bundle.map { locationClassForBundle($0.url) },
            cliResolved: cliURL != nil && (supportsPS || supportsRM),
            cliExecutableURL: cliURL?.path,
            cliExecutableLocationClass: locationClass,
            cliVersion: cliVersion,
            supportsPS: supportsPS,
            supportsRM: supportsRM,
            guiExecutableRejectedAsCLI: guiRejected,
            localAPIReachable: api.reachable,
            localAPIIdentityVerified: api.identityVerified,
            localAPIVersion: api.version,
            resolutionMethod: method,
            resolutionEvidence: evidence,
            resolutionDurationMs: Int(Date().timeIntervalSince(started) * 1000),
            binaryFingerprint: fingerprint,
            observedAt: context.now
        )
    }

    // MARK: - CLI contract (read-only)

    public struct CLIContract: Sendable {
        public var supportsPS: Bool
        public var supportsRM: Bool
        public var version: String?
    }

    public static func proveCLIContract(
        _ executable: URL,
        runner: any BoundedProcessRunner
    ) -> CLIContract {
        var version: String?
        var helpText = ""

        let ver = runner.run(BoundedProcessRequest(
            executableURL: executable,
            arguments: ["--version"],
            timeoutSeconds: 5
        ))
        if ver.outcome == .commandAccepted || ver.outcome == .nonzeroExit {
            let combined = (ver.stdout + "\n" + ver.stderr).lowercased()
            if combined.contains("ollama") || combined.contains("version") {
                version = String((ver.stdout.isEmpty ? ver.stderr : ver.stdout).prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let help = runner.run(BoundedProcessRequest(
            executableURL: executable,
            arguments: ["help"],
            timeoutSeconds: 5
        ))
        if help.outcome == .commandAccepted || help.outcome == .nonzeroExit {
            helpText = (help.stdout + "\n" + help.stderr).lowercased()
        }
        // Some builds use bare `ollama` with usage on stderr
        if helpText.isEmpty {
            let bare = runner.run(BoundedProcessRequest(
                executableURL: executable,
                arguments: [],
                timeoutSeconds: 5
            ))
            helpText = (bare.stdout + "\n" + bare.stderr).lowercased()
        }

        let looksLikeOllama = (version?.lowercased().contains("ollama") == true)
            || helpText.contains("ollama")
            || helpText.contains("large language model")
        guard looksLikeOllama || version != nil || !helpText.isEmpty else {
            return CLIContract(supportsPS: false, supportsRM: false, version: nil)
        }

        let supportsPS = helpText.contains(" ps") || helpText.contains("\nps")
            || helpText.contains("list running") || helpText.hasPrefix("ps")
            || helpText.contains("usage:") && helpText.contains("ps")
        // Prove rm support from help only — never execute rm.
        let supportsRM = helpText.contains(" rm") || helpText.contains("\nrm")
            || helpText.contains("remove a model") || helpText.contains("delete a model")
            || (helpText.contains("commands") && helpText.contains("rm"))

        // Optional bounded ps probe only when help already suggests CLI family.
        var psOK = supportsPS
        if !psOK, version != nil, looksLikeOllama, helpText.contains("pull") || helpText.contains("run") || helpText.contains("serve") {
            let ps = runner.run(BoundedProcessRequest(
                executableURL: executable,
                arguments: ["ps"],
                timeoutSeconds: 5
            ))
            if ps.outcome == .commandAccepted {
                let out = ps.stdout.lowercased()
                // Require table-like header — never accept arbitrary one-line GUI stdout.
                if out.contains("name") && (out.contains("id") || out.contains("size") || out.contains("processor")) {
                    psOK = true
                }
            }
        }

        // RM must appear in help/registry text. Do not infer from version alone.
        let rmOK = supportsRM
        return CLIContract(supportsPS: psOK, supportsRM: rmOK, version: version)
    }

    // MARK: - Local API

    private struct APIProbe {
        var reachable: Bool
        var identityVerified: Bool
        var version: String?
    }

    private static func probeLocalAPI(context: Context) -> APIProbe {
        let get = context.httpGET ?? defaultHTTPGET
        guard let versionURL = URL(string: "\(localAPIBase)/api/version") else {
            return APIProbe(reachable: false, identityVerified: false, version: nil)
        }
        guard let resp = get(versionURL), resp.status == 200 else {
            return APIProbe(reachable: false, identityVerified: false, version: nil)
        }
        var version: String?
        var identity = false
        if let obj = try? JSONSerialization.jsonObject(with: resp.body) as? [String: Any] {
            if let v = obj["version"] as? String {
                version = v
                identity = true
            }
        }
        // Spoof guard: require version key.
        return APIProbe(reachable: true, identityVerified: identity, version: version)
    }

    private static func defaultHTTPGET(_ url: URL) -> (status: Int, body: Data)? {
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0)
        var result: (Int, Data)?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { sem.signal() }
            guard let http = response as? HTTPURLResponse, let data else { return }
            result = (http.statusCode, data)
        }.resume()
        _ = sem.wait(timeout: .now() + 2.5)
        return result.map { ($0.0, $0.1) }
    }

    // MARK: - Runtime proof

    public static func proveExactRuntime(
        canonicalModel: String,
        resolution: OllamaNativeInterfaceResolution,
        context: Context = Context(),
        freshnessSeconds: TimeInterval = 120
    ) -> OllamaExactRuntimeProof {
        let now = context.now
        let freshUntil = now.addingTimeInterval(freshnessSeconds)
        let serviceRunning = resolution.localAPIReachable
            || context.processExecutablePaths.contains { $0.lowercased().contains("ollama") }

        // Prefer CLI ps when available
        if resolution.supportsPS, let path = resolution.cliExecutableURL {
            let exe = URL(fileURLWithPath: path)
            let snap = OllamaRunningModelsObserver.capture(
                runner: context.processRunner,
                executableURL: exe
            )
            return makeRuntimeProof(
                canonical: canonicalModel,
                source: "CLI_PS",
                snap: snap,
                serviceRunning: serviceRunning,
                now: now,
                freshUntil: freshUntil
            )
        }

        // Local API /api/ps when identity verified
        if resolution.localAPIReachable, resolution.localAPIIdentityVerified {
            let get = context.httpGET ?? defaultHTTPGET
            if let url = URL(string: "\(localAPIBase)/api/ps"),
               let resp = get(url), resp.status == 200 {
                let names = parseAPIRunningModels(resp.body)
                let snap = OllamaRunningModelsSnapshot(
                    completeness: .complete,
                    runningModelIdentities: names,
                    observedAt: now,
                    rawStdoutSummary: String(data: resp.body.prefix(400), encoding: .utf8) ?? ""
                )
                return makeRuntimeProof(
                    canonical: canonicalModel,
                    source: "LOCAL_API_PS",
                    snap: snap,
                    serviceRunning: true,
                    now: now,
                    freshUntil: freshUntil
                )
            }
            return OllamaExactRuntimeProof(
                targetEntityID: "",
                targetModel: canonicalModel,
                observationSource: "LOCAL_API_PS",
                snapshotCompleteness: .partial,
                runningModelCount: 0,
                runningModelIdentities: [],
                targetStatus: .unknown,
                targetConfidence: .unknown,
                observedAt: now,
                freshUntil: freshUntil,
                failureReason: "LOCAL_API_PS_FAILED",
                serviceRunning: true,
                serviceRunningUsedAsTargetProof: false
            )
        }

        return OllamaExactRuntimeProof(
            targetEntityID: "",
            targetModel: canonicalModel,
            observationSource: "NONE",
            snapshotCompleteness: .unknown,
            runningModelCount: 0,
            runningModelIdentities: [],
            targetStatus: .unknown,
            targetConfidence: .unknown,
            observedAt: now,
            freshUntil: freshUntil,
            failureReason: serviceRunning
                ? "SERVICE_ONLY_NO_AUTHORITATIVE_SNAPSHOT"
                : (resolution.cliResolved ? "RUNTIME_PROBE_UNAVAILABLE" : "OLLAMA_EXECUTABLE_UNRESOLVED"),
            serviceRunning: serviceRunning,
            serviceRunningUsedAsTargetProof: false
        )
    }

    private static func makeRuntimeProof(
        canonical: String,
        source: String,
        snap: OllamaRunningModelsSnapshot,
        serviceRunning: Bool,
        now: Date,
        freshUntil: Date
    ) -> OllamaExactRuntimeProof {
        guard snap.completeness == .complete else {
            return OllamaExactRuntimeProof(
                targetEntityID: "",
                targetModel: canonical,
                observationSource: source,
                snapshotCompleteness: snap.completeness,
                runningModelCount: snap.runningModelIdentities.count,
                runningModelIdentities: Array(snap.runningModelIdentities).sorted(),
                targetStatus: .unknown,
                targetConfidence: .unknown,
                observedAt: now,
                freshUntil: freshUntil,
                failureReason: snap.failureReason ?? "SNAPSHOT_INCOMPLETE",
                serviceRunning: serviceRunning,
                serviceRunningUsedAsTargetProof: false
            )
        }
        let present = snap.runningModelIdentities.contains {
            OllamaModelIdentityNormalization.matches($0, canonical: canonical)
        }
        return OllamaExactRuntimeProof(
            targetEntityID: "",
            targetModel: canonical,
            observationSource: source,
            snapshotCompleteness: .complete,
            runningModelCount: snap.runningModelIdentities.count,
            runningModelIdentities: Array(snap.runningModelIdentities).sorted(),
            targetStatus: present ? .active : .inactive,
            targetConfidence: .verified,
            observedAt: now,
            freshUntil: freshUntil,
            failureReason: nil,
            serviceRunning: serviceRunning,
            serviceRunningUsedAsTargetProof: false
        )
    }

    public static func parseAPIRunningModels(_ data: Data) -> Set<String> {
        var out: Set<String> = []
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return out }
        let models = (obj["models"] as? [[String: Any]]) ?? []
        for m in models {
            if let name = m["name"] as? String, !name.isEmpty {
                out.insert(name)
            } else if let model = m["model"] as? String, !model.isEmpty {
                out.insert(model)
            }
        }
        return out
    }

    // MARK: - Helpers

    private static func classify(
        cliResolved: Bool,
        supportsRM: Bool,
        appFound: Bool,
        guiRejected: Bool,
        apiReachable: Bool,
        modelData: Bool
    ) -> (OllamaNativeInterfaceKind, OllamaNativeInterfaceStatus, OllamaInstallReality) {
        if cliResolved, supportsRM {
            let reality: OllamaInstallReality = appFound ? .ollamaAppWithEmbeddedCLI : .cliInstalledNonstandardLocation
            return (.cli, .resolvedCLI, reality)
        }
        if apiReachable, !cliResolved {
            return (.localAPI, .resolvedLocalAPIOnly, .localAPIAvailableWithoutCLI)
        }
        if appFound, guiRejected || !cliResolved {
            return (.guiOnly, .guiOnly, .guiAppOnly)
        }
        if modelData, !cliResolved, !apiReachable, !appFound {
            return (.none, .unresolved, .staleModelDataWithNoInstall)
        }
        if !cliResolved, !apiReachable, !appFound {
            return (.none, .unresolved, .cliNotInstalled)
        }
        return (.unknown, .unknown, .other)
    }

    private static func isExecutableFile(_ path: String, fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return false }
        return fm.isExecutableFile(atPath: path)
    }

    /// Case-sensitive basename check (APFS may be case-insensitive).
    private static func actualBasename(_ url: URL, fm: FileManager) -> String? {
        let parent = url.deletingLastPathComponent()
        guard let names = try? fm.contentsOfDirectory(atPath: parent.path) else {
            return url.lastPathComponent
        }
        let target = url.lastPathComponent.lowercased()
        return names.first { $0.lowercased() == target }
    }

    private static func isExactBasenameExecutable(
        _ url: URL,
        expectedBasename: String,
        fm: FileManager
    ) -> Bool {
        guard isExecutableFile(url.path, fm: fm) else { return false }
        guard let actual = actualBasename(url, fm: fm) else { return false }
        return actual == expectedBasename
    }

    private static func defaultModelDataPresent(fm: FileManager) -> Bool {
        let root = (NSHomeDirectory() as NSString).appendingPathComponent(".ollama/models")
        return fm.fileExists(atPath: root)
    }

    private static func locationClassForFixed(_ path: String) -> String {
        if path.hasPrefix("/opt/homebrew") { return "HOMEBREW_PREFIX" }
        if path.hasPrefix("/usr/local") { return "USR_LOCAL" }
        if path.contains("/.local/") { return "USER_LOCAL_BIN" }
        return "FIXED_PATH"
    }

    private static func locationClassForBundle(_ url: URL) -> String {
        let p = url.path
        if p.hasPrefix("/Applications") { return "APPLICATIONS" }
        if p.contains("/Users/") && p.contains("/Applications/") { return "USER_APPLICATIONS" }
        return "BUNDLE_OTHER"
    }

    private static func binaryFingerprint(_ url: URL, fm: FileManager) -> String? {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "path=\(url.path);size=\(size);mtime=\(Int(mtime))"
    }

    private static func lookupBundleViaWorkspace() -> (id: String, url: URL, version: String?)? {
        #if canImport(AppKit)
        let ws = NSWorkspace.shared
        for id in knownBundleIDs {
            if let url = ws.urlForApplication(withBundleIdentifier: id) {
                let version = Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
                return (id, url, version)
            }
        }
        #endif
        return nil
    }
}
