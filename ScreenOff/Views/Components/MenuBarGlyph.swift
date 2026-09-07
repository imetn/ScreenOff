import SwiftUI

/// 菜单栏与快捷操作共用的屏幕字形。
/// 顶部菜单栏固定使用 Figma 定稿的斜杠版本；空心、实心仅表达快捷按钮状态。
/// SVG 以模板图标方式由 macOS 自动适配明暗。
enum MenuBarGlyph: String {
    /// 快捷按钮：屏幕当前点亮。
    case outline = "MenuBarGlyphOutline"
    /// 顶部菜单栏使用的定稿图标。
    case diagonal = "MenuBarGlyphDiagonal"
    /// 快捷按钮：屏幕当前关闭。
    case filled = "MenuBarGlyphFilled"

    var image: Image {
        Image(rawValue).renderingMode(.template)
    }

}
