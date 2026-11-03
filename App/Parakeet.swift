import FluidAudio
import Foundation

/// A loaded Parakeet, writing 16 kHz sound down in English.
nonisolated protocol Parakeet: Sendable {
    func write(_ samples: [Float]) async throws -> String
}

extension AsrManager: Parakeet {
    /// Held to the Latin alphabet, which v3 otherwise leaves for Cyrillic on short or unclear English.
    func write(_ samples: [Float]) async throws -> String {
        var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
        return try await transcribe(samples, decoderState: &state, language: .english).text
    }
}

nonisolated extension Parakeet {
    /// The recording leveled (`Recording.leveled`), and a tap with next to nothing said padded up to the shortest sound
    /// Parakeet takes. On the Neural Engine a minute of talking is written in well under a second.
    func dictate(_ recording: [Float]) async throws -> String {
        var samples = Recording.leveled(recording)
        let shortest = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        if samples.count < shortest { samples += repeatElement(0, count: shortest - samples.count) }
        return try await write(samples).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
