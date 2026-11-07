import Darwin
import Foundation

/// Sends iikb's files to the backup server built in as `Resources/Keys/backup.key` (its address on the first line, its
/// token on the second; docs/backup.md) each time they change, so they outlive a crash, a delete, an install of any kind,
/// a lost iPhone, and a bug that saves over them: the server keeps every version and deletes nothing.
/// It sends each file the server lacks or holds at another size or modification time to the second, as rsync's quick
/// check does, so a send that failed goes with the next one.
nonisolated public enum Backup {
    /// A folder and the name it has on the server, the same as `scripts/backup` gives it.
    public typealias Folder = (name: String, url: URL)

    public enum Outcome: Sendable {
        case upToDate, unreachable
    }

    private static let server: (url: URL, token: String)? = {
        guard let key = Bundle.module.url(forResource: "backup", withExtension: "key", subdirectory: "Keys"),
              let lines = try? String(contentsOf: key, encoding: .utf8).split(whereSeparator: \.isNewline), lines.count == 2, // file: bundled key
              let url = URL(string: String(lines[0]))
        else { return nil }
        return (url, String(lines[1]))
    }()

    public static var isBuiltIn: Bool { server != nil }

    /// The kind of device this is, from its model ("iPad16,4" is an iPad). The server keeps an iPhone's files where it
    /// always has, and another device's in a backup of its own (`server/backup.ts`), so an iPad never sends its files
    /// over the iPhone's. An iPhone's build from before this sends no kind, and the server takes it for an iPhone.
    static let device: String = {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return String(machine.prefix { $0.isLetter })
    }()

    /// The server's listing of what it holds for this device, or nil when it can't be reached. A device other than an
    /// iPhone gets one only from a server that says it keeps that device apart, since an older one would put its files
    /// over the iPhone's.
    private static func listing(_ server: (url: URL, token: String)) async -> (request: URLRequest, held: [String: [Int]])? {
        var request = URLRequest(url: server.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Authorization")
        request.setValue(device, forHTTPHeaderField: "X-Device")
        guard let (data, response) = try? await URLSession.shared.data(for: request), let response = response as? HTTPURLResponse,
              response.statusCode == 200, device == "iPhone" || response.value(forHTTPHeaderField: "X-Device") == device,
              let held = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else { return nil }
        return (request, held)
    }

    private static var library: URL { .libraryDirectory }

    /// What the keyboard learned, its emoji and GIF picks, its copy of the clipboard, and its settings.
    public static var keyboard: [Folder] {
        [("keyboard/support", .applicationSupportDirectory), ("keyboard/Preferences", library.appending(path: "Preferences"))]
    }

    /// Transcripts and their recordings, the Dictionary, and the app's settings.
    public static var app: [Folder] {
        [("app", .applicationSupportDirectory), ("app/Preferences", library.appending(path: "Preferences"))]
    }

    /// The clipboard history, the taps the keyboard shares, and the settings both sides read.
    public static var group: [Folder] {
        AppGroup.library.map { [("group/Library", $0)] } ?? []
    }

    /// Parakeet's models and the personal network, which download again, and what iOS may clear.
    private static let skipped: Set<String> = ["FluidAudio", "Personal", "Caches"]

    /// Sends what changed in the background, letting the app or keyboard finish even as it goes away. `skip` names files
    /// not to send yet, by their name on the server.
    public static func sync(_ folders: [Folder], skip: @escaping @Sendable (String) -> Bool = { _ in false }) {
        guard isBuiltIn else { return }
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Backing up iikb") { expired in
            guard !expired else { return }
            let done = DispatchSemaphore(value: 0)
            Task {
                await send(folders, skip: skip)
                done.signal()
            }
            done.wait()
        }
    }

    /// Sends what changed and says how it went, or nil when the build has no backup server.
    @discardableResult
    public static func send(_ folders: [Folder], skip: @Sendable (String) -> Bool = { _ in false }) async -> Outcome? {
        guard let server else { return nil }
        guard let (request, held) = await listing(server) else { return .unreachable }
        let files = folders.flatMap(contents).filter { !skip($0.name) }
        var outcome = Outcome.upToDate
        for file in files where held[file.name] != [file.size, file.modified] {
            var put = request
            put.url = server.url.appending(path: file.name)
            put.httpMethod = "PUT"
            put.setValue(String(file.modified), forHTTPHeaderField: "X-Modified")
            // One file the server turns away, or one deleted since the listing, never keeps the files after it from going.
            guard let (_, response) = try? await URLSession.shared.upload(for: put, fromFile: file.url) else {
                if FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)) { return .unreachable }
                continue
            }
            if (response as? HTTPURLResponse)?.statusCode != 204 { outcome = .unreachable }
        }
        return outcome
    }

    public enum Pulled: Sendable {
        case fetched, current, unavailable, failed
    }

    /// Fetches a file the server made for the iPhone (under `personal/`) to `url`, when the server holds it at another size
    /// or modification time than the copy there (the quick check `send` uses) and made it after `after`; the copy gets the
    /// server's time. `current` when the copy is the server's or the server has nothing newer to give.
    public static func pull(_ name: String, to url: URL, after: Date = .distantPast) async -> Pulled {
        guard let server else { return .unavailable }
        guard let (listed, held) = await listing(server) else { return .unavailable }
        var request = listed
        guard let theirs = held[name], theirs.count == 2, Date(timeIntervalSince1970: Double(theirs[1])) > after else { return .current }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        if values?.fileSize == theirs[0], values?.contentModificationDate.map({ Int($0.timeIntervalSince1970) }) == theirs[1] { return .current }
        request.url = server.url.appending(path: name)
        guard let (downloaded, response) = try? await URLSession.shared.download(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              (try? downloaded.resourceValues(forKeys: [.fileSizeKey]))?.fileSize == theirs[0]
        else { return .failed }
        let manager = FileManager.default
        try? manager.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(theirs[1]))], ofItemAtPath: downloaded.path(percentEncoded: false))
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: url.path(percentEncoded: false)) {
            return (try? manager.replaceItemAt(url, withItemAt: downloaded)) != nil ? .fetched : .failed
        }
        return (try? manager.moveItem(at: downloaded, to: url)) != nil ? .fetched : .failed
    }

    private static func contents(of folder: Folder) -> [(name: String, url: URL, size: Int, modified: Int)] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let root = folder.url.resolvingSymlinksInPath().pathComponents
        guard let walk = FileManager.default.enumerator(at: folder.url, includingPropertiesForKeys: Array(keys)) else { return [] }
        var files: [(name: String, url: URL, size: Int, modified: Int)] = []
        for case let url as URL in walk {
            if skipped.contains(url.lastPathComponent) {
                walk.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let size = values.fileSize, let modified = values.contentModificationDate
            else { continue }
            let path = url.resolvingSymlinksInPath().pathComponents.dropFirst(root.count)
            files.append((([folder.name] + path).joined(separator: "/"), url, size, Int(modified.timeIntervalSince1970)))
        }
        return files
    }
}
