import AppKit
import Foundation
import Observation
import os

/// 全局状态机。视图只读取状态、发送意图，所有系统调用都经由这里。
///
/// 暗屏会话不变量：
/// 1. 进入会话前必须成功读到原亮度，读不到就不写入；
/// 2. 原值同时写入偏好快照，异常终止后下次启动可还原；
/// 3. 关闭功能、系统睡眠、退出与还原完成后，快照必须清空。
@MainActor
@Observable
final class ScreenOffController {
    enum ScreenState {
        case on
        case off
    }

    let preferences: ScreenOffPreferences

    @ObservationIgnored private let power = PowerAssertionService()
    @ObservationIgnored private let display = DisplayBrightnessService()
    @ObservationIgnored private let keyboard = KeyboardBacklightService()
    @ObservationIgnored private let powerSource = PowerSourceMonitor()
    @ObservationIgnored private let input = PhysicalInputMonitor()
    @ObservationIgnored private let log = Logger(subsystem: AppLog.subsystem, category: "controller")

    @ObservationIgnored private var tickTask: Task<Void, Never>?

    /// 手动关屏后只忽略一小段固定时间内的输入，且输入不会延长保护期。
    /// 这样既不会被关闭按钮本身立刻唤醒，也不会因持续移动鼠标而永远无法唤醒。
    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private var wakeAllowedAfter: ContinuousClock.Instant?
    @ObservationIgnored private let manualWakeGrace: Duration = .milliseconds(300)

    private(set) var screenState: ScreenState = .on
    private(set) var isOnACPower: Bool = true
    private(set) var displayBrightness: Float = 1
    private(set) var launchAtLogin: Bool = false
    private(set) var lastError: String?
    /// 为 false 时无法区分远程注入事件，自动关屏会被远程操作打断。
    private(set) var isInputMonitoringReliable = true

    var canControlDisplay: Bool { display.isAvailable }
    var canControlKeyboardBacklight: Bool { keyboard.isAvailable }

    init(preferences: ScreenOffPreferences) {
        self.preferences = preferences
        isOnACPower = PowerSourceMonitor.readIsOnACPower()
        launchAtLogin = LoginItemService.isEnabled
        displayBrightness = display.brightness() ?? 1
    }

    // MARK: - 生命周期

    func start() {
        log.notice("启动：display=\(self.display.isAvailable) keyboard=\(self.keyboard.isAvailable)")
        restoreLeftoverStateIfNeeded()
        observePowerSource()
        observeSystemSleep()
        startInputMonitoring()
        syncAssertions()
        refreshSchedule()
        log.notice("就绪：keepAwake=\(self.preferences.keepAwake) inputReliable=\(self.isInputMonitoringReliable)")
    }

    /// 正常退出路径：先还原屏幕与键盘，再释放全部断言。
    func shutdown() {
        tickTask?.cancel()
        tickTask = nil
        exitDimSession()
        power.releaseAll()
        powerSource.stop()
        input.stop()
    }

    private func startInputMonitoring() {
        input.start { [weak self] in
            guard let self else { return }
            handlePhysicalInput()
        }
        isInputMonitoringReliable = input.isReliable
    }

    // MARK: - 用户意图

    func setKeepAwake(_ enabled: Bool) {
        preferences.keepAwake = enabled
        syncAssertions()
    }

    func setKeepAwakeWithLidClosed(_ enabled: Bool) {
        preferences.keepAwakeWithLidClosed = enabled
        syncAssertions()
    }

    func setAutoScreenOff(_ enabled: Bool) {
        preferences.autoScreenOff = enabled
        // 配置变了就先回到干净状态，下一轮空闲再按新配置重新进入。
        if !enabled, isSessionActive { exitDimSession() }
        refreshSchedule()
    }

    func setAutoKeyboardBacklightOff(_ enabled: Bool) {
        preferences.autoKeyboardBacklightOff = enabled
        if enabled,
           screenState == .off,
           preferences.pendingKeyboardBrightness == nil,
           let current = keyboard.brightness()
        {
            preferences.pendingKeyboardBrightness = current
            if !keyboard.setBrightness(0) {
                preferences.pendingKeyboardBrightness = nil
            }
        } else if !enabled, let saved = preferences.pendingKeyboardBrightness {
            keyboard.setBrightness(saved)
            preferences.pendingKeyboardBrightness = nil
        }
    }

    func toggleScreen() {
        if screenState == .off { exitDimSession() } else { enterDimSession(manual: true) }
    }

    func setIdleDelay(_ seconds: Int) {
        preferences.idleDelay = seconds
        refreshSchedule()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        switch LoginItemService.setEnabled(enabled) {
        case .success(let actual):
            launchAtLogin = actual
            lastError = actual == enabled ? nil : "登录项：\(LoginItemService.statusDescription)"
        case .failure(let error):
            launchAtLogin = LoginItemService.isEnabled
            lastError = "登录项设置失败：\(error.localizedDescription)"
        }
    }

    /// 拖动亮度滑杆。暗屏中拖动视为用户主动干预：直接以新值结束会话。
    func setDisplayBrightness(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        displayBrightness = clamped
        guard display.setBrightness(clamped) else {
            lastError = "无法调整屏幕亮度"
            return
        }
        guard isSessionActive else { return }
        // 用户已经指定了想要的亮度，直接以新值结束会话，不再还原旧值。
        preferences.pendingDisplayBrightness = nil
        if let saved = preferences.pendingKeyboardBrightness {
            keyboard.setBrightness(saved)
            preferences.pendingKeyboardBrightness = nil
        }
        screenState = .on
        wakeAllowedAfter = nil
        refreshSchedule()
    }

