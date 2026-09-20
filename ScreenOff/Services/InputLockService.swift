import AppKit
import ApplicationServices
@preconcurrency import CoreGraphics
import Observation
import os

/// 关闭输入：用 CGEventTap 吞掉本机键盘、触控板与鼠标事件，只保留 Fn + Delete 长按解锁。
///
/// 安全约束（每一条都是防锁死的必要条件）：
/// 1. 拦截只在本进程存活期间有效。崩溃、被强杀或正常退出时系统立刻回收 tap，输入自动恢复；
/// 2. 系统因回调超时禁用 tap 时立即重新启用，不让「显示已锁定」与「其实没拦住」脱节；
/// 3. 解锁组合键本身不下发给前台应用，避免解锁时误删内容；
/// 4. 不拦截 systemDefined 事件，亮度、音量等硬件键在锁定期间仍然可用。
@MainActor
@Observable
final class InputLockService {
    /// 解锁手势的阶段，浮层直接渲染它。
    enum Stage: Equatable {
        case locked
        case holding(progress: Double)
        case readyToRelease
        case restored
    }

    /// 需要按住的时长，和浮层提示文案保持一致。
    static let holdDuration: TimeInterval = 1.0
    /// Delete（退格）键的虚拟键码。
    private static let deleteKeyCode: Int64 = 51
    private static let progressInterval: TimeInterval = 0.04

    private(set) var isLocked = false
    private(set) var stage: Stage = .locked
    /// 最近一次锁定失败的原因，nil 表示没有未处理的失败。
    private(set) var lastError: String?

    /// 锁定状态变化时回调，供浮层与菜单同步。解锁手势发生在事件回调内部，外部只能由此得知。
    @ObservationIgnored var onLockChanged: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var holdStartedAt: ContinuousClock.Instant?
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var restoredTask: Task<Void, Never>?
    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private let log = Logger(subsystem: AppLog.subsystem, category: "input-lock")

    /// 是否已取得辅助功能授权。界面读这份缓存，否则 SwiftUI 无从得知授权在系统设置里发生了变化。
    private(set) var hasAccess = AXIsProcessTrusted()

    /// 向系统重新查询授权状态并刷新缓存；加锁等内部判断一律走它，避免读到过期值。
    @discardableResult
    func refreshAccess() -> Bool {
        let granted = AXIsProcessTrusted()
        if granted != hasAccess { hasAccess = granted }
        return granted
    }

    /// 弹出系统授权引导。只在用户主动点击「关闭输入」而尚未授权时调用。
    func requestAccess() {
        // 常量本身在 Swift 6 下不是并发安全的可变全局，这里直接用它的取值。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// 开始锁定。失败时保持未锁定，并把原因写进 `lastError`。
    @discardableResult
    func lock() -> Bool {
        guard !isLocked else { return true }
        restoredTask?.cancel()
        restoredTask = nil
        guard refreshAccess() else {
            lastError = String(localized: "未取得「辅助功能」权限，无法关闭输入")
            requestAccess()
            log.notice("关闭输入被拒：缺少辅助功能授权")
            return false
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: inputLockTapCallback,
            userInfo: context
        ) else {
            lastError = String(localized: "系统拒绝创建事件拦截，关闭输入不可用")
            log.error("CGEvent.tapCreate 失败")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        runLoopSource = source
        isLocked = true
        stage = .locked
        lastError = nil
        log.notice("输入已锁定")
        onLockChanged?(true)
        return true
    }

    /// 解除锁定。`showRestoredHint` 为假时用于退出流程，不再留提示。
    func unlock(showRestoredHint: Bool = true) {
        cancelHold()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
        guard isLocked else { return }
        isLocked = false
        log.notice("输入已恢复")
        onLockChanged?(false)
        guard showRestoredHint else {
            stage = .locked
            return
        }
        stage = .restored
        restoredTask?.cancel()
        restoredTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, let self, !isLocked else { return }
            stage = .locked
        }
    }

    // MARK: - 事件处理

    /// 在主线程由 C 回调转入。返回 nil 表示吞掉事件。
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log.notice("事件拦截被系统禁用，已重新启用")
            return nil
        }
        guard isLocked else { return Unmanaged.passUnretained(event) }

        let holdingFn = event.flags.contains(.maskSecondaryFn)
        switch type {
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == Self.deleteKeyCode, holdingFn {
                beginHold()
            }
        case .keyUp:
            if event.getIntegerValueField(.keyboardEventKeycode) == Self.deleteKeyCode {
                finishHold()
            }
        case .flagsChanged:
            if !holdingFn { finishHold() }
        default:
            break
        }
        return nil
    }

    private func beginHold() {
        guard holdStartedAt == nil else { return }  // 键盘自动重复不重新计时
        let start = clock.now
        holdStartedAt = start
        stage = .holding(progress: 0)
        holdTask?.cancel()
        holdTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(Self.progressInterval * 1000)))
                guard !Task.isCancelled, let self, isLocked, holdStartedAt == start else { return }
                let elapsed = clock.now - start
                let progress = min(1, elapsed / .seconds(Self.holdDuration))
                if progress >= 1 {
                    stage = .readyToRelease
                    return
                }
                stage = .holding(progress: progress)
            }
        }
    }

    /// 松开按键或松开 Fn：按满时长才解锁，否则回到等待状态。
    private func finishHold() {
        guard holdStartedAt != nil else { return }
        let completed = stage == .readyToRelease
        cancelHold()
        if completed {
            unlock()
        } else {
            stage = .locked
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        holdStartedAt = nil
    }
}

private extension Duration {
    /// 以秒为单位的比值，用于把按住时长换算成进度。
    static func / (lhs: Duration, rhs: Duration) -> Double {
        let left = Double(lhs.components.seconds) + Double(lhs.components.attoseconds) * 1e-18
        let right = Double(rhs.components.seconds) + Double(rhs.components.attoseconds) * 1e-18
        guard right > 0 else { return 0 }
        return left / right
    }
}

/// C 回调必须是无捕获的函数指针；tap 加在主 run loop 上，因此回调始终在主线程。
private let inputLockTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<InputLockService>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated { service.handle(type: type, event: event) }
}
