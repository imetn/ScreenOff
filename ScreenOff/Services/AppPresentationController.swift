import AppKit

/// 协调菜单栏 App 与设置窗口之间的激活策略。
/// 设置窗口存在时显示 Dock 图标；窗口关闭后恢复为纯菜单栏 App。
@MainActor
final class AppPresentationController: NSObject {
    private weak var settingsWindow: NSWindow?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func prepareToOpenSettings() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            !(window is NSPanel),
            window.styleMask.contains(.titled)
        else { return }
        settingsWindow = window
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        settingsWindow = nil

        DispatchQueue.main.async {
            let hasVisibleAppWindow = NSApplication.shared.windows.contains { window in
                window.isVisible && !(window is NSPanel) && window.styleMask.contains(.titled)
            }
            if !hasVisibleAppWindow {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
