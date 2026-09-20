import AppKit
import Foundation
import KeyboardShortcuts
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
    let remoteMode: RemoteModeSession
    let inputLock = InputLockService()
    let lidWake = LidWakeService()
    private(set) var defaultDisplayModeDescription = RemoteDesktopService.defaultDisplayDescription()
    @ObservationIgnored private var remoteTask: Task<Void, Never>?
    @ObservationIgnored private var remoteOwnsDimSession = false
    @ObservationIgnored private var shuttingDown = false
    /// 断言失败的提示由 syncAssertions 自己清除，不依赖文案内容。
    @ObservationIgnored private var assertionErrorPresented = false

    @ObservationIgnored private let power = PowerAssertionService()
    @ObservationIgnored private let display = DisplayBrightnessService()
    @ObservationIgnored private let keyboard = KeyboardBacklightService()
    @ObservationIgnored private let powerSource = PowerSourceMonitor()
    @ObservationIgnored private let input = PhysicalInputMonitor()
    @ObservationIgnored private let screenOffShortcut = ScreenOffShortcutService()
    @ObservationIgnored private let remoteModeShortcut = ScreenOffShortcutService()
    @ObservationIgnored private let inputLockOverlay = InputLockOverlayController()
    @ObservationIgnored private let log = Logger(subsystem: AppLog.subsystem, category: "controller")

    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var sleepObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var screenParametersObserver: NSObjectProtocol?

    /// 手动关屏后只忽略一小段固定时间内的输入，且输入不会延长保护期。
    /// 这样既不会被关闭按钮本身立刻唤醒，也不会因持续移动鼠标而永远无法唤醒。
    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private var wakeAllowedAfter: ContinuousClock.Instant?
    @ObservationIgnored private let manualWakeGrace: Duration = .milliseconds(300)

    /// 远程点击「点亮屏幕」是一次明确的用户意图，但不会被 HID 监控记作本机输入。
    /// 因此单独从这次操作重新计算自动关屏倒计时，避免刚点亮就被旧空闲时间再次关暗。
    @ObservationIgnored private var manualWakeAutoOffAllowedAfter: ContinuousClock.Instant?

    /// 没有有效快照时的保守点亮亮度；例如 App 启动时屏幕已经是 0。
    @ObservationIgnored private let defaultWakeBrightness: Float = 0.3
    @ObservationIgnored private var lastLitDisplayBrightness: Float = 0.3

    /// 空闲到点但进不了会话（例如合盖后内建屏离线）时的重试间隔，避免 0.5 秒一次的空转。
    @ObservationIgnored private let failedEntryRetryInterval: TimeInterval = 10

    private(set) var isOnACPower: Bool = true
    private(set) var displayBrightness: Float = 1
    private(set) var launchAtLogin: Bool = false
    private(set) var lastError: String?
    /// 合盖保持唤醒的失败原因，单列一个属性而不是并进 `lastError`：
    /// `lastError` 显示在「远程」页，守护进程的问题出现在那里会让人找不着北。
    private(set) var lidWakeError: String?
    /// 为 false 时无法区分远程注入事件，自动关屏会被远程操作打断。
    private(set) var isInputMonitoringReliable = false
    /// 用户已在系统设置中明确拒绝「输入监控」，只能引导其手动开启。
    private(set) var isInputMonitoringDenied = false

    var canControlDisplay: Bool { display.isAvailable }
    var canControlKeyboardBacklight: Bool { keyboard.isAvailable }
    /// 菜单按钮只翻译屏幕真实亮度，不再翻译内部会话状态。
    var screenState: ScreenState { Self.isDark(displayBrightness) ? .off : .on }

    init(preferences: ScreenOffPreferences) {
        self.preferences = preferences
        remoteMode = RemoteModeSession(environment: RemoteDesktopService(), defaults: preferences.storage)
        isOnACPower = PowerSourceMonitor.readIsOnACPower()
        launchAtLogin = LoginItemService.isEnabled
        displayBrightness = display.brightness() ?? 1
        if !Self.isDark(displayBrightness) {
            lastLitDisplayBrightness = displayBrightness
        }
    }

    // MARK: - 生命周期

    func start() {
        log.notice("启动：display=\(self.display.isAvailable) keyboard=\(self.keyboard.isAvailable)")
        restoreLeftoverStateIfNeeded()
        if remoteMode.needsRecovery { restoreRemoteMode() }
        observeInputLock()
        reconcileLidWake()
        observePowerSource()
        observeSystemSleep()
        // 只有已开启自动关屏的用户才在启动时申请授权；其他人首次开启该开关时再申请。
        syncInputMonitoring(requestAccess: preferences.needsIdleTracking)
        syncAssertions()
        syncScreenOffShortcut()
        syncRemoteModeShortcut()
        refreshSchedule()
        log.notice("就绪：keepAwake=\(self.preferences.keepAwake) inputReliable=\(self.isInputMonitoringReliable)")
    }

    /// 正常退出路径：先还原屏幕与键盘，再释放全部断言。
    func shutdown() {
        shuttingDown = true
        lidWake.shutdown()
        inputLock.unlock(showRestoredHint: false)
        inputLockOverlay.dismissNow()
        screenOffShortcut.stop()
        remoteModeShortcut.stop()
        tickTask?.cancel()
        tickTask = nil
        if isSessionActive { exitDimSession() }
        power.releaseAll()
        powerSource.stop()
        input.stop()
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.forEach { center.removeObserver($0) }
        sleepObservers = []
        if let screenParametersObserver { NotificationCenter.default.removeObserver(screenParametersObserver) }
        screenParametersObserver = nil
    }

    /// 启动对账：系统里残留的 `SleepDisabled` 必须与用户偏好一致，
    /// 否则上一次异常退出会留下一台合盖永不睡眠的 Mac。
    private func reconcileLidWake() {
        lidWake.refresh()
        let wanted = preferences.keepAwakeWithLidClosed && isOnACPower && preferences.keepAwake
        guard wanted != lidWake.isSleepDisabled else { return }
        if wanted, lidWake.readiness != .ready { 
            preferences.keepAwakeWithLidClosed = false
            return
        }
        Task { await applyLidWake(wanted) }
    }

    /// 打开或重试 HID 订阅。`requestAccess` 为真且系统尚未询问过时弹出授权；
    /// 授权状态变化只在这里落到界面状态。
    private func syncInputMonitoring(requestAccess: Bool) {
        if requestAccess, input.accessStatus == .unknown {
            input.requestAccess()
        }
        let wasReliable = input.isReliable
        input.start { [weak self] in
            guard let self else { return }
            handlePhysicalInput()
        }
        isInputMonitoringReliable = input.isReliable
        isInputMonitoringDenied = input.accessStatus == .denied
        if wasReliable != input.isReliable {
            log.notice("输入监控路径变化 reliable=\(self.isInputMonitoringReliable)")
            refreshSchedule()
        }
    }

    // MARK: - 用户意图

    func setKeepAwake(_ enabled: Bool) {
        preferences.keepAwake = enabled
        // 关掉保持唤醒就不该留下合盖不睡的系统设置。
        if !enabled { Task { await applyLidWake(false) } }
        syncAssertions()
    }

    /// 权限可能在系统设置里被改动，界面重新出现时必须重新查询，
    /// 否则用户授权完切回来，状态还停在「未授权」。
    func refreshPermissions() {
        syncInputMonitoring(requestAccess: false)
        inputLock.refreshAccess()
        lidWake.refresh()
    }

    /// 合盖保持唤醒：写的是系统级 `SleepDisabled`，只在接通电源时允许开启。
    func setKeepAwakeWithLidClosed(_ enabled: Bool) {
        guard !enabled || isOnACPower else {
            lidWakeError = String(localized: "电池供电时不能合盖保持唤醒，请先接通电源")
            return
        }
        lidWakeError = nil
        lidWake.refresh()
        if enabled, lidWake.readiness == .notRegistered, !lidWake.registerHelper() {
            lidWakeError = lidWake.lastError
            return
        }
        Task { await applyLidWake(enabled) }
    }

    /// 统一的写入口：成功才落偏好，失败把系统真实状态回写到界面。
    private func applyLidWake(_ enabled: Bool) async {
        let succeeded = await lidWake.setEnabled(enabled)
        if succeeded {
            preferences.keepAwakeWithLidClosed = enabled
            lidWakeError = nil
        } else {
            preferences.keepAwakeWithLidClosed = lidWake.isSleepDisabled
            lidWakeError = lidWake.lastError
        }
    }

    /// Serializes entry/exit; a second click cannot overwrite the original settings snapshot.
    func toggleRemoteMode() {
        guard remoteTask == nil, !shuttingDown else { return }
        if remoteMode.isActive || remoteMode.needsRecovery { restoreRemoteMode(); return }
        let configuration = preferences.remoteModeConfiguration.validated
        if configuration.dimDisplay, !canControlDisplay {
            lastError = String(localized: "当前无法调节内建屏幕，请关闭远程模式中的背光选项后重试。")
            return
        }
        if configuration.dimDisplay { syncInputMonitoring(requestAccess: true) }
        remoteTask = Task { [weak self] in
            guard let self else { return }
            await remoteMode.activate(configuration)
            if remoteMode.isActive {
                guard syncAssertions() else {
                    let failure = lastError
                    await remoteMode.deactivate()
                    refreshSchedule()
                    lastError = failure
                    remoteTask = nil
                    return
                }
                remoteOwnsDimSession = configuration.dimDisplay && !isSessionActive && screenState == .on
                if remoteOwnsDimSession {
                    enterDimSession(manual: true, keyboardOverride: configuration.dimKeyboard)
                    if !isSessionActive {
                        let failure = lastError ?? String(localized: "关闭屏幕背光失败")
                        await remoteMode.deactivate()
                        remoteOwnsDimSession = false
                        lastError = failure
                    }
                }
            }
            syncAssertions()
            refreshSchedule()
            remoteTask = nil
        }
    }

    private func restoreRemoteMode() {
        guard remoteTask == nil else { return }
        remoteTask = Task { [weak self] in
            guard let self else { return }
            await remoteMode.deactivate()
            if remoteOwnsDimSession {
                exitDimSession(restartAutoOffCountdown: true)
                remoteOwnsDimSession = false
            }
            syncAssertions()
            refreshSchedule()
            remoteTask = nil
        }
    }

    /// AppDelegate waits for this before terminating so system settings restoration finishes.
    func prepareToQuit() async {
        shuttingDown = true
        await lidWake.setEnabled(false)
        lidWake.shutdown()
        inputLock.unlock(showRestoredHint: false)
        inputLockOverlay.dismissNow()
        tickTask?.cancel()
        await remoteTask?.value
        await remoteMode.deactivate()
        if isSessionActive { exitDimSession() }
    }

    func setAutoScreenOff(_ enabled: Bool) {
        preferences.autoScreenOff = enabled
        if !enabled { manualWakeAutoOffAllowedAfter = nil }
        // 配置变了就先回到干净状态，下一轮空闲再按新配置重新进入。
        if !enabled, isSessionActive { exitDimSession() }
        // 首次开启时用户正在本机操作、屏幕点亮，是申请「输入监控」授权的合适时机。
        if enabled { syncInputMonitoring(requestAccess: true) }
        refreshSchedule()
    }

    func setShowsInputLockOverlay(_ enabled: Bool) {
        preferences.showsInputLockOverlay = enabled
        if inputLock.isLocked {
            if enabled { inputLockOverlay.present(service: inputLock) } else { inputLockOverlay.dismissNow() }
        }
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

    /// 关闭输入：锁定本机键鼠，同时熄屏——锁输入的场景里屏幕不该继续亮着。
    /// 解锁后恢复原亮度，浮层是锁定期间唯一的出口提示。
    func toggleInputLock() {
        if inputLock.isLocked {
            inputLock.unlock()
            return
        }
        guard inputLock.lock() else {
            if let message = inputLock.lastError { lastError = message }
            return
        }
        reconcileDisplayReading()
        if screenState == .on { enterDimSession(manual: true) }
    }

    /// 锁定状态只能由服务通知：解锁手势发生在事件回调里，控制器无从轮询。
    private func observeInputLock() {
        inputLock.onLockChanged = { [weak self] locked in
            guard let self else { return }
            if locked {
                if preferences.showsInputLockOverlay {
                    inputLockOverlay.present(service: inputLock)
                }
            } else {
                inputLockOverlay.dismissAfterHint()
                if isSessionActive { exitDimSession(restartAutoOffCountdown: true) }
            }
        }
    }

    func toggleScreen() {
        reconcileDisplayReading()
        if screenState == .off {
            exitDimSession(restartAutoOffCountdown: true)
        } else {
            enterDimSession(manual: true)
        }
    }

    /// 全局快捷键只关屏，不作为开关；已关屏时再次触发不主动点亮。
    func turnScreenOff() {
        reconcileDisplayReading()
        guard screenState == .on else { return }
        enterDimSession(manual: true)
    }

    func setScreenOffShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        guard preferences.screenOffShortcut != shortcut else { return }
        guard shortcut == nil || shortcut != preferences.remoteModeShortcut else { return }
        preferences.screenOffShortcut = shortcut
        syncScreenOffShortcut()
    }

    func validateScreenOffShortcut(_ shortcut: KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.ValidationResult {
        ScreenOffShortcutService.validate(
            shortcut, replacing: preferences.screenOffShortcut, excluding: preferences.remoteModeShortcut
        )
    }

    func setRemoteModeShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        guard preferences.remoteModeShortcut != shortcut else { return }
        guard shortcut == nil || shortcut != preferences.screenOffShortcut else { return }
        preferences.remoteModeShortcut = shortcut
        syncRemoteModeShortcut()
    }

    func validateRemoteModeShortcut(_ shortcut: KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.ValidationResult {
        ScreenOffShortcutService.validate(
            shortcut, replacing: preferences.remoteModeShortcut, excluding: preferences.screenOffShortcut
        )
    }

    private func syncRemoteModeShortcut() {
        remoteModeShortcut.setShortcut(preferences.remoteModeShortcut) { [weak self] in
            self?.toggleRemoteMode()
        }
    }

    private func syncScreenOffShortcut() {
        screenOffShortcut.setShortcut(preferences.screenOffShortcut) { [weak self] in
            self?.turnScreenOff()
        }
    }

    func setIdleDelay(_ seconds: Int) {
        preferences.idleDelay = seconds
        if manualWakeAutoOffAllowedAfter != nil {
            restartManualAutoOffCountdown()
        }
        refreshSchedule()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        switch LoginItemService.setEnabled(enabled) {
        case .success(let actual):
            launchAtLogin = actual
            lastError = actual == enabled ? nil : String(localized: "登录项：\(LoginItemService.statusDescription)")
        case .failure(let error):
            launchAtLogin = LoginItemService.isEnabled
            lastError = String(localized: "登录项设置失败：\(error.localizedDescription)")
        }
    }

    /// 拖动亮度滑杆。暗屏中拖动视为用户主动干预：直接以新值结束会话。
    func setDisplayBrightness(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        let previous = displayBrightness
        let createdSnapshot = Self.isDark(clamped) && preferences.pendingDisplayBrightness == nil

        if createdSnapshot {
            preferences.pendingDisplayBrightness = wakeBrightness(preferred: previous)
        }

        guard display.setBrightness(clamped) else {
            if createdSnapshot { preferences.pendingDisplayBrightness = nil }
            lastError = String(localized: "无法调整屏幕亮度")
            return
        }

        displayBrightness = display.brightness() ?? clamped

        if Self.isDark(displayBrightness) {
            manualWakeAutoOffAllowedAfter = nil
            if preferences.autoKeyboardBacklightOff,
               preferences.pendingKeyboardBrightness == nil,
               let current = keyboard.brightness()
            {
                preferences.pendingKeyboardBrightness = current
                if !keyboard.setBrightness(0) {
                    preferences.pendingKeyboardBrightness = nil
                }
            }
            wakeAllowedAfter = clock.now.advanced(by: manualWakeGrace)
        } else {
            // 用户已经指定了新的真实亮度，以该值结束旧会话，不再还原更早的快照。
            lastLitDisplayBrightness = displayBrightness
            preferences.pendingDisplayBrightness = nil
            restoreKeyboardBacklightIfNeeded()
            wakeAllowedAfter = nil
            restartManualAutoOffCountdown()
        }
        lastError = nil
        refreshSchedule()
    }

    /// 打开菜单时刷新一次读数，避免用亮度快捷键改过之后显示不同步；
    /// 同时重试 HID 订阅，用户在系统设置里授权后无需重启。
    func refreshReadings() {
        reconcileDisplayReading()
        defaultDisplayModeDescription = RemoteDesktopService.defaultDisplayDescription()
        isOnACPower = powerSource.isOnACPower
        launchAtLogin = LoginItemService.isEnabled
        syncInputMonitoring(requestAccess: false)
    }

    /// 跳到系统设置的「输入监控」页面。
    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 暗屏会话

    /// 会话是否进行中：只要还存有任一原值快照，就说明系统状态被改过。
    var isSessionActive: Bool {
        preferences.pendingDisplayBrightness != nil || preferences.pendingKeyboardBrightness != nil
    }

    /// 进入暗屏会话。键盘背光只在屏幕确实进入暗屏时跟随关闭。
    private func enterDimSession(manual: Bool, keyboardOverride: Bool? = nil) {
        let dimDisplay = (manual || preferences.autoScreenOff)
            && screenState == .on
            && display.isAvailable
        let dimKeyboard = dimDisplay
            && (keyboardOverride ?? preferences.autoKeyboardBacklightOff)
            && preferences.pendingKeyboardBrightness == nil
            && keyboard.isAvailable
        guard dimDisplay || dimKeyboard else {
            if manual { lastError = String(localized: "当前设备不支持调节内建屏幕亮度") }
            return
        }

        var didChange = false

        if dimDisplay {
            guard let current = display.brightness() else {
                lastError = String(localized: "读取屏幕亮度失败，未做任何修改")
                return
            }
            displayBrightness = current
            guard !Self.isDark(current) else { return }
            lastLitDisplayBrightness = current
            let createdSnapshot = preferences.pendingDisplayBrightness == nil
            if createdSnapshot {
                preferences.pendingDisplayBrightness = current
            }
            if display.setBrightness(0) {
                displayBrightness = display.brightness() ?? 0
                guard Self.isDark(displayBrightness) else {
                    if createdSnapshot { preferences.pendingDisplayBrightness = nil }
                    lastError = String(localized: "屏幕亮度未降至 0")
                    return
                }
                didChange = true
            } else {
                if createdSnapshot { preferences.pendingDisplayBrightness = nil }
                lastError = String(localized: "无法关闭屏幕背光")
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

        manualWakeAutoOffAllowedAfter = nil
        wakeAllowedAfter = manual ? clock.now.advanced(by: manualWakeGrace) : clock.now
        lastError = nil
        log.info("进入暗屏会话 display=\(dimDisplay) keyboard=\(dimKeyboard) manual=\(manual)")
        refreshSchedule()
    }

    /// 退出会话并还原全部原值。可重复调用。
    private func exitDimSession(restartAutoOffCountdown: Bool = false) {
        guard isSessionActive || screenState == .off else { return }

        if screenState == .off {
            let target = wakeBrightness(preferred: preferences.pendingDisplayBrightness)
            guard display.setBrightness(target) else {
                lastError = String(localized: "无法点亮屏幕")
                return
            }
            displayBrightness = display.brightness() ?? target
            guard !Self.isDark(displayBrightness) else {
                lastError = String(localized: "屏幕亮度仍为 0，未能点亮屏幕")
                return
            }
            lastLitDisplayBrightness = displayBrightness
        }

        preferences.pendingDisplayBrightness = nil
        restoreKeyboardBacklightIfNeeded()
        wakeAllowedAfter = nil
        lastError = nil
        if restartAutoOffCountdown {
            restartManualAutoOffCountdown()
        } else {
            manualWakeAutoOffAllowedAfter = nil
        }
        log.info("退出暗屏会话 brightness=\(self.displayBrightness)")
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
        // 输入已锁定时本机按键只是误触，不应唤醒屏幕，也不应重置自动关屏倒计时。
        guard !inputLock.isLocked else { return }
        manualWakeAutoOffAllowedAfter = nil
        guard
            isSessionActive,
            let wakeAllowedAfter,
            clock.now >= wakeAllowedAfter
        else { return }
        exitDimSession()
    }

    // MARK: - 断言

    @discardableResult
    private func syncAssertions() -> Bool {
        guard !shuttingDown else { return false }
        let policy = ScreenOffPowerPolicy(
            keepAwake: preferences.keepAwake, automaticScreenOff: preferences.autoScreenOff,
            canControlDisplay: canControlDisplay, remoteMode: remoteMode.isActive, dimSession: isSessionActive
        )
        let idleOK = power.set(.idle, active: policy.preventSystemIdleSleep)
        let displayOK = power.set(.display, active: policy.preventDisplayIdleSleep)
        if !idleOK || !displayOK {
            lastError = String(localized: "未能接管系统空闲计时，请重试；当前可能仍按系统设置睡眠。")
            assertionErrorPresented = true
        } else if assertionErrorPresented {
            // 用标志位而不是比对文案：文案本地化后前缀匹配必然失效，提示会永远留在界面上。
            lastError = nil
            assertionErrorPresented = false
        }
        return idleOK && displayOK
    }

    private func observePowerSource() {
        powerSource.start { [weak self] isOnAC in
            guard let self else { return }
            isOnACPower = isOnAC
            // 拔掉电源立即回退：合盖不睡会在包里持续发热并耗尽电池。
            if !isOnAC, preferences.keepAwakeWithLidClosed {
                lastError = String(localized: "已拔掉电源，合盖保持唤醒已关闭")
                Task { await applyLidWake(false) }
            }
            syncAssertions()
        }
    }

    private func observeSystemSleep() {
        let center = NSWorkspace.shared.notificationCenter
        let willSleep = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isSessionActive { self.exitDimSession() }
            }
        }
        let didWake = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 睡前的时间戳会让唤醒瞬间就满足空闲条件，必须重置。
                self.input.resetIdle()
                self.refreshSchedule()
            }
        }
        let displayChanged = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.defaultDisplayModeDescription = RemoteDesktopService.defaultDisplayDescription()
                if self.remoteMode.needsRecovery { self.restoreRemoteMode() }
            }
        }
        sleepObservers = [willSleep, didWake]
        screenParametersObserver = displayChanged
    }

    // MARK: - 空闲轮询

    /// 事件驱动为主，轮询只负责「空闲到点关屏」与降级路径的兜底：
    /// 会话中若 HID 可靠，唤醒完全由回调完成，不建轮询。
    private var needsTickLoop: Bool {
        isSessionActive ? !input.isReliable : preferences.needsIdleTracking
    }

    private func refreshSchedule() {
        syncAssertions()
        tickTask?.cancel()
        guard !shuttingDown else { tickTask = nil; return }
        guard needsTickLoop else {
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
        guard !remoteMode.isBusy else { return 0.5 }
        if isSessionActive {
            // 正常情况下 HID 可靠时不会建轮询；这里只服务降级路径。
            guard !input.isReliable else { return 5 }
            if let wakeAllowedAfter, clock.now >= wakeAllowedAfter, input.idleSeconds < 0.5 {
                exitDimSession()
            }
            return 0.5
        }

        guard preferences.needsIdleTracking else { return 2 }

        if let allowedAfter = manualWakeAutoOffAllowedAfter {
            let remaining = seconds(from: clock.now, to: allowedAfter)
            if remaining > 0 {
                return min(max(remaining, 0.5), 5)
            }
            manualWakeAutoOffAllowedAfter = nil
        }

        // 用户在系统设置里授权后，下一轮轮询自动接回 HID 路径。
        if !input.isReliable { syncInputMonitoring(requestAccess: false) }

        let remaining = TimeInterval(preferences.idleDelay) - input.idleSeconds
        if remaining <= 0 {
            enterDimSession(manual: false)
            // 成功时 refreshSchedule 已重建循环；仍未进入会话说明屏幕当前不可控，退避重试。
            return isSessionActive ? 0.5 : failedEntryRetryInterval
        }
        return min(max(remaining, 0.5), 5)
    }

    // MARK: - 亮度状态

    private static func isDark(_ brightness: Float) -> Bool {
        brightness <= 0.0001
    }

    /// 读取并采用系统当前真实亮度。若亮度已被系统或用户从外部调高，旧暗屏会话随之结束。
    private func reconcileDisplayReading() {
        guard let current = display.brightness() else { return }
        displayBrightness = current
        guard !Self.isDark(current) else { return }

        lastLitDisplayBrightness = current
        if preferences.pendingDisplayBrightness != nil {
            preferences.pendingDisplayBrightness = nil
            restoreKeyboardBacklightIfNeeded()
            wakeAllowedAfter = nil
        }
    }

    private func wakeBrightness(preferred: Float?) -> Float {
        if let preferred, !Self.isDark(preferred) { return preferred }
        if !Self.isDark(lastLitDisplayBrightness) { return lastLitDisplayBrightness }
        return defaultWakeBrightness
    }

    private func restoreKeyboardBacklightIfNeeded() {
        guard let saved = preferences.pendingKeyboardBrightness else { return }
        if keyboard.setBrightness(saved) {
            preferences.pendingKeyboardBrightness = nil
        }
    }

    private func restartManualAutoOffCountdown() {
        guard preferences.autoScreenOff else {
            manualWakeAutoOffAllowedAfter = nil
            return
        }
        manualWakeAutoOffAllowedAfter = clock.now.advanced(by: .seconds(preferences.idleDelay))
    }

    private func seconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> TimeInterval {
        let components = start.duration(to: end).components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
