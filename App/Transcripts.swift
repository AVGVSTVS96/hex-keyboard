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
    /// What the model wrote, when your `Vocabulary` changed it.
    var heard: String?

    var words: Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// Every dictation the app transcribed, newest first, in one JSON line each in the app's own container, and the sound of
/// each as a `Recording` beside it, up to 512 MB (about 4½ hours of talking), past which the oldest lose their sound.
/// Nothing leaves the iPhone: the keyboard never reads it, and the app's only download is the voice model.
@Observable final class Transcripts {
    static let shared = Transcripts()

    private(set) var all: [Transcript] = []
    @ObservationIgnored private let url = URL.applicationSupportDirectory.appending(path: "transcripts.jsonl")
    @ObservationIgnored private let recordings = URL.applicationSupportDirectory.appending(path: "recordings")

    private init() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        all = data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(Transcript.self, from: $0) }.reversed()
    }

    func add(_ text: String, heard: String, at date: Date, seconds: Double, typed: Bool, model: String, mic: String?, recording: [Float]) {
        guard !text.isEmpty else { return }
        let transcript = Transcript(date: date, text: text, seconds: seconds, typed: typed, model: model, mic: mic, heard: heard == text ? nil : heard)
        all.insert(transcript, at: 0)
        keep(recording, of: transcript.id)
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

    private func keep(_ recording: [Float], of id: Transcript.ID) {
        guard !recording.isEmpty else { return }
        let (folder, url) = (recordings, self.recording(of: id))
        Task.detached(priority: .utility) {
            let files = FileManager.default
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
            try? Recording.write(recording, to: url)
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
