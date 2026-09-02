import Foundation
import Testing

/// 每个用例使用独立的 UserDefaults suite，结束后删除持久域，不触碰真实偏好。
@Suite("ScreenOffPreferences 持久化")
@MainActor
struct ScreenOffPreferencesTests {
    private struct Suite {
        let name = "com.ethan.screenoff.tests.\(UUID().uuidString)"
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
        #expect(preferences.pendingDisplayBrightness == nil)
        #expect(preferences.pendingKeyboardBrightness == nil)
        #expect(preferences.needsIdleTracking == false)
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
}
