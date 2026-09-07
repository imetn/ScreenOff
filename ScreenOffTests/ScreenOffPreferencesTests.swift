import Foundation
import KeyboardShortcuts
import Testing

/// 每个用例使用独立的 UserDefaults suite，结束后删除持久域，不触碰真实偏好。
@Suite("ScreenOffPreferences 持久化")
@MainActor
struct ScreenOffPreferencesTests {
    private struct Suite {
        let name = "com.frameflowtech.screenoff.tests.\(UUID().uuidString)"
        var defaults: UserDefaults { UserDefaults(suiteName: name)! }

        /// 清空持久域后 cfprefsd 仍会留下空 plist，一并删除，保证测试不在 ~/Library/Preferences 留痕。
        func tearDown() {
            defaults.removePersistentDomain(forName: name)
            let plist = FileManager.default
                .homeDirectoryForCurrentUser
                .appending(path: "Library/Preferences/\(name).plist")
            try? FileManager.default.removeItem(at: plist)
        }
    }

    @Test("全新安装使用保守默认值")
    func freshDefaults() {
        let suite = Suite()
        defer { suite.tearDown() }
        let preferences = ScreenOffPreferences(defaults: suite.defaults)

        #expect(preferences.keepAwake == false)
        #expect(preferences.keepAwakeWithLidClosed == false)
        #expect(preferences.autoScreenOff == false)
        #expect(preferences.autoKeyboardBacklightOff == false)
        #expect(preferences.idleDelay == IdleDelay.defaultSeconds)
        #expect(preferences.screenOffShortcut == nil)
        #expect(preferences.pendingDisplayBrightness == nil)
        #expect(preferences.pendingKeyboardBrightness == nil)
        #expect(preferences.needsIdleTracking == false)
    }

    @Test("Bundle ID 迁移保留设置、快捷键与恢复快照，不复制无关数据")
    func migratingLegacyDomainPreservesKnownPreferences() throws {
        let legacy = Suite()
        let current = Suite()
        defer { legacy.tearDown(); current.tearDown() }
        let shortcut = KeyboardShortcuts.Shortcut(.s, modifiers: [.control, .option])
        legacy.defaults.setPersistentDomain([
            "keepAwake": true,
            "keepAwakeWithLidClosed": true,
            "autoScreenOff": true,
            "autoKeyboardBacklightOff": true,
            "idleDelaySeconds": 1800,
            "screenOffShortcut": try JSONEncoder().encode(shortcut),
            "pendingDisplayBrightness": 0.45,
            "pendingKeyboardBrightness": 0.25,
            "SUEnableAutomaticChecks": false,
            "SUAutomaticallyUpdate": false,
            "unrelatedValue": "must not migrate",
        ], forName: legacy.name)

        ScreenOffPreferences.migrateLegacyPreferences(
            defaults: current.defaults, from: legacy.name, to: current.name
        )
        let preferences = ScreenOffPreferences(defaults: current.defaults)

        #expect(preferences.keepAwake)
        #expect(preferences.keepAwakeWithLidClosed)
        #expect(preferences.autoScreenOff)
        #expect(preferences.autoKeyboardBacklightOff)
        #expect(preferences.idleDelay == 1800)
        #expect(preferences.screenOffShortcut == shortcut)
        #expect(preferences.pendingDisplayBrightness == Float(0.45))
        #expect(preferences.pendingKeyboardBrightness == Float(0.25))
        #expect(current.defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool == false)
        #expect(current.defaults.object(forKey: "SUAutomaticallyUpdate") as? Bool == false)
        #expect(current.defaults.object(forKey: "unrelatedValue") == nil)
        #expect(legacy.defaults.object(forKey: "screenOffShortcut") != nil)
    }

