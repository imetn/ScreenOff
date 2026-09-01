import Foundation
import ObjectiveC.runtime
import os

/// 内建键盘背光控制。
///
/// 通过 `dlopen` 加载 `CoreBrightness`，再用 ObjC runtime 解析 `KeyboardBrightnessClient`。
/// 任一环节失败即整体判定为不可用；无背光键盘不会报错，也不会影响屏幕亮度功能。
@MainActor
final class KeyboardBacklightService {
    private typealias GetBrightness = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetBrightness = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    /// 内建键盘固定使用 1。
    private static let builtinKeyboard: UInt64 = 1

    private let log = Logger(subsystem: AppLog.subsystem, category: "keyboard")

    private let client: NSObject?
    private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
    private let getBrightness: GetBrightness?
    private let setBrightnessFn: SetBrightness?

    let isAvailable: Bool

    init() {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        // 句柄与 App 同生命周期，不做 dlclose：卸载后 ObjC 类会失效。
        _ = dlopen(path, RTLD_LAZY)

        let instance = (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
        client = instance

        if let instance,
           instance.responds(to: getSelector),
           instance.responds(to: setSelector),
           let getIMP = instance.method(for: getSelector),
           let setIMP = instance.method(for: setSelector) {
            getBrightness = unsafeBitCast(getIMP, to: GetBrightness.self)
            setBrightnessFn = unsafeBitCast(setIMP, to: SetBrightness.self)
            isAvailable = true
            log.info("KeyboardBrightnessClient 解析成功")
        } else {
            getBrightness = nil
            setBrightnessFn = nil
            isAvailable = false
            log.notice("KeyboardBrightnessClient 不可用，键盘背光控制关闭")
        }
    }

    /// 读取背光亮度，范围 0…1；不可用或读数异常返回 nil。
    func brightness() -> Float? {
        guard let client, let getBrightness else { return nil }
        let value = getBrightness(client, getSelector, Self.builtinKeyboard)
        guard value.isFinite, value >= 0, value <= 1 else {
            log.error("键盘背光读数异常 \(value)")
            return nil
        }
        return value
    }

    @discardableResult
    func setBrightness(_ value: Float) -> Bool {
        guard let client, let setBrightnessFn else { return false }
        let clamped = min(max(value, 0), 1)
        let ok = setBrightnessFn(client, setSelector, clamped, Self.builtinKeyboard)
        if !ok { log.error("写入键盘背光失败 value=\(clamped)") }
        return ok
    }
}
