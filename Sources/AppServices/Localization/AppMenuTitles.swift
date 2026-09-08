import Foundation

/// v0.2 UX FIX 001 — native macOS app-menu item titles.
///
/// Scope is deliberately narrower than the product UI:
/// the app UI ships 9 locales, but the **native app menu** is Japanese when the
/// app language is Japanese and English otherwise. That is an intentional
/// decision for this fix, not missing translation work — which is why these
/// titles live here as an explicit table rather than in the 9-locale catalog,
/// where English entries would read as untranslated defects.
///
/// Titles only. Selectors, key equivalents and the Services submenu are never
/// touched by this type.
public enum AppMenuItemKind: String, Sendable, CaseIterable, Equatable {
    case about
    case services
    case hide
    case hideOthers
    case showAll
    case quit
    /// The Option-key alternate of Quit. Shares `terminate:` with `.quit`, so it
    /// can only be told apart by NSMenuItem.isAlternate — matching on the
    /// selector alone would label both items "Quit".
    case quitKeepingWindows

    /// The standard AppKit selector that identifies this item.
    ///
    /// Items are matched by selector, never by their current title — titles
    /// change with locale, so title matching breaks the moment it is needed.
    public var selectorName: String? {
        switch self {
        case .about: return "orderFrontStandardAboutPanel:"
        case .services: return nil // identified via NSApplication.servicesMenu
        case .hide: return "hide:"
        case .hideOthers: return "hideOtherApplications:"
        case .showAll: return "unhideAllApplications:"
        case .quit, .quitKeepingWindows: return "terminate:"
        }
    }

    /// Whether the title embeds the application name.
    public var usesAppName: Bool {
        switch self {
        case .about, .hide, .quit: return true
        case .services, .hideOthers, .showAll, .quitKeepingWindows: return false
        }
    }
}

public enum AppMenuTitles {
    /// Japanese app menu is used when the **effective** UI language is Japanese.
    ///
    /// This resolves through L10n rather than comparing the enum, because
    /// `.system` on a Japanese Mac renders the whole product UI in Japanese —
    /// and an English app menu next to a Japanese UI is precisely the mismatch
    /// this fix exists to remove. Every other effective locale gets English,
    /// which is the intended scope for the native menu (the product UI stays
    /// 9-locale).
    public static func usesJapanese(_ language: AppLanguage) -> Bool {
        L10n.catalogLocaleID(for: language) == "ja"
    }

    /// Title for one standard app-menu item.
    ///
    /// - Parameters:
    ///   - kind: which standard item
    ///   - language: current in-app language
    ///   - appName: the running application's display name
    public static func title(
        for kind: AppMenuItemKind,
        language: AppLanguage,
        appName: String
    ) -> String {
        usesJapanese(language)
            ? japanese(kind, appName: appName)
            : english(kind, appName: appName)
    }

    private static func japanese(_ kind: AppMenuItemKind, appName: String) -> String {
        switch kind {
        case .about: return "\(appName)について"
        case .services: return "サービス"
        case .hide: return "\(appName)を非表示"
        case .hideOthers: return "ほかを非表示"
        case .showAll: return "すべてを表示"
        case .quit: return "\(appName)を終了"
        case .quitKeepingWindows: return "ウインドウを残して終了"
        }
    }

    private static func english(_ kind: AppMenuItemKind, appName: String) -> String {
        switch kind {
        case .about: return "About \(appName)"
        case .services: return "Services"
        case .hide: return "Hide \(appName)"
        case .hideOthers: return "Hide Others"
        case .showAll: return "Show All"
        case .quit: return "Quit \(appName)"
        case .quitKeepingWindows: return "Quit and Keep Windows"
        }
    }
}
