import AppKit
import SwiftUI

/// 菜单栏快捷窗口。304 pt 紧凑布局：主操作 → 亮度 → 分组开关 → 图标页脚。
struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: ScreenOffController
    let presentationController: AppPresentationController

    private var preferences: ScreenOffPreferences { controller.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            primaryAction
            brightnessControl
            Divider().padding(.vertical, 12)
            keepAwakeSection
            autoOffSection.padding(.top, 12)
            if let status {
                statusFooter(status)
            }
            Divider().padding(.vertical, 12)
            footer
        }
        .padding(14)
        .frame(width: 304)
        .onAppear { controller.refreshReadings() }
    }

    // MARK: - 立即关闭屏幕

    private var primaryAction: some View {
        Button {
            controller.toggleScreen()
        } label: {
            HStack(spacing: 7) {
                (controller.screenState == .off ? MenuBarGlyph.filled : MenuBarGlyph.outline).image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15)
                Text(controller.screenState == .off ? "点亮屏幕" : "立即关闭屏幕")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!controller.canControlDisplay)
        .help(controller.canControlDisplay ? "" : "当前设备无法调节内建屏幕亮度")
    }

    // MARK: - 屏幕亮度

    private var brightnessControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("屏幕亮度")
            Slider(
                value: Binding(
                    get: { Double(controller.displayBrightness) },
                    set: { controller.setDisplayBrightness(Float($0)) }
                ),
                in: 0...1
            )
            .disabled(!controller.canControlDisplay)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // MARK: - 分组开关

    private var keepAwakeSection: some View {
        CardSection("保持唤醒", titleInset: 12, showsContainer: false) {
            CardRow(title: "保持电脑唤醒") {
                Toggle("", isOn: Binding(
                    get: { preferences.keepAwake },
                    set: { controller.setKeepAwake($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            CardDivider()
            CardRow(
                title: "合盖后保持唤醒",
                subtitle: controller.isOnACPower ? nil : "需接通电源，当前已暂停"
            ) {
                Toggle("", isOn: Binding(
                    get: { preferences.keepAwakeWithLidClosed },
                    set: { controller.setKeepAwakeWithLidClosed($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    private var autoOffSection: some View {
        CardSection("屏幕关闭", titleInset: 12, showsContainer: false) {
            CardRow(title: "自动关闭屏幕", isEnabled: controller.canControlDisplay) {
                Toggle("", isOn: Binding(
                    get: { preferences.autoScreenOff },
                    set: { controller.setAutoScreenOff($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!controller.canControlDisplay)
            }
            CardDivider()
            CardRow(title: "同时关闭键盘背光", isEnabled: controller.canControlKeyboardBacklight) {
                Toggle("", isOn: Binding(
                    get: { preferences.autoKeyboardBacklightOff },
                    set: { controller.setAutoKeyboardBacklightOff($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!controller.canControlKeyboardBacklight)
            }
            CardDivider()
            IdleDelayRow(
                seconds: preferences.idleDelay,
                isEnabled: preferences.needsIdleTracking
            ) { controller.setIdleDelay($0) }
        }
    }

    // MARK: - 状态与页脚

    private struct Status {
        let message: String
        /// 为真时附带「前往系统设置」入口。
        var offersInputMonitoringSettings = false
    }

    private var status: Status? {
        if let error = controller.lastError { return Status(message: error) }
        if !controller.canControlDisplay { return Status(message: "未能解析屏幕亮度接口，自动关闭屏幕不可用") }
        if preferences.needsIdleTracking, !controller.isInputMonitoringReliable {
            return Status(
                message: controller.isInputMonitoringDenied
                    ? "「输入监控」权限已被拒绝，无法区分远程输入，自动关闭可能被远程操作打断"
                    : "未取得「输入监控」权限，无法区分远程输入，自动关闭可能被远程操作打断",
                offersInputMonitoringSettings: true
            )
        }
        if !controller.canControlKeyboardBacklight { return Status(message: "当前键盘不支持背光调节") }
        return nil
    }

    private func statusFooter(_ status: Status) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(status.message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if status.offersInputMonitoringSettings {
                Button("前往系统设置授权…") { controller.openInputMonitoringSettings() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                    .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var footer: some View {
        HStack {
            Button {
                dismiss()
                presentationController.prepareToOpenSettings()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 36, height: 30)
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
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 36, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("退出 Screen Off")
            .accessibilityLabel("退出 Screen Off")
        }
        .padding(.horizontal, 8)
    }
}
