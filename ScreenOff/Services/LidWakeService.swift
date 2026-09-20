import AppKit
import Observation
import ServiceManagement
import os

/// 合盖保持唤醒。
///
/// 只有 `SleepDisabled` 能真正阻止合盖睡眠，而它必须由 root 写入，所以写入交给随 App 分发的
/// 特权守护进程；读取不需要特权，直接在 App 内完成，界面因此永远显示系统真实状态而不是本地猜测。
///
/// 这个开关被打开后，Mac 合盖不再睡眠：散热受限且电池会被耗尽。因此调用方必须保证
/// 拔掉电源、退出 App 时立即关闭它，helper 侧也会在连接断开时兜底恢复。
@MainActor
@Observable
final class LidWakeService {
    enum Readiness: Equatable {
        case unsupported
        case notRegistered
        case requiresApproval
        case ready
    }

    /// 系统当前是否真的处于「不因合盖而睡眠」状态，每次刷新都向系统查询。
    private(set) var isSleepDisabled = false
    private(set) var lastError: String?

    @ObservationIgnored private var connection: NSXPCConnection?
    /// 每次运行只重装一次守护进程，避免在真正的故障上反复注销注册。
    @ObservationIgnored private var didAttemptReinstall = false
    @ObservationIgnored private let log = Logger(subsystem: AppLog.subsystem, category: "lid-wake")

    private var service: SMAppService { SMAppService.daemon(plistName: LidWakeHelper.plistName) }

    var isSupported: Bool { SystemPowerSetting.canRead }

    /// 界面读这份缓存；`SMAppService.status` 是计算值，批准动作发生在系统设置里，
    /// 不刷新就永远停在「等待批准」。
    private(set) var readiness: Readiness = .notRegistered

    /// 内部判断一律用实时值，避免拿过期缓存去写系统设置。
    private var currentReadiness: Readiness {
        guard isSupported else { return .unsupported }
        return switch service.status {
        case .enabled: .ready
        case .requiresApproval: .requiresApproval
        default: .notRegistered
        }
    }

    func refresh() {
        isSleepDisabled = SystemPowerSetting.isSleepDisabled() ?? false
        let current = currentReadiness
        if current != readiness { readiness = current }
    }

    // MARK: - 守护进程注册

