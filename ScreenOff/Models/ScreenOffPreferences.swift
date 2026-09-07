import Foundation
import KeyboardShortcuts
import Observation

/// 用户偏好。仅存开关、时长与用户指定的快捷键，不保存任何输入、屏幕或会话内容。
///
/// `pendingDisplayBrightness` / `pendingKeyboardBrightness` 是崩溃恢复快照：
/// 进入暗屏会话时写入，退出会话时清空；下次启动若仍有值，说明上次是异常终止，需要还原。
@MainActor
@Observable
final class ScreenOffPreferences {
    private enum Key {
        static let keepAwake = "keepAwake"
        static let keepAwakeWithLidClosed = "keepAwakeWithLidClosed"
        static let autoScreenOff = "autoScreenOff"
        static let idleDelay = "idleDelaySeconds"
        static let autoKeyboardBacklightOff = "autoKeyboardBacklightOff"
        static let screenOffShortcut = "screenOffShortcut"
        static let pendingDisplayBrightness = "pendingDisplayBrightness"
        static let pendingKeyboardBrightness = "pendingKeyboardBrightness"
        static let migratedLegacyDomain = "migratedLegacyPreferencesDomain"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var keepAwake: Bool {
        didSet {
            defaults.set(keepAwake, forKey: Key.keepAwake)
            if !keepAwake, keepAwakeWithLidClosed { keepAwakeWithLidClosed = false }
        }
    }

    var keepAwakeWithLidClosed: Bool {
        didSet {
            defaults.set(keepAwakeWithLidClosed, forKey: Key.keepAwakeWithLidClosed)
            if keepAwakeWithLidClosed, !keepAwake { keepAwake = true }
        }
    }

    var autoScreenOff: Bool {
        didSet { defaults.set(autoScreenOff, forKey: Key.autoScreenOff) }
    }

    var autoKeyboardBacklightOff: Bool {
        didSet { defaults.set(autoKeyboardBacklightOff, forKey: Key.autoKeyboardBacklightOff) }
    }

    /// 空闲多久后触发，单位秒。取值见 `IdleDelay.options`。
    var idleDelay: Int {
        didSet { defaults.set(idleDelay, forKey: Key.idleDelay) }
    }

    /// 默认不分配全局组合键，避免占用用户已有的快捷键。
    var screenOffShortcut: KeyboardShortcuts.Shortcut? {
        didSet {
            if let screenOffShortcut, let data = try? JSONEncoder().encode(screenOffShortcut) {
                defaults.set(data, forKey: Key.screenOffShortcut)
            } else {
                defaults.removeObject(forKey: Key.screenOffShortcut)
            }
        }
    }

    /// 未进行暗屏会话时为 nil。
    var pendingDisplayBrightness: Float? {
        didSet { store(pendingDisplayBrightness, forKey: Key.pendingDisplayBrightness) }
    }

    var pendingKeyboardBrightness: Float? {
        didSet { store(pendingKeyboardBrightness, forKey: Key.pendingKeyboardBrightness) }
    }

    init(defaults: UserDefaults = .standard) {
        if defaults === UserDefaults.standard,
           Bundle.main.bundleIdentifier == "com.frameflowtech.screenoff" {
            Self.migrateLegacyPreferences(defaults: defaults)
        }
        self.defaults = defaults
        defaults.register(defaults: [
            Key.keepAwake: false,
            Key.keepAwakeWithLidClosed: false,
            Key.autoScreenOff: false,
            Key.autoKeyboardBacklightOff: false,
            Key.idleDelay: IdleDelay.defaultSeconds,
        ])

        keepAwake = defaults.bool(forKey: Key.keepAwake)
        keepAwakeWithLidClosed = defaults.bool(forKey: Key.keepAwakeWithLidClosed)
        autoScreenOff = defaults.bool(forKey: Key.autoScreenOff)
        autoKeyboardBacklightOff = defaults.bool(forKey: Key.autoKeyboardBacklightOff)
        idleDelay = IdleDelay.seconds(at: IdleDelay.index(of: defaults.integer(forKey: Key.idleDelay)))
        screenOffShortcut = Self.loadShortcut(defaults)
        pendingDisplayBrightness = Self.load(defaults, Key.pendingDisplayBrightness)
        pendingKeyboardBrightness = Self.load(defaults, Key.pendingKeyboardBrightness)
    }

    /// 键盘背光只跟随关屏，不单独触发空闲计时。
    var needsIdleTracking: Bool { autoScreenOff }

    /// 更换 Bundle ID 时仅迁移本 App 的设置；不覆盖新域、不复制系统授权或更新缓存。
    /// 恢复快照也需迁移，避免旧进程异常退出后失去还原亮度的依据。
    static func migrateLegacyPreferences(
        defaults: UserDefaults,
        from legacyDomain: String = "com.ethan.screenoff",
        to currentDomain: String = "com.frameflowtech.screenoff"
    ) {
        guard legacyDomain != currentDomain else { return }
        var current = defaults.persistentDomain(forName: currentDomain) ?? [:]
        guard current[Key.migratedLegacyDomain] as? Bool != true else { return }
        let legacy = defaults.persistentDomain(forName: legacyDomain) ?? [:]
        let keys = [
            Key.keepAwake, Key.keepAwakeWithLidClosed, Key.autoScreenOff,
            Key.autoKeyboardBacklightOff, Key.idleDelay, Key.screenOffShortcut,
            Key.pendingDisplayBrightness, Key.pendingKeyboardBrightness,
            "SUEnableAutomaticChecks", "SUAutomaticallyUpdate",
        ]
        for key in keys where current[key] == nil {
            current[key] = legacy[key]
        }
        // 即使旧域不存在也记录完成，避免日后恢复备份时重新导入已清除的快捷键或快照。
        current[Key.migratedLegacyDomain] = true
        defaults.setPersistentDomain(current, forName: currentDomain)
    }

    private static func loadShortcut(_ defaults: UserDefaults) -> KeyboardShortcuts.Shortcut? {
        guard
            let data = defaults.data(forKey: Key.screenOffShortcut),
            let shortcut = try? JSONDecoder().decode(KeyboardShortcuts.Shortcut.self, from: data),
            (0...127).contains(shortcut.carbonKeyCode),
            shortcut.carbonModifiers >= 0,
            shortcut == KeyboardShortcuts.Shortcut(
                carbonKeyCode: shortcut.carbonKeyCode,
                carbonModifiers: shortcut.carbonModifiers
            )
        else { return nil }
        return shortcut
    }

    private func store(_ value: Float?, forKey key: String) {
        if let value {
            defaults.set(Double(value), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func load(_ defaults: UserDefaults, _ key: String) -> Float? {
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = Float(defaults.double(forKey: key))
        guard value.isFinite, value >= 0, value <= 1 else { return nil }
        return value
    }
}
