import AVFoundation
import FluidAudio
import Observation
import Speech
import UIKit

/// The speech model voice typing writes with, picked in Settings: one of NVIDIA's Parakeets, run on the Neural Engine by
/// FluidAudio and downloaded from Hugging Face once, or Apple's SpeechTranscriber. A dictation made while the picked
/// Parakeet gets ready is written by it once it's ready. Either way the sound never leaves the iPhone.
@Observable final class VoiceModel {
    static let shared = VoiceModel()

    nonisolated enum Model: String, CaseIterable {
        case ultra, v3, apple

        var title: String {
            switch self {
            case .ultra: "Parakeet Ultra"
            case .v3: "Parakeet v3"
            case .apple: "Apple"
            }
        }

        var detail: String {
            switch self {
            case .v3: "Fast and accurate. Downloads once, about 500 MB."
            case .ultra: "A little more accurate. Takes minutes to get ready, and warms the iPhone, each time Hex opens."
            case .apple: "Built into iOS. Writes as you speak."
            }
        }

        var version: AsrModelVersion? {
            switch self {
            case .ultra: .ultra
            case .v3: .v3
            case .apple: nil
            }
        }

        /// Loads the Parakeet, downloading it first if it isn't on the iPhone yet; nil for Apple's. iOS sometimes kills its
        /// Neural Engine compiler for memory while it compiles the encoder after an install, and Core ML then runs the
        /// encoder on the CPU, ten times slower, until it's loaded again: so it's loaded again, up to three times.
        var loader: (@Sendable (@escaping ProgressHandler) async throws -> any Parakeet)? {
            guard let version else { return nil }
            let title = title
            return { progress in
                let folder = try await AsrModels.download(version: version, progressHandler: progress)
                var load = 1
                while true {
                    let parakeet = AsrManager(config: .default)
                    try await parakeet.loadModels(try await AsrModels.load(from: folder, version: version))
                    guard load < 3, try await !parakeet.onNeuralEngine() else { return parakeet }
                    HostApp.log.error("\(title, privacy: .public)'s encoder ran on the CPU after load \(load)")
                    load += 1
                }
            }
        }
    }

    enum State: Equatable {
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    private static let modelKey = "voiceModel"

    private(set) var model = UserDefaults.standard.string(forKey: modelKey).flatMap(Model.init) ?? .v3
    private(set) var state = State.loading
    @ObservationIgnored private var parakeet: Task<any Parakeet, any Error>?

    private init() {}

    /// Lets go of the model in use, so only one is ever in memory, and gets the new one ready.
    func pick(_ model: Model) {
        guard model != self.model else { return }
        UserDefaults.standard.set(model.rawValue, forKey: Self.modelKey)
        self.model = model
        parakeet?.cancel()
        parakeet = nil
        state = .loading
        prepare()
    }

    /// Tries the picked model again after it failed to download or load.
    func retry() {
        guard case .failed = state else { return }
        state = .loading
        prepare()
    }

    /// The picked model and how far along it is, in a few words.
    var status: String {
        switch state {
        case .downloading(let done): "\(model.title), downloading \(done.formatted(.percent.precision(.fractionLength(0))))"
        case .loading: "\(model.title), getting ready"
        case .ready: "\(model.title), ready"
        case .failed: "\(model.title) couldn’t load"
        }
    }

