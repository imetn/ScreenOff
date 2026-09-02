import AppKit
import CoreGraphics
import IOKit.hid
import os

/// 物理输入监控。
///
/// 主路径用 `IOHIDManager` 直接订阅内建键盘与触控板设备：回调只更新一个时间戳，
/// 不读取任何键值或坐标，因此不保存输入内容。
/// 实测软件合成事件（远程控制常用的 `CGEvent` 注入）不会触发该回调，
/// 而 `CGEventSource` 的 `hidSystemState` 会被注入事件重置——所以降级路径不可靠，
/// 必须在界面上明说。
///
/// 打开 HID 设备本身会触发系统「输入监控」授权弹窗，所以 `start()` 只在授权已通过时打开设备；
/// 何时向用户申请授权由调用方通过 `requestAccess()` 决定。
@MainActor
final class PhysicalInputMonitor {
    enum Reliability {
        /// IOHIDManager 生效，可区分远程注入。
        case hidDevices
        /// 降级读数，远程注入会重置计时。
        case eventSource
    }

    enum AccessStatus {
        case granted
        case denied
        /// 系统尚未询问过用户。
        case unknown
    }

    private let log = Logger(subsystem: AppLog.subsystem, category: "input")

    private var manager: IOHIDManager?
    private var lastInputAt = Date()
    private var onInput: (() -> Void)?

    private(set) var reliability: Reliability = .eventSource

    var isReliable: Bool { reliability == .hidDevices }

    /// 「输入监控」授权状态，每次读取都向系统查询。
    var accessStatus: AccessStatus {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access == kIOHIDAccessTypeGranted { return .granted }
        if access == kIOHIDAccessTypeDenied { return .denied }
        return .unknown
    }

    /// 弹出系统授权请求。用户尚未决定时立即返回 false，之后需再调用 `start()` 重试。
    @discardableResult
    func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// 距上一次物理输入的秒数。
    var idleSeconds: TimeInterval {
        switch reliability {
        case .hidDevices:
            Date().timeIntervalSince(lastInputAt)
        case .eventSource:
            CGEventSource.secondsSinceLastEventType(
                .hidSystemState,
                eventType: .tapDisabledByUserInput
            )
        }
    }

    /// 系统唤醒后调用，避免用睡眠前的旧时间戳立即触发关屏。
    func resetIdle() { lastInputAt = Date() }

    /// 启动或重试订阅；可重复调用。已订阅时只更新回调，未授权时不打开设备、保持降级路径。
    /// `onInput` 在每次物理输入时于主线程回调，用于即时恢复亮度。
    func start(onInput: @escaping () -> Void) {
        self.onInput = onInput
        guard manager == nil else { return }
        guard accessStatus == .granted else {
            reliability = .eventSource
            return
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<PhysicalInputMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.handleInput() }
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let deviceCount = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.count ?? 0

        if result == kIOReturnSuccess, deviceCount > 0 {
            self.manager = manager
            lastInputAt = Date()
            reliability = .hidDevices
            log.info("IOHIDManager 已订阅 \(deviceCount) 个输入设备")
        } else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            reliability = .eventSource
            log.error("IOHIDManager 不可用 code=\(String(result, radix: 16)) devices=\(deviceCount)，降级为事件源读数")
        }
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        onInput = nil
        reliability = .eventSource
    }

    private func handleInput() {
        lastInputAt = Date()
        onInput?()
    }
}
