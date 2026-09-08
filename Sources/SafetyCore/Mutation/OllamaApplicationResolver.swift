import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Bounded native macOS Ollama.app discovery. No disk crawl. No PATH.
public enum OllamaApplicationResolver {
    public struct Result: Sendable, Equatable {
        public var appFound: Bool
        public var bundleURL: URL?
        public var bundleLocationClass: String?
        public var bundleIdentifier: String?
        public var bundleVersion: String?
        public var mainExecutableURL: URL?
        public var resourcesURL: URL?

        public init(
            appFound: Bool,
            bundleURL: URL? = nil,
            bundleLocationClass: String? = nil,
            bundleIdentifier: String? = nil,
            bundleVersion: String? = nil,
            mainExecutableURL: URL? = nil,
            resourcesURL: URL? = nil
        ) {
            self.appFound = appFound
            self.bundleURL = bundleURL
            self.bundleLocationClass = bundleLocationClass
            self.bundleIdentifier = bundleIdentifier
            self.bundleVersion = bundleVersion
            self.mainExecutableURL = mainExecutableURL
            self.resourcesURL = resourcesURL
        }
    }

    public static func resolve(
        bundleLookup: (@Sendable ([String]) -> (id: String, url: URL, version: String?)?)? = nil
    ) -> Result {
        let hit = bundleLookup?(OllamaNativeInterfaceResolver.knownBundleIDs) ?? workspaceLookup()
        guard let hit else {
            return Result(appFound: false)
        }
        let main = hit.url.appendingPathComponent("Contents/MacOS/Ollama")
        let resources = hit.url.appendingPathComponent("Contents/Resources")
        return Result(
            appFound: true,
            bundleURL: hit.url,
            bundleLocationClass: locationClass(for: hit.url),
            bundleIdentifier: hit.id,
            bundleVersion: hit.version,
            mainExecutableURL: FileManager.default.fileExists(atPath: main.path) ? main : nil,
            resourcesURL: FileManager.default.fileExists(atPath: resources.path) ? resources : nil
        )
    }

    private static func locationClass(for url: URL) -> String {
        let p = url.path
        if p.hasPrefix("/Applications") { return "APPLICATIONS" }
        if p.contains("/Users/") && p.contains("/Applications/") { return "USER_APPLICATIONS" }
        return "BUNDLE_OTHER"
    }

    private static func workspaceLookup() -> (id: String, url: URL, version: String?)? {
        #if canImport(AppKit)
        let ws = NSWorkspace.shared
        for id in OllamaNativeInterfaceResolver.knownBundleIDs {
            if let url = ws.urlForApplication(withBundleIdentifier: id) {
                let version = Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
                return (id, url, version)
            }
        }
        #endif
        return nil
    }
}
