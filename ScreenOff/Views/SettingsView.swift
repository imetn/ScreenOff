import AppKit
import KeyboardShortcuts
import SwiftUI

/// 设置窗口参考 One Switch：顶部工具栏式标签，内容使用紧凑的原生分组布局。
struct SettingsView: View {
    @Bindable var controller: ScreenOffController
    @Bindable var updateController: UpdateController
    let presentationController: AppPresentationController
    @State private var maximumContentHeight: CGFloat = .infinity
    @State private var shortcutRecordingMessage: String?

    private var preferences: ScreenOffPreferences { controller.preferences }
    private var minimumContentHeight: CGFloat { min(324, maximumContentHeight) }

    var body: some View {
        WholePointHeightLayout {
            TabView {
                featureSettings
                    .tabItem { Label("功能", systemImage: "switch.2") }

                generalSettings
                    .tabItem { Label("通用", systemImage: "gearshape") }

                aboutSettings
                    .tabItem { Label("关于", systemImage: "info.circle") }
            }
            .frame(width: 520)
            // 以最高的功能页（约 322 pt）为统一基准，较短页面共用这个最小高度。
            .frame(minHeight: minimumContentHeight, maxHeight: maximumContentHeight)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) {
            Divider()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background(SettingsWindowSizing(maximumContentHeight: $maximumContentHeight))
        .navigationTitle("设置")
        .onAppear { controller.refreshReadings() }
    }

    // MARK: - 功能

    private var featureSettings: some View {
        settingsForm {
            Section("保持唤醒") {
                Toggle("保持电脑唤醒", isOn: Binding(
                    get: { preferences.keepAwake },
                    set: { controller.setKeepAwake($0) }
                ))
                Toggle(isOn: Binding(
                    get: { preferences.keepAwakeWithLidClosed },
                    set: { controller.setKeepAwakeWithLidClosed($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("合盖后保持唤醒")
                        Text(controller.isOnACPower ? "仅在接通电源时生效" : "当前使用电池，已暂停")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("自动关闭屏幕", isOn: Binding(
                    get: { preferences.autoScreenOff },
                    set: { controller.setAutoScreenOff($0) }
                ))
                .disabled(!controller.canControlDisplay)
                Toggle("同时关闭键盘背光", isOn: Binding(
                    get: { preferences.autoKeyboardBacklightOff },
                    set: { controller.setAutoKeyboardBacklightOff($0) }
                ))
                .disabled(!controller.canControlKeyboardBacklight)
                LabeledContent("空闲时间") {
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
                        .accessibilityLabel("空闲时间")
                        .accessibilityValue(IdleDelay.title(preferences.idleDelay))

                        Text(IdleDelay.title(preferences.idleDelay))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                .disabled(!preferences.autoScreenOff)
            } header: {
                Text("屏幕关闭")
            } footer: {
                if let note = capabilityNote {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(note.message, systemImage: "exclamationmark.triangle")
                        if note.offersInputMonitoringSettings {
                            Button("打开系统设置…") { controller.openInputMonitoringSettings() }
                                .buttonStyle(.link)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 通用

    private var generalSettings: some View {
        settingsForm {
            Section("启动") {
                Toggle("登录时启动", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                ))
            }

            Section("快捷键") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("关闭屏幕") {
                        HStack(spacing: 6) {
                            ShortcutRecorderButton(
                                shortcut: Binding(
                                    get: { preferences.screenOffShortcut },
                                    set: { controller.setScreenOffShortcut($0) }
                                ),
                                validate: { controller.validateScreenOffShortcut($0) },
                                onRecordingMessage: { shortcutRecordingMessage = $0 }
                            )
                            .fixedSize()

                            if preferences.screenOffShortcut != nil {
                                Button {
                                    controller.setScreenOffShortcut(nil)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("清除快捷键")
                                .accessibilityLabel("清除关闭屏幕快捷键")
                            }
                        }
                    }
                    if let shortcutRecordingMessage {
                        Text(shortcutRecordingMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("软件更新") {
                Toggle("自动检查更新", isOn: Binding(
                    get: { updateController.automaticallyChecksForUpdates },
                    set: { updateController.setAutomaticallyChecksForUpdates($0) }
                ))
                .disabled(!updateController.isConfigured)
            }
        }
    }

    /// 两页共用原生表单，统一开关、标题、分隔线与内外留白。
    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form(content: content)
            .formStyle(.grouped)
            // 窄表单不向全宽标题栏延伸底色，保留系统标签的玻璃选中效果。
            .scrollContentBackground(.hidden)
            .frame(width: 392)
            // 系统滚动口袋仍可能绘制到标题栏；将其裁剪在正文边界内。
            .clipped()
            .frame(maxWidth: .infinity)
    }

    // MARK: - 关于

    private var aboutSettings: some View {
        ScrollView {
            aboutContent
        }
    }

    private var aboutContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 28) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Screen Off")
                        .font(.title2.weight(.semibold))

                    Text("让 Mac 保持在线，同时关闭不必要的屏幕与键盘背光。")
                        .foregroundStyle(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前版本")
                            .font(.headline)

                        HStack(spacing: 10) {
                            Text(versionText)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 12)

                            Button("检查更新") { updateController.checkForUpdates() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!updateController.isConfigured)
                        }

                        if !updateController.isConfigured {
                            Text(updateController.configurationMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("开源")
                            .font(.headline)
                        Text(updateController.githubURL == nil ? "GitHub 仓库尚未发布" : "源代码与问题反馈均托管在 GitHub")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 24)

            HStack(spacing: 12) {
                if let githubURL = updateController.githubURL {
                    Link(destination: githubURL) {
                        Label {
                            Text("GitHub")
                        } icon: {
                            Image("GitHubMark")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                        }
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
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 392)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(minHeight: minimumContentHeight, alignment: .top)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private struct CapabilityNote {
        let message: String
        var offersInputMonitoringSettings = false
    }

    private var capabilityNote: CapabilityNote? {
        if !controller.canControlDisplay { return CapabilityNote(message: "无法控制内建屏幕亮度，屏幕关闭功能不可用。") }
        if preferences.needsIdleTracking, !controller.isInputMonitoringReliable {
            return CapabilityNote(
                message: controller.isInputMonitoringDenied
                    ? "「输入监控」权限已被拒绝，无法区分物理输入与远程输入。"
                    : "请在系统设置的「输入监控」中允许 Screen Off，否则无法区分远程输入。",
                offersInputMonitoringSettings: true
            )
        }
        if !controller.canControlKeyboardBacklight { return CapabilityNote(message: "当前键盘不支持背光调节。") }
        return nil
    }
}

/// 原生表单的理想高度可能包含小数；窗口取整向下时会产生不足 1 pt 的虚假滚动范围。
/// 向上取整后，将完整高度重新提议给内容，不隐藏真正溢出时所需的滚动条。
private struct WholePointHeightLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(proposal)
        return CGSize(width: size.width, height: ceil(size.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}
