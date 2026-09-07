import CryptoKit
import Foundation

/// The mirror keeps the signed feed and archive byte-for-byte identical to GitHub.
struct UpdateSource: Equatable, Sendable {
    static let mirrorRoot = URL(string: "https://frameflowtech.com/updates/screenoff/")!
    static let githubPrefix = "https://github.com/imetn/ScreenOff/releases/download/"

    let feedURL: URL
    let isMirror: Bool

    func downloadURL(for original: URL) -> URL? {
        guard original.absoluteString.hasPrefix(Self.githubPrefix),
              original.query == nil, original.fragment == nil else { return nil }
        let suffix = String(original.absoluteString.dropFirst(Self.githubPrefix.count))
        guard suffix.range(of: #"^v[0-9]+\.[0-9]+\.[0-9]+/ScreenOff\.zip$"#,
                           options: .regularExpression) != nil else { return nil }
        return isMirror ? Self.mirrorRoot.appendingPathComponent(suffix) : original
    }

    struct Availability: Sendable {
        let source: UpdateSource
        let build: Int
        let elapsed: TimeInterval
    }

    static func availableSources(_ sources: [UpdateSource], publicKey: Data,
                                 session: URLSession) async -> [Availability] {
        await withTaskGroup(of: Availability?.self) { group in
            for source in sources {
                group.addTask { try? await source.probe(publicKey: publicKey, session: session) }
            }
            var results: [Availability] = []
            for await result in group {
                if let result { results.append(result) }
            }
            // Prefer a newer signed release when a mirror has not caught up yet.
            return results.sorted {
                $0.build == $1.build ? $0.elapsed < $1.elapsed : $0.build > $1.build
            }
        }
    }

    func probe(publicKey: Data, session: URLSession) async throws -> Availability {
        let start = Date()
        let feed = try await read(feedURL, limit: 1_048_576, session: session)
        let content = try Self.verifiedFeed(feed, publicKey: publicKey)
        let document = try XMLDocument(data: content, options: [.nodeLoadExternalEntitiesNever])
        guard let item = try document.nodes(forXPath: "/rss/channel/item").first,
              let buildText = try item.nodes(forXPath: "*[local-name()='version']").first?.stringValue,
              let build = Int(buildText), build > 0,
              let enclosure = try item.nodes(forXPath: "enclosure").first as? XMLElement,
              let rawURL = enclosure.attribute(forName: "url")?.stringValue,
              let original = URL(string: rawURL), let archive = downloadURL(for: original),
              let lengthText = enclosure.attribute(forName: "length")?.stringValue,
              let length = Int64(lengthText), length > 0 else { throw URLError(.cannotParseResponse) }
        // Test the real release asset, including GitHub's redirect to its asset host.
        _ = try await read(archive, limit: 1, expectedArchiveLength: length, session: session)
        return Availability(source: self, build: build, elapsed: Date().timeIntervalSince(start))
    }

    private func read(_ url: URL, limit: Int, expectedArchiveLength: Int64? = nil,
                      session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 4)
        request.setValue("ScreenOff-Update-Check", forHTTPHeaderField: "User-Agent")
        if expectedArchiveLength != nil {
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, response.url?.scheme == "https" else {
            throw URLError(.badServerResponse)
        }
        if let expectedArchiveLength {
            let range = http.value(forHTTPHeaderField: "Content-Range")
            guard (http.statusCode == 206 && range == "bytes 0-0/\(expectedArchiveLength)") ||
                    (http.statusCode == 200 && response.expectedContentLength == expectedArchiveLength)
            else { throw URLError(.badServerResponse) }
        } else if http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            if expectedArchiveLength != nil { break }
            if data.count > limit { throw URLError(.dataLengthExceedsMaximum) }
        }
        guard !data.isEmpty else { throw URLError(.zeroByteResource) }
        return data
    }

    /// Sparkle 2.9's signed-feed envelope. Sparkle still independently verifies the chosen feed.
    static func verifiedFeed(_ data: Data, publicKey: Data) throws -> Data {
        let prefix = Data("<!-- sparkle-signatures:\n".utf8)
        guard let start = data.range(of: prefix, options: .backwards),
              let end = data.range(of: Data("-->".utf8), in: start.upperBound..<data.endIndex),
              let block = String(data: data[start.upperBound..<end.lowerBound], encoding: .utf8)
        else { throw URLError(.cannotDecodeContentData) }
        var fields: [String: String] = [:]
        for line in block.split(separator: "\n") {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2 {
                fields[String(pair[0])] = pair[1].trimmingCharacters(in: .whitespaces)
            }
        }
        let content = Data(data[..<start.lowerBound])
        guard Int(fields["length"] ?? "") == content.count,
              let signature = Data(base64Encoded: fields["edSignature"] ?? ""),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signature, for: content) else {
            throw URLError(.cannotDecodeContentData)
        }
        return content
    }
}
