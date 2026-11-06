import Foundation
import KeyboardStore
import Observation

/// A computer that shares its typing and dictation with Stats: an address that answers `GET typing-stats.json`, in
/// Keystroke's shape, to whoever sends its token. `mac/share` sets a Mac up and shows its link (docs/computers.md).
nonisolated struct Computer: Codable, Hashable, Sendable {
    var name: String
    var url: URL
    var token: String

    /// `iikb://computer?name=…&url=…&token=…`, the link `mac/share` shows as a QR code.
    init?(link: URL) {
        guard link.scheme == "iikb", link.host() == "computer",
              let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
              let name = items.first(where: { $0.name == "name" })?.value, !name.isEmpty,
              let url = items.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)), Source.allows(url),
              let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty
        else { return nil }
        self.name = name
        self.url = url
        self.token = token
    }
}

/// The computers you added, each with what it last shared, kept so a computer that's asleep or out of reach shows as it
/// last was.
@MainActor @Observable final class Computers {
    static let shared = Computers()

    private(set) var all: [Computer]
    private(set) var activity: [String: Activity] = [:]
    /// When each computer last changed what it shares.
    private(set) var asOf: [String: Date] = [:]
    @ObservationIgnored private var reading = false

    private static let list = URL.applicationSupportDirectory.appending(path: "computers.json")
    private static let copies = URL.cachesDirectory.appending(path: "computers")

    private init() {
        all = (try? Data(contentsOf: Self.list)).flatMap { try? JSONDecoder().decode([Computer].self, from: $0) } ?? [] // file: the computers you added
        for computer in all { load(computer.name) }
    }

    /// Adds `computer`, in place of one with the same name, and reads it.
    func add(_ computer: Computer) {
        all = all.filter { $0.name != computer.name } + [computer]
        save()
        Task { await read(computer) }
    }

    func remove(_ name: String) {
        all.removeAll { $0.name == name }
        activity[name] = nil
        asOf[name] = nil
        try? FileManager.default.removeItem(at: Self.copy(name))
        save()
    }

    func read() async {
        guard !reading else { return }
        reading = true
        defer { reading = false }
        await withTaskGroup { group in
            for computer in all { group.addTask { await self.read(computer) } }
        }
    }

    private func read(_ computer: Computer) async {
        var request = URLRequest(url: computer.url.appending(path: "typing-stats.json"), cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(computer.token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let activity = KeystrokeStats.decode(data), all.contains(computer)
        else { return }
        let modified = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified").flatMap(Self.httpDate) ?? .now
        self.activity[computer.name] = activity
        asOf[computer.name] = modified
        let copy = Self.copy(computer.name)
        try? FileManager.default.createDirectory(at: Self.copies, withIntermediateDirectories: true)
        try? data.write(to: copy, options: .atomic) // file: cache of what the computer shares, fetched again from it
        try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: copy.path(percentEncoded: false))
    }

    private func load(_ name: String) {
        let copy = Self.copy(name)
        activity[name] = (try? Data(contentsOf: copy)).flatMap(KeystrokeStats.decode) // file: cache of what the computer shares
        asOf[name] = try? copy.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.list.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: Self.list, options: .atomic) // file: the computers you added
    }

    private static func copy(_ name: String) -> URL {
        copies.appending(path: (name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name) + ".json")
    }

    private static func httpDate(_ text: String) -> Date? {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .gmt
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return format.date(from: text)
    }
}
