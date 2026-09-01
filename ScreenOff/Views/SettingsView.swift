import AppKit
import SwiftUI

/// 设置窗口参考 One Switch：顶部工具栏式标签，内容使用紧凑的原生分组布局。
struct SettingsView: View {
    @Bindable var controller: ScreenOffController
    @Bindable var updateController: UpdateController
    let presentationController: AppPresentationController

    private var preferences: ScreenOffPreferences { controller.preferences }

    var body: some View {
        TabView {
            featureSettings
                .tabItem { Label("功能", systemImage: "switch.2") }

            generalSettings
                .tabItem { Label("通用", systemImage: "gearshape") }

            aboutSettings
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 281)
        .navigationTitle("设置")
        .onAppear { controller.refreshReadings() }
    }

    // MARK: - 功能

    private var featureSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSection("保持唤醒", titleInset: 10) {
                CardRow(title: "保持电脑唤醒", height: 36) {
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
                    subtitle: controller.isOnACPower ? "仅在接通电源时生效" : "当前使用电池，已暂停",
                    height: 40
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.keepAwakeWithLidClosed },
                        set: { controller.setKeepAwakeWithLidClosed($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            CardSection("屏幕关闭", titleInset: 10) {
                CardRow(title: "自动关闭屏幕", height: 36, isEnabled: controller.canControlDisplay) {
                    Toggle("", isOn: Binding(
                        get: { preferences.autoScreenOff },
                        set: { controller.setAutoScreenOff($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!controller.canControlDisplay)
                }
                CardDivider()
                CardRow(
                    title: "同时关闭键盘背光",
                    height: 36,
                    isEnabled: controller.canControlKeyboardBacklight
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.autoKeyboardBacklightOff },
                        set: { controller.setAutoKeyboardBacklightOff($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!controller.canControlKeyboardBacklight)
                }
                CardDivider()
                CardRow(title: "空闲时间", height: 42, isEnabled: preferences.autoScreenOff) {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { Double(IdleDelay.index(of: preferences.idleDelay)) },
                                set: { controller.setIdleDelay(IdleDelay.seconds(at: Int($0.rounded()))) }
                            ),
                            in: 0...Double(IdleDelay.maximumIndex),
                            step: 1
                        )
                        .frame(width: 148)
                        .disabled(!preferences.autoScreenOff)

                        Text(IdleDelay.title(preferences.idleDelay))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }

            if let note = capabilityNote {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 392)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - 通用

    private var generalSettings: some View {
        Form {
            Section("启动") {
                Toggle("登录时启动", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                ))
            }

            Section("软件更新") {
                Toggle("自动检查更新", isOn: Binding(
                    get: { updateController.automaticallyChecksForUpdates },
                    set: { updateController.setAutomaticallyChecksForUpdates($0) }
                ))
                .disabled(!updateController.isConfigured)

                LabeledContent("更新方式") {
                    Text(updateController.configurationMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 392)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 14)
    }

    // MARK: - 关于

    private var aboutSettings: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 28) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Screen Off")
                            .font(.title2.weight(.semibold))
                        Text("版本 \(versionText)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    Text("让 Mac 保持在线，同时关闭不必要的屏幕与键盘背光。")
                        .foregroundStyle(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("开源")
                            .font(.headline)
                        Text(updateController.githubURL == nil ? "GitHub 仓库尚未发布" : "源代码与问题反馈均托管在 GitHub")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("软件更新")
                            .font(.headline)
                        Text(updateController.configurationMessage)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 18)

            HStack {
                if let githubURL = updateController.githubURL {
                    Link(destination: githubURL) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("GitHub 尚未发布") {}
                        .buttonStyle(.bordered)
                        .disabled(true)
                }

                if let issuesURL = updateController.issuesURL {
                    Link(destination: issuesURL) {
                        Label("反馈问题", systemImage: "exclamationmark.bubble")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                    } label: {
                        Label("反馈问题", systemImage: "exclamationmark.bubble")
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }

                Spacer()

                Button("检查更新…") { updateController.checkForUpdates() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!updateController.isConfigured)
            }
        }
        .frame(width: 392)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var capabilityNote: String? {
        if !controller.canControlDisplay { return "无法控制内建屏幕亮度，屏幕关闭功能不可用。" }
        if preferences.needsIdleTracking, !controller.isInputMonitoringReliable {
            return "请在系统设置的输入监控中允许 Screen Off，否则无法区分物理输入与远程输入。"
        }
        if !controller.canControlKeyboardBacklight { return "当前键盘不支持背光调节。" }
        return nil
    }
}
