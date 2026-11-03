import Foundation
import Observation

struct Transcript: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    var seconds: Double
    /// False when you canceled it in Hex: kept here, never typed.
    var typed: Bool
    /// The speech model that wrote it; nil before Hex kept it.
    var model: String?
    /// The microphone it was said into, as iOS names it; nil before Hex kept it.
    var mic: String?
    /// What the model wrote, when your style or `Vocabulary` changed it.
    var heard: String?

    var words: Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// Every dictation the app transcribed, newest first, in one JSON line each in the app's own container, and the sound of
/// each as a `Recording` beside it, written as it's heard, up to 512 MB (about 4½ hours of talking), past which the oldest
/// lose their sound. A recording with no transcript, left by an app that ended mid-dictation, is written down the next
/// time the app opens. Nothing leaves the iPhone: the keyboard never reads it, and the app's only download is the voice
/// model.
@Observable final class Transcripts {
    static let shared = Transcripts()

    private(set) var all: [Transcript] = []
    @ObservationIgnored private let url = URL.applicationSupportDirectory.appending(path: "transcripts.jsonl")
    @ObservationIgnored private let recordings = URL.applicationSupportDirectory.appending(path: "recordings")
    @ObservationIgnored private var unwritten: [URL] = []

    private init() {
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            all = data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(Transcript.self, from: $0) }.sorted { $0.date > $1.date }
        }
        let ids = Set(all.map(\.id))
        unwritten = ((try? FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)) ?? []).filter { file in
            UUID(uuidString: file.deletingPathExtension().lastPathComponent).map { !ids.contains($0) } ?? false
        }
    }

    /// Writes down the recordings an ended app left without a transcript, kept as not typed. One that can't be written
    /// now waits for the next launch.
    func recover() async {
        for file in unwritten {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), let samples = try? Recording.read(file) else { continue }
            guard !samples.isEmpty else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            let date = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
            do {
                let written = try await VoiceModel.shared.write(samples)
                try? Recording.write(samples, to: file)
                add(written.text, heard: written.heard, id: id, at: date, seconds: Double(samples.count) / 16_000, typed: false, model: written.model, mic: nil)
            } catch {
                HostApp.log.error("couldn't write down \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        unwritten = []
    }

    /// Keeps a dictation whose `Recording` was written to `recording(of: id)` as it was heard, or, when nothing was
    /// said, drops its sound.
    func add(_ text: String, heard: String, id: Transcript.ID, at date: Date, seconds: Double, typed: Bool, model: String, mic: String?) {
        guard !text.isEmpty else {
            try? FileManager.default.removeItem(at: recording(of: id))
            return
        }
        let transcript = Transcript(id: id, date: date, text: text, seconds: seconds, typed: typed, model: model, mic: mic, heard: heard == text ? nil : heard)
        all.insert(transcript, at: all.firstIndex { $0.date < date } ?? all.endIndex)
        trim()
        guard let line = try? JSONEncoder().encode(transcript) else { return }
        do {
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.seekToEnd()
            try file.write(contentsOf: line + [UInt8(ascii: "\n")])
        } catch {
            save()
        }
    }

    func delete(_ ids: Set<Transcript.ID>) {
        all.removeAll { ids.contains($0.id) }
        save()
        for id in ids { try? FileManager.default.removeItem(at: recording(of: id)) }
    }

    /// Puts a new writing of a transcript's recording in its place.
    func replace(_ id: Transcript.ID, with text: String, heard: String, model: String) {
        guard let index = all.firstIndex(where: { $0.id == id }), !text.isEmpty else { return }
        all[index].text = text
        all[index].heard = heard == text ? nil : heard
        all[index].model = model
        save()
    }

    func recording(of id: Transcript.ID) -> URL {
        recordings.appending(path: "\(id.uuidString).wav")
    }

    func hasRecording(_ id: Transcript.ID) -> Bool {
        FileManager.default.fileExists(atPath: recording(of: id).path)
    }

    private func trim() {
        let folder = recordings
        Task.detached(priority: .utility) {
            let files = FileManager.default
            let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey]
            let kept = ((try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []).compactMap { url in
                (try? url.resourceValues(forKeys: Set(keys))).map { (url, $0.fileSize ?? 0, $0.creationDate ?? .distantPast) }
            }.sorted { $0.2 > $1.2 }
            var bytes = 0
            for (url, size, _) in kept {
                bytes += size
                if bytes > 512_000_000 { try? files.removeItem(at: url) }
            }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        let lines = all.reversed().compactMap { try? encoder.encode($0) + [UInt8(ascii: "\n")] }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(lines.joined()).write(to: url, options: .atomic)
    }
}