    /// 首次启用时注册。注册后系统通常要求用户在「登录项与扩展」里批准，之后才真正可用。
    @discardableResult
    func registerHelper() -> Bool {
        do {
            try service.register()
            lastError = nil
            log.notice("守护进程已注册 status=\(self.service.status.rawValue)")
            return true
        } catch {
            // 已注册时重复调用会报错，这不算失败。
            if service.status == .enabled || service.status == .requiresApproval {
                lastError = nil
                return true
            }
            lastError = String(localized: "无法注册后台守护进程：\(error.localizedDescription)")
            log.error("注册守护进程失败 \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// 关闭功能时不注销：注销会让用户下次开启重新走一遍批准流程。
    /// 只有用户明确要移除时才调用。
    func unregisterHelper() async {
        await setEnabled(false)
        disconnect()
        try? await service.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - 开关

    /// 写入系统设置。返回是否达成目标状态；失败时 `lastError` 说明原因。
    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard isSupported else {
            lastError = String(localized: "当前系统不支持合盖保持唤醒")
            return false
        }
        // 关闭时即使 helper 已不可用也要把状态对齐，避免界面显示与系统不一致。
        guard enabled || isSleepDisabled else {
            refresh()
            return true
        }

        var outcome = await send(enabled)
        // launchd 不会因为 App 升级就换掉已在运行的 daemon 进程：它手里还是旧的可执行
        // 文件，说的也是旧协议。重新注册会先让旧进程收到 SIGTERM 恢复默认再退出，
        // 之后拉起的才是当前 bundle 里的版本。每次运行只自愈一次，避免反复打扰用户。
        if outcome.communicationFailed, !didAttemptReinstall {
            didAttemptReinstall = true
            log.notice("守护进程通信失败，重新注册后重试")
            if await reinstallHelper() {
                outcome = await send(enabled)
            }
        }

        refresh()
        if outcome.succeeded {
            lastError = nil
        } else {
            lastError = outcome.message ?? String(localized: "写入系统睡眠设置失败")
            log.error("设置合盖保持唤醒失败 \(self.lastError ?? "", privacy: .public)")
        }
        return outcome.succeeded && isSleepDisabled == enabled
    }

    private func send(_ enabled: Bool) async -> Outcome {
        guard let proxy = makeProxy() else {
            return Outcome(message: lastError)
        }
        return await withCheckedContinuation { continuation in
            let box = ReplyBox(continuation: continuation)
            let handler = proxy(box.errorHandler)
            guard let helper = handler as? LidWakeHelperProtocol else {
                box.finish(Outcome(message: String(localized: "守护进程接口不可用"), communicationFailed: true))
                return
            }
            helper.setSleepDisabled(enabled) { success, code in
                // helper 进程没有本地化资源，文案一律在 App 侧按回传的 IOReturn 生成。
                box.finish(Outcome(
                    succeeded: success,
                    message: success ? nil : SystemPowerSetting.describe(code)
                ))
            }
        }
    }

    /// 注销再注册。注销让 launchd 回收旧进程，注册后系统通常会重新要求批准，
    /// 界面随后显示「等待批准」——这比一个永远打不开的开关清楚得多。
    private func reinstallHelper() async -> Bool {
        disconnect()
        try? await service.unregister()
        // 注销后 launchd 要一点时间回收旧进程，立刻注册可能又连回同一个实例。
        try? await Task.sleep(for: .milliseconds(400))
        let ok = registerHelper()
        refresh()
        return ok
    }

    /// 退出路径：先还原系统设置，再断开连接。断开本身也会触发 helper 兜底还原。
    func shutdown() {
        if isSleepDisabled, let helper = connectedProxy() {
            helper.setSleepDisabled(false) { _, _ in }
        }
        disconnect()
        refresh()
    }

    // MARK: - XPC

    private func makeProxy() -> ((@escaping @Sendable (Error) -> Void) -> Any?)? {
        guard currentReadiness == .ready else {
            lastError = currentReadiness == .requiresApproval
                ? String(localized: "后台守护进程等待批准，请在「登录项与扩展」中允许 Screen Off")
                : String(localized: "后台守护进程尚未安装")
            return nil
        }
        let connection = activeConnection()
        return { errorHandler in connection.remoteObjectProxyWithErrorHandler(errorHandler) }
    }

    private func connectedProxy() -> LidWakeHelperProtocol? {
        guard currentReadiness == .ready else { return nil }
        return activeConnection().remoteObjectProxy as? LidWakeHelperProtocol
    }

    /// 连接保持存活：helper 在最后一个客户端断开时会恢复系统默认，这正是我们要的兜底。
    private func activeConnection() -> NSXPCConnection {
        if let connection { return connection }
        let created = NSXPCConnection(machServiceName: LidWakeHelper.label, options: .privileged)
        created.remoteObjectInterface = NSXPCInterface(with: LidWakeHelperProtocol.self)
        created.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        created.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        created.resume()
        connection = created
        return created
    }

    private func disconnect() {
        connection?.invalidationHandler = nil
        connection?.invalidate()
        connection = nil
    }
}

/// 一次写入尝试的结果。要区分「系统拒绝写入」和「根本没说上话」：
/// 后者往往是 launchd 还占着旧版本的 daemon，重新注册就能修好。
private struct Outcome {
    var succeeded = false
    var message: String?
    var communicationFailed = false
}

/// XPC 的错误回调与正常回复只会有一个先到，但两者都可能到；这里保证 continuation 只恢复一次。
private final class ReplyBox: @unchecked Sendable {
    private let continuation: CheckedContinuation<Outcome, Never>
    private let lock = NSLock()
    private var finished = false

    init(continuation: CheckedContinuation<Outcome, Never>) {
        self.continuation = continuation
    }

    var errorHandler: @Sendable (Error) -> Void {
        { [self] error in
            finish(Outcome(
                message: String(localized: "守护进程通信失败：\(error.localizedDescription)"),
                communicationFailed: true
            ))
        }
    }

    func finish(_ value: Outcome) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume(returning: value)
    }
}
