import Foundation
import IOKit.ps
import os

/// 供电来源监控。合盖保持唤醒只在接通电源时有效，拔掉电源必须立即回退。
@MainActor
final class PowerSourceMonitor {
    private let log = Logger(subsystem: AppLog.subsystem, category: "powersource")

    private var runLoopSource: CFRunLoopSource?
    private var onChange: ((Bool) -> Void)?

    private(set) var isOnACPower: Bool = PowerSourceMonitor.readIsOnACPower()

    static func readIsOnACPower() -> Bool {
        guard let type = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String? else {
            return true
        }
        return type == kIOPSACPowerValue
    }

    /// 注册系统电源变化通知；重复调用只保留最后一个回调。
    func start(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        guard runLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.handleChange() }
        }, context)?.takeRetainedValue() else {
            log.error("注册电源通知失败")
            return
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func stop() {
        guard let runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        self.runLoopSource = nil
        onChange = nil
    }

    private func handleChange() {
        let current = Self.readIsOnACPower()
        guard current != isOnACPower else { return }
        isOnACPower = current
        log.info("供电来源变化 isOnACPower=\(current)")
        onChange?(current)
    }
}
