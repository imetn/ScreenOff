import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: ScreenOffPreferences

    var body: some View {
        Form {
            Section("电源") {
                Toggle("保持电脑唤醒", isOn: $preferences.keepAwake)
                Toggle("合盖后保持唤醒", isOn: $preferences.keepAwakeWithLidClosed)
                Text("合盖模式首版仅在接通电源时生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("屏幕与键盘") {
                Toggle("自动关闭屏幕", isOn: $preferences.autoScreenOff)

                Picker("空闲时间", selection: $preferences.screenOffDelay) {
                    ForEach(ScreenOffDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                }
                .disabled(!preferences.autoScreenOff)

                Toggle(
                    "同时关闭键盘背光",
                    isOn: $preferences.turnOffKeyboardBacklight
                )
                .disabled(!preferences.autoScreenOff)
            }

            Section("通用") {
                Toggle("登录时启动", isOn: $preferences.launchAtLogin)
                    .disabled(true)
                Text("登录启动将在接入 SMAppService 后开放。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("项目骨架阶段：这里保存的配置尚未改变系统状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 410)
        .scenePadding()
    }
}

