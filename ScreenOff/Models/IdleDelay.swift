import Foundation

/// 空闲时长档位：1 分钟到 4 小时。
/// 低档密、高档疏，贴合「短暂离开」到「长时间挂机」的真实节奏。
enum IdleDelay {
    static let options: [Int] = [
        60, 120, 180, 300, 600, 900, 1200, 1800,
        2700, 3600, 5400, 7200, 10800, 14400,
    ]

    static let defaultSeconds = 300

    static var maximumIndex: Int { options.count - 1 }

    static func title(_ seconds: Int) -> String {
        if seconds < 3600 { return "\(seconds / 60) 分钟" }
        let hours = Double(seconds) / 3600
        return hours == hours.rounded()
            ? "\(Int(hours)) 小时"
            : String(format: "%.1f 小时", hours)
    }

    /// 找不到精确档位时回落到默认值，避免旧偏好（含已下线的秒级档位）带来越界。
    static func index(of seconds: Int) -> Int {
        options.firstIndex(of: seconds) ?? options.firstIndex(of: defaultSeconds) ?? 0
    }

    static func seconds(at index: Int) -> Int {
        options[min(max(index, 0), maximumIndex)]
    }
}
