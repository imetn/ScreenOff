import AppKit
import KeyboardShortcuts
import Testing

/// 注入空事件流，直接验证配对和订阅生命周期，不占用真实全局快捷键、不调节亮度。
@Suite("关屏快捷键事件")
@MainActor
struct ScreenOffShortcutServiceTests {
    private func makeService() -> ScreenOffShortcutService {
        ScreenOffShortcutService(events: { _ in AsyncStream { _ in } })
    }

    @Test("单个按键、单独功能键和仅 Shift 的输入都不能设为快捷键")
    func rejectsSingleKeys() {
        for shortcut: KeyboardShortcuts.Shortcut in [
            .init(.a), .init(.f1), .init(.f12), .init(.space), .init(.a, modifiers: .shift),
            .init(.f8, modifiers: .shift), .init(.command, modifiers: .command),
            .init(carbonKeyCode: 128, carbonModifiers: 256)
        ] {
            #expect(!ScreenOffShortcutService.isSupported(shortcut))
            // 即使是旧版本保存的同一按键，也必须先通过组合键规则。
            #expect(ScreenOffShortcutService.validate(shortcut, replacing: shortcut) != .allow)
        }
    }

    @Test("支持修饰键加普通键或功能键")
    func acceptsCombinations() {
        for shortcut: KeyboardShortcuts.Shortcut in [
            .init(.s, modifiers: [.control, .option]), .init(.d, modifiers: .command),
            .init(.f8, modifiers: [.control, .shift]), .init(.s, modifiers: .option)
        ] {
            #expect(ScreenOffShortcutService.isSupported(shortcut))
        }
    }

    @Test("旧版单键设置不会被注册为全局快捷键")
    func doesNotRegisterUnsupportedShortcut() {
        var registrations = 0
        var calls = 0
        let service = ScreenOffShortcutService(events: { _ in
            registrations += 1
            return AsyncStream { _ in }
        })
        defer { service.stop() }
        service.setShortcut(.init(.f8)) { calls += 1 }
        service.receive(.keyDown)
        service.receive(.keyUp)
        #expect(registrations == 0)
        #expect(calls == 0)
    }

    @Test("菜单冲突检查包含子菜单和大写形式的 Shift 快捷键")
    func checksMenuConflicts() {
        let menu = NSMenu()
        let parent = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let item = NSMenuItem(title: "另存为", action: nil, keyEquivalent: "S")
        item.keyEquivalentModifierMask = .command
        submenu.addItem(item)
        parent.submenu = submenu
        menu.addItem(parent)
        #expect(ScreenOffShortcutService.conflictingMenuTitle(for: .init(.s, modifiers: [.command, .shift]), in: menu) == "另存为")
        #expect(ScreenOffShortcutService.conflictingMenuTitle(for: .init(.s, modifiers: [.control, .option]), in: menu) == nil)
    }

    @Test("录入后的单独松键不关屏，完整按键只触发一次")
    func ignoresUnpairedReleaseAndKeyRepeat() {
        let service = makeService()
        defer { service.stop() }
        var count = 0
        service.setShortcut(.init(.s, modifiers: [.control, .option])) { count += 1 }

        service.receive(.keyUp)
        #expect(count == 0)
        service.receive(.keyDown)
        service.receive(.keyDown)
        #expect(count == 0)
        service.receive(.keyUp)
        service.receive(.keyUp)
        #expect(count == 1)
    }

    @Test("修改快捷键会重置旧按键状态并替换动作")
    func replacementClearsPendingPress() {
        let service = makeService()
        defer { service.stop() }
        var oldCount = 0
        var newCount = 0
        service.setShortcut(.init(.s, modifiers: [.control, .option])) { oldCount += 1 }
        service.receive(.keyDown)

        service.setShortcut(.init(.d, modifiers: [.control, .option])) { newCount += 1 }
        service.receive(.keyUp)
        #expect(oldCount == 0)
        #expect(newCount == 0)
        service.receive(.keyDown)
        service.receive(.keyUp)
        #expect(oldCount == 0)
        #expect(newCount == 1)
    }

    @Test("清除快捷键或退出后不再触发")
    func clearingAndStoppingDisableAction() {
        let service = makeService()
        var count = 0
        let shortcut = KeyboardShortcuts.Shortcut(.s, modifiers: [.control, .option])
        service.setShortcut(shortcut) { count += 1 }
        service.receive(.keyDown)
        service.setShortcut(nil) { count += 1 }
        service.receive(.keyUp)
        service.receive(.keyDown)
        service.receive(.keyUp)
        #expect(count == 0)

        service.setShortcut(shortcut) { count += 1 }
        service.receive(.keyDown)
        service.stop()
        service.receive(.keyUp)
        #expect(count == 0)
    }
}