    @Test("迁移不覆盖新域，且不会在后续启动时恢复用户已清除的值")
    func migrationDoesNotOverwriteOrRepeat() throws {
        let legacy = Suite()
        let current = Suite()
        defer { legacy.tearDown(); current.tearDown() }
        legacy.defaults.set(true, forKey: "keepAwake")
        legacy.defaults.set(try JSONEncoder().encode(
            KeyboardShortcuts.Shortcut(.s, modifiers: [.control, .option])
        ), forKey: "screenOffShortcut")
        legacy.defaults.set(0.7, forKey: "pendingDisplayBrightness")
        current.defaults.set(false, forKey: "keepAwake")

        ScreenOffPreferences.migrateLegacyPreferences(
            defaults: current.defaults, from: legacy.name, to: current.name
        )
        #expect(current.defaults.bool(forKey: "keepAwake") == false)
        current.defaults.removeObject(forKey: "screenOffShortcut")
        current.defaults.removeObject(forKey: "pendingDisplayBrightness")
        ScreenOffPreferences.migrateLegacyPreferences(
            defaults: current.defaults, from: legacy.name, to: current.name
        )

        #expect(current.defaults.object(forKey: "screenOffShortcut") == nil)
        #expect(current.defaults.object(forKey: "pendingDisplayBrightness") == nil)
        #expect(legacy.defaults.object(forKey: "pendingDisplayBrightness") != nil)
    }

    @Test("无旧域时迁移仍保留保守默认值，并不会读取真实用户设置")
    func migrationWithoutLegacyDomainKeepsFreshDefaults() {
        let legacy = Suite()
        let current = Suite()
        defer { legacy.tearDown(); current.tearDown() }
        ScreenOffPreferences.migrateLegacyPreferences(
            defaults: current.defaults, from: legacy.name, to: current.name
        )
        let preferences = ScreenOffPreferences(defaults: current.defaults)
        #expect(preferences.keepAwake == false)
        #expect(preferences.autoScreenOff == false)
        #expect(preferences.screenOffShortcut == nil)
        #expect(preferences.pendingDisplayBrightness == nil)

        legacy.defaults.set(true, forKey: "keepAwake")
        ScreenOffPreferences.migrateLegacyPreferences(
            defaults: current.defaults, from: legacy.name, to: current.name
        )
        #expect(ScreenOffPreferences(defaults: current.defaults).keepAwake == false)
    }

    @Test("合盖保持唤醒隐含保持唤醒，并写入持久层")
    func lidClosedImpliesKeepAwake() {
        let suite = Suite()
        defer { suite.tearDown() }
        let preferences = ScreenOffPreferences(defaults: suite.defaults)

        preferences.keepAwakeWithLidClosed = true

        #expect(preferences.keepAwake == true)
        #expect(suite.defaults.bool(forKey: "keepAwake") == true)
        #expect(suite.defaults.bool(forKey: "keepAwakeWithLidClosed") == true)
    }

    @Test("关闭保持唤醒时同时关闭合盖保持唤醒")
    func disablingKeepAwakeClearsLidClosed() {
        let suite = Suite()
        defer { suite.tearDown() }
        let preferences = ScreenOffPreferences(defaults: suite.defaults)
        preferences.keepAwakeWithLidClosed = true

        preferences.keepAwake = false

        #expect(preferences.keepAwakeWithLidClosed == false)
        #expect(suite.defaults.bool(forKey: "keepAwakeWithLidClosed") == false)
    }

    @Test("亮度快照写入即持久化，清空即删除键")
    func snapshotPersistsAndClears() {
        let suite = Suite()
        defer { suite.tearDown() }
        let preferences = ScreenOffPreferences(defaults: suite.defaults)

        preferences.pendingDisplayBrightness = 0.5
        preferences.pendingKeyboardBrightness = 0.3
        #expect(suite.defaults.object(forKey: "pendingDisplayBrightness") != nil)
        #expect(suite.defaults.object(forKey: "pendingKeyboardBrightness") != nil)

        preferences.pendingDisplayBrightness = nil
        preferences.pendingKeyboardBrightness = nil
        #expect(suite.defaults.object(forKey: "pendingDisplayBrightness") == nil)
        #expect(suite.defaults.object(forKey: "pendingKeyboardBrightness") == nil)
    }

