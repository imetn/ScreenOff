import Foundation
import Observation

struct RemoteModeConfiguration: Codable, Equatable, Sendable {
    enum SwitchSetting: String, Codable, CaseIterable {
        case unchanged, enabled, disabled
        var title: String {
            switch self { case .unchanged: String(localized: "保持原样"); case .enabled: String(localized: "开启"); case .disabled: String(localized: "关闭") }
        }
    }
    var defaultDisplayMode = true
    var dockVisibility: SwitchSetting = .enabled
    var resizeDock = true
    var dockSize = 0.8
    var stageManager: SwitchSetting = .enabled
    var dimDisplay = true
    var dimKeyboard = true

    enum BacklightSetting: String, CaseIterable {
        case unchanged, display, displayAndKeyboard

        var title: String {
            switch self {
            case .unchanged: String(localized: "保持原样")
            case .display: String(localized: "仅屏幕")
            case .displayAndKeyboard: String(localized: "屏幕和键盘")
            }
        }
    }

    /// Keyboard dimming follows a display session; the picker never offers an unsupported keyboard-only mode.
    var backlightSetting: BacklightSetting {
        get { !dimDisplay ? .unchanged : dimKeyboard ? .displayAndKeyboard : .display }
        set {
            dimDisplay = newValue != .unchanged
            dimKeyboard = newValue == .displayAndKeyboard
        }
    }

    // Dock stores an integer pixel size. Its normalized getter can differ by up to one step.
    static func dockSizeMatches(actual: Double, requested: Double) -> Bool {
        actual.isFinite && requested.isFinite && abs(actual - requested) <= 0.01
    }

    var validated: Self {
        var copy = self
        copy.dockSize = dockSize.isFinite ? min(1, max(0, dockSize)) : 0.8
        return copy
    }
}

struct RemoteDisplayMode: Codable, Equatable, Sendable {
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshRate: Double
    var modeID: Int32
    var isDefault: Bool
    var isHiDPI: Bool { pixelWidth > width }
    var title: String { "\(width) × \(height)" }

    func matches(_ other: Self) -> Bool {
        width == other.width && height == other.height && pixelWidth == other.pixelWidth
            && pixelHeight == other.pixelHeight && abs(refreshRate - other.refreshRate) < 0.1
    }

    static func recommended(in modes: [Self]) -> Self? {
        // The display driver identifies its default; never infer it from a model name or screen size.
        modes.filter(\.isDefault).sorted {
            if $0.isHiDPI != $1.isHiDPI { return $0.isHiDPI }
            return $0.refreshRate > $1.refreshRate
        }.first
    }
}

struct RemoteModeSnapshot: Codable, Equatable, Sendable {
    struct Display: Codable, Equatable, Sendable {
        var uuid: String
        var original: RemoteDisplayMode
        var target: RemoteDisplayMode
    }
    struct Dock: Codable, Equatable, Sendable {
        var autohide: Bool?
        var size: Double?
    }
    struct StageManager: Codable, Equatable, Sendable {
        // nil means the key did not exist before the session started.
        var value: Bool?

        /// 恢复时要写回的值。键缺失的等价行为就是关闭，因此 nil 必须还原成 false：
        /// 只把键删掉不会让 WindowManager 退出台前调度，它随后会把运行中的状态写回偏好。
        var restoreTarget: Bool { value ?? false }
    }
    var version = 1
    var display: Display?
    var dock: Dock?
    var stageManager: StageManager?
    var isEmpty: Bool { display == nil && dock == nil && stageManager == nil }
}

struct RemoteModeRestoreResult {
    var remaining: RemoteModeSnapshot
    var errors: [String]
}

@MainActor
protocol RemoteModeEnvironment {
    func capture(_ configuration: RemoteModeConfiguration) async throws -> RemoteModeSnapshot
    func apply(_ configuration: RemoteModeConfiguration, snapshot: RemoteModeSnapshot) async throws
    func restore(_ snapshot: RemoteModeSnapshot) async -> RemoteModeRestoreResult
}

enum RemoteModeError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): message }
    }
}

/// Durable transaction: record all original values before the first write; retain failed restores.
@MainActor
@Observable
final class RemoteModeSession {
    enum State { case inactive, changing, active, recoveryRequired }
    private(set) var state: State = .inactive
    private(set) var error: String?
    @ObservationIgnored private let environment: any RemoteModeEnvironment
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var snapshot: RemoteModeSnapshot?
    static let snapshotKey = "remoteModeRecoverySnapshot"

    var isActive: Bool { state == .active }
    var isBusy: Bool { state == .changing }
    var needsRecovery: Bool { state == .recoveryRequired }

    init(environment: any RemoteModeEnvironment, defaults: UserDefaults = .standard) {
        self.environment = environment
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.snapshotKey) {
            snapshot = try? JSONDecoder().decode(RemoteModeSnapshot.self, from: data)
            state = .recoveryRequired
            if snapshot?.version != 1 {
                snapshot = nil
                error = String(localized: "远程模式恢复记录无法读取，请保留记录并联系支持。")
            }
        }
    }

    func activate(_ configuration: RemoteModeConfiguration) async {
        guard state == .inactive else { return }
        state = .changing
        error = nil
        do {
            let saved = try await environment.capture(configuration.validated)
            try persist(saved)
            snapshot = saved
            try await environment.apply(configuration.validated, snapshot: saved)
            state = .active
        } catch {
            let failure = error.localizedDescription
            if snapshot != nil {
                await restoreSnapshot()
                self.error = [failure, self.error].compactMap { $0 }.joined(separator: "；")
            } else {
                state = .inactive
                self.error = failure
            }
        }
    }

    func deactivate() async {
        guard state != .changing, state != .inactive else { return }
        state = .changing
        error = nil
        await restoreSnapshot()
    }

    private func restoreSnapshot() async {
        guard let snapshot else {
            state = .recoveryRequired
            error = String(localized: "恢复记录无法读取，已停止修改系统设置。")
            return
        }
        let result = await environment.restore(snapshot)
        do {
            if result.remaining.isEmpty {
                defaults.removeObject(forKey: Self.snapshotKey)
                guard defaults.synchronize() else { throw RemoteModeError.unavailable(String(localized: "无法保存恢复状态")) }
                self.snapshot = nil
                state = .inactive
            } else {
                try persist(result.remaining)
                self.snapshot = result.remaining
                state = .recoveryRequired
            }
            error = result.errors.isEmpty ? nil : result.errors.joined(separator: "；")
        } catch {
            state = .recoveryRequired
            self.error = error.localizedDescription
        }
    }

    private func persist(_ snapshot: RemoteModeSnapshot) throws {
        defaults.set(try JSONEncoder().encode(snapshot), forKey: Self.snapshotKey)
        guard defaults.synchronize() else {
            throw RemoteModeError.unavailable(String(localized: "无法保存原设置，未开启远程模式"))
        }
    }
}

/// Keep the display powered while Screen Off owns its timer/backlight, independently of system idle sleep.
struct ScreenOffPowerPolicy: Equatable {
    var preventSystemIdleSleep: Bool
    var preventDisplayIdleSleep: Bool

    init(keepAwake: Bool, automaticScreenOff: Bool, canControlDisplay: Bool, remoteMode: Bool, dimSession: Bool) {
        preventSystemIdleSleep = keepAwake || remoteMode
        preventDisplayIdleSleep = remoteMode || dimSession || (automaticScreenOff && canControlDisplay)
    }
}
