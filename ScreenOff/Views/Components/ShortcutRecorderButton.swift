import AppKit
import KeyboardShortcuts
import SwiftUI

/// 真正的按钮式录制入口；仅在用户点击后接收当前窗口的按键，不使用文本输入框。
struct ShortcutRecorderButton: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcuts.Shortcut?
    let validate: (KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.ValidationResult
    let onRecordingMessage: (String?) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        RecorderButton(frame: .zero)
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onChange = { shortcut = $0 }
        button.validate = validate
        button.onRecordingMessage = onRecordingMessage
        button.updateShortcut(shortcut)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RecorderButton, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: max(96, size.width), height: size.height)
    }

    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) {
        button.stopRecording()
    }

    final class RecorderButton: NSButton {
        var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?
        var validate: ((KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.ValidationResult)?
        var onRecordingMessage: ((String?) -> Void)?
        private var shortcut: KeyboardShortcuts.Shortcut?
        private var eventMonitor: Any?
        private var resignObserver: NSObjectProtocol?
        private var previousHotKeysEnabled: Bool?

        override var acceptsFirstResponder: Bool { true }

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            font = .systemFont(ofSize: NSFont.systemFontSize)
            target = self
            action = #selector(toggleRecording)
            setAccessibilityIdentifier("screenOffShortcutRecorder")
            setAccessibilityLabel("关闭屏幕快捷键")
            updateAppearance()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func updateShortcut(_ value: KeyboardShortcuts.Shortcut?) {
            if shortcut != value {
                stopRecording()
                shortcut = value
            }
            updateAppearance()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow !== window { stopRecording() }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidHide() {
            stopRecording()
            super.viewDidHide()
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { stopRecording() }
            return resigned
        }

        @objc private func toggleRecording() {
            guard eventMonitor == nil else {
                stopRecording()
                return
            }
            guard let window, window.makeFirstResponder(self) else { return }

            previousHotKeysEnabled = KeyboardShortcuts.isEnabled
            KeyboardShortcuts.isEnabled = false
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                let shouldPassThrough = MainActor.assumeIsolated {
                    guard let self else { return true }
                    return self.receive(event) != nil
                }
                return shouldPassThrough ? event : nil
            }
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopRecording() }
            }
            updateAppearance()
            showMessage("按下含 ⌘、⌃ 或 ⌥ 的组合键；Esc 取消。")
        }

        func stopRecording() {
            guard let previousHotKeysEnabled else { return }
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            eventMonitor = nil
            resignObserver = nil
            self.previousHotKeysEnabled = nil
            KeyboardShortcuts.isEnabled = previousHotKeysEnabled
            updateAppearance()
            showMessage(nil)
        }

        private func receive(_ event: NSEvent) -> NSEvent? {
            guard event.window === window else {
                stopRecording()
                return event
            }
            if event.type == .keyUp { return nil }
            guard event.type == .keyDown else {
                if !bounds.contains(convert(event.locationInWindow, from: nil)) {
                    stopRecording()
                }
                return event
            }
            guard !event.isARepeat, let candidate = KeyboardShortcuts.Shortcut(event: event) else { return nil }
            let modifiers = candidate.modifiers.intersection([.command, .control, .option, .shift])
            if candidate.key == .escape, modifiers.isEmpty {
                stopRecording()
                return nil
            }
            if candidate.key == .tab, modifiers.subtracting(.shift).isEmpty {
                stopRecording()
                return event
            }
            switch validate?(candidate) ?? .disallow(reason: "暂时无法设置快捷键，请重试。") {
            case .allow:
                stopRecording()
                onChange?(candidate)
            case .disallow(let reason):
                NSSound.beep()
                showMessage(reason)
            }
            return nil
        }

        private func updateAppearance() {
            let recording = eventMonitor != nil
            title = recording ? "按下组合键…" : (shortcut?.description ?? "未设置")
            contentTintColor = recording ? .controlAccentColor : nil
            toolTip = recording ? "按下组合键保存；按 Esc 或点击其他位置取消。" : "点击设置关闭屏幕快捷键。"
            setAccessibilityValue(title)
            setAccessibilityHelp(toolTip)
            invalidateIntrinsicContentSize()
        }

        private func showMessage(_ message: String?) {
            // 拆除或更新原生控件时也可能取消录制，避免在 SwiftUI 更新过程中回写状态。
            let callback = onRecordingMessage
            DispatchQueue.main.async { callback?(message) }
        }
    }
}
