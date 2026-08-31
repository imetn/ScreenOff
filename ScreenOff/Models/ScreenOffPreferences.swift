import Foundation
import Observation

enum ScreenOffDelay: Int, CaseIterable, Identifiable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .fiveSeconds: "5 秒"
        case .tenSeconds: "10 秒"
        case .thirtySeconds: "30 秒"
        case .oneMinute: "1 分钟"
        case .fiveMinutes: "5 分钟"
        }
    }
}

@MainActor
@Observable
final class ScreenOffPreferences {
    private enum Key {
        static let keepAwake = "keepAwake"
        static let keepAwakeWithLidClosed = "keepAwakeWithLidClosed"
        static let autoScreenOff = "autoScreenOff"
        static let screenOffDelay = "screenOffDelay"
        static let turnOffKeyboardBacklight = "turnOffKeyboardBacklight"
        static let launchAtLogin = "launchAtLogin"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var keepAwake: Bool {
        didSet {
            defaults.set(keepAwake, forKey: Key.keepAwake)
            if !keepAwake, keepAwakeWithLidClosed {
                keepAwakeWithLidClosed = false
            }
        }
    }

    var keepAwakeWithLidClosed: Bool {
        didSet {
            defaults.set(keepAwakeWithLidClosed, forKey: Key.keepAwakeWithLidClosed)
            if keepAwakeWithLidClosed, !keepAwake {
                keepAwake = true
            }
        }
    }

    var autoScreenOff: Bool {
        didSet { defaults.set(autoScreenOff, forKey: Key.autoScreenOff) }
    }

    var screenOffDelay: ScreenOffDelay {
        didSet { defaults.set(screenOffDelay.rawValue, forKey: Key.screenOffDelay) }
    }

    var turnOffKeyboardBacklight: Bool {
        didSet {
            defaults.set(turnOffKeyboardBacklight, forKey: Key.turnOffKeyboardBacklight)
        }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.keepAwake: false,
            Key.keepAwakeWithLidClosed: false,
            Key.autoScreenOff: false,
            Key.screenOffDelay: ScreenOffDelay.tenSeconds.rawValue,
            Key.turnOffKeyboardBacklight: true,
            Key.launchAtLogin: false,
        ])

        keepAwake = defaults.bool(forKey: Key.keepAwake)
        keepAwakeWithLidClosed = defaults.bool(forKey: Key.keepAwakeWithLidClosed)
        autoScreenOff = defaults.bool(forKey: Key.autoScreenOff)
        screenOffDelay = ScreenOffDelay(
            rawValue: defaults.integer(forKey: Key.screenOffDelay)
        ) ?? .tenSeconds
        turnOffKeyboardBacklight = defaults.bool(forKey: Key.turnOffKeyboardBacklight)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
    }

    var configurationSummary: String {
        if keepAwakeWithLidClosed {
            return "已配置合盖保持唤醒"
        }
        if keepAwake {
            return "已配置保持唤醒"
        }
        if autoScreenOff {
            return "已配置自动暗屏"
        }
        return "未启用自动控制"
    }
}

