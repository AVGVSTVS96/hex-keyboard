import FluidAudio
import Foundation
import KeyboardStore

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

nonisolated extension AsrModelVersion {
    /// Where this Parakeet's files live: the App Group's container, whose path outlives an install, where the app's own
    /// container gets a new one with each, and Core ML keys what it compiles by the path a model loads from (App/Voice/AGENTS.md).
    var folder: URL {
        Self.clearCompiled
        let own = AsrModels.defaultCacheDirectory(for: self)
        return Self.shared?.appending(path: "Models").appending(path: own.lastPathComponent) ?? own
    }

    /// Core ML's compiles, `<bundle ID>/com.apple.e5rt.e5bundlecache/<OS build>/…` in the app's caches, emptied the first
    /// time a new install or iOS reaches for a Parakeet, before any is loaded. Each install compiles them again beside
    /// the last's, which nothing else removes: 1.3 GB on the Duo and 15 GB in a simulator by Nov 5.
    private static let clearCompiled: Void = {
        let install = "\(Bundle.main.bundlePath) \(ProcessInfo.processInfo.operatingSystemVersionString)"
        guard UserDefaults.standard.string(forKey: "compiledFor") != install else { return }
        try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "\(Bundle.main.bundleIdentifier ?? "")/com.apple.e5rt.e5bundlecache"))
        UserDefaults.standard.set(install, forKey: "compiledFor")
    }()

    /// The App Group's FluidAudio folder. The app's own is moved there the first time, a rename.
    private static let shared: URL? = {
        guard let library = AppGroup.library else { return nil }
        let own = URL.applicationSupportDirectory.appending(path: "FluidAudio")
        let shared = library.appending(path: "Application Support/FluidAudio")
        let files = FileManager.default
        guard files.fileExists(atPath: own.path(percentEncoded: false)), !files.fileExists(atPath: shared.path(percentEncoded: false)) else { return shared }
        try? files.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? files.moveItem(at: own, to: shared)) != nil else { return nil }
        return shared
    }()
}
