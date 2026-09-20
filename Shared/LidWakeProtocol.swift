import Foundation

/// App 与特权 helper 之间的契约。两端共用同一份定义，避免标签、服务名或签名要求写歪。
enum LidWakeHelper {
    /// launchd Label、Mach service 名与可执行文件名三者一致，便于排查。
    static let label = "com.frameflowtech.screenoff.lidhelper"
    static let plistName = "com.frameflowtech.screenoff.lidhelper.plist"

    /// helper 只接受本 App 的连接：Bundle ID、Apple 锚点与团队 ID 三者同时满足才放行。
    static let clientRequirement = """
        identifier "com.frameflowtech.screenoff" \
        and anchor apple generic \
        and certificate leaf[subject.OU] = "PRYY9PKKUP"
        """
}

@objc protocol LidWakeHelperProtocol {
    /// 写入 `SleepDisabled`。失败时回传原始 IOReturn，由 App 侧译成用户语言——
    /// helper 是独立进程，bundle 里没有本地化资源，在它那边生成的文案永远是中文。
    func setSleepDisabled(_ disabled: Bool, reply: @escaping @Sendable (Bool, Int32) -> Void)

    /// 健康检查：确认 helper 已就绪且具备写入能力。
    func status(reply: @escaping @Sendable (Bool, Bool) -> Void)
}
