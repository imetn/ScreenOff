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
@MainActor
final class PhysicalInputMonitor {
    enum Reliability {
        /// IOHIDManager 生效，可区分远程注入。
        case hidDevices
        /// 降级读数，远程注入会重置计时。
        case eventSource
    }

    private let log = Logger(subsystem: AppLog.subsystem, category: "input")

    private var manager: IOHIDManager?
    private var lastInputAt = Date()
    private var onInput: (() -> Void)?

    private(set) var reliability: Reliability = .eventSource

    var isReliable: Bool { reliability == .hidDevices }

    var accessDenied: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeDenied
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

    /// 启动监控。`onInput` 在每次物理输入时于主线程回调，用于即时恢复亮度。
    func start(onInput: @escaping () -> Void) {
        self.onInput = onInput
        guard manager == nil else { return }

        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
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
