import Foundation
import Observation

/// 用户偏好。仅存开关与时长，不保存任何输入、屏幕或会话内容。
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
        static let pendingDisplayBrightness = "pendingDisplayBrightness"
        static let pendingKeyboardBrightness = "pendingKeyboardBrightness"
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

    /// 未进行暗屏会话时为 nil。
    var pendingDisplayBrightness: Float? {
        didSet { store(pendingDisplayBrightness, forKey: Key.pendingDisplayBrightness) }
    }

    var pendingKeyboardBrightness: Float? {
        didSet { store(pendingKeyboardBrightness, forKey: Key.pendingKeyboardBrightness) }
    }

    init(defaults: UserDefaults = .standard) {
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
        pendingDisplayBrightness = Self.load(defaults, Key.pendingDisplayBrightness)
        pendingKeyboardBrightness = Self.load(defaults, Key.pendingKeyboardBrightness)
    }

    /// 键盘背光只跟随关屏，不单独触发空闲计时。
    var needsIdleTracking: Bool { autoScreenOff }

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
