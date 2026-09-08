import AppKit
import AppServices

/// v0.2 UX FIX 001 — applies localized titles to the native macOS app menu.
///
/// SwiftUI's `App` lifecycle builds AppKit's standard menu from the process
/// locale, so an in-app language override leaves it in English. This walks the
/// existing menu and rewrites **titles only**.
///
/// Never changes: target, action, key equivalent, modifier mask, tag, item
/// order, or the Services submenu wiring.
///
/// Timing is the hard part here. SwiftUI rebuilds the main menu on its own
/// schedule, and when the app is launched through LaunchServices that rebuild
/// lands *after* the launch and activation notifications — so a one-shot pass,
/// or one hung off `didBecomeActive`, gets silently overwritten and the user
/// still sees English even though the in-process menu briefly looked right.
/// The authoritative hook is `NSMenuDelegate.menuNeedsUpdate(_:)`, which AppKit
/// calls immediately before a menu is displayed, after any rebuild.
@MainActor
public enum AppMenuLocalizer {

    private static var observers: [NSObjectProtocol] = []
    fileprivate static var currentLanguage: AppLanguage = .system
    private static let menuDelegate = MenuTitleDelegate()

    /// Keep the app menu localized for the lifetime of the process.
    public static func install(language: AppLanguage, app: NSApplication = .shared) {
        currentLanguage = language
        attachDelegate(app: app)
        apply(language: language, app: app)

        guard observers.isEmpty else { return }
        // A rebuild drops our delegate along with the old NSMenu, so re-attach
        // on the events that bracket one. Delivered synchronously (`queue: nil`)
        // so the work lands before anything draws.
        for name in [
            NSApplication.didBecomeActiveNotification,
            NSMenu.didBeginTrackingNotification,
        ] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                    MainActor.assumeIsolated {
                        attachDelegate(app: app)
                        apply(language: currentLanguage, app: app)
                    }
                }
            )
        }
    }

    /// Switch language at runtime (Settings → Language), no restart.
    public static func setLanguage(_ language: AppLanguage, app: NSApplication = .shared) {
        currentLanguage = language
        attachDelegate(app: app)
        apply(language: language, app: app)
    }

    /// Rewrite the standard app-menu item titles for the given language.
    ///
    /// Safe to call repeatedly and safe to call before the menu exists.
    public static func apply(language: AppLanguage, app: NSApplication = .shared) {
        guard let mainMenu = app.mainMenu else { return }
        guard let appMenu = appMenu(in: mainMenu, app: app) else { return }

        let appName = applicationName()

        // The app menu's own title is the app name on macOS — leave it alone.
        for item in appMenu.items {
            guard let kind = kind(of: item, app: app) else { continue }
            let newTitle = AppMenuTitles.title(for: kind, language: language, appName: appName)
            guard item.title != newTitle else { continue }
            item.title = newTitle
            // Submenu titles must track the item, otherwise Services renders stale.
            if kind == .services, let submenu = item.submenu, submenu.title != newTitle {
                submenu.title = newTitle
            }
        }
    }

    // MARK: - Delegate attachment

    private static func attachDelegate(app: NSApplication = .shared) {
        guard let mainMenu = app.mainMenu,
              let appMenu = appMenu(in: mainMenu, app: app) else { return }
        guard !(appMenu.delegate is MenuTitleDelegate) else { return }
        menuDelegate.previous = appMenu.delegate
        appMenu.delegate = menuDelegate
    }

    /// Localizes on `menuNeedsUpdate`, then forwards to whatever delegate was
    /// already installed so nothing else loses its callback.
    private final class MenuTitleDelegate: NSObject, NSMenuDelegate {
        weak var previous: NSMenuDelegate?

        func menuNeedsUpdate(_ menu: NSMenu) {
            MainActor.assumeIsolated {
                AppMenuLocalizer.apply(language: AppMenuLocalizer.currentLanguage)
            }
            previous?.menuNeedsUpdate?(menu)
        }
    }

    // MARK: - Identification

    /// The first menu is the application menu on macOS.
    private static func appMenu(in mainMenu: NSMenu, app: NSApplication) -> NSMenu? {
        mainMenu.items.first?.submenu
    }

    /// Identify by selector (and by `servicesMenu` identity for Services).
    ///
    /// Deliberately never matches on `item.title` — the title is exactly what
    /// this type changes, so title matching would only work on first run.
    private static func kind(of item: NSMenuItem, app: NSApplication) -> AppMenuItemKind? {
        // Services is deliberately NOT handled here.
        //
        // AppKit re-localizes the standard items from the bundle on every menu
        // update, so a runtime rewrite of those does not stick — but the
        // Services item does, because the app owns that submenu. Renaming only
        // Services produced a menu that was half Japanese and half English,
        // which is worse than either. Leave the whole standard menu to the
        // bundle localization (en.lproj / ja.lproj), which macOS applies
        // consistently.
        guard let action = item.action else { return nil }
        let name = NSStringFromSelector(action)
        // `terminate:` backs both Quit and its Option-key alternate, so the
        // alternate flag is what separates them.
        if name == "terminate:" {
            return item.isAlternate ? .quitKeepingWindows : .quit
        }
        return AppMenuItemKind.allCases.first { $0.selectorName == name }
    }

    private static func applicationName() -> String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? ProcessInfo.processInfo.processName
    }
}
