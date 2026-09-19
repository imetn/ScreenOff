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
            instantActions
            Divider().padding(.vertical, 10)
            continuousStates
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

    // MARK: - 即时操作

    private var instantActions: some View {
        HStack(spacing: 8) {
            Button {
                controller.toggleScreen()
            } label: {
                Label(
                    controller.screenState == .off ? "点亮屏幕" : "关闭屏幕",
                    systemImage: "display"
                )
                .frame(maxWidth: .infinity, minHeight: 24)
            }
            .disabled(!controller.canControlDisplay)
            .accessibilityIdentifier("toggleScreen")

            Button {
                dismiss()
                controller.toggleInputLock()
            } label: {
                Label(
                    controller.inputLock.isLocked ? "恢复输入" : "关闭输入",
                    systemImage: "keyboard"
                )
                .frame(maxWidth: .infinity, minHeight: 24)
            }
            .accessibilityIdentifier("toggleInputLock")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    // MARK: - 持续状态

    private var continuousStates: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: controller.remoteMode.needsRecovery ? "arrow.clockwise" : "desktopcomputer")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(remoteModeTitle)
                Spacer(minLength: 8)
                if controller.remoteMode.isBusy {
                    ProgressView().controlSize(.small)
                }
                Toggle("", isOn: Binding(
                    get: { controller.remoteMode.isActive },
                    set: { _ in controller.toggleRemoteMode() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(controller.remoteMode.isBusy)
                .accessibilityLabel(remoteModeTitle)
                .accessibilityIdentifier("toggleRemoteMode")
            }
            .frame(height: 36)

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

    private var remoteModeTitle: String {
        if controller.remoteMode.isBusy { return "远程模式切换中" }
        if controller.remoteMode.needsRecovery { return "重试恢复原设置" }
        return "远程模式"
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
        if !controller.canControlDisplay { return Status(message: "未能解析屏幕亮度接口，自动关闭屏幕不可用") }
        if preferences.needsIdleTracking, !controller.isInputMonitoringReliable {
            return Status(
                message: controller.isInputMonitoringDenied
                    ? "「输入监控」权限已被拒绝，无法区分远程输入，自动关闭可能被远程操作打断"
                    : "未取得「输入监控」权限，无法区分远程输入，自动关闭可能被远程操作打断",
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
                Label("设置…", systemImage: "gearshape")
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
