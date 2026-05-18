import SwiftUI

@main
struct RightClickBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Keep a Settings scene so the app can show a window when needed.
        Settings {
            SettingsView()
        }
    }
}
