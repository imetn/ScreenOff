import AppKit
import SwiftUI

/// SwiftUI 按内容决定实际高度；此桥接读取可用空间，并禁用不一致的系统自动顶部边界。
/// 不直接改 NSWindow 尺寸，避免与 Settings 场景的内容尺寸约束互相争抢。
struct SettingsWindowSizing: NSViewRepresentable {
    @Binding var maximumContentHeight: CGFloat

    func makeNSView(context: Context) -> MeasuringView { MeasuringView() }

    func updateNSView(_ nsView: MeasuringView, context: Context) {
        nsView.onMeasure = { height in
            guard abs(maximumContentHeight - height) > 0.5 else { return }
            maximumContentHeight = height
        }
        nsView.scheduleMeasurement()
    }

    static func dismantleNSView(_ nsView: MeasuringView, coordinator: ()) {
        NotificationCenter.default.removeObserver(nsView)
        nsView.onMeasure = nil
    }

    final class MeasuringView: NSView {
        var onMeasure: ((CGFloat) -> Void)?
        private var measurementScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self)
            guard let window else { return }
            // SettingsView 统一绘制分割线，避免系统按各页滚动状态再生成一条。
            window.titlebarSeparatorStyle = .none
            for name in [NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                center.addObserver(self, selector: #selector(windowMetricsChanged), name: name, object: window)
            }
            center.addObserver(
                self,
                selector: #selector(windowMetricsChanged),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
            scheduleMeasurement()
        }

        @objc private func windowMetricsChanged(_ notification: Notification) {
            scheduleMeasurement()
        }

        func scheduleMeasurement() {
            guard !measurementScheduled else { return }
            measurementScheduled = true
            // 等当前布局完成后再回传约束，避免在 SwiftUI 更新期间修改状态。
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                measurementScheduled = false
                guard let window, let screen = window.screen else { return }
                let chromeHeight = window.frame.height - window.contentLayoutRect.height
                let availableHeight = screen.visibleFrame.height - chromeHeight - 32
                onMeasure?(max(1, floor(availableHeight)))
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
