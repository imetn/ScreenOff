import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

/// 设置窗口参考 One Switch：顶部工具栏式标签，内容使用紧凑的原生分组布局。
struct SettingsView: View {
    @Bindable var controller: ScreenOffController
    @Bindable var updateController: UpdateController
    let presentationController: AppPresentationController
    @State private var maximumContentHeight: CGFloat = .infinity
    @State private var shortcutRecordingMessage: String?
    @State private var remoteShortcutRecordingMessage: String?

    private var preferences: ScreenOffPreferences { controller.preferences }
    private var minimumContentHeight: CGFloat { min(332, maximumContentHeight) }

    var body: some View {
        WholePointHeightLayout {
            TabView {
                featureSettings
                    .tabItem { Label("功能", systemImage: "switch.2") }

                remoteSettings
                    .tabItem { Label("远程模式", systemImage: "desktopcomputer") }

                generalSettings
                    .tabItem { Label("通用", systemImage: "gearshape") }

                aboutSettings
                    .tabItem { Label("关于", systemImage: "info.circle") }
            }
            .frame(width: 520)
            // 四页保持相同高度；小屏幕仍允许表单内部滚动。
            .frame(height: minimumContentHeight)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) {
            Divider()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background(SettingsWindowSizing(maximumContentHeight: $maximumContentHeight))
        .navigationTitle("设置")
        .onAppear {
            controller.refreshReadings()
            controller.refreshPermissions()
        }
        // 授权是在系统设置里完成的，切回本窗口时必须重新查询，否则状态会一直停在旧值。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshPermissions()
        }
    }

    // MARK: - 功能

    private var featureSettings: some View {
        settingsForm {
            Section {
                if controller.remoteMode.isActive {
                    LabeledContent("保持 Mac 唤醒", value: "随远程模式")
                } else {
                    Toggle("保持 Mac 唤醒", isOn: Binding(
                        get: { preferences.keepAwake },
                        set: { controller.setKeepAwake($0) }
                    ))
                }
                Toggle("合盖后保持唤醒", isOn: Binding(
                    get: { preferences.keepAwakeWithLidClosed },
                    set: { controller.setKeepAwakeWithLidClosed($0) }
                ))
                .disabled(!controller.lidWake.isSupported || !controller.isOnACPower)
                .help("写入系统级睡眠设置，让 Mac 合上盖子也不睡眠。需要一次性批准后台守护进程；拔掉电源、退出 App 或 App 异常结束时都会自动恢复。")
                if let note = lidWakeNote {
                    HStack(spacing: 8) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if controller.lidWake.readiness == .requiresApproval {
                            Button("前往批准…") { controller.lidWake.openLoginItemsSettings() }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                }
                Toggle("自动关闭屏幕", isOn: Binding(
                    get: { preferences.autoScreenOff },
                    set: { controller.setAutoScreenOff($0) }
                ))
                .disabled(!controller.canControlDisplay)
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
                .disabled(!preferences.autoScreenOff || !controller.canControlDisplay)
                Toggle("同时关闭键盘背光", isOn: Binding(
                    get: { preferences.autoKeyboardBacklightOff },
                    set: { controller.setAutoKeyboardBacklightOff($0) }
                ))
                .disabled(!controller.canControlKeyboardBacklight)
                Toggle("关闭输入时显示解锁提示", isOn: Binding(
                    get: { preferences.showsInputLockOverlay },
                    set: { controller.setShowsInputLockOverlay($0) }
                ))
                .help("关闭输入后屏幕会一并熄灭；提示写明按住 Fn + Delete 一秒解锁。关掉提示后解锁方式不变。")
            }

            Section {
                LabeledContent("屏幕亮度") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { Double(controller.displayBrightness) },
                            set: { controller.setDisplayBrightness(Float($0)) }
                        ), in: 0...1)
                        .frame(width: 136)
                        .accessibilityLabel("屏幕亮度")
                        Button(controller.screenState == .off ? "点亮屏幕" : "关闭屏幕") {
                            controller.toggleScreen()
                        }
                    }
                }
                .disabled(!controller.canControlDisplay)
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

    // MARK: - 远程模式

    private func remoteBinding<Value>(_ keyPath: WritableKeyPath<RemoteModeConfiguration, Value>) -> Binding<Value> {
        Binding(get: { preferences.remoteModeConfiguration[keyPath: keyPath] },
                set: { preferences.remoteModeConfiguration[keyPath: keyPath] = $0 })
    }

