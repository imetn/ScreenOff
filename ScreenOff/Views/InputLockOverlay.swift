import AppKit
import SwiftUI

/// 锁定期间的屏幕提示。锁定时键鼠全被吞掉，用户只能靠这块浮层知道怎么解锁。
struct InputLockOverlayView: View {
    let service: InputLockService

    private var stage: InputLockService.Stage { service.stage }
    private var isRestored: Bool { stage == .restored }
    private var isArmed: Bool {
        if case .holding = stage { return true }
        return stage == .readyToRelease
    }

    /// 面板尺寸固定，卡片在其中居中：状态切换时卡片会改变大小，窗口不能跟着跳。
    static let panelSize = NSSize(width: 384, height: 308)

    var body: some View {
        card.frame(width: Self.panelSize.width, height: Self.panelSize.height)
    }

    private var card: some View {
        VStack(spacing: 14) {
            Image(systemName: isRestored ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: isRestored ? 26 : 24, weight: .medium))
                .foregroundStyle(isRestored ? Color.green : Color.primary.opacity(0.85))
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !isRestored {
                keyCombination
                VStack(spacing: 7) {
                    progressTrack
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.vertical, isRestored ? 26 : 24)
        .frame(width: isRestored ? 240 : 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.24), radius: 24, y: 8)
        .animation(.easeOut(duration: 0.18), value: isRestored)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)。\(hint)")
    }

    private var keyCombination: some View {
        HStack(spacing: 8) {
            keyCap("fn")
            Text("+")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            keyCap("delete", trailingSymbol: "delete.left")
        }
    }

    private func keyCap(_ label: String, trailingSymbol: String? = nil) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(isArmed ? Color.white : Color.primary.opacity(0.8))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isArmed ? Color.accentColor : Color.primary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(isArmed ? 0 : 0.12), lineWidth: 0.5)
        )
    }

    private var progressTrack: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(stage == .readyToRelease ? Color.green : Color.accentColor)
                    .frame(width: max(0, geometry.size.width * progress))
            }
        }
        .frame(height: 4)
        .animation(.linear(duration: 0.05), value: progress)
    }

    private var progress: Double {
        switch stage {
        case .locked: 0
        case .holding(let value): value
        case .readyToRelease, .restored: 1
        }
    }

    private var title: String {
        switch stage {
        case .locked: String(localized: "输入已关闭")
        case .holding: String(localized: "正在解锁")
        case .readyToRelease: String(localized: "松开按键即可解锁")
        case .restored: String(localized: "输入已恢复")
        }
    }

    private var subtitle: String {
        stage == .restored ? String(localized: "键盘与触控板可正常使用") : String(localized: "键盘与触控板已锁定")
    }

    private func heldSeconds(_ progress: Double) -> String {
        let held = String(format: "%.1f", progress * InputLockService.holdDuration)
        return String(localized: "继续按住 · \(held) / 1 秒")
    }

    private var hint: String {
        switch stage {
        case .locked: String(localized: "按住 Fn + Delete 1 秒解锁")
        case .holding(let value):
            heldSeconds(value)
        case .readyToRelease, .restored: String(localized: "已按住 1 秒")
        }
    }
}

/// 承载浮层的无边框面板：不抢焦点、不吃事件、跨空间常驻。
@MainActor
final class InputLockOverlayController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func present(service: InputLockService) {
        dismissTask?.cancel()
        dismissTask = nil
        if panel == nil { panel = makePanel(service: service) }
        guard let panel else { return }
        reposition(panel)
        panel.orderFrontRegardless()
    }

    /// 解锁后留出「输入已恢复」的提示时间，再收起面板。
    func dismissAfterHint() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1250))
            guard !Task.isCancelled else { return }
            self?.dismissNow()
        }
    }

    func dismissNow() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel(service: InputLockService) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: InputLockOverlayView.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: InputLockOverlayView(service: service))
        return panel
    }

    private func reposition(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = InputLockOverlayView.panelSize
        panel.setContentSize(size)
        // 整屏居中：锁定时菜单栏和 Dock 都不可用，可见区域不再是合适的参考系。
        let frame = screen.frame
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
