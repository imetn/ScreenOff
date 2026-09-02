import AppKit

/// 协调菜单栏 App 与设置窗口之间的激活策略。
/// 打开设置前切到 `.regular` 显示 Dock 图标；任一带标题窗口关闭后，
/// 若已没有可见的带标题窗口，就恢复为纯菜单栏 App。
/// 不记录具体是哪个窗口，因此 Sparkle 更新窗口等其他常规窗口也走同一规则。
@MainActor
final class AppPresentationController: NSObject {
    override init() {
        super.init()
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

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, Self.isRegularWindow(closing) else { return }

        // willClose 时窗口仍算可见，延后一轮再统计剩余窗口。
        DispatchQueue.main.async {
            let hasVisibleAppWindow = NSApplication.shared.windows.contains { window in
                window !== closing && window.isVisible && Self.isRegularWindow(window)
            }
            if !hasVisibleAppWindow {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
    }

    /// 菜单栏弹窗与各类面板都是 `NSPanel`，只有带标题的普通窗口才影响 Dock 图标。
    private static func isRegularWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
