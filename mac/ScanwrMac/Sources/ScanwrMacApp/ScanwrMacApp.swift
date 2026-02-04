import SwiftUI

@main
struct ScanwrMacApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ShellView()
                .environmentObject(appModel)
        }
        .windowStyle(.titleBar)
        .commands {
            MenuCommands(model: appModel)
        }

        // Provides the standard macOS “Preferences…” menu item (⌘,) automatically.
        Settings {
            SettingsSheet()
                .environmentObject(appModel)
        }
    }
}
