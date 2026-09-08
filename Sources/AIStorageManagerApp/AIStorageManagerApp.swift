import AppKit
import SwiftUI
import AppServices
import AIStorageManagerUI
import SafetyCore

/// v0.2 UX FIX 001 — the native app menu is built by AppKit after launch, so the
/// in-app language override has to be applied to it once the menu exists.
/// Titles only: actions, key equivalents and Services stay untouched.
final class AppMenuLocalizingDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenuLocalizer.install(language: LanguageStore.shared.language)
    }
}

@main
struct AIStorageManagerApp: App {
    @NSApplicationDelegateAdaptor(AppMenuLocalizingDelegate.self) private var appDelegate
    @StateObject private var viewModel = StorageViewModel(
        coordinator: LiveStorageActionCoordinator(
            executor: StorageActionExecutorRouter()
        )
    )
    @StateObject private var languageStore = LanguageStore.shared

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(viewModel)
                .environmentObject(languageStore)
                .frame(minWidth: 1100, minHeight: 820)
                .onAppear {
                    AppMenuLocalizer.install(language: languageStore.language)
                }
                .onChange(of: languageStore.language) { newValue in
                    // Live update: English → Japanese and back, no restart.
                    AppMenuLocalizer.setLanguage(newValue)
                }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

#if DEBUG
struct AIStorageManagerApp_Previews: PreviewProvider {
    static var previews: some View {
        AppShellView()
            .environmentObject(StorageViewModel(coordinator: FakeStorageActionCoordinator()))
            .environmentObject(LanguageStore())
            .frame(width: 800, height: 600)
    }
}
#endif
