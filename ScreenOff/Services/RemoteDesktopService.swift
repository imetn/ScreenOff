import AppKit
import CoreGraphics
import Foundation
import IOKit.graphics

@MainActor
final class RemoteDesktopService: RemoteModeEnvironment {
    private static let stageDomain = "com.apple.WindowManager" as CFString
    private static let stageKey = "GloballyEnabled" as CFString

    static var stageManagerAvailable: Bool {
        FileManager.default.fileExists(atPath: "/System/Library/CoreServices/WindowManager.app")
    }

    static func defaultDisplayDescription() -> String {
        guard let display = builtinDisplay(),
              let target = RemoteDisplayMode.recommended(in: modes(display).map(describe)) else {
            return "未检测到可用的内建显示器默认模式"
        }
        return "按当前内建显示器识别：\(target.title)\(target.isHiDPI ? " · Retina" : "")"
    }

    func capture(_ configuration: RemoteModeConfiguration) async throws -> RemoteModeSnapshot {
        var result = RemoteModeSnapshot()
        if configuration.defaultDisplayMode {
            guard let display = Self.builtinDisplay(), CGDisplayIsInMirrorSet(display) == 0,
                  let current = CGDisplayCopyDisplayMode(display),
                  let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
                  let target = RemoteDisplayMode.recommended(in: Self.modes(display).map(Self.describe)) else {
                throw RemoteModeError.unavailable("无法识别内建显示器默认模式，或正在镜像显示。请在远程模式设置中关闭默认缩放后重试。")
            }
            result.display = .init(uuid: CFUUIDCreateString(nil, uuid) as String,
                                   original: Self.describe(current), target: target)
        }
        if configuration.dockVisibility != .unchanged || configuration.resizeDock {
            let dock = try await Self.readDock()
            result.dock = .init(autohide: configuration.dockVisibility == .unchanged ? nil : dock.autohide,
                                size: configuration.resizeDock ? dock.size : nil)
        }
        if configuration.stageManager != .unchanged {
            guard Self.stageManagerAvailable else { throw RemoteModeError.unavailable("当前系统不支持台前调度") }
            guard !CFPreferencesAppValueIsForced(Self.stageKey, Self.stageDomain) else {
                throw RemoteModeError.unavailable("台前调度由设备管理策略控制")
            }
            if configuration.stageManager == .enabled,
               CFPreferencesCopyAppValue("spans-displays" as CFString, "com.apple.spaces" as CFString) as? Bool == true {
                throw RemoteModeError.unavailable("台前调度需要先在系统设置中开启「显示器具有单独的空间」并重新登录。")
            }
            result.stageManager = .init(value: try Self.readStageManager())
        }
        return result
    }

    func apply(_ configuration: RemoteModeConfiguration, snapshot: RemoteModeSnapshot) async throws {
        if let display = snapshot.display { try Self.setDisplay(display.uuid, mode: display.target) }
        if let dock = snapshot.dock {
            try await Self.setDock(autohide: dock.autohide == nil ? nil : configuration.dockVisibility == .disabled,
                                   size: dock.size == nil ? nil : configuration.dockSize)
        }
        if snapshot.stageManager != nil { try Self.setStageManager(configuration.stageManager == .enabled) }
    }

    func restore(_ snapshot: RemoteModeSnapshot) async -> RemoteModeRestoreResult {
        var remaining = snapshot
        var errors: [String] = []
        if let stage = snapshot.stageManager {
            do { try Self.setStageManager(stage.value); remaining.stageManager = nil }
            catch { errors.append("台前调度恢复失败：\(error.localizedDescription)") }
        }
        if let dock = snapshot.dock {
            do { try await Self.setDock(autohide: dock.autohide, size: dock.size); remaining.dock = nil }
            catch { errors.append("Dock 恢复失败：\(error.localizedDescription)") }
        }
        if let display = snapshot.display {
            do { try Self.setDisplay(display.uuid, mode: display.original); remaining.display = nil }
            catch { errors.append("显示缩放恢复失败：\(error.localizedDescription)") }
        }
        return .init(remaining: remaining, errors: errors)
    }

