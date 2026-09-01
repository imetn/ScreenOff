import AppKit
import Observation
import Sparkle

/// Sparkle 的最小包装层。只有 HTTPS Feed 与合法 EdDSA 公钥齐备时才启动更新器。
@MainActor
@Observable
final class UpdateController {
    @ObservationIgnored private var standardController: SPUStandardUpdaterController?

    private(set) var isConfigured = false
    private(set) var configurationMessage = "更新服务配置不完整"

    init(bundle: Bundle = .main) {
        let feedURL = Self.httpsURL(for: "SUFeedURL", in: bundle)
        let publicKey = Self.edPublicKey(in: bundle)

        guard feedURL != nil, publicKey != nil else { return }

        standardController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        isConfigured = true
        configurationMessage = "通过 Sparkle 安全检查并安装更新"
    }

    var automaticallyChecksForUpdates: Bool {
        standardController?.updater.automaticallyChecksForUpdates ?? false
    }

    var githubURL: URL? {
        Self.url(for: "ScreenOffGitHubURL", in: .main)
    }

    var issuesURL: URL? {
        Self.url(for: "ScreenOffIssuesURL", in: .main)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        standardController?.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        guard let standardController else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        standardController.checkForUpdates(nil)
    }

    private static func nonemptyString(_ key: String, in bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func url(for key: String, in bundle: Bundle) -> URL? {
        guard let value = nonemptyString(key, in: bundle) else { return nil }
        return URL(string: value)
    }

    private static func httpsURL(for key: String, in bundle: Bundle) -> URL? {
        guard let url = url(for: key, in: bundle), url.scheme == "https", url.host != nil else {
            return nil
        }
        return url
    }

    /// Sparkle Ed25519 公钥解码后固定为 32 字节。
    private static func edPublicKey(in bundle: Bundle) -> String? {
        guard
            let value = nonemptyString("SUPublicEDKey", in: bundle),
            Data(base64Encoded: value)?.count == 32
        else { return nil }
        return value
    }
}
