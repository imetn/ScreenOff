import AppKit
import SwiftUI

/// 菜单栏按「双操作 + 持续状态」组织：
/// 关闭屏幕与关闭输入是即时操作，远程模式与保持唤醒是持续状态，自动关屏连同时长自成一组。
/// 完整配置仍然只在设置窗口里。
struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: ScreenOffController
    let presentationController: AppPresentationController

    private var preferences: ScreenOffPreferences { controller.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            modeActions
            Divider().padding(.vertical, 10)
            screenAndAwake
            Divider().padding(.vertical, 10)
            automaticScreenOff
            if let status {
                statusFooter(status)
            }
            Divider().padding(.vertical, 10)
            footer
        }
        .padding(15)
        .frame(width: 320)
        .onAppear { controller.refreshReadings() }
    }

    // MARK: - 两个模式

    /// 顶部只放「进入后要显式退出」的两件事。关闭屏幕是一次性动作，放在下面那组。
    private var modeActions: some View {
        HStack(spacing: 8) {
            modeButton(
                title: remoteModeButtonTitle,
                systemImage: controller.remoteMode.needsRecovery ? "arrow.clockwise" : "desktopcomputer",
                active: controller.remoteMode.isActive,
                busy: controller.remoteMode.isBusy,
                identifier: "toggleRemoteMode"
            ) { controller.toggleRemoteMode() }

            modeButton(
                title: controller.inputLock.isLocked ? String(localized: "恢复输入") : String(localized: "关闭输入"),
                systemImage: "keyboard",
                active: controller.inputLock.isLocked,
                busy: false,
                identifier: "toggleInputLock"
            ) {
                dismiss()
                controller.toggleInputLock()
            }
        }
        .controlSize(.large)
    }

    /// 两个模式共用同一种按钮：生效时填强调色。这是菜单里唯一需要一眼看出开没开的地方。
    @ViewBuilder
    private func modeButton(
        title: String,
        systemImage: String,
        active: Bool,
        busy: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        let content = HStack(spacing: 6) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .frame(maxWidth: .infinity, minHeight: 24)

        if active {
            Button(action: action) { content }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                .accessibilityIdentifier(identifier)
        } else {
            Button(action: action) { content }
                .buttonStyle(.bordered)
                .disabled(busy)
                .accessibilityIdentifier(identifier)
        }
    }

    private var remoteModeButtonTitle: String {
        if controller.remoteMode.isBusy { return String(localized: "切换中") }
        if controller.remoteMode.needsRecovery { return String(localized: "重试恢复") }
        return String(localized: "远程模式")
    }

    // MARK: - 屏幕与唤醒

    private var screenAndAwake: some View {
        VStack(spacing: 0) {
            // 文案是状态不是动作：「关闭屏幕」配一个开关会读不通——开着到底指屏幕亮还是指功能启用。
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text("屏幕")
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { controller.screenState == .on },
                    set: { _ in controller.toggleScreen() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(controller.screenState == .off ? String(localized: "点亮屏幕") : String(localized: "关闭屏幕"))
                .accessibilityIdentifier("toggleScreen")
            }
            .frame(height: 36)
            .disabled(!controller.canControlDisplay)

            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                if controller.remoteMode.isActive {
                    Text("已保持唤醒")
                    Spacer(minLength: 8)
                    Text("随远程模式")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("保持唤醒")
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { preferences.keepAwake },
                        set: { controller.setKeepAwake($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel("保持唤醒")
                }
            }
            .frame(height: 36)
        }
    }

    // MARK: - 自动关屏

    private var automaticScreenOff: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("自动关屏")
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { preferences.autoScreenOff },
                    set: { controller.setAutoScreenOff($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("自动关屏")
                .accessibilityIdentifier("toggleAutoScreenOff")
            }
            .frame(height: 28)
            .disabled(!controller.canControlDisplay)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("空闲时长")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(IdleDelay.title(preferences.idleDelay))
                        .monospacedDigit()
                }
                .frame(height: 20)

                Slider(
                    value: Binding(
                        get: { Double(IdleDelay.index(of: preferences.idleDelay)) },
                        set: { controller.setIdleDelay(IdleDelay.seconds(at: Int($0.rounded()))) }
                    ),
                    in: 0...Double(IdleDelay.maximumIndex),
                    step: 1
                )
                .controlSize(.small)
                .accessibilityLabel("空闲时长")
                .accessibilityValue(IdleDelay.title(preferences.idleDelay))
                .accessibilityIdentifier("menuIdleDelay")

                HStack {
                    Text(IdleDelay.title(IdleDelay.options.first ?? 60))
                    Spacer()
                    Text(IdleDelay.title(IdleDelay.options.last ?? 14400))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .disabled(!preferences.autoScreenOff || !controller.canControlDisplay)
        }
    }

    // MARK: - 状态与页脚

    private struct Status {
        let message: String
        /// 为真时附带「前往系统设置」入口。
        var settingsAction: (() -> Void)?
    }

    private var status: Status? {
        if let error = controller.inputLock.lastError {
            return Status(message: error, settingsAction: { controller.inputLock.openAccessibilitySettings() })
        }
        if let error = controller.remoteMode.error { return Status(message: error) }
        if let error = controller.lastError { return Status(message: error) }
        if !controller.canControlDisplay { return Status(message: String(localized: "未能解析屏幕亮度接口，自动关闭屏幕不可用")) }
        if preferences.needsIdleTracking, !controller.isInputMonitoringReliable {
            return Status(
                message: controller.isInputMonitoringDenied
                    ? String(localized: "「输入监控」权限已被拒绝，无法区分远程输入，自动关闭可能被远程操作打断")
                    : String(localized: "未取得「输入监控」权限，无法区分远程输入，自动关闭可能被远程操作打断"),
                settingsAction: { controller.openInputMonitoringSettings() }
            )
        }
        return nil
    }

    private func statusFooter(_ status: Status) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(status.message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action = status.settingsAction {
                Button("前往系统设置授权…", action: action)
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.leading, 20)
            }
        }
        .padding(.top, 12)
    }

    private var footer: some View {
        HStack {
            Button {
                dismiss()
                presentationController.prepareToOpenSettings()
                openSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
                    .font(.system(size: 13))
                    .frame(minWidth: 60, minHeight: 30, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("设置")
            .accessibilityLabel("设置")
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                // 图标放在文字右侧：与左端的齿轮一起朝外，页脚两端才对称。
                HStack(spacing: 6) {
                    Text("退出")
                    Image(systemName: "power")
                }
                .font(.system(size: 13))
                .frame(minWidth: 54, minHeight: 30, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("退出 Screen Off")
            .accessibilityLabel("退出 Screen Off")
        }
    }
}