    /// 打开菜单时刷新一次读数，避免用亮度快捷键改过之后显示不同步。
    func refreshReadings() {
        if screenState == .on, let value = display.brightness() { displayBrightness = value }
        isOnACPower = powerSource.isOnACPower
        launchAtLogin = LoginItemService.isEnabled
        isInputMonitoringReliable = input.isReliable
    }

    // MARK: - 暗屏会话

    /// 会话是否进行中：只要还存有任一原值快照，就说明系统状态被改过。
    var isSessionActive: Bool {
        preferences.pendingDisplayBrightness != nil || preferences.pendingKeyboardBrightness != nil
    }

    /// 进入暗屏会话。键盘背光只在屏幕确实进入暗屏时跟随关闭。
    private func enterDimSession(manual: Bool) {
        let dimDisplay = (manual || preferences.autoScreenOff)
            && screenState == .on
            && display.isAvailable
        let dimKeyboard = dimDisplay
            && preferences.autoKeyboardBacklightOff
            && preferences.pendingKeyboardBrightness == nil
            && keyboard.isAvailable
        guard dimDisplay || dimKeyboard else {
            if manual { lastError = "当前设备不支持调节内建屏幕亮度" }
            return
        }

        var didChange = false

        if dimDisplay {
            guard let current = display.brightness() else {
                lastError = "读取屏幕亮度失败，未做任何修改"
                return
            }
            preferences.pendingDisplayBrightness = current
            if display.setBrightness(0) {
                displayBrightness = current
                screenState = .off
                didChange = true
            } else {
                preferences.pendingDisplayBrightness = nil
                lastError = "无法关闭屏幕背光"
                return
            }
        }

        if dimKeyboard, let current = keyboard.brightness() {
            preferences.pendingKeyboardBrightness = current
            if keyboard.setBrightness(0) {
                didChange = true
            } else {
                preferences.pendingKeyboardBrightness = nil
            }
        }

        guard didChange else { return }

        wakeAllowedAfter = manual ? clock.now.advanced(by: manualWakeGrace) : clock.now
        lastError = nil
        log.info("进入暗屏会话 display=\(dimDisplay) keyboard=\(dimKeyboard) manual=\(manual)")
        refreshSchedule()
    }

    /// 退出会话并还原全部原值。可重复调用。
    private func exitDimSession() {
        guard isSessionActive || screenState == .off else { return }
        if let saved = preferences.pendingDisplayBrightness {
            display.setBrightness(saved)
            displayBrightness = saved
            preferences.pendingDisplayBrightness = nil
        }
        if let saved = preferences.pendingKeyboardBrightness {
            keyboard.setBrightness(saved)
            preferences.pendingKeyboardBrightness = nil
        }
        screenState = .on
        wakeAllowedAfter = nil
        log.info("退出暗屏会话")
        refreshSchedule()
    }

    /// 上次异常终止留下的亮度快照，启动时立即还原。
    private func restoreLeftoverStateIfNeeded() {
        guard isSessionActive else { return }
        log.notice("发现上次未还原的亮度快照，正在恢复")
        exitDimSession()
        displayBrightness = display.brightness() ?? displayBrightness
    }

    /// 物理输入回调：固定保护期结束后的第一次输入立即恢复，早期输入不会延长保护期。
    private func handlePhysicalInput() {
        guard
            isSessionActive,
            let wakeAllowedAfter,
            clock.now >= wakeAllowedAfter
        else { return }
        exitDimSession()
    }

    // MARK: - 断言

    private func syncAssertions() {
        power.set(.idle, active: preferences.keepAwake)
        power.set(.system, active: preferences.keepAwakeWithLidClosed && isOnACPower)

        if preferences.keepAwakeWithLidClosed, !isOnACPower {
            lastError = "合盖保持唤醒需要接通电源，当前已暂停"
        } else if lastError?.hasPrefix("合盖保持唤醒") == true {
            lastError = nil
        }
    }

    private func observePowerSource() {
        powerSource.start { [weak self] isOnAC in
            guard let self else { return }
            isOnACPower = isOnAC
            syncAssertions()
        }
    }

    private func observeSystemSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isSessionActive { self.exitDimSession() }
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 睡前的时间戳会让唤醒瞬间就满足空闲条件，必须重置。
                self.input.resetIdle()
                self.refreshSchedule()
            }
        }
    }

    // MARK: - 空闲轮询

    /// 事件驱动为主，轮询只负责「空闲到点关屏」与降级路径的兜底。
    private func refreshSchedule() {
        tickTask?.cancel()
        guard preferences.needsIdleTracking || isSessionActive else {
            tickTask = nil
            return
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = tick()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// 返回下一次轮询间隔。
    private func tick() -> TimeInterval {
        let idle = input.idleSeconds

        if isSessionActive {
            // HID 主路径由回调即时恢复；降级路径仍只能用事件源轮询兜底。
            if input.isReliable {
                return 5
            }
            if let wakeAllowedAfter, clock.now >= wakeAllowedAfter, idle < 0.5 {
                exitDimSession()
            }
            return 0.5
        }

        guard preferences.needsIdleTracking else { return 2 }

        let remaining = TimeInterval(preferences.idleDelay) - idle
        if remaining <= 0 {
            enterDimSession(manual: false)
            return 0.5
        }
        return min(max(remaining, 0.5), 5)
    }
}
