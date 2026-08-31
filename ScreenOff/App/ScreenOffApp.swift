import SwiftUI

@main
struct ScreenOffApp: App {
    @State private var preferences = ScreenOffPreferences()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(preferences: preferences)
        } label: {
            Image(systemName: "display")
                .accessibilityLabel("Screen Off")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(preferences: preferences)
        }
    }
}

