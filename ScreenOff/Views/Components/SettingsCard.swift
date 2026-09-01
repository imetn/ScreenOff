import SwiftUI

/// 分区标题 + 可选圆角容器，菜单栏可仅保留间距与分隔线。
struct CardSection<Content: View>: View {
    let title: String?
    let titleInset: CGFloat
    let showsContainer: Bool
    @ViewBuilder let content: Content

    init(
        _ title: String? = nil,
        titleInset: CGFloat = 0,
        showsContainer: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleInset = titleInset
        self.showsContainer = showsContainer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, titleInset)
            }
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(showsContainer ? Color(nsColor: .controlBackgroundColor) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            showsContainer ? Color(nsColor: .separatorColor).opacity(0.7) : .clear,
                            lineWidth: 0.5
                        )
                )
        }
    }
}

/// 卡片中的一行：左侧文案，右侧控件，可选副标题。
struct CardRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var height: CGFloat = 42
    var isEnabled: Bool = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// 卡片内的通栏分隔线。
struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.7))
            .frame(height: 0.5)
    }
}

/// 空闲时长滑块行：标题与当前值一行，滑块占满下一行。
/// 档位是离散的，滑块按索引取值，因此拖动始终落在合法档位上。
struct IdleDelayRow: View {
    let seconds: Int
    var isEnabled: Bool = true
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("空闲时间")
                Spacer()
                Text(IdleDelay.title(seconds))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(IdleDelay.index(of: seconds)) },
                    set: { onChange(IdleDelay.seconds(at: Int($0.rounded()))) }
                ),
                in: 0...Double(IdleDelay.maximumIndex),
                step: 1
            )
            .disabled(!isEnabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
