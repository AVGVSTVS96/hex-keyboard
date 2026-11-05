import AVFoundation

/// A dictation's sound as Hex keeps it, beside its transcript: 16 kHz mono, which is what a Parakeet reads, saved as a
/// 16-bit WAV.
nonisolated enum Recording {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    /// The recording with its speech brought up toward -20 dBFS, but its quietest stretches (the room) to no more than
    /// -55 dBFS, and never clipped. FluidAudio's Parakeets drop whole stretches of quiet speech: on 170 of Bassim's
    /// dictations made 30 dB quieter, v3 lost 651 words instead of 42 (11.8% wrong instead of 2.5%). A room lifted
    /// louder than that comes back as "Thank you."
    static func leveled(_ samples: [Float]) -> [Float] {
        let frame = 320
        guard samples.count >= frame else { return samples }
        let levels = stride(from: 0, to: samples.count - frame + 1, by: frame).map { start in
            let slice = samples[start ..< start + frame]
            let mean = slice.reduce(0, +) / Float(frame)
            return (slice.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(frame)).squareRoot()
        }.sorted()
        let (room, speech) = (levels[levels.count / 10], levels[levels.count * 95 / 100])
        let peak = samples.reduce(0) { max($0, abs($1)) }
        guard speech > 0, peak > 0 else { return samples }
        let gain = min(0.1 / speech, room > 0 ? 0.001_78 / room : .infinity, 0.99 / peak)
        return gain > 1 ? samples.map { $0 * gain } : samples
    }

    static func write(_ samples: [Float], to url: URL) throws {
        try (header(bytes: samples.count * 2) + pcm(samples)).write(to: url, options: .atomic) // file: recording audio
    }

    private static func header(bytes: Int) -> Data {
        var data = Data(capacity: 44)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(16_000))
        append(UInt32(32_000))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(bytes))
        return data
    }

    private static func pcm(_ samples: some Collection<Float>) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples { withUnsafeBytes(of: Int16(max(-1, min(1, sample)) * Float(Int16.max)).littleEndian) { data.append(contentsOf: $0) } }
        return data
    }

    /// A recording written to disk as it's heard, so an app that ends mid-dictation (a crash, an install, a dead
    /// iPhone) leaves the sound up to then. `read` reads one whose header never got its length.
    nonisolated final class File {
        private let handle: FileHandle
        private var bytes = 0

        init?(_ url: URL) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: url.path, contents: Recording.header(bytes: 0)), // file: recording audio, written as it's heard
                  let handle = try? FileHandle(forWritingTo: url) // file: recording audio, written as it's heard
            else { return nil }
            _ = try? handle.seekToEnd()
            self.handle = handle
        }

        func append(_ samples: UnsafeBufferPointer<Float>) {
            let data = Recording.pcm(samples)
            try? handle.write(contentsOf: data)
            bytes += data.count
        }

        func close() {
            try? handle.seek(toOffset: 0)
            try? handle.write(contentsOf: Recording.header(bytes: bytes))
            try? handle.close()
        }
    }

    /// The recording at `url` as a voice memo named `name`: AAC in a .m4a, as Voice Memos keeps its own.
    static func memo(_ url: URL, named name: String) throws -> URL {
        let samples = try read(url)
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { throw CocoaError(.fileReadCorruptFile) }
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].update(from: samples, count: samples.count)
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let memo = folder.appending(path: "\(name).m4a")
        let file = try AVAudioFile(forWriting: memo, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1], commonFormat: .pcmFormatFloat32, interleaved: false) // file: voice memo export
        try file.write(from: buffer)
        file.close()
        return memo
    }

    /// A recording `write` saved.
    static func read(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url) // file: recording audio
        let count = max(0, (data.count - 44) / 2)
        return data.withUnsafeBytes { raw in
            (0 ..< count).map { Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: 44 + $0 * 2, as: Int16.self))) / Float(Int16.max) }
        }
    }
}
