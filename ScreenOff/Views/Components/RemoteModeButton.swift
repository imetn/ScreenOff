import SwiftUI

/// 主窗口与菜单栏共用同一个远程模式动作和过渡状态。
struct RemoteModeButton: View {
    @Bindable var controller: ScreenOffController

    var body: some View {
        Button { controller.toggleRemoteMode() } label: {
            HStack(spacing: 7) {
                if controller.remoteMode.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: controller.remoteMode.needsRecovery ? "arrow.clockwise" : "desktopcomputer")
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(controller.remoteMode.isBusy)
        .accessibilityLabel(title)
        .accessibilityIdentifier("toggleRemoteMode")
    }

    private var title: String {
        if controller.remoteMode.isBusy { return String(localized: "正在切换…") }
        if controller.remoteMode.needsRecovery { return String(localized: "重试恢复原设置") }
        return controller.remoteMode.isActive ? String(localized: "关闭并恢复") : String(localized: "开启远程模式")
    }
}
