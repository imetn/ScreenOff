import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

/// 仅订阅用户指定的全局组合键；不监听或保存普通输入内容。
@MainActor
final class ScreenOffShortcutService {
    private let events: (KeyboardShortcuts.Shortcut) -> AsyncStream<KeyboardShortcuts.EventType>
    private var eventTask: Task<Void, Never>?
    private var onRelease: (() -> Void)?
    private var keyIsDown = false

    init(
        events: @escaping (KeyboardShortcuts.Shortcut) -> AsyncStream<KeyboardShortcuts.EventType> = {
            KeyboardShortcuts.events(for: $0)
        }
    ) {
        self.events = events
    }

    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?, action: @escaping () -> Void) {
        stop()
        guard let shortcut, Self.isSupported(shortcut) else { return }
        onRelease = action
        let stream = events(shortcut)
        eventTask = Task { [weak self] in
            for await event in stream {
                // 清除或替换组合键后，不执行旧订阅中已经排队的事件。
                guard !Task.isCancelled else { return }
                self?.receive(event)
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        onRelease = nil
        keyIsDown = false
    }

    /// 要求完整的按下/松开配对：录制保存组合键后的单独 keyUp 不得立即关屏。
    func receive(_ event: KeyboardShortcuts.EventType) {
        guard onRelease != nil else { return }
        switch event {
        case .keyDown:
            keyIsDown = true
        case .keyUp:
            guard keyIsDown else { return }
            keyIsDown = false
            onRelease?()
        }
    }

    /// 必须含 Command、Control 或 Option 和一个非修饰键；不能占用普通打字或单个功能键。
    static func isSupported(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        let modifierKeys: Set<KeyboardShortcuts.Key> = [
            .command, .rightCommand, .control, .rightControl, .option, .rightOption,
            .shift, .rightShift, .capsLock, .function
        ]
        guard (0...127).contains(shortcut.carbonKeyCode), let key = shortcut.key,
              !modifierKeys.contains(key) else { return false }
        return !shortcut.modifiers.isDisjoint(with: [.command, .control, .option])
    }

    /// 统一验证组合键规则、系统/菜单冲突，以及其他应用的 Carbon 注册占用。
    static func validate(
        _ shortcut: KeyboardShortcuts.Shortcut,
        replacing current: KeyboardShortcuts.Shortcut?
    ) -> KeyboardShortcuts.ValidationResult {
        guard isSupported(shortcut) else {
            return .disallow(reason: "不支持单个按键，请搭配 ⌘、⌃ 或 ⌥。")
        }
        if let menu = NSApp?.mainMenu, let title = conflictingMenuTitle(for: shortcut, in: menu) {
            return .disallow(reason: "与「\(title)」冲突，请换一组。")
        }
        if shortcut.isTakenBySystem {
            return .disallow(reason: "这个组合键已被系统使用，请换一组。")
        }
        guard shortcut != current else { return .allow }
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(
            UInt32(shortcut.carbonKeyCode),
            UInt32(shortcut.carbonModifiers),
            EventHotKeyID(signature: 0x534F5052, id: 1),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if let reference { UnregisterEventHotKey(reference) }
        guard result == noErr else {
            return .disallow(reason: "这个快捷键已被占用或无法注册，请换一组。")
        }
        return .allow
    }

    static func conflictingMenuTitle(for shortcut: KeyboardShortcuts.Shortcut, in menu: NSMenu) -> String? {
        for item in menu.items {
            var modifiers = item.keyEquivalentModifierMask
            let equivalent = item.keyEquivalent.lowercased()
            if equivalent != item.keyEquivalent { modifiers.insert(.shift) }
            if !equivalent.isEmpty, shortcut.nsMenuItemKeyEquivalent?.lowercased() == equivalent,
               shortcut.modifiers == modifiers {
                return item.title
            }
            if let submenu = item.submenu, let title = conflictingMenuTitle(for: shortcut, in: submenu) {
                return title
            }
        }
        return nil
    }
}
