import Foundation

/// Resolves a trustworthy Ollama install source. No curl|sh. No mirrors.
public enum OllamaTrustedInstallSourceResolver {
    public static let officialDownloadURL = URL(string: "https://ollama.com/download/Ollama-darwin.zip")!
    public static let officialHostAllowlist: Set<String> = [
        "ollama.com",
        "www.ollama.com",
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]

    public struct ResolvedSource: Codable, Sendable, Equatable {
        public var method: SoftwareInstallMethod
        public var sourceClass: SoftwareInstallSourceClass
        public var sourceVerified: Bool
        public var artifactIdentity: String?
        public var localArtifactPath: String?
        public var remoteURL: String?
        public var packageManagerFormula: String?
        public var verificationNotes: [String]
        public var unresolvedReason: String?
    }

    public struct Context: Sendable {
        public var fileManager: FileManager
        public var homeDirectory: String
        public var localSearchRoots: [String]
        public var brewExecutablePath: String?
        public var preferPackageManager: Bool

        public init(
            fileManager: FileManager = .default,
            homeDirectory: String = NSHomeDirectory(),
            localSearchRoots: [String]? = nil,
            brewExecutablePath: String? = nil,
            preferPackageManager: Bool = false
        ) {
            self.fileManager = fileManager
            self.homeDirectory = homeDirectory
            let downloads = (homeDirectory as NSString).appendingPathComponent("Downloads")
            self.localSearchRoots = localSearchRoots ?? [downloads, "/tmp"]
            self.brewExecutablePath = brewExecutablePath
                ?? OllamaTrustedInstallSourceResolver.detectBrew(fileManager: fileManager)
            self.preferPackageManager = preferPackageManager
        }
    }

    public static func resolve(context: Context = Context()) -> ResolvedSource {
        if let local = findLocalOfficialArtifact(context: context) {
            return local
        }

        if context.preferPackageManager,
           let brew = packageManagerSource(context: context) {
            return brew
        }

        // Official remote distribution (bounded download later — not curl|sh).
        let notes = [
            "OFFICIAL_DOWNLOAD_URL=\(officialDownloadURL.absoluteString)",
            "HOST_ALLOWLIST=\(officialHostAllowlist.sorted().joined(separator: ","))",
            "NO_CURL_PIPE_SHELL",
        ]
        return ResolvedSource(
            method: .officialAppInstall,
            sourceClass: .officialRemoteDistribution,
            sourceVerified: false, // verified after download + codesign
            artifactIdentity: "ollama.com/download/Ollama-darwin.zip",
            localArtifactPath: nil,
            remoteURL: officialDownloadURL.absoluteString,
            packageManagerFormula: nil,
            verificationNotes: notes,
            unresolvedReason: nil
        )
    }

    public static func packageManagerFallback(context: Context = Context()) -> ResolvedSource? {
        packageManagerSource(context: context)
    }

    private static func findLocalOfficialArtifact(context: Context) -> ResolvedSource? {
        let names = ["Ollama-darwin.zip", "Ollama.dmg", "Ollama.zip"]
        for root in context.localSearchRoots {
            for name in names {
                let path = (root as NSString).appendingPathComponent(name)
                if context.fileManager.fileExists(atPath: path) {
                    return ResolvedSource(
                        method: .existingOfficialInstaller,
                        sourceClass: .officialLocalArtifact,
                        sourceVerified: false,
                        artifactIdentity: name,
                        localArtifactPath: path,
                        remoteURL: nil,
                        packageManagerFormula: nil,
                        verificationNotes: ["LOCAL_ARTIFACT=\(path)"],
                        unresolvedReason: nil
                    )
                }
            }
        }
        return nil
    }

    private static func packageManagerSource(context: Context) -> ResolvedSource? {
        guard let brew = context.brewExecutablePath,
              context.fileManager.isExecutableFile(atPath: brew) else {
            return nil
        }
        return ResolvedSource(
            method: .packageManagerInstall,
            sourceClass: .establishedPackageManager,
            sourceVerified: true,
            artifactIdentity: "homebrew/core/ollama",
            localArtifactPath: nil,
            remoteURL: nil,
            packageManagerFormula: "ollama",
            verificationNotes: [
                "BREW=\(brew)",
                "FORMULA=ollama",
                "VENDOR=https://ollama.com/",
            ],
            unresolvedReason: nil
        )
    }

    private static func detectBrew(fileManager: FileManager) -> String? {
        let candidates = ["/usr/local/bin/brew", "/opt/homebrew/bin/brew"]
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    public static func hostAllowed(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return officialHostAllowlist.contains(host)
    }
}