    @Test("越界或非数的快照在启动时被丢弃，避免写入非法亮度", arguments: [1.7, -0.1, Double.nan, Double.infinity])
    func invalidSnapshotIsDropped(value: Double) {
        let suite = Suite()
        defer { suite.tearDown() }
        suite.defaults.set(value, forKey: "pendingDisplayBrightness")

        let preferences = ScreenOffPreferences(defaults: suite.defaults)

        #expect(preferences.pendingDisplayBrightness == nil)
    }

    @Test("旧版本留下的秒级空闲档位回落到默认值")
    func legacyIdleDelayFallsBack() {
        let suite = Suite()
        defer { suite.tearDown() }
        suite.defaults.set(5, forKey: "idleDelaySeconds")

        let preferences = ScreenOffPreferences(defaults: suite.defaults)

        #expect(preferences.idleDelay == IdleDelay.defaultSeconds)
    }

    @Test("重新启动后读回同一份偏好与快照")
    func roundTripAcrossInstances() {
        let suite = Suite()
        defer { suite.tearDown() }
        let first = ScreenOffPreferences(defaults: suite.defaults)
        first.autoScreenOff = true
        first.autoKeyboardBacklightOff = true
        first.idleDelay = 1800
        first.pendingDisplayBrightness = 0.42

        let second = ScreenOffPreferences(defaults: suite.defaults)

        #expect(second.autoScreenOff == true)
        #expect(second.autoKeyboardBacklightOff == true)
        #expect(second.idleDelay == 1800)
        #expect(second.needsIdleTracking == true)
        #expect(second.pendingDisplayBrightness.map { abs($0 - 0.42) < 0.0001 } == true)
    }

    @Test("关屏快捷键可保存、替换，并在重启后读回")
    func shortcutRoundTripAndReplacement() {
        let suite = Suite()
        defer { suite.tearDown() }
        let preferences = ScreenOffPreferences(defaults: suite.defaults)
        let first = KeyboardShortcuts.Shortcut(.s, modifiers: [.control, .option])
        let second = KeyboardShortcuts.Shortcut(.d, modifiers: [.command, .shift])

        preferences.screenOffShortcut = first
        #expect(ScreenOffPreferences(defaults: suite.defaults).screenOffShortcut == first)
        preferences.screenOffShortcut = second
        #expect(ScreenOffPreferences(defaults: suite.defaults).screenOffShortcut == second)
    }

    @Test("清除快捷键会删除持久值，重启后仍未设置")
    func clearingShortcutRemovesStoredValue() {
        let suite = Suite()
        defer { suite.tearDown() }
        let preferences = ScreenOffPreferences(defaults: suite.defaults)
        preferences.screenOffShortcut = .init(.s, modifiers: [.control, .option])

        preferences.screenOffShortcut = nil

        #expect(suite.defaults.object(forKey: "screenOffShortcut") == nil)
        #expect(ScreenOffPreferences(defaults: suite.defaults).screenOffShortcut == nil)
    }

    @Test("损坏的快捷键数据不会注册或导致启动崩溃", arguments: [
        "not-json",
        "{\"carbonKeyCode\":-1,\"carbonModifiers\":4096}",
        "{\"carbonKeyCode\":9999999999,\"carbonModifiers\":4096}",
        "{\"carbonKeyCode\":1,\"carbonModifiers\":-1}",
    ])
    func invalidShortcutIsDropped(json: String) {
        let suite = Suite()
        defer { suite.tearDown() }
        suite.defaults.set(Data(json.utf8), forKey: "screenOffShortcut")

        #expect(ScreenOffPreferences(defaults: suite.defaults).screenOffShortcut == nil)
    }
}
