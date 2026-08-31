import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var preferences: ScreenOffPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Off")
                        .font(.headline)
                    Text(preferences.configurationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button("立即关闭屏幕", systemImage: "moon.fill") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(true)
                .help("系统控制层尚未接入")

            Divider()

            Toggle("保持电脑唤醒", isOn: $preferences.keepAwake)
            Toggle("合盖后保持唤醒", isOn: $preferences.keepAwakeWithLidClosed)
            Toggle("自动关闭屏幕", isOn: $preferences.autoScreenOff)

            if preferences.autoScreenOff {
                Picker("空闲时间", selection: $preferences.screenOffDelay) {
                    ForEach(ScreenOffDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                }

                Toggle(
                    "同时关闭键盘背光",
                    isOn: $preferences.turnOffKeyboardBacklight
                )
            }

            Divider()

            HStack {
                SettingsLink {
                    Label("设置…", systemImage: "gearshape")
                }

                Spacer()

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }

            Text("当前仅保存配置，系统控制将在后续阶段接入。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 300)
    }
}

