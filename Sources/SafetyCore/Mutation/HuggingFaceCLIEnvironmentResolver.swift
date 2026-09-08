import Foundation

/// Read-only HF CLI environment probe. Never installs. Never mutates package state.
public enum HuggingFaceCLIEnvironmentResolver {
    public struct Context: Sendable {
        public var fileManager: FileManager
        public var processRunner: any BoundedProcessRunner
        public var brewCandidatePaths: [String]
        public var uvCandidatePaths: [String]
        public var pipxCandidatePaths: [String]
        public var pythonCandidatePaths: [String]
        public var hostArchitecture: CPUArchitectureClass
        public var hfFixedCLICandidatePaths: [String]?
        public var now: Date

        public init(
            fileManager: FileManager = .default,
            processRunner: any BoundedProcessRunner = FoundationProcessRunner(),
            brewCandidatePaths: [String] = [
                "/opt/homebrew/bin/brew",
                "/usr/local/bin/brew",
            ],
            uvCandidatePaths: [String] = [
                "/opt/homebrew/bin/uv",
                "/usr/local/bin/uv",
                "\(NSHomeDirectory())/.local/bin/uv",
                "\(NSHomeDirectory())/.cargo/bin/uv",
            ],
            pipxCandidatePaths: [String] = [
                "/opt/homebrew/bin/pipx",
                "/usr/local/bin/pipx",
                "\(NSHomeDirectory())/.local/bin/pipx",
            ],
            pythonCandidatePaths: [String] = [
                "/opt/homebrew/bin/python3",
                "/usr/local/bin/python3",
                "/usr/bin/python3",
                "\(NSHomeDirectory())/.pyenv/shims/python3",
            ],
            hostArchitecture: CPUArchitectureClass = .host(),
            hfFixedCLICandidatePaths: [String]? = nil,
            now: Date = Date()
        ) {
            self.fileManager = fileManager
            self.processRunner = processRunner
            self.brewCandidatePaths = brewCandidatePaths
            self.uvCandidatePaths = uvCandidatePaths
            self.pipxCandidatePaths = pipxCandidatePaths
            self.pythonCandidatePaths = pythonCandidatePaths
            self.hostArchitecture = hostArchitecture
            self.hfFixedCLICandidatePaths = hfFixedCLICandidatePaths
            self.now = now
        }
    }

