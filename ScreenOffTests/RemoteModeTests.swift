import Foundation
import Testing

@Suite("远程模式事务与恢复")
@MainActor
struct RemoteModeTests {
    @Test("背光组合选项兼容已有配置，不产生仅键盘的无效远程模式")
    func backlightOptionsPreserveStoredFormat() throws {
        var configuration = RemoteModeConfiguration(dimDisplay: false, dimKeyboard: true)
        #expect(configuration.backlightSetting == .unchanged)
        for choice in RemoteModeConfiguration.BacklightSetting.allCases {
            configuration.backlightSetting = choice
            let saved = try JSONEncoder().encode(configuration)
            let restored = try JSONDecoder().decode(RemoteModeConfiguration.self, from: saved)
            #expect(restored.backlightSetting == choice)
            #expect(restored.dimDisplay == (choice != .unchanged))
            #expect(restored.dimKeyboard == (choice == .displayAndKeyboard))
        }
    }

    private final class Environment: RemoteModeEnvironment {
        var dockHidden = true
        var dockSize = 0.35
        var stage: Bool? = nil
        var failCapture = false
        var failApply = false
        var failStageRestore = false
        var captureCount = 0
        var applied = 0
        var onApply: () -> Void = {}
        var restores: [RemoteModeSnapshot] = []

