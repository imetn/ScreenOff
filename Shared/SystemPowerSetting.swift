import Foundation

/// `SleepDisabled` 是 `pmset disablesleep` 背后的系统电源设置，也是唯一能真正阻止合盖睡眠的开关。
///
/// 两个符号都不在公开 SDK 头文件里，按项目规则动态解析：解析不到就判定能力不可用，绝不崩溃。
/// 读取不需要特权，写入必须是 root——因此写入只在特权 helper 中发生。
enum SystemPowerSetting {
    static let sleepDisabledKey = "SleepDisabled"

    private typealias CopyFn = @convention(c) () -> Unmanaged<CFDictionary>?
    private typealias SetFn = @convention(c) (CFString, CFTypeRef) -> Int32

    /// RTLD_DEFAULT：在已加载的镜像里按名字查找，不额外 dlopen 任何私有框架。
    private static var defaultHandle: UnsafeMutableRawPointer? { UnsafeMutableRawPointer(bitPattern: -2) }

    private static let copyFunction: CopyFn? = {
        guard let symbol = dlsym(defaultHandle, "IOPMCopySystemPowerSettings") else { return nil }
        return unsafeBitCast(symbol, to: CopyFn.self)
    }()

    private static let setFunction: SetFn? = {
        guard let symbol = dlsym(defaultHandle, "IOPMSetSystemPowerSetting") else { return nil }
        return unsafeBitCast(symbol, to: SetFn.self)
    }()

    static var canRead: Bool { copyFunction != nil }
    static var canWrite: Bool { setFunction != nil }

    /// 当前是否已禁止睡眠。读不到设置时返回 nil，调用方据此降级而不是假设默认值。
    static func isSleepDisabled() -> Bool? {
        guard let copyFunction, let settings = copyFunction()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        guard let value = settings[sleepDisabledKey] else { return false }
        if let number = value as? NSNumber { return number.boolValue }
        if let flag = value as? Bool { return flag }
        return false
    }

    /// 写入需要 root：非特权进程会拿到 `kIOReturnNotPrivileged`。返回原始 IOReturn 便于记录。
    @discardableResult
    static func setSleepDisabled(_ disabled: Bool) -> Int32 {
        guard let setFunction else { return Int32(bitPattern: 0xE00002C7) }  // kIOReturnUnsupported
        return setFunction(sleepDisabledKey as CFString, disabled ? kCFBooleanTrue : kCFBooleanFalse)
    }

    static func describe(_ code: Int32) -> String {
        switch UInt32(bitPattern: code) {
        case 0: "成功"
        case 0xE00002C1: "需要管理员权限"
        case 0xE00002C7: "系统不支持该设置"
        default: String(format: "IOReturn 0x%08X", UInt32(bitPattern: code))
        }
    }
}