    private var remoteSettings: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsForm {
                    Section {
                        Picker("显示缩放", selection: remoteBinding(\.defaultDisplayMode)) {
                            Text("保持原样").tag(false)
                            Text("默认").tag(true)
                        }
                        .help(controller.defaultDisplayModeDescription)

                        Picker("关闭背光", selection: remoteBinding(\.backlightSetting)) {
                            ForEach(RemoteModeConfiguration.BacklightSetting.allCases, id: \.self) { setting in
                                Text(setting.title).tag(setting)
                                    .disabled(setting != .unchanged && (!controller.canControlDisplay ||
                                        (setting == .displayAndKeyboard && !controller.canControlKeyboardBacklight)))
                            }
                        }

                        Picker("Dock 显示", selection: remoteBinding(\.dockVisibility)) {
                            Text("保持原样").tag(RemoteModeConfiguration.SwitchSetting.unchanged)
                            Text("始终显示").tag(RemoteModeConfiguration.SwitchSetting.enabled)
                                .disabled(!RemoteDesktopService.dockAvailable)
                            Text("自动隐藏").tag(RemoteModeConfiguration.SwitchSetting.disabled)
                                .disabled(!RemoteDesktopService.dockAvailable)
                        }

                        Toggle("调整 Dock 大小", isOn: remoteBinding(\.resizeDock))
                            .toggleStyle(.switch)
                            .disabled(!RemoteDesktopService.dockAvailable && !preferences.remoteModeConfiguration.resizeDock)

                        LabeledContent("大小") {
                            HStack(spacing: 10) {
                                Slider(value: remoteBinding(\.dockSize), in: 0...1, step: 0.05)
                                    .labelsHidden()
                                    .frame(width: 244)
                                    .accessibilityLabel("远程模式 Dock 大小")
                                Text(preferences.remoteModeConfiguration.dockSize, format: .percent.precision(.fractionLength(0)))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit().frame(width: 38, alignment: .trailing)
                            }
                        }
                        .disabled(!preferences.remoteModeConfiguration.resizeDock || !RemoteDesktopService.dockAvailable)

                        Picker("台前调度", selection: remoteBinding(\.stageManager)) {
                            ForEach(RemoteModeConfiguration.SwitchSetting.allCases, id: \.self) { setting in
                                Text(setting.title).tag(setting)
                                    .disabled(setting != .unchanged && !RemoteDesktopService.stageManagerAvailable)
                            }
                        }
                    }
                    .disabled(controller.remoteMode.state != .inactive)
                }
                // 六个独立设置项；开关与大小滑块各占一条原生表单行。
                .frame(height: 270)

