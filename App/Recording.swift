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
        var data = Data(capacity: 44 + samples.count * 2)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(16_000))
        append(UInt32(32_000))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(bytes)
        for sample in samples { append(Int16(max(-1, min(1, sample)) * Float(Int16.max))) }
        try data.write(to: url, options: .atomic)
    }

    /// A recording `write` saved.
    static func read(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let count = max(0, (data.count - 44) / 2)
        return data.withUnsafeBytes { raw in
            (0 ..< count).map { Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: 44 + $0 * 2, as: Int16.self))) / Float(Int16.max) }
        }
    }
}