    public static func inspect(context: Context = Context()) -> HFCLIEnvironmentSnapshot {
        let started = Date()
        var evidence: [String] = []

        let brewStarted = Date()
        let brewArch = HomebrewArchitectureResolver.resolve(
            context: .init(
                fileManager: context.fileManager,
                processRunner: context.processRunner,
                candidatePaths: context.brewCandidatePaths,
                hostArchitecture: context.hostArchitecture,
                now: context.now
            )
        )
        evidence.append("HOST_ARCH=\(brewArch.hostArchitecture.rawValue)")
        evidence.append("BREW_SELECTION=\(brewArch.selectionReason)")
        if brewArch.multipleInstallations {
            evidence.append("MULTIPLE_HOMEBREW_INSTALLATIONS")
        }
        let brew = inspectBrew(context: context, architecture: brewArch, evidence: &evidence)
        let brewMs = Int(Date().timeIntervalSince(brewStarted) * 1000)

        let uvStarted = Date()
        let uv = inspectUV(context: context, evidence: &evidence)
        let uvMs = Int(Date().timeIntervalSince(uvStarted) * 1000)

        let pipx = inspectPipx(context: context, evidence: &evidence)

        let pyStarted = Date()
        let py = inspectPython(context: context, evidence: &evidence)
        let pyMs = Int(Date().timeIntervalSince(pyStarted) * 1000)

        // Trusted executable: known brew/uv/local *hf* entry points only — not arbitrary PATH.
        // Never treat the package-manager binary itself (brew/uv) as the HF CLI.
        var trustedPresent = false
        var presence: HFCLIPresenceClass = .notInstalled
        let defaultTrusted = [
            brew.linkedExecutable,
            uv.hfToolURL,
            "\(NSHomeDirectory())/.local/bin/hf",
            "/opt/homebrew/bin/hf",
            "/usr/local/bin/hf",
        ].compactMap { $0 }
        let trustedCandidates = context.hfFixedCLICandidatePaths ?? defaultTrusted

        for path in trustedCandidates {
            if context.fileManager.isExecutableFile(atPath: path) {
                trustedPresent = true
                presence = .trustedCLIPresent
                evidence.append("TRUSTED_EXECUTABLE=\(path)")
                break
            }
        }

        if !trustedPresent, brew.formulaInstalled, !brew.executablePresent {
            presence = .installedButNotResolvable
            evidence.append("CLI_INSTALLED_BUT_NOT_RESOLVABLE")
        } else if !trustedPresent, !py.entryPoints.isEmpty {
            // Package metadata without trusted linked executable — not auto-trusted.
            presence = .notInstalled
            evidence.append("ENTRY_POINTS_WITHOUT_TRUSTED_LINK")
        }

        // Also check resolver fixed candidates + uv tool path.
        let ifaceCandidates = context.hfFixedCLICandidatePaths
            ?? (HuggingFaceNativeInterfaceResolver.fixedCLICandidates
                + [
                    "\(NSHomeDirectory())/.local/share/uv/tools/hf/bin/hf",
                    brew.prefix.map { "\($0)/bin/hf" },
                ].compactMap { $0 })
        let iface = HuggingFaceNativeInterfaceResolver.resolve(
            context: .init(
                fileManager: context.fileManager,
                processRunner: context.processRunner,
                fixedCLICandidatePaths: ifaceCandidates,
                now: context.now
            )
        )
        if iface.cliResolved, iface.executionTransportAvailable {
            trustedPresent = true
            presence = .trustedCLIPresent
            evidence.append("RESOLVER_CONTRACT_OK=\(iface.cliExecutableURL ?? "")")
        }

        // Prefer host-native hf path when present among trusted candidates.
        let preferredHF = brewArch.selectedPrefix.map {
            HomebrewArchitectureResolver.expectedHFExecutable(prefix: $0)
        }
        let hfURL: String?
        if let preferredHF, context.fileManager.isExecutableFile(atPath: preferredHF) {
            hfURL = preferredHF
        } else if brew.executablePresent {
            hfURL = brew.linkedExecutable
        } else {
            hfURL = nil
        }

        return HFCLIEnvironmentSnapshot(
            brewPresent: brew.present,
            brewExecutableURL: brew.executableURL,
            brewPrefix: brew.prefix,
            brewVersion: brew.version,
            hostArchitecture: brewArch.hostArchitecture,
            brewArchitecture: brewArch.selectedArchitecture ?? brew.architecture,
            brewArchitectureMatchesHost: brewArch.architectureMatchesHost,
            brewSelectionReason: brewArch.selectionReason,
            brewMultipleInstallations: brewArch.multipleInstallations,
            brewAlternateInstallations: brewArch.alternateInstallations,
            homebrewResolution: brewArch,
            hfBrewFormulaRecognized: brew.formulaRecognized,
            hfBrewFormulaVersion: brew.formulaVersion,
            hfBrewFormulaInstalled: brew.formulaInstalled,
            hfBrewExecutablePresent: brew.executablePresent || (preferredHF.map { context.fileManager.isExecutableFile(atPath: $0) } ?? false),
            hfBrewExecutableURL: hfURL,
            brewDeclaredDependencies: brew.dependencies,
            uvPresent: uv.present,
            uvExecutableURL: uv.executableURL,
            uvVersion: uv.version,
            existingUVHFTool: uv.hfToolPresent,
            uvHFExecutableURL: uv.hfToolURL,
            pipxPresent: pipx.present,
            existingPipxHF: pipx.hfPresent,
            pythonRuntimesInspected: py.runtimes,
            huggingfaceHubPackagesFound: py.packages,
            existingHFEntryPoints: py.entryPoints,
            trustedHFCLIAlreadyPresent: trustedPresent,
            presenceClass: presence,
            evidence: evidence,
            observedAt: context.now,
            brewMetadataMs: brewMs,
            uvMetadataMs: uvMs,
            pythonMetadataMs: pyMs,
            totalResolutionMs: Int(Date().timeIntervalSince(started) * 1000)
        )
    }

    // MARK: - Brew

    private struct BrewInfo {
        var present: Bool
        var executableURL: String?
        var prefix: String?
        var version: String?
        var architecture: CPUArchitectureClass?
        var formulaRecognized: Bool
        var formulaVersion: String?
        var formulaInstalled: Bool
        var executablePresent: Bool
        var linkedExecutable: String?
        var dependencies: [String]
    }