    private static func builtinDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private static func modes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []).filter { $0.isUsableForDesktopGUI() }
    }

    private static func describe(_ mode: CGDisplayMode) -> RemoteDisplayMode {
        .init(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
              refreshRate: mode.refreshRate, modeID: mode.ioDisplayModeID,
              isDefault: mode.ioFlags & UInt32(kDisplayModeDefaultFlag) != 0)
    }

    private static func setDisplay(_ uuidString: String, mode requested: RemoteDisplayMode) throws {
        guard let uuid = CFUUIDCreateFromString(nil, uuidString as CFString) else {
            throw RemoteModeError.unavailable("显示器标识无效")
        }
        let id = CGDisplayGetDisplayIDFromUUID(uuid)
        guard id != kCGNullDirectDisplay, CGDisplayIsOnline(id) != 0, CGDisplayIsInMirrorSet(id) == 0 else {
            throw RemoteModeError.unavailable("原显示器未连接或处于镜像模式，请恢复连接后重试")
        }
        if let current = CGDisplayCopyDisplayMode(id), requested.matches(describe(current)) { return }
        let matches = modes(id).filter { requested.matches(describe($0)) }
        guard let mode = matches.first(where: { $0.ioDisplayModeID == requested.modeID }) ?? matches.first else {
            throw RemoteModeError.unavailable("原显示模式暂不可用，已保留恢复记录")
        }
        // App-only mode changes are undone again by WindowServer when this process exits.
        // A session configuration lets the restored original survive normal quit without
        // overwriting the user's permanent display configuration.
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success, let configuration else {
            throw RemoteModeError.unavailable("无法开始显示器配置")
        }
        guard CGConfigureDisplayWithDisplayMode(configuration, id, mode, nil) == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw RemoteModeError.unavailable("系统不支持请求的显示模式")
        }
        guard CGCompleteDisplayConfiguration(configuration, .forSession) == .success,
              let actual = CGDisplayCopyDisplayMode(id), requested.matches(describe(actual)) else {
            throw RemoteModeError.unavailable("系统未应用请求的显示模式")
        }
    }

    /// Undocumented CoreDock SPI, resolved at runtime just like the brightness services.
    /// Reading both properties successfully is required before either setter can run.
    private struct DockAPI {
        let getHidden: @convention(c) () -> UInt8
        let setHidden: @convention(c) (UInt8) -> Void
        let getSize: @convention(c) () -> Float
        let setSize: @convention(c) (Float) -> Void

        init?() {
            guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY),
                  let gh = dlsym(handle, "CoreDockGetAutoHideEnabled"),
                  let sh = dlsym(handle, "CoreDockSetAutoHideEnabled"),
                  let gs = dlsym(handle, "CoreDockGetTileSize"),
                  let ss = dlsym(handle, "CoreDockSetTileSize") else { return nil }
            getHidden = unsafeBitCast(gh, to: (@convention(c) () -> UInt8).self)
            setHidden = unsafeBitCast(sh, to: (@convention(c) (UInt8) -> Void).self)
            getSize = unsafeBitCast(gs, to: (@convention(c) () -> Float).self)
            setSize = unsafeBitCast(ss, to: (@convention(c) (Float) -> Void).self)
        }
    }
    private static let dockAPI = DockAPI()
    static var dockAvailable: Bool { dockAPI != nil }

    private static func readDock() async throws -> (autohide: Bool, size: Double) {
        guard let api = dockAPI else { throw RemoteModeError.unavailable("当前系统的 Dock 控制接口不可用") }
        let hidden = api.getHidden()
        let size = Double(api.getSize())
        guard hidden <= 1, size.isFinite, (0...1).contains(size) else {
            throw RemoteModeError.unavailable("无法读取 Dock 原设置，未做修改")
        }
        return (hidden == 1, size)
    }

    private static func setDock(autohide: Bool?, size: Double?) async throws {
        guard let api = dockAPI else { throw RemoteModeError.unavailable("当前系统的 Dock 控制接口不可用") }
        _ = try await readDock()
        if let size, !size.isFinite || !(0...1).contains(size) {
            throw RemoteModeError.unavailable("Dock 大小无效")
        }
        if let autohide { api.setHidden(autohide ? 1 : 0) }
        if let size { api.setSize(Float(size)) }
        for _ in 0..<20 {
            let actual = try await readDock()
            if (autohide == nil || actual.autohide == autohide),
               (size == nil || RemoteModeConfiguration.dockSizeMatches(actual: actual.size, requested: size ?? actual.size)) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw RemoteModeError.unavailable("系统未应用 Dock 设置，已保留恢复记录")
    }

    private static func readStageManager() throws -> Bool? {
        guard CFPreferencesSynchronize(stageDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw RemoteModeError.unavailable("无法读取台前调度设置")
        }
        guard let raw = CFPreferencesCopyValue(stageKey, stageDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return nil }
        guard CFGetTypeID(raw) == CFBooleanGetTypeID(), let value = raw as? Bool else {
            throw RemoteModeError.unavailable("台前调度设置格式不受支持")
        }
        return value
    }

    private static func setStageManager(_ enabled: Bool?) throws {
        CFPreferencesSetValue(stageKey, enabled.map { $0 as CFBoolean }, stageDomain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(stageDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
              try readStageManager() == enabled else {
            throw RemoteModeError.unavailable("系统未保存台前调度设置")
        }
    }
}
