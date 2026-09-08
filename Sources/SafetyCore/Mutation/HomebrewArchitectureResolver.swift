import Foundation

/// Host vs package-manager architecture for Homebrew selection.
public enum CPUArchitectureClass: String, Codable, Sendable, Equatable {
    case arm64 = "arm64"
    case x86_64 = "x86_64"
    case unknown = "unknown"

    public static func host() -> CPUArchitectureClass {
        // Prefer silicon truth over process arch (Rosetta processes report x86_64).
        var arm64: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &arm64, &size, nil, 0) == 0, arm64 == 1 {
            return .arm64
        }
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        if machine.contains("arm64") || machine.contains("aarch64") { return .arm64 }
        if machine.contains("x86_64") || machine.contains("i386") { return .x86_64 }
        return .unknown
        #endif
    }
}

public struct HomebrewCandidate: Codable, Sendable, Equatable {
    public var executableURL: String
    public var prefix: String?
    public var architecture: CPUArchitectureClass
    public var version: String?
    public var usable: Bool
    public var hostNative: Bool
    public var formulaHFAvailable: Bool?
    public var evidence: [String]
}

public struct HomebrewInstallationResolution: Codable, Sendable, Equatable {
    public var hostArchitecture: CPUArchitectureClass
    public var candidates: [HomebrewCandidate]
    public var selectedExecutable: String?
    public var selectedPrefix: String?
    public var selectedArchitecture: CPUArchitectureClass?
    public var architectureMatchesHost: Bool
    public var selectionReason: String
    public var alternateInstallations: [String]
    public var multipleInstallations: Bool
    public var observedAt: Date
    public var resolutionMs: Int
}

/// Resolves Homebrew installations with host-native preference. PATH order must not win.
public enum HomebrewArchitectureResolver {
    public static let defaultCandidatePaths: [String] = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    public struct Context: Sendable {
        public var fileManager: FileManager
        public var processRunner: any BoundedProcessRunner
        public var candidatePaths: [String]
        public var hostArchitecture: CPUArchitectureClass
        public var now: Date
        /// Optional pre-inspected candidates (for fixtures). When non-empty, skips process probes.
        public var injectedCandidates: [HomebrewCandidate]?

        public init(
            fileManager: FileManager = .default,
            processRunner: any BoundedProcessRunner = FoundationProcessRunner(),
            candidatePaths: [String] = HomebrewArchitectureResolver.defaultCandidatePaths,
            hostArchitecture: CPUArchitectureClass = .host(),
            now: Date = Date(),
            injectedCandidates: [HomebrewCandidate]? = nil
        ) {
            self.fileManager = fileManager
            self.processRunner = processRunner
            self.candidatePaths = candidatePaths
            self.hostArchitecture = hostArchitecture
            self.now = now
            self.injectedCandidates = injectedCandidates
        }
    }

    public static func resolve(context: Context = Context()) -> HomebrewInstallationResolution {
        let started = Date()
        let candidates: [HomebrewCandidate]
        if let injected = context.injectedCandidates {
            candidates = injected
        } else {
            var found: [HomebrewCandidate] = []
            for path in context.candidatePaths {
                guard context.fileManager.isExecutableFile(atPath: path) else { continue }
                found.append(inspect(path: path, host: context.hostArchitecture, context: context))
            }
            candidates = found
        }

        let multiple = candidates.count > 1
        let usable = candidates.filter(\.usable)
        let native = usable.filter { $0.hostNative }
        let foreign = usable.filter { !$0.hostNative }

        let selected: HomebrewCandidate?
        let reason: String

        if let first = native.first {
            selected = first
            reason = multiple
                ? "HOST_NATIVE_PREFERRED_OVER_PATH_ORDER_MULTIPLE_INSTALLATIONS"
                : "HOST_NATIVE_BREW_SELECTED"
        } else if !foreign.isEmpty, native.isEmpty {
            // Foreign-only: do NOT auto-select as preferred native install mechanism.
            selected = nil
            reason = "ONLY_FOREIGN_ARCHITECTURE_BREW_PRESENT_DO_NOT_AUTO_SELECT_AS_NATIVE"
        } else if context.hostArchitecture == .unknown, let first = usable.first {
            selected = first
            reason = "HOST_ARCH_UNKNOWN_FALLBACK"
        } else {
            selected = nil
            reason = usable.isEmpty ? "NO_USABLE_HOMEBREW" : "NO_HOST_NATIVE_BREW_USABLE"
        }

        let match = selected.map { $0.architecture == context.hostArchitecture && $0.architecture != .unknown } ?? false
        return HomebrewInstallationResolution(
            hostArchitecture: context.hostArchitecture,
            candidates: candidates,
            selectedExecutable: selected?.executableURL,
            selectedPrefix: selected?.prefix,
            selectedArchitecture: selected?.architecture,
            architectureMatchesHost: match,
            selectionReason: reason,
            alternateInstallations: candidates
                .map(\.executableURL)
                .filter { $0 != selected?.executableURL },
            multipleInstallations: multiple,
            observedAt: context.now,
            resolutionMs: Int(Date().timeIntervalSince(started) * 1000)
        )
    }

    public static func expectedHFExecutable(prefix: String) -> String {
        (prefix as NSString).appendingPathComponent("bin/hf")
    }

