import AppKit
import Observation
import OSLog
import Sparkle

/// Sparkle 的最小包装层。只有 HTTPS Feed 与合法 EdDSA 公钥齐备时才启动更新器。
@MainActor
@Observable
final class UpdateController: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var userDriver: UpdateUserDriver?
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var sources: [UpdateSource] = []
    @ObservationIgnored private var candidates: [UpdateSource] = []
    @ObservationIgnored private var candidateIndex = 0
    @ObservationIgnored private var prepared = false
    @ObservationIgnored private var publicKey = Data()
    private static let selectionErrorDomain = "com.frameflowtech.screenoff.update-selection"
    private static let logger = Logger(subsystem: "com.frameflowtech.screenoff", category: "Updates")

    private(set) var isConfigured = false
    private(set) var configurationMessage = "更新服务配置不完整"

    init(bundle: Bundle = .main) {
        super.init()
        let feedURL = Self.httpsURL(for: "SUFeedURL", in: bundle)
        let publicKey = Self.edPublicKey(in: bundle)

        guard let feedURL, let publicKey, let keyData = Data(base64Encoded: publicKey) else { return }
        self.publicKey = keyData
        sources = [
            UpdateSource(feedURL: UpdateSource.mirrorRoot.appendingPathComponent("latest/appcast.xml"),
                         isMirror: true),
            UpdateSource(feedURL: feedURL, isMirror: false)
        ]
        let driver = UpdateUserDriver(hostBundle: bundle, delegate: nil)
        driver.suppressError = { [weak self] error in
            error.domain == Self.selectionErrorDomain || self?.canRetry(error) == true
        }
        userDriver = driver
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle,
                                 userDriver: driver, delegate: self)
        self.updater = updater
        do {
            try updater.start()
            isConfigured = true
            configurationMessage = "自动选择可用更新源，通过 Sparkle 安全安装更新"
        } catch {
            configurationMessage = "更新服务启动失败：\(error.localizedDescription)"
        }
    }

    var automaticallyChecksForUpdates: Bool {
        updater?.automaticallyChecksForUpdates ?? false
    }

    var githubURL: URL? {
        Self.url(for: "ScreenOffGitHubURL", in: .main)
    }

    var issuesURL: URL? {
        Self.url(for: "ScreenOffIssuesURL", in: .main)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        guard isConfigured, let updater else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        if selectionTask != nil { return }
        if updater.sessionInProgress {
            updater.checkForUpdates()
        } else {
            selectSources(for: .updates)
        }
    }

    private func selectSources(for check: SPUUpdateCheck) {
        guard selectionTask == nil else { return }
        userDriver?.approvedItem = nil
        candidates = []
        candidateIndex = 0
        if check == .updates {
            userDriver?.showUserInitiatedUpdateCheck(cancellation: { [weak self] in
                self?.selectionTask?.cancel()
                self?.userDriver?.dismissUpdateInstallation()
            })
        }
        selectionTask = Task { [weak self] in
            guard let self else { return }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4
            config.timeoutIntervalForResource = 6
            config.waitsForConnectivity = false
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel(); selectionTask = nil }
            let available = await UpdateSource.availableSources(sources, publicKey: publicKey, session: session)
            guard !Task.isCancelled else { return }
            if check == .updates { userDriver?.dismissUpdateInstallation() }
            // A stale mirror must not silently replace the newer version selected for this attempt.
            candidates = available.filter { $0.build == available.first?.build }.map(\.source)
            guard !candidates.isEmpty else {
                if check == .updates {
                    userDriver?.showUpdaterError(NSError(domain: NSURLErrorDomain,
                        code: URLError.cannotConnectToHost.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "暂时无法连接更新服务",
                                   NSLocalizedRecoverySuggestionErrorKey: "两个更新源均未通过连接与签名检查，请稍后重试。"]),
                        acknowledgement: {})
                }
                return
            }
            performPreparedCheck(check)
        }
    }

    private func performPreparedCheck(_ check: SPUUpdateCheck) {
        prepared = true
        Self.logger.info("Using update source: \(self.candidates[self.candidateIndex].feedURL.absoluteString, privacy: .public)")
        switch check {
        case .updates: updater?.checkForUpdates()
        case .updateInformation: updater?.checkForUpdateInformation()
        default: updater?.checkForUpdatesInBackground()
        }
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if prepared {
            prepared = false
        } else {
            // Sparkle's synchronous gate defers scheduled checks until asynchronous probes finish.
            throw NSError(domain: Self.selectionErrorDomain, code: 1)
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        candidates.indices.contains(candidateIndex) ? candidates[candidateIndex].feedURL.absoluteString : nil
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem,
                 with request: NSMutableURLRequest) {
        if candidates.indices.contains(candidateIndex), let original = item.fileURL,
           let url = candidates[candidateIndex].downloadURL(for: original) {
            request.url = url
        }
        request.timeoutInterval = 15
    }

    private func canRetry(_ error: NSError) -> Bool {
        candidateIndex + 1 < candidates.count && Self.isRetryableSourceError(error)
    }

    static func isRetryableSourceError(_ error: NSError, depth: Int = 0) -> Bool {
        guard depth < 8 else { return false }
        // Never hide signature, extraction, installation failures or user cancellation.
        if error.domain == SUSparkleErrorDomain {
            guard error.code == SUError.appcastError.rawValue || error.code == SUError.downloadError.rawValue
            else { return false }
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                return isRetryableSourceError(underlying, depth: depth + 1)
            }
            return true
        }
        return error.domain == NSURLErrorDomain && error.code != URLError.cancelled.rawValue
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: Error?) {
        if let error = error as NSError? {
            if error.domain == Self.selectionErrorDomain {
                selectSources(for: updateCheck)
                return
            }
            if canRetry(error) {
                candidateIndex += 1
                performPreparedCheck(updateCheck)
                return
            }
        }
        userDriver?.approvedItem = nil
        candidates = []
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

/// Keep Sparkle's native UI; only suppress a recoverable source error and preserve same-item consent.
@MainActor
private final class UpdateUserDriver: SPUStandardUserDriver {
    var suppressError: ((NSError) -> Bool)?
    var approvedItem: NSDictionary?

    override func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if suppressError?(error as NSError) == true {
            acknowledgement()
        } else {
            super.showUpdaterError(error, acknowledgement: acknowledgement)
        }
    }

    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                                  reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let item = appcastItem.propertiesDictionary as NSDictionary
        if let approvedItem, approvedItem.isEqual(item), state.stage == .notDownloaded {
            super.dismissUpdateInstallation()
            reply(.install)
        } else {
            super.showUpdateFound(with: appcastItem, state: state) { [weak self] choice in
                self?.approvedItem = choice == .install ? item : nil
                reply(choice)
            }
        }
    }
}