                VStack(spacing: 12) {
                    if let error = controller.remoteMode.error ?? controller.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    RemoteModeButton(controller: controller)
                }
                .padding(.horizontal, 56)
                .padding(.bottom, 20)
            }
        }
    }

    /// 权限项的状态。名称一律用系统设置里的原名，用户才知道该去哪一栏找。
    private enum PermissionState {
        case granted, missing, denied, pendingApproval, unsupported

        var symbol: String {
            switch self {
            case .granted: "checkmark.circle.fill"
            case .missing: "circle.dashed"
            case .denied: "xmark.circle.fill"
            case .pendingApproval: "clock.fill"
            case .unsupported: "minus.circle"
            }
        }

        var tint: Color {
            switch self {
            case .granted: .green
            case .denied: .red
            case .pendingApproval: .orange
            case .missing, .unsupported: .secondary
            }
        }

        /// 已授权与不可用没有下一步动作，只显示状态文字。
        var actionTitle: String? {
            switch self {
            case .granted, .unsupported: nil
            case .missing: "授权…"
            case .denied: "前往设置…"
            case .pendingApproval: "前往批准…"
            }
        }

        var statusText: String {
            switch self {
            case .granted: "已授权"
            case .unsupported: "不可用"
            case .missing: "未授权"
            case .denied: "已拒绝"
            case .pendingApproval: "等待批准"
            }
        }
    }

    private var lidWakePermissionState: PermissionState {
        switch controller.lidWake.readiness {
        case .ready: .granted
        case .requiresApproval: .pendingApproval
        case .notRegistered: .missing
        case .unsupported: .unsupported
        }
    }

    private func permissionRow(
        title: String, detail: String, state: PermissionState, action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: state.symbol)
                    .foregroundStyle(state.tint)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 8)
                if let actionTitle = state.actionTitle {
                    Button(actionTitle, action: action)
                } else {
                    Text(state.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(state.statusText)。\(detail)")
    }

    /// 合盖保持唤醒的前置条件说明，条件满足时不占位置。
    private var lidWakeNote: String? {
        guard controller.lidWake.isSupported else { return "当前系统不支持写入睡眠设置，合盖仍会睡眠。" }
        if !controller.isOnACPower { return "电池供电时不可用：合盖不睡会耗尽电池，请接通电源。" }
        switch controller.lidWake.readiness {
        case .requiresApproval: return "后台守护进程等待批准，批准后才会生效。"
        case .notRegistered: return preferences.keepAwakeWithLidClosed ? "后台守护进程尚未安装。" : nil
        default: return nil
        }
    }

    // MARK: - 通用

    private var generalSettings: some View {
        settingsForm {
            Section {
                Toggle("登录时启动", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                ))
                shortcutRow("关闭屏幕", identifier: "screenOffShortcutRecorder", shortcut: Binding(
                    get: { preferences.screenOffShortcut }, set: { controller.setScreenOffShortcut($0) }
                ), message: $shortcutRecordingMessage, validate: controller.validateScreenOffShortcut)
                shortcutRow("远程模式", identifier: "remoteModeShortcutRecorder", shortcut: Binding(
                    get: { preferences.remoteModeShortcut }, set: { controller.setRemoteModeShortcut($0) }
                ), message: $remoteShortcutRecordingMessage, validate: controller.validateRemoteModeShortcut)
                Toggle("自动检查更新", isOn: Binding(
                    get: { updateController.automaticallyChecksForUpdates },
                    set: { updateController.setAutomaticallyChecksForUpdates($0) }
                ))
                .disabled(!updateController.isConfigured)
                Toggle("发送匿名系统信息", isOn: Binding(
                    get: { updateController.sendsSystemProfile },
                    set: { updateController.setSendsSystemProfile($0) }
                ))
                .disabled(!updateController.isConfigured)
                .help("随更新检查发送 macOS 版本、机型、CPU、内存与系统语言，用于了解版本分布。不含任何账号、输入、屏幕或远程会话信息，也不生成设备标识。")
            }
            Section {
                permissionRow(
                    title: "输入监控",
                    detail: "自动关屏靠它区分本机键鼠与远程操作。不记录输入内容，快捷键不需要它。",
                    state: controller.isInputMonitoringDenied ? .denied
                        : (controller.isInputMonitoringReliable ? .granted : .missing),
                    action: { controller.openInputMonitoringSettings() }
                )
                permissionRow(
                    title: "辅助功能",
                    detail: "「关闭输入」靠它拦截本机键盘与触控板。只吞掉事件，不读取按键内容。",
                    state: controller.inputLock.hasAccess ? .granted : .missing,
                    action: { controller.inputLock.openAccessibilitySettings() }
                )
                permissionRow(
                    title: "后台守护进程",
                    detail: "「合盖后保持唤醒」靠它以系统身份写入睡眠设置。只做这一件事。",
                    state: lidWakePermissionState,
                    action: { controller.lidWake.openLoginItemsSettings() }
                )
            }
        }
    }

    private func shortcutRow(
        _ title: String,
        identifier: String,
        shortcut: Binding<KeyboardShortcuts.Shortcut?>,
        message: Binding<String?>,
        validate: @escaping (KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.ValidationResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("\(title)快捷键") {
                HStack(spacing: 6) {
                    ShortcutRecorderButton(
                        shortcut: shortcut, actionTitle: title, accessibilityIdentifier: identifier,
                        validate: validate, onRecordingMessage: { message.wrappedValue = $0 }
                    ).fixedSize()
                    if shortcut.wrappedValue != nil {
                        Button { shortcut.wrappedValue = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("清除快捷键")
                        .accessibilityLabel("清除\(title)快捷键")
                    }
                }
            }
            if let message = message.wrappedValue {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 原生表单自带左右内边距，448 pt 滚动区域产生约 408 pt 的实际内容宽度。
    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form(content: content)
            .formStyle(.grouped)
            // 窄表单不向全宽标题栏延伸底色，保留系统标签的玻璃选中效果。
            .scrollContentBackground(.hidden)
            .frame(width: 448)
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
            .padding(.top, 20)
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
        if preferences.autoKeyboardBacklightOff, !controller.canControlKeyboardBacklight {
            return CapabilityNote(message: "当前键盘不支持背光调节。")
        }
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