        func capture(_ configuration: RemoteModeConfiguration) async throws -> RemoteModeSnapshot {
            captureCount += 1
            if failCapture { throw RemoteModeError.unavailable("read failed") }
            return .init(dock: .init(autohide: dockHidden, size: dockSize), stageManager: .init(value: stage))
        }
        func apply(_ configuration: RemoteModeConfiguration, snapshot: RemoteModeSnapshot) async throws {
            onApply()
            applied += 1
            dockHidden = false
            dockSize = configuration.dockSize
            if failApply { throw RemoteModeError.unavailable("partial apply failed") }
            stage = true
        }
        func restore(_ snapshot: RemoteModeSnapshot) async -> RemoteModeRestoreResult {
            restores.append(snapshot)
            var pending = snapshot
            if let dock = snapshot.dock {
                if let hidden = dock.autohide { dockHidden = hidden }
                if let size = dock.size { dockSize = size }
                pending.dock = nil
            }
            if let original = snapshot.stageManager, !failStageRestore {
                stage = original.value
                pending.stageManager = nil
            }
            return .init(remaining: pending, errors: failStageRestore ? ["stage restore failed"] : [])
        }
    }

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let name = "com.frameflowtech.screenoff.tests.remote.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name); defaults.synchronize() }
        try await body(defaults)
    }

    @Test("台前调度原本无键时恢复成关闭，而不是只删键")
    func stageManagerRestoreTarget() {
        // 键缺失的等价行为是关闭。若恢复时只把键删掉，WindowManager 不会退出台前调度，
        // 随后还会把运行中的状态写回偏好，用户看到的就是开关没有恢复。
        #expect(RemoteModeSnapshot.StageManager(value: nil).restoreTarget == false)
        #expect(RemoteModeSnapshot.StageManager(value: false).restoreTarget == false)
        #expect(RemoteModeSnapshot.StageManager(value: true).restoreTarget == true)
    }

    @Test("修改前保存原值，重复开启不覆盖快照，关闭后恢复缺省键")
    func transaction() async throws {
        try await withDefaults { defaults in
            let environment = Environment()
            environment.onApply = { #expect(defaults.data(forKey: RemoteModeSession.snapshotKey) != nil) }
            let session = RemoteModeSession(environment: environment, defaults: defaults)
            await session.activate(.init())
            #expect(session.isActive)
            #expect(environment.dockSize == 0.8)
            #expect(environment.stage == true)
            await session.activate(.init(dockSize: 0.5))
            #expect(environment.applied == 1)
            let persisted = try JSONDecoder().decode(RemoteModeSnapshot.self, from: #require(defaults.data(forKey: RemoteModeSession.snapshotKey)))
            #expect(persisted.dock?.size == 0.35)
            #expect(persisted.stageManager != nil && persisted.stageManager?.value == nil)
            await session.deactivate()
            #expect(session.state == .inactive)
            #expect(environment.dockHidden && environment.dockSize == 0.35)
            #expect(environment.stage == nil)
            #expect(defaults.object(forKey: RemoteModeSession.snapshotKey) == nil)
        }
    }

    @Test("读取失败不写系统，部分应用失败立即回滚")
    func failures() async {
        await withDefaults { defaults in
            let environment = Environment()
            let session = RemoteModeSession(environment: environment, defaults: defaults)
            environment.failCapture = true
            await session.activate(.init())
            #expect(environment.applied == 0 && environment.restores.isEmpty)
            #expect(defaults.object(forKey: RemoteModeSession.snapshotKey) == nil)
            environment.failCapture = false
            environment.failApply = true
            await session.activate(.init())
            #expect(session.state == .inactive)
            #expect(environment.dockSize == 0.35 && environment.dockHidden)
            #expect(session.error?.contains("partial apply failed") == true)
        }
    }

    @Test("异常重启只恢复；部分恢复失败只重试剩余项目")
    func crashAndPartialRecovery() async throws {
        try await withDefaults { defaults in
            let environment = Environment()
            let original = RemoteModeSession(environment: environment, defaults: defaults)
            await original.activate(.init())
            let restarted = RemoteModeSession(environment: environment, defaults: defaults)
            #expect(restarted.needsRecovery && !restarted.isActive)
            environment.failStageRestore = true
            await restarted.deactivate()
            #expect(restarted.needsRecovery)
            let remaining = try JSONDecoder().decode(RemoteModeSnapshot.self, from: #require(defaults.data(forKey: RemoteModeSession.snapshotKey)))
            #expect(remaining.dock == nil && remaining.stageManager != nil)
            environment.dockSize = 0.6 // user's edit after this component has already been restored
            await restarted.activate(.init())
            #expect(environment.captureCount == 1)
            environment.failStageRestore = false
            await restarted.deactivate()
            #expect(restarted.state == .inactive && environment.stage == nil)
            #expect(environment.dockSize == 0.6)
        }
    }

    @Test("损坏的快照阻止新会话且保留原记录")
    func corruptSnapshot() async {
        await withDefaults { defaults in
            let corrupt = Data("invalid".utf8)
            defaults.set(corrupt, forKey: RemoteModeSession.snapshotKey)
            let environment = Environment()
            let session = RemoteModeSession(environment: environment, defaults: defaults)
            await session.activate(.init())
            await session.deactivate()
            #expect(session.needsRecovery && environment.captureCount == 0)
            #expect(defaults.data(forKey: RemoteModeSession.snapshotKey) == corrupt)
        }
    }
}

@Suite("显示模式与电源策略")
struct RemoteModePolicyTests {
    private func mode(_ width: Int, pixels: Int, hz: Double = 60, isDefault: Bool = false) -> RemoteDisplayMode {
        .init(width: width, height: 900, pixelWidth: pixels, pixelHeight: pixels > width ? 1800 : 900,
              refreshRate: hz, modeID: 1, isDefault: isDefault)
    }

    @Test("按系统标记选默认 Retina 模式，不按机型或最大分辨率猜测")
    func displaySelection() {
        let low = mode(1512, pixels: 1512, isDefault: true)
        let retina = mode(1512, pixels: 3024, hz: 120, isDefault: true)
        let large = mode(2056, pixels: 4112)
        #expect(RemoteDisplayMode.recommended(in: [low, large, retina]) == retina)
        #expect(RemoteDisplayMode.recommended(in: [large]) == nil)
        #expect(!retina.matches(low))
        #expect(!retina.matches(mode(1512, pixels: 3024, hz: 60)))
    }

    @Test("自动关屏拥有显示器计时，关闭后交还系统；远程模式同时防止整机空闲睡眠")
    func powerPolicy() {
        let idleOnly = ScreenOffPowerPolicy(keepAwake: true, automaticScreenOff: false, canControlDisplay: true, remoteMode: false, dimSession: false)
        #expect(idleOnly.preventSystemIdleSleep && !idleOnly.preventDisplayIdleSleep)
        let timer = ScreenOffPowerPolicy(keepAwake: false, automaticScreenOff: true, canControlDisplay: true, remoteMode: false, dimSession: false)
        #expect(timer.preventDisplayIdleSleep)
        let remote = ScreenOffPowerPolicy(keepAwake: false, automaticScreenOff: false, canControlDisplay: true, remoteMode: true, dimSession: false)
        #expect(remote.preventDisplayIdleSleep && remote.preventSystemIdleSleep)
        let off = ScreenOffPowerPolicy(keepAwake: false, automaticScreenOff: false, canControlDisplay: true, remoteMode: false, dimSession: false)
        #expect(!off.preventDisplayIdleSleep && !off.preventSystemIdleSleep)
        let unsupported = ScreenOffPowerPolicy(keepAwake: false, automaticScreenOff: true, canControlDisplay: false, remoteMode: false, dimSession: false)
        #expect(!unsupported.preventDisplayIdleSleep)
        let dark = ScreenOffPowerPolicy(keepAwake: false, automaticScreenOff: false, canControlDisplay: true, remoteMode: false, dimSession: true)
        #expect(dark.preventDisplayIdleSleep)
    }

    @Test("Dock 大小验证")
    func dockSize() {
        #expect(RemoteModeConfiguration.dockSizeMatches(actual: 0.79464287, requested: 0.8))
        #expect(!RemoteModeConfiguration.dockSizeMatches(actual: 0.75, requested: 0.8))
        #expect(!RemoteModeConfiguration.dockSizeMatches(actual: .nan, requested: 0.8))
        #expect(RemoteModeConfiguration(dockSize: .nan).validated.dockSize == 0.8)
        #expect(RemoteModeConfiguration(dockSize: 2).validated.dockSize == 1)
        #expect(RemoteModeConfiguration(dockSize: -1).validated.dockSize == 0)
    }
}
