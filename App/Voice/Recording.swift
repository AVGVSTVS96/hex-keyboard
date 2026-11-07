import AVFoundation

/// A dictation's sound as iikb keeps it, beside its transcript: 16 kHz mono, which is what a Parakeet reads, saved as a
/// 16-bit WAV.
nonisolated enum Recording {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    /// The recording with its speech brought up toward -20 dBFS, but its quietest stretches (the room) to no more than
    /// -55 dBFS, and never clipped. FluidAudio's Parakeets drop whole stretches of quiet speech: on 170 of Bassim's
    /// dictations made 30 dB quieter, v3 lost 651 words instead of 42 (11.8% wrong instead of 2.5%). A room lifted
    /// louder than that comes back as "Thank you."
    static func leveled(_ samples: [Float]) -> [Float] {
        guard let (room, speech) = levels(samples) else { return samples }
        let peak = samples.reduce(0) { max($0, abs($1)) }
        guard speech > 0, peak > 0 else { return samples }
        let gain = min(0.1 / speech, room > 0 ? 0.001_78 / room : .infinity, 0.99 / peak)
        return gain > 1 ? samples.map { $0 * gain } : samples
    }

    /// The room and the speech: the quietest tenth and the loudest twentieth of the recording's 20 ms stretches, each
    /// the root mean square about its mean; nil when it's shorter than one.
    static func levels(_ samples: [Float]) -> (room: Float, speech: Float)? {
        let frame = 320
        guard samples.count >= frame else { return nil }
        let levels = stride(from: 0, to: samples.count - frame + 1, by: frame).map { start in
            let slice = samples[start ..< start + frame]
            let mean = slice.reduce(0, +) / Float(frame)
            return (slice.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(frame)).squareRoot()
        }.sorted()
        return (levels[levels.count / 10], levels[levels.count * 95 / 100])
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

    /// How a recording leaves iikb: an .m4a in AAC, as Voice Memos keeps its own, or a .caf in Opus at 24 kHz, as
    /// Messages records its audio messages.
    enum Export {
        case memo, message
    }

    /// The recording at `url` as a file named `name`, in a folder of its own to delete once it's sent.
    static func export(_ url: URL, named name: String, as kind: Export) throws -> URL {
        let samples = try read(url)
        let rate: Double = kind == .memo ? 16_000 : 24_000
        guard !samples.isEmpty,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let buffer = converted(samples, to: target)
        else { throw CocoaError(.fileReadCorruptFile) }
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appending(path: kind == .memo ? "\(name).m4a" : "\(name).caf")
        let codec = kind == .memo ? kAudioFormatMPEG4AAC : kAudioFormatOpus
        let file = try AVAudioFile(forWriting: out, settings: [AVFormatIDKey: codec, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1], commonFormat: .pcmFormatFloat32, interleaved: false) // file: recording export
        try file.write(from: buffer)
        file.close()
        return out
    }

    /// `samples` at 16 kHz in `format`.
    static func converted(_ samples: [Float], to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: Recording.format, frameCapacity: AVAudioFrameCount(samples.count)),
              let converter = AVAudioConverter(from: Recording.format, to: format),
              let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(samples.count) * format.sampleRate / 16_000) + 1)
        else { return nil }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData?[0].update(from: $0.baseAddress!, count: samples.count) }
        nonisolated(unsafe) var fed = false
        converter.convert(to: converted, error: nil) { _, status in
            status.pointee = fed ? .endOfStream : .haveData
            defer { fed = true }
            return fed ? nil : buffer
        }
        return converted
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
