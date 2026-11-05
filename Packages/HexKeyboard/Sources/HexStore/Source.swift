import Foundation

/// A service the keyboard tells what you type, which can answer with a hint over the suggestions (docs/sources.md).
nonisolated public struct Source: Codable, Hashable, Sendable {
    public var name: String
    public var url: URL
    public var token: String?

    public init(name: String, url: URL, token: String? = nil) {
        self.name = name
        self.url = url
        self.token = token
    }

    /// `hexkeyboard://source?name=…&url=…&token=…`, the link a source gives you to add it.
    public init?(link: URL) {
        guard link.scheme == "hexkeyboard", link.host() == "source",
              let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
              let name = items.first(where: { $0.name == "name" })?.value, !name.isEmpty,
              let url = items.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)), Self.allows(url)
        else { return nil }
        self.init(name: name, url: url, token: items.first { $0.name == "token" }?.value)
    }

    /// iOS lets a keyboard reach `https` anywhere, and `http` only on the local network (`localhost`, `.local`).
    public static func allows(_ url: URL) -> Bool {
        url.scheme == "https" || url.scheme == "http" && url.host().map { $0 == "localhost" || $0.hasSuffix(".local") } == true
    }
}

/// The sources you added in the app, kept like every other setting.
public enum SourceStore {
    private static let key = "sources"

    public static func load(sharing: Bool = true) -> [Source] {
        (SettingsStore.value(forKey: key, sharing: sharing) as? Data).flatMap { try? JSONDecoder().decode([Source].self, from: $0) } ?? []
    }

    public static func save(_ sources: [Source]) {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        SettingsStore.set(data, forKey: key)
    }

    /// Adds `source`, in place of one with the same name.
    public static func add(_ source: Source) {
        save(load().filter { $0.name != source.name } + [source])
    }
}
