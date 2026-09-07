import CryptoKit
import Foundation

/// Public-key-only verification; syncing an existing release never needs Keychain access.
@main
struct VerifyUpdateRelease {
    static func main() throws {
        guard CommandLine.arguments.count == 4,
              let rawKey = Data(base64Encoded: CommandLine.arguments[3]) else {
            throw URLError(.cannotDecodeContentData)
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let tag = CommandLine.arguments[2]
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
        let feed = try Data(contentsOf: directory.appendingPathComponent("appcast.xml"))
        let content = try UpdateSource.verifiedFeed(feed, publicKey: rawKey)
        let xml = try XMLDocument(data: content, options: [.nodeLoadExternalEntitiesNever])
        let items = try xml.nodes(forXPath: "/rss/channel/item")
        guard items.count == 1, let item = items.first,
              try item.nodes(forXPath: "*[local-name()='shortVersionString']").first?.stringValue == String(tag.dropFirst()),
              let enclosure = try item.nodes(forXPath: "enclosure").first as? XMLElement,
              enclosure.attribute(forName: "url")?.stringValue == UpdateSource.githubPrefix + tag + "/ScreenOff.zip",
              let encoded = enclosure.attributes?.first(where: { $0.localName == "edSignature" })?.stringValue,
              let signature = Data(base64Encoded: encoded) else { throw URLError(.cannotParseResponse) }
        let archive = try Data(contentsOf: directory.appendingPathComponent("ScreenOff.zip"), options: .mappedIfSafe)
        guard Int(enclosure.attribute(forName: "length")?.stringValue ?? "") == archive.count,
              key.isValidSignature(signature, for: archive) else { throw URLError(.cannotDecodeContentData) }
        let manifest = try String(contentsOf: directory.appendingPathComponent("SHA256SUMS"), encoding: .utf8)
        var remaining: Set<String> = ["ScreenOff.zip", "ScreenOff.dmg", "appcast.xml"]
        for line in manifest.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count == 2, remaining.remove(String(parts[1])) != nil else { throw URLError(.cannotParseResponse) }
            let data = try Data(contentsOf: directory.appendingPathComponent(String(parts[1])), options: .mappedIfSafe)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == parts[0] else { throw URLError(.cannotDecodeContentData) }
        }
        guard remaining.isEmpty else { throw URLError(.cannotParseResponse) }
        print("Release signatures and SHA-256 verified: \(tag)")
    }
}
