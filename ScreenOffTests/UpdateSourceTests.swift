import CryptoKit
import Foundation
import Sparkle
import Testing

@Suite("更新源选择", .serialized)
struct UpdateSourceTests {
    private let key = Curve25519.Signing.PrivateKey()
    private let github = UpdateSource(feedURL: URL(string: "https://github.test/appcast.xml")!, isMirror: false)
    private let mirror = UpdateSource(feedURL: URL(string: "https://mirror.test/appcast.xml")!, isMirror: true)

    private func feed(build: Int = 3) -> Data {
        let content = Data("""
        <?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:version>\(build)</sparkle:version>
        <enclosure url="https://github.com/imetn/ScreenOff/releases/download/v0.1.2/ScreenOff.zip" length="100"/>
        </item></channel></rss>
        """.utf8)
        let signature = try! key.signature(for: content).base64EncodedString()
        return content + Data("<!-- sparkle-signatures:\nedSignature: \(signature)\nlength: \(content.count)\n-->\n".utf8)
    }

    private func session(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, [String: String], Data)) -> URLSession {
        UpdateProbeProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateProbeProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("镜像仅替换本仓库的标准 ZIP 地址")
    func archiveMapping() {
        let original = URL(string: UpdateSource.githubPrefix + "v0.1.2/ScreenOff.zip")!
        #expect(github.downloadURL(for: original) == original)
        #expect(mirror.downloadURL(for: original)?.absoluteString ==
                "https://frameflowtech.com/updates/screenoff/v0.1.2/ScreenOff.zip")
        for raw in ["http://github.com/imetn/ScreenOff/releases/download/v0.1.2/ScreenOff.zip",
                    UpdateSource.githubPrefix + "v0.1.2/Other.zip",
                    UpdateSource.githubPrefix + "v0.1.2/ScreenOff.zip?token=x",
                    UpdateSource.githubPrefix + "../ScreenOff.zip",
                    "https://github.com.evil.test/imetn/ScreenOff/releases/download/v0.1.2/ScreenOff.zip"] {
            #expect(mirror.downloadURL(for: URL(string: raw)!) == nil)
        }
    }

    @Test("清单必须通过公钥与长度校验，篡改和错误密钥均被拒绝")
    func feedAuthentication() throws {
        let signed = feed()
        let publicKey = key.publicKey.rawRepresentation
        #expect(try !UpdateSource.verifiedFeed(signed, publicKey: publicKey).isEmpty)
        var tampered = signed
        tampered[40] ^= 1
        #expect(throws: (any Error).self) { try UpdateSource.verifiedFeed(tampered, publicKey: publicKey) }
        #expect(throws: (any Error).self) {
            try UpdateSource.verifiedFeed(signed, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        }
        #expect(throws: (any Error).self) { try UpdateSource.verifiedFeed(Data("<rss/>".utf8), publicKey: publicKey) }
        let wrongLength = Data(String(decoding: signed, as: UTF8.self)
            .replacingOccurrences(of: "length: ", with: "length: 99").utf8)
        #expect(throws: (any Error).self) { try UpdateSource.verifiedFeed(wrongLength, publicKey: publicKey) }
    }

    @Test("GitHub 不可达时使用服务器，包括真实安装包探测")
    func githubBlocked() async {
        let signed = feed()
        let session = session { request in
            if request.url?.host == "github.test" { throw URLError(.cannotConnectToHost) }
            if request.url?.pathExtension == "xml" { return (200, [:], signed) }
            #expect(request.url?.host == "frameflowtech.com")
            #expect(request.value(forHTTPHeaderField: "Range") == "bytes=0-0")
            return (206, ["Content-Range": "bytes 0-0/100"], Data([80]))
        }
        defer { session.invalidateAndCancel() }
        let result = await UpdateSource.availableSources([github, mirror], publicKey: key.publicKey.rawRepresentation, session: session)
        #expect(result.map(\.source) == [mirror])
    }

    @Test("服务器清单正常但安装包不可达时回退 GitHub")
    func mirrorArchiveBlocked() async {
        let signed = feed()
        let session = session { request in
            if request.url?.pathExtension == "xml" { return (200, [:], signed) }
            if request.url?.host == "frameflowtech.com" { return (404, [:], Data("missing".utf8)) }
            return (206, ["Content-Range": "bytes 0-0/100"], Data([80]))
        }
        defer { session.invalidateAndCancel() }
        let result = await UpdateSource.availableSources([github, mirror], publicKey: key.publicKey.rawRepresentation, session: session)
        #expect(result.map(\.source) == [github])
    }

    @Test("较旧镜像不会遮蔽较新的已签名版本")
    func newestBuildWins() async {
        let newest = feed(build: 4), old = feed(build: 3)
        let session = session { request in
            if request.url?.pathExtension == "xml" {
                return (200, [:], request.url?.host == "github.test" ? newest : old)
            }
            return (206, ["Content-Range": "bytes 0-0/100"], Data([80]))
        }
        defer { session.invalidateAndCancel() }
        let result = await UpdateSource.availableSources([mirror, github], publicKey: key.publicKey.rawRepresentation, session: session)
        #expect(result.map(\.build) == [4, 3])
        #expect(result.first?.source == github)
    }

    @Test("错误页和错误长度不能被当成可用安装包")
    func invalidArchiveResponse() async {
        let signed = feed()
        let session = session { request in
            if request.url?.pathExtension == "xml" { return (200, [:], signed) }
            return (200, ["Content-Length": "5"], Data("error".utf8))
        }
        defer { session.invalidateAndCancel() }
        let result = await UpdateSource.availableSources([github, mirror], publicKey: key.publicKey.rawRepresentation, session: session)
        #expect(result.isEmpty)
    }

    @Test("两源均不可达时结束检查")
    func bothOffline() async {
        let session = session { _ in throw URLError(.notConnectedToInternet) }
        defer { session.invalidateAndCancel() }
        let result = await UpdateSource.availableSources([github, mirror], publicKey: key.publicKey.rawRepresentation, session: session)
        #expect(result.isEmpty)
    }

    @Test("仅重试源错误，保留签名、安装、取消与磁盘错误")
    @MainActor
    func retryBoundaries() {
        #expect(UpdateController.isRetryableSourceError(URLError(.timedOut) as NSError))
        #expect(UpdateController.isRetryableSourceError(NSError(domain: SUSparkleErrorDomain,
            code: Int(SUError.downloadError.rawValue), userInfo: [NSUnderlyingErrorKey: URLError(.networkConnectionLost)])))
        for code in [SUError.signatureError, .appcastParseError, .unarchivingError, .installationError,
                     .installationCanceledError, .noUpdateError] {
            #expect(!UpdateController.isRetryableSourceError(NSError(domain: SUSparkleErrorDomain,
                code: Int(code.rawValue))))
        }
        for underlying in [URLError(.cancelled) as NSError,
                           NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)] {
            #expect(!UpdateController.isRetryableSourceError(NSError(domain: SUSparkleErrorDomain,
                code: Int(SUError.downloadError.rawValue), userInfo: [NSUnderlyingErrorKey: underlying])))
        }
    }
}

private final class UpdateProbeProtocol: URLProtocol, @unchecked Sendable {
    // The owning suite is serialized; each handler is installed before its session starts.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
