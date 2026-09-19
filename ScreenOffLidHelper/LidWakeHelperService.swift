import Foundation
import os

/// 特权 helper 的全部职责：以 root 写入 `SleepDisabled`，并保证这个开关不会比调用方活得更久。
///
/// 安全不变量：
/// 1. 只接受签名匹配本 App 的连接；
/// 2. 最后一个客户端断开（含 App 崩溃、被强杀）时立即恢复系统默认；
/// 3. 收到 SIGTERM 时同样先恢复再退出。
/// 任何一条失效，用户都可能合盖后永不睡眠——那是会发热和耗尽电池的状态。
final class LidWakeHelperService: NSObject, LidWakeHelperProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "\(LidWakeHelper.label).state")
    private let log = Logger(subsystem: LidWakeHelper.label, category: "helper")
    private var clientCount = 0
    private var didDisableSleep = false

    // MARK: - XPC

    func setSleepDisabled(_ disabled: Bool, reply: @escaping @Sendable (Bool, String?) -> Void) {
        queue.async { [self] in
            guard SystemPowerSetting.canWrite else {
                reply(false, "当前系统不支持写入睡眠设置")
                return
            }
            let code = SystemPowerSetting.setSleepDisabled(disabled)
            guard code == 0 else {
                log.error("写入 SleepDisabled=\(disabled) 失败 code=\(code)")
                reply(false, SystemPowerSetting.describe(code))
                return
            }
            didDisableSleep = disabled
            log.notice("SleepDisabled=\(disabled)")
            reply(true, nil)
        }
    }

    func status(reply: @escaping @Sendable (Bool, Bool) -> Void) {
        queue.async {
            reply(SystemPowerSetting.canWrite, SystemPowerSetting.isSleepDisabled() ?? false)
        }
    }

    // MARK: - 生命周期安全网

    func clientConnected() {
        queue.async { [self] in clientCount += 1 }
    }

    /// 连接断开就回退：App 崩溃或被强杀时，这是唯一还会执行的恢复路径。
    func clientDisconnected() {
        queue.async { [self] in
            clientCount = max(0, clientCount - 1)
            guard clientCount == 0 else { return }
            restoreDefaultLocked(reason: "客户端已断开")
        }
    }

    /// launchd 停止 helper 前调用，同步等待写入完成再退出。
    func restoreAndExit() {
        queue.sync { restoreDefaultLocked(reason: "helper 即将退出") }
        exit(0)
    }

    private func restoreDefaultLocked(reason: String) {
        guard didDisableSleep else { return }
        let code = SystemPowerSetting.setSleepDisabled(false)
        didDisableSleep = code != 0
        log.notice("\(reason, privacy: .public)，恢复系统睡眠默认 code=\(code)")
    }
}

/// 连接受理：签名不匹配一律拒绝，不给任何其他进程改系统电源设置的机会。
final class LidWakeListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let service: LidWakeHelperService
    private let log = Logger(subsystem: LidWakeHelper.label, category: "listener")

    init(service: LidWakeHelperService) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard isTrusted(pid: connection.processIdentifier) else {
            log.error("拒绝未通过签名校验的连接 pid=\(connection.processIdentifier)")
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: LidWakeHelperProtocol.self)
        connection.exportedObject = service
        let service = service
        connection.invalidationHandler = { service.clientDisconnected() }
        connection.interruptionHandler = { service.clientDisconnected() }
        service.clientConnected()
        connection.resume()
        return true
    }

    private func isTrusted(pid: pid_t) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else {
            return false
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            LidWakeHelper.clientRequirement as CFString, [], &requirement
        ) == errSecSuccess, let requirement else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