    /// Downloads the picked Parakeet if it isn't on the iPhone yet, then loads it, unless it's loaded, on its way, or
    /// failed since it was picked. The first load after an install compiles it for the Neural Engine; later ones read
    /// that from a cache. It asks iOS for time in the background to finish, since iOS suspends Hex there within seconds
    /// (after `scripts/phone` starts it, or once you're back in your app with the microphone off) and the compile with it.
    func prepare() {
        guard let load = model.loader else { return state = .ready }
        if case .failed = state { return }
        guard parakeet == nil else { return }
        let model = model
        let began = Date.now
        let parakeet = Task.detached {
            try await load { progress in
                Task { @MainActor in
                    guard VoiceModel.shared.model == model else { return }
                    if case .downloading = progress.phase {
                        VoiceModel.shared.state = .downloading(progress.fractionCompleted)
                    } else {
                        VoiceModel.shared.state = .loading
                    }
                }
            }
        }
        self.parakeet = parakeet
        nonisolated(unsafe) var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(background) }
        Task {
            defer { UIApplication.shared.endBackgroundTask(background) }
            do {
                _ = try await parakeet.value
                guard self.parakeet == parakeet else { return }
                state = .ready
                HostApp.log.notice("\(model.title, privacy: .public) ready after \(Date.now.timeIntervalSince(began), format: .fixed(precision: 1))s")
            } catch {
                guard self.parakeet == parakeet else { return }
                self.parakeet = nil
                state = .failed(error.localizedDescription)
                HostApp.log.error("\(model.title, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A new dictation's transcription, by the picked model. A Parakeet still getting ready writes the recording once
    /// it's ready; one that failed to load is tried again.
    func transcription() async throws -> any Transcription {
        retry()
        prepare()
        guard let parakeet else { return try await SpeechTranscription.make() }
        return ParakeetTranscription(parakeet, model: model.title)
    }
}

/// One dictation, from the microphone's sound to text.
nonisolated protocol Transcription: AnyObject, Sendable {
    /// For the log and the transcript.
    var model: String { get }
    /// The sound it hears while you talk, which the microphone's is converted to; nil when it only reads the recording.
    var format: AVAudioFormat? { get }
    /// Runs on the audio thread.
    func hear(_ buffer: AVAudioPCMBuffer)
    /// Everything said, once no more sound is coming, given all of it as a `Recording`.
    func text(of recording: [Float]) async throws -> String
    func cancel() async
}

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

    /// Whether the encoder runs on the Neural Engine, from how long it takes over a second of silence, which it pads to
    /// its 15-second window: on the iPhone Duo about 0.1 s there, and 1.5 s on the CPU.
    func onNeuralEngine() async throws -> Bool {
        let began = ContinuousClock.now
        _ = try await write([Float](repeating: 0, count: ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)))
        return ContinuousClock.now - began < .seconds(0.5)
    }
}

/// Writes the whole recording down when you're done: Parakeet takes it at once, fast enough on the Neural Engine that a
/// minute of talking is written in well under a second.
nonisolated final class ParakeetTranscription: Transcription, @unchecked Sendable {
    let model: String
    let format: AVAudioFormat? = nil
    private let parakeet: Task<any Parakeet, any Error>

    init(_ parakeet: Task<any Parakeet, any Error>, model: String) {
        self.parakeet = parakeet
        self.model = model
    }

    func hear(_ buffer: AVAudioPCMBuffer) {}

    /// Pads a tap with next to nothing said up to the shortest sound Parakeet takes.
    func text(of recording: [Float]) async throws -> String {
        var samples = Recording.leveled(recording)
        let shortest = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        if samples.count < shortest { samples += repeatElement(0, count: shortest - samples.count) }
        return try await parakeet.value.write(samples).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {}
}

/// Apple's SpeechTranscriber (the iOS 26 model, not the older one behind the system's dictation key), else the dictation
/// model with punctuation. It writes as you speak, so when you're done only the last words are left to finish.
nonisolated final class SpeechTranscription: Transcription, @unchecked Sendable {
    var model = "Apple"
    let format: AVAudioFormat?
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let analyzer: Task<SpeechAnalyzer, any Error>
    private let heard: Task<String, any Error>

    static func make() async throws -> SpeechTranscription {
        let (module, heard) = try await transcriber()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw Unsupported() }
        return SpeechTranscription(module, format: format, heard: heard)
    }

    private init(_ module: any SpeechModule, format: AVAudioFormat, heard: Task<String, any Error>) {
        self.format = format
        self.heard = heard
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        self.input = input
        analyzer = Task {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) { try await request.downloadAndInstall() }
            let analyzer = SpeechAnalyzer(modules: [module])
            try await analyzer.start(inputSequence: stream)
            return analyzer
        }
    }

    func hear(_ buffer: AVAudioPCMBuffer) {
        input.yield(AnalyzerInput(buffer: buffer))
    }

    func text(of _: [Float]) async throws -> String {
        input.finish()
        try await analyzer.value.finalizeAndFinishThroughEndOfInput()
        return try await heard.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        input.finish()
        heard.cancel()
        await (try? analyzer.value)?.cancelAndFinishNow()
    }

    private static func transcriber() async throws -> (any SpeechModule, Task<String, any Error>) {
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            let module = SpeechTranscriber(locale: locale, preset: .transcription)
            return (module, Task {
                var text = ""
                for try await result in module.results where result.isFinal { text += String(result.text.characters) }
                return text
            })
        }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else { throw Unsupported() }
        let module = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [], attributeOptions: [])
        return (module, Task {
            var text = ""
            for try await result in module.results where result.isFinal { text += String(result.text.characters) }
            return text
        })
    }

    private struct Unsupported: LocalizedError {
        var errorDescription: String? { "Voice typing doesn't support this iPhone's language yet." }
    }
}
