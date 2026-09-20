import AppKit
import Foundation

/// 界面语言。写的是系统的 `AppleLanguages` 键，因此必须重启 App 才生效——
/// 这是在不自己接管 Bundle 字符串查找的前提下，macOS 上唯一可靠的切换方式。
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"

    var id: String { rawValue }

    /// 每种语言用它自己的写法，用户不必先看懂当前界面语言才能找到自己的语言。
    var title: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .japanese: "日本語"
        }
    }

    private static let key = "AppleLanguages"

    /// 用户显式选过的语言；从未选过时为 nil，表示跟随系统。
    static var selected: AppLanguage? {
        guard let code = UserDefaults.standard.stringArray(forKey: key)?.first else { return nil }
        return allCases.first { code.hasPrefix($0.rawValue) }
    }

    /// 选择器需要一个确定初值：没选过时看系统实际落到哪本地化。
    static var effective: AppLanguage {
        if let selected { return selected }
        for code in Bundle.main.preferredLocalizations {
            if let match = allCases.first(where: { code.hasPrefix($0.rawValue) }) { return match }
        }
        return .simplifiedChinese
    }

    static func apply(_ language: AppLanguage) {
        UserDefaults.standard.set([language.rawValue], forKey: key)
    }

    /// 重启走正常退出路径，让亮度、输入锁定与合盖设置先还原，不留系统状态。
    static func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
