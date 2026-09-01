import AppKit
import SwiftUI

@main
struct ScreenOffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                controller: appDelegate.controller,
                presentationController: appDelegate.presentationController
            )
        } label: {
            MenuBarGlyph.diagonal.image
                .accessibilityLabel("Screen Off")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                controller: appDelegate.controller,
                updateController: appDelegate.updateController,
                presentationController: appDelegate.presentationController
            )
        }
        .defaultSize(width: 520, height: 281)
    }
}

/// App 唯一的状态机持有者，同时负责启动与退出时的系统状态收尾。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = ScreenOffController(preferences: ScreenOffPreferences())
    let updateController = UpdateController()
    let presentationController = AppPresentationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }
}
