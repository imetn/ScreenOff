import CoreGraphics
import Foundation
import os

/// 内建屏幕亮度控制。
///
/// 通过 `dlopen` 动态解析 `DisplayServices` 私有框架；符号缺失时整体降级为不可用，
/// 绝不因缺符号崩溃，也绝不在读取失败时写入。
@MainActor
final class DisplayBrightnessService {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool

    private let log = Logger(subsystem: AppLog.subsystem, category: "display")

    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private let canChangeBrightness: CanChangeBrightness?

    /// 能力探测结果：三个符号齐备才认为可用。
    let isAvailable: Bool

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        // 句柄与 App 同生命周期，不做 dlclose：私有框架可能仍被系统组件持有。
        let handle = dlopen(path, RTLD_LAZY)

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        getBrightness = symbol("DisplayServicesGetBrightness", as: GetBrightness.self)
        setBrightness = symbol("DisplayServicesSetBrightness", as: SetBrightness.self)
        canChangeBrightness = symbol("DisplayServicesCanChangeBrightness", as: CanChangeBrightness.self)

        isAvailable = getBrightness != nil && setBrightness != nil

        if isAvailable {
            log.info("DisplayServices 解析成功")
        } else {
            log.error("DisplayServices 解析失败，屏幕亮度控制不可用")
        }
    }

    /// 内建屏幕的 display id；没有内建屏幕时返回 nil。
    var builtinDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    var canControl: Bool {
        guard isAvailable, let display = builtinDisplay else { return false }
        guard let canChangeBrightness else { return true }
        return canChangeBrightness(display)
    }

    /// 读取当前亮度，范围 0…1；失败返回 nil。
    func brightness() -> Float? {
        guard let getBrightness, let display = builtinDisplay else { return nil }
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else {
            log.error("读取亮度失败")
            return nil
        }
        guard value.isFinite, value >= 0, value <= 1 else {
            log.error("读取亮度超出范围 \(value)")
            return nil
        }
        return value
    }

    /// 写入亮度。范围外的值会被夹紧到 0…1。
    @discardableResult
    func setBrightness(_ value: Float) -> Bool {
        guard let setBrightness, let display = builtinDisplay else { return false }
        let clamped = min(max(value, 0), 1)
        let result = setBrightness(display, clamped)
        if result != 0 {
            log.error("写入亮度失败 value=\(clamped) code=\(result)")
            return false
        }
        return true
    }
}