    private static func inspect(path: String, host: CPUArchitectureClass, context: Context) -> HomebrewCandidate {
        var evidence: [String] = ["EXECUTABLE=\(path)"]
        let prefixOut = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: path), arguments: ["--prefix"], timeoutSeconds: 8
        ))
        let prefix = firstLine(prefixOut.stdout)
            ?? URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent().path
        evidence.append("PREFIX=\(prefix)")

        let verOut = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: path), arguments: ["--version"], timeoutSeconds: 8
        ))
        let version = firstLine(verOut.stdout)

        let configOut = context.processRunner.run(BoundedProcessRequest(
            executableURL: URL(fileURLWithPath: path), arguments: ["config"], timeoutSeconds: 15
        ))
        let config = configOut.stdout + configOut.stderr
        var arch = architectureFromBrewConfig(config, evidence: &evidence)

        // Corroborate with a binary under the prefix when present.
        let probeBins = [
            "\(prefix)/opt/openssl@3/bin/openssl",
            "\(prefix)/bin/openssl",
            "\(prefix)/bin/python3",
            "\(prefix)/bin/bash",
        ]
        for bin in probeBins {
            guard context.fileManager.isExecutableFile(atPath: bin) else { continue }
            let fileOut = context.processRunner.run(BoundedProcessRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/file"),
                arguments: [bin],
                timeoutSeconds: 5
            ))
            let text = (fileOut.stdout + fileOut.stderr).lowercased()
            if text.contains("arm64") {
                arch = .arm64
                evidence.append("FILE_ARM64=\(bin)")
                break
            }
            if text.contains("x86_64") {
                arch = .x86_64
                evidence.append("FILE_X86_64=\(bin)")
                break
            }
        }

        // Known-default hints only as last resort — never sole proof when metadata exists.
        if arch == .unknown {
            if prefix.hasPrefix("/opt/homebrew") {
                arch = .arm64
                evidence.append("PREFIX_HINT_OPT_HOMEBREW")
            } else if prefix.hasPrefix("/usr/local") {
                arch = .x86_64
                evidence.append("PREFIX_HINT_USR_LOCAL")
            }
        }

        let hostNative = arch == host && arch != .unknown
        return HomebrewCandidate(
            executableURL: path,
            prefix: prefix,
            architecture: arch,
            version: version,
            usable: true,
            hostNative: hostNative,
            formulaHFAvailable: nil,
            evidence: evidence
        )
    }

    /// Parse `brew config` lines for CPU / Rosetta / macOS arch.
    public static func architectureFromBrewConfig(_ config: String, evidence: inout [String]) -> CPUArchitectureClass {
        let lines = config.split(whereSeparator: \.isNewline).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        var rosetta: Bool?
        var cpu: String?
        var macos: String?
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("rosetta 2:") {
                rosetta = lower.contains("true")
            } else if lower.hasPrefix("cpu:") {
                cpu = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces).lowercased()
            } else if lower.hasPrefix("macos:") {
                macos = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces).lowercased()
            }
        }
        if rosetta == true {
            evidence.append("BREW_CONFIG_ROSETTA_TRUE")
            return .x86_64
        }
        if let cpu, cpu.contains("arm") || cpu.contains("apple") {
            evidence.append("BREW_CONFIG_CPU_ARM")
            return .arm64
        }
        if let macos, macos.contains("arm64") {
            evidence.append("BREW_CONFIG_MACOS_ARM64")
            return .arm64
        }
        if let macos, macos.contains("x86_64") {
            evidence.append("BREW_CONFIG_MACOS_X86_64")
            return .x86_64
        }
        if let cpu, cpu.contains("intel") || cpu.contains("x86") {
            evidence.append("BREW_CONFIG_CPU_X86")
            return .x86_64
        }
        return .unknown
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(160)) }
    }
}

/// Vendor ≈ semantic size comparison for dry-run agreement.
public enum HuggingFaceDryRunSizeAgreement {
    public enum Result: String, Codable, Sendable {
        case agrees = "AGREES"
        case agreesWithFormattingDifference = "AGREES_WITH_FORMATTING_DIFFERENCE"
        case conflict = "CONFLICT"
        case unknown = "UNKNOWN"
    }

    public static func compare(vendorExpectedFreedBytes: Int64?, semanticBytes: Int64?) -> Result {
        guard let v = vendorExpectedFreedBytes, let s = semanticBytes, v > 0, s > 0 else { return .unknown }
        if v == s { return .agrees }
        let delta = abs(Double(v - s)) / Double(s)
        // 3.1G display vs exact 3083520968 ≈ within ~8%
        if delta <= 0.08 { return .agreesWithFormattingDifference }
        return .conflict
    }

    public static func parseVendorSizeToken(_ text: String) -> Int64? {
        let lower = text.lowercased()
        if let r = lower.range(of: #"[0-9]+(\.[0-9]+)?\s*g(i)?b?"#, options: .regularExpression) {
            let token = String(lower[r])
            let numPart = token.split(whereSeparator: { !$0.isNumber && $0 != "." }).first.map(String.init)
            if let n = numPart.flatMap(Double.init) {
                if token.contains("gi") {
                    return Int64(n * 1_073_741_824)
                }
                return Int64(n * 1_000_000_000)
            }
        }
        if let r = text.range(of: #"[0-9]{7,}"#, options: .regularExpression) {
            return Int64(String(text[r]))
        }
        return nil
    }
}
