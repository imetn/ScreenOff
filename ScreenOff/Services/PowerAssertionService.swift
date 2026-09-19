import Foundation
import IOKit.pwr_mgt
import os

/// 电源断言服务：集中持有 IOKit 断言，保证任何路径下都能完整释放。
///
/// - `idle`  阻止「空闲导致的系统睡眠」，开盖使用，电池供电也生效。
/// - `display` 阻止系统提前熄屏，让 App 的空闲计时和远程暗屏保持有效。
/// 两种断言均不能阻止合盖、主动睡眠或低电量强制睡眠。
@MainActor
final class PowerAssertionService {
    enum Kind: CaseIterable {
        case idle
        case display

        var ioKitType: String {
            switch self {
            case .idle: kIOPMAssertionTypePreventUserIdleSystemSleep
            case .display: kIOPMAssertionTypePreventUserIdleDisplaySleep
            }
        }

        /// 断言名会出现在 `pmset -g assertions` 中，使用 ASCII 以保证可读。
        var reason: String {
            switch self {
            case .idle: "Screen Off: keep awake"
            case .display: "Screen Off: manage display idle timer"
            }
        }
    }

    private let log = Logger(subsystem: AppLog.subsystem, category: "power")
    private var identifiers: [Kind: IOPMAssertionID] = [:]

    /// 幂等：已持有时直接返回 true。
    @discardableResult
    func acquire(_ kind: Kind) -> Bool {
        if identifiers[kind] != nil { return true }

        var id: IOPMAssertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kind.ioKitType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            kind.reason as CFString,
            &id
        )

        guard result == kIOReturnSuccess else {
            log.error("创建断言失败 \(kind.ioKitType, privacy: .public) code=\(result)")
            return false
        }

        identifiers[kind] = id
        log.info("持有断言 \(kind.ioKitType, privacy: .public) id=\(id)")
        return true
    }

    /// 幂等：未持有时直接返回。
    func release(_ kind: Kind) {
        guard let id = identifiers[kind] else { return }
        let result = IOPMAssertionRelease(id)
        if result == kIOReturnSuccess {
            identifiers.removeValue(forKey: kind)
            log.info("释放断言 \(kind.ioKitType, privacy: .public) id=\(id)")
        } else {
            log.error("释放断言失败 \(kind.ioKitType, privacy: .public) code=\(result)")
        }
    }

    @discardableResult
    func set(_ kind: Kind, active: Bool) -> Bool {
        if active { return acquire(kind) }
        release(kind)
        return identifiers[kind] == nil
    }

    /// 退出、异常恢复与关闭功能时统一调用。
    func releaseAll() {
        for kind in Kind.allCases { release(kind) }
    }
}
