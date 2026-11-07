import Foundation
import KeyboardStore

/// An app's name as people know it, from its bundle ID: its App Store name without the tagline or maker ("Gmail -
/// Email by Google" is Gmail, "Claude by Anthropic" Claude), asked of Apple's iTunes Search API once and kept in
/// Caches. Until the answer is in, and for an app the store doesn't list, the bundle ID's last part stands in.
@Observable final class AppName {
    static func of(_ bundle: String) -> String { shared.name(bundle) }

    private static let shared = AppName()

    private var names: [String: String]
    @ObservationIgnored private var pending: Set<String> = []
    @ObservationIgnored private var asked: Set<String> = []
    @ObservationIgnored private let file = StoredFile<[String: String]>(URL.cachesDirectory.appending(path: "app-names.json"))

    private init() {
        names = file.read().value ?? [:]
    }

    /// Apple's own that the App Store doesn't list.
    private static let unlisted = [
        "com.apple.Preferences": "Settings",
        "com.apple.Spotlight": "Search",
        "com.apple.springboard": "Home Screen",
        "com.apple.AppStore": "App Store",
        "com.apple.InCallService": "Phone",
    ]

    private func name(_ bundle: String) -> String {
        if let name = Self.unlisted[bundle] ?? names[bundle], !name.isEmpty { return name }
        if names[bundle] == nil, asked.insert(bundle).inserted {
            if pending.isEmpty { Task { await lookUp() } }
            pending.insert(bundle)
        }
        return bundle.split(separator: ".").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? bundle
    }

    private func lookUp() async {
        let bundles = pending.sorted()
        pending = []
        var query = URLComponents(string: "https://itunes.apple.com/lookup")!
        query.queryItems = [
            URLQueryItem(name: "bundleId", value: bundles.joined(separator: ",")),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "US"),
        ]
        guard let (data, _) = try? await URLSession.shared.data(from: query.url!),
              let found = try? JSONDecoder().decode(Lookup.self, from: data)
        else { return }
        var names = self.names
        for bundle in bundles { names[bundle] = "" }
        for app in found.results { names[app.bundleId] = Self.short(app.trackName, by: app.artistName) }
        self.names = names
        file.save(names)
    }

    /// A store name without its tagline, which follows a dash, a colon or a bar, or its maker's "by".
    static func short(_ name: String, by maker: String) -> String {
        let cut = [" - ", " – ", " — ", ": ", " | "].compactMap { name.range(of: $0)?.lowerBound }.min()
        let title = String(name[..<(cut ?? name.endIndex)]).trimmingCharacters(in: .whitespaces)
        guard let by = title.range(of: " by ", options: .backwards), maker.hasPrefix(title[by.upperBound...]) else { return title }
        return String(title[..<by.lowerBound])
    }

    private struct Lookup: Decodable {
        struct App: Decodable {
            let bundleId: String
            let trackName: String
            let artistName: String
        }

        let results: [App]
    }
}
