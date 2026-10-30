import Foundation
import KeyboardCore
import UIKit
import UniformTypeIdentifiers

/// GIFs from KLIPY's API (docs/design.md, "GIF"). Its key is `Resources/Keys/klipy.key`, which stays out of git; a
/// build without it has no GIF panel.
nonisolated public struct Klipy: Sendable {
    let key: String
    /// A random ID for this install, which KLIPY asks for to rank results and keep its counts per user.
    let customer: String

    public static let shared: Klipy? = {
        guard let url = Bundle.module.url(forResource: "klipy", withExtension: "key", subdirectory: "Keys"),
              let key = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
        else { return nil }
        return Klipy(key: key, customer: customerID())
    }()

    private static func customerID() -> String {
        let key = "klipyCustomer"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// The GIFs for a feed, in KLIPY's order, or nil when the request failed.
    public func gifs(_ feed: GifSearch.Feed) async -> [Gif]? {
        let request: URLRequest
        switch feed {
        case .trending: request = get("gifs/trending", ["per_page": "30"])
        case .search(let words): request = get("gifs/search", ["q": words, "per_page": "30"])
        case .recents(let slugs): request = get("gifs/items", ["slugs": slugs.joined(separator: ",")])
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let page = try? JSONDecoder().decode(Page.self, from: data), page.result
        else { return nil }
        let gifs = page.data.data.compactMap(\.gif)
        guard case .recents(let slugs) = feed else { return gifs }
        return slugs.compactMap { slug in gifs.first { Self.base($0.id) == slug } }
    }

    /// A slug without the suffix a search adds to it (`cat-dance--k55hIoaZo`), as `gifs/items` answers with it, so the
    /// same GIF found by two searches is one recent.
    static func base(_ slug: String) -> String {
        slug.range(of: "--").map { String(slug[..<$0.lowerBound]) } ?? slug
    }

    /// Tells KLIPY a GIF was sent, with the search that found it.
    public func shared(_ gif: Gif, search: String) {
        var request = URLRequest(url: url("gifs/share/\(gif.id)", [:]))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["customer_id": customer, "q": search])
        URLSession.shared.dataTask(with: request).resume()
    }

    private func get(_ path: String, _ query: [String: String]) -> URLRequest {
        URLRequest(url: url(path, query.merging(["customer_id": customer, "format_filter": "gif,webp"]) { a, _ in a }))
    }

    private func url(_ path: String, _ query: [String: String]) -> URL {
        var components = URLComponents(string: "https://api.klipy.com/api/v1/\(key)/\(path)")!
        components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    struct Page: Decodable {
        struct Items: Decodable { var data: [Item] }
        var result: Bool
        var data: Items
    }

    struct Item: Decodable {
        struct File: Decodable {
            var url: String
            var width: Int
            var height: Int
        }

        var slug: String?
        var title: String?
        var type: String?
        var file: [String: [String: File]]?

        /// The grid shows the small WebP; the clipboard gets the medium GIF, the format every app pastes. Ads and items
        /// missing either are left out.
        var gif: Gif? {
            guard type == nil || type == "gif", let slug, let preview = file?["sm"]?["webp"] ?? file?["sm"]?["gif"], let full = file?["md"]?["gif"] ?? file?["hd"]?["gif"] else { return nil }
            return Gif(id: slug, title: title ?? "", preview: .init(url: preview.url, width: preview.width, height: preview.height),
                       full: .init(url: full.url, width: full.width, height: full.height))
        }
    }
}

/// Puts a GIF on the clipboard. A keyboard can only type text into the app (`UITextDocumentProxy` has no way to insert
/// an image), so a GIF goes on the clipboard for you to paste, as GIPHY's and Raycast's keyboards do. Writing the
/// clipboard needs Full Access.
enum GifClipboard {
    /// The GIF's file, or nil when the download failed.
    static func download(_ gif: Gif) async -> Data? {
        guard let url = URL(string: gif.full.url), let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    /// Puts a GIF on the clipboard. Returns the clipboard's change count after the write, so the clipboard history can
    /// skip it (KLIPY doesn't allow keeping copies of its GIFs).
    static func put(_ data: Data) -> Int {
        UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
        return UIPasteboard.general.changeCount
    }
}