    private static func inspectBrew(
        context: Context,
        architecture: HomebrewInstallationResolution,
        evidence: inout [String]
    ) -> BrewInfo {
        // Prefer architecture-selected brew; if none selected (foreign-only), still probe for metadata
        // but leave executableURL nil for install preference (planner checks architectureMatchesHost).
        let brewForMetadata = architecture.selectedExecutable
            ?? architecture.candidates.first(where: \.usable)?.executableURL
        guard let brew = brewForMetadata else {
            evidence.append("BREW_ABSENT")
            return BrewInfo(
                present: false, executableURL: nil, prefix: nil, version: nil, architecture: nil,
                formulaRecognized: false, formulaVersion: nil, formulaInstalled: false,
                executablePresent: false, linkedExecutable: nil, dependencies: []
            )
        }
        evidence.append("BREW_METADATA=\(brew)")
        if let selected = architecture.selectedExecutable {
            evidence.append("BREW_SELECTED=\(selected)")
        } else {
            evidence.append("BREW_NOT_SELECTED_FOR_NATIVE_INSTALL")
        }

        let prefixOut = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: brew), arguments: ["--prefix"], timeoutSeconds: 8
        ))
        let prefix = firstLine(prefixOut.stdout)
            ?? architecture.selectedPrefix
            ?? inferPrefix(from: brew)
        let verOut = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: brew), arguments: ["--version"], timeoutSeconds: 8
        ))
        let version = firstLine(verOut.stdout)
            ?? architecture.candidates.first(where: { $0.executableURL == brew })?.version

        let listOut = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: brew),
            arguments: ["list", "--formula", "hf"],
            timeoutSeconds: 15
        ))
        let formulaInstalled = listOut.outcome == .commandAccepted
            && !(listOut.stdout + listOut.stderr).lowercased().contains("no such keg")

        let infoOut = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: brew),
            arguments: ["info", "--json=v2", "hf"],
            timeoutSeconds: 20
        ))
        var formulaRecognized = false
        var formulaVersion: String?
        var deps: [String] = []
        if let parsed = parseBrewInfoJSON(infoOut.stdout) {
            formulaRecognized = true
            formulaVersion = parsed.version
            deps = parsed.dependencies
            evidence.append("BREW_FORMULA=hf@\(parsed.version ?? "?")")
        } else if infoOut.outcome == .commandAccepted || !(infoOut.stdout + infoOut.stderr).isEmpty {
            let text = (infoOut.stdout + infoOut.stderr).lowercased()
            formulaRecognized = text.contains("hf:") || text.contains("\"name\": \"hf\"")
            evidence.append("BREW_INFO_TEXT=\(infoOut.outcome.rawValue)")
        }

        let installPrefix = architecture.selectedPrefix ?? prefix
        let linked = installPrefix.map { HomebrewArchitectureResolver.expectedHFExecutable(prefix: $0) }
        let exePresent = linked.map { context.fileManager.isExecutableFile(atPath: $0) } ?? false

        // Present=true when any brew exists; selected executable only when architecture matches.
        return BrewInfo(
            present: true,
            executableURL: architecture.selectedExecutable,
            prefix: architecture.selectedPrefix ?? prefix,
            version: version,
            architecture: architecture.selectedArchitecture
                ?? architecture.candidates.first(where: { $0.executableURL == brew })?.architecture,
            formulaRecognized: formulaRecognized,
            formulaVersion: formulaVersion,
            formulaInstalled: formulaInstalled,
            executablePresent: exePresent,
            linkedExecutable: linked,
            dependencies: deps
        )
    }

    private struct BrewFormulaParse {
        var version: String?
        var dependencies: [String]
    }

    private static func parseBrewInfoJSON(_ text: String) -> BrewFormulaParse? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = obj["formulae"] as? [[String: Any]],
              let first = formulae.first,
              (first["name"] as? String) == "hf" else { return nil }
        let versions = first["versions"] as? [String: Any]
        let stable = versions?["stable"] as? String
        let deps = (first["dependencies"] as? [String]) ?? []
        return BrewFormulaParse(version: stable, dependencies: deps)
    }

    // MARK: - UV

    private struct UVInfo {
        var present: Bool
        var executableURL: String?
        var version: String?
        var hfToolPresent: Bool
        var hfToolURL: String?
    }

    private static func inspectUV(context: Context, evidence: inout [String]) -> UVInfo {
        guard let uv = firstExecutable(context.uvCandidatePaths, fm: context.fileManager) else {
            evidence.append("UV_ABSENT")
            return UVInfo(present: false, executableURL: nil, version: nil, hfToolPresent: false, hfToolURL: nil)
        }
        evidence.append("UV=\(uv)")
        let ver = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: uv), arguments: ["--version"], timeoutSeconds: 8
        ))
        let toolPath = "\(NSHomeDirectory())/.local/share/uv/tools/hf/bin/hf"
        let present = context.fileManager.isExecutableFile(atPath: toolPath)
        // `uv tool list` is metadata-only — no download.
        let list = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: uv), arguments: ["tool", "list"], timeoutSeconds: 15
        ))
        let listed = (list.stdout + list.stderr).lowercased().contains("\nhf ")
            || (list.stdout + list.stderr).split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("hf") }
        return UVInfo(
            present: true,
            executableURL: uv,
            version: firstLine(ver.stdout),
            hfToolPresent: present || listed,
            hfToolURL: present ? toolPath : nil
        )
    }

    // MARK: - pipx

    private struct PipxInfo {
        var present: Bool
        var hfPresent: Bool
    }

    private static func inspectPipx(context: Context, evidence: inout [String]) -> PipxInfo {
        guard let pipx = firstExecutable(context.pipxCandidatePaths, fm: context.fileManager) else {
            evidence.append("PIPX_ABSENT")
            return PipxInfo(present: false, hfPresent: false)
        }
        evidence.append("PIPX=\(pipx)")
        let list = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: pipx), arguments: ["list", "--short"], timeoutSeconds: 15
        ))
        let text = (list.stdout + list.stderr).lowercased()
        let hf = text.contains("huggingface") || text.split(whereSeparator: \.isNewline).contains {
            $0.trimmingCharacters(in: .whitespaces) == "hf"
                || $0.trimmingCharacters(in: .whitespaces).hasPrefix("huggingface-hub")
                || $0.trimmingCharacters(in: .whitespaces).hasPrefix("huggingface_hub")
        }
        return PipxInfo(present: true, hfPresent: hf)
    }

    // MARK: - Python

    private struct PythonInfo {
        var runtimes: [String]
        var packages: [String]
        var entryPoints: [String]
    }

    private static func inspectPython(context: Context, evidence: inout [String]) -> PythonInfo {
        var runtimes: [String] = []
        var packages: [String] = []
        var entryPoints: [String] = []
        for path in context.pythonCandidatePaths {
            guard context.fileManager.isExecutableFile(atPath: path) else { continue }
            runtimes.append(path)
            // Bounded: import metadata only — no pip install.
            let script = """
            import importlib.metadata as m
            try:
                d = m.distribution('huggingface_hub')
                print('PKG', d.version)
                for e in d.entry_points:
                    if e.group == 'console_scripts' and e.name in ('hf', 'huggingface-cli'):
                        print('EP', e.name)
            except Exception:
                print('NONE')
            """
            let result = context.processRunner.run(BoundedProcessRequest(
                executableURL: URL(fileURLWithPath: path),
                arguments: ["-c", script],
                timeoutSeconds: 10
            ))
            let out = result.stdout
            for line in out.split(whereSeparator: \.isNewline).map(String.init) {
                if line.hasPrefix("PKG ") {
                    let ver = String(line.dropFirst(4))
                    packages.append("huggingface_hub==\(ver) @ \(path)")
                    evidence.append("HUB_PKG=\(path)=\(ver)")
                }
                if line.hasPrefix("EP ") {
                    entryPoints.append("\(String(line.dropFirst(3))) via \(path)")
                }
            }
        }
        return PythonInfo(runtimes: runtimes, packages: packages, entryPoints: entryPoints)
    }

    // MARK: - helpers

    private static func firstExecutable(_ paths: [String], fm: FileManager) -> String? {
        for p in paths where fm.isExecutableFile(atPath: p) {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue {
                return p
            }
        }
        return nil
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(160)) }
    }

    private static func inferPrefix(from brewPath: String) -> String? {
        // /opt/homebrew/bin/brew → /opt/homebrew ; /usr/local/bin/brew → /usr/local
        let url = URL(fileURLWithPath: brewPath)
        return url.deletingLastPathComponent().deletingLastPathComponent().path
    }
}
