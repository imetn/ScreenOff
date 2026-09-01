import Foundation
import IOKit.pwr_mgt
import os

/// 电源断言服务：集中持有 IOKit 断言，保证任何路径下都能完整释放。
///
/// - `idle`  阻止「空闲导致的系统睡眠」，开盖使用，电池供电也生效。
/// - `system` 阻止「系统睡眠」，是合盖保持运行的关键；系统规定仅在接通电源时有效。
@MainActor
final class PowerAssertionService {
    enum Kind: CaseIterable {
        case idle
        case system

        var ioKitType: String {
            switch self {
            case .idle: kIOPMAssertionTypePreventUserIdleSystemSleep
            case .system: kIOPMAssertionTypePreventSystemSleep
            }
        }

        /// 断言名会出现在 `pmset -g assertions` 中，使用 ASCII 以保证可读。
        var reason: String {
            switch self {
            case .idle: "Screen Off: keep awake"
            case .system: "Screen Off: keep awake with lid closed"
            }
        }
    }

    private let log = Logger(subsystem: AppLog.subsystem, category: "power")
    private var identifiers: [Kind: IOPMAssertionID] = [:]

    var heldKinds: Set<Kind> { Set(identifiers.keys) }

    func isHolding(_ kind: Kind) -> Bool { identifiers[kind] != nil }

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
        guard let id = identifiers.removeValue(forKey: kind) else { return }
        let result = IOPMAssertionRelease(id)
        if result == kIOReturnSuccess {
            log.info("释放断言 \(kind.ioKitType, privacy: .public) id=\(id)")
        } else {
            log.error("释放断言失败 \(kind.ioKitType, privacy: .public) code=\(result)")
        }
    }

    func set(_ kind: Kind, active: Bool) {
        if active { acquire(kind) } else { release(kind) }
    }

    /// 退出、异常恢复与关闭功能时统一调用。
    func releaseAll() {
        for kind in Kind.allCases { release(kind) }
    }
}
