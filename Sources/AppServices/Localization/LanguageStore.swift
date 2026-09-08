import Foundation
import Combine

/// Persists in-app language override. Presentation only — never Safety.
@MainActor
public final class LanguageStore: ObservableObject {
    public static let shared = LanguageStore()

    private static let defaultsKey = "appLanguage.v1"
    private let defaults: UserDefaults

    @Published public var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.defaultsKey)
            L10n.setOverride(language)
            applyNativeLanguageOverride()
        }
    }

    /// v0.2 UX FIX 001 — make the in-app choice reach macOS itself.
    ///
    /// The native app menu (About / Services / Hide / Quit, and the Edit / View
    /// / Window / Help titles) is rendered by AppKit from the bundle's
    /// localizations, chosen by `AppleLanguages`. Nothing the process does to
    /// `NSApp.mainMenu` at runtime survives AppKit's own rebuild, so the only
    /// way an in-app language choice can reach that menu is to record it here.
    ///
    /// This takes effect on next launch, which is what the Settings screen
    /// already tells the user (`settings.language.restartNote`).
    private func applyNativeLanguageOverride() {
        switch language {
        case .system:
            defaults.removeObject(forKey: "AppleLanguages")
        default:
            // The bundle ships en + ja menus; anything else falls back to en.
            let native = language == .japanese ? "ja" : "en"
            defaults.set([native], forKey: "AppleLanguages")
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.defaultsKey)
        let parsed = AppLanguage.parse(stored)
        self.language = parsed
        L10n.setOverride(parsed)
    }

    public var resolvedLocale: Locale {
        L10n.resolvedLocale(for: language)
    }
}
