import Foundation
import ServiceManagement
import os

/// 登录启动。使用 `SMAppService.mainApp`，不安装任何额外 Helper。
@MainActor
enum LoginItemService {
    private static let log = Logger(subsystem: AppLog.subsystem, category: "loginitem")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 返回实际生效状态；失败时返回失败原因，供界面直接展示。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<Bool, Error> {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return .success(isEnabled)
        } catch {
            log.error("登录项切换失败 \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: "已开启"
        case .notRegistered: "未开启"
        case .notFound: "登录项不可用"
        case .requiresApproval: "需在系统设置中批准"
        @unknown default: "状态未知"
        }
    }
}
