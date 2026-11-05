import AVFoundation
import FluidAudio
import KeyboardCore
import Observation
import Speech
import UIKit

/// The speech model voice typing writes with, picked in Settings: one of NVIDIA's Parakeets, run on the Neural Engine by
/// FluidAudio and downloaded from Hugging Face once, or Apple's SpeechTranscriber. It only ever writes finished
/// recordings (`write`), so it never stands between you and the microphone: a dictation made while the picked Parakeet
/// gets ready is recorded as any other and written once it's ready. Either way the sound never leaves the iPhone.
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
            case .ultra: "A little more accurate. Takes minutes to get ready, and warms the iPhone, each time iikb opens."
            case .apple: "Built into iOS."
            }
        }

        /// Loads in a moment once this install has compiled it, so iikb lets go of it between dictations; Ultra's
        /// encoder never caches, so iikb keeps it.
        var reloadsQuickly: Bool { self == .v3 }

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
                    guard VoiceModel.hasNeuralEngine, load < 3, try await !parakeet.onNeuralEngine() else { return parakeet }
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
    private(set) var state = State.loading { didSet { if state != oldValue { onState?() } } }
    @ObservationIgnored var onState: (() -> Void)?
    @ObservationIgnored private var parakeet: Task<any Parakeet, any Error>?
    @ObservationIgnored private var writes = 0
    /// Whether iikb has its microphone on, which gets the Parakeet ready and keeps it for the next dictation.
    @ObservationIgnored var micIsOn = false { didSet { if micIsOn { prepare() } else { letGoIfIdle() } } }

    #if targetEnvironment(simulator)
    /// The simulator has no Neural Engine, so a Parakeet would compile on the Mac's CPU, and its UI tests stand in for
    /// the app's voice (`scripts/voiceapp.py`).
    nonisolated static let hasNeuralEngine = false
    #else
    nonisolated static let hasNeuralEngine = true
    #endif

    private init() {}

    /// Lets go of the model in use, so only one is ever in memory, and gets the new one ready.
    func pick(_ model: Model) {
        guard model != self.model else { return }
        UserDefaults.standard.set(model.rawValue, forKey: Self.modelKey)
        self.model = model
        parakeet?.cancel()
        parakeet = nil
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

    /// What dictations wait for while the model gets ready, in a few words for the keyboard's bar; nil once it's ready.
    var waiting: String? {
        switch state {
        case .downloading(let done): "Model downloading, \(done.formatted(.percent.precision(.fractionLength(0))))"
        case .loading: "Model loading…"
        case .ready: nil
        case .failed: "Model couldn’t load"
        }
    }

    /// Downloads the picked Parakeet if it isn't on the iPhone yet, then loads it, unless it's loaded or on its way; one
    /// that failed is tried again. The first load after an install compiles it for the Neural Engine; later ones read
    /// that from a cache. It asks iOS for time in the background to finish, since iOS suspends Hex there within seconds
    /// (after `scripts/phone` starts it, or once you're back in your app with the microphone off) and the compile with it.
    func prepare() {
        guard let load = model.loader else { return state = .ready }
        guard parakeet == nil else { return }
        state = .loading
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
                letGoIfIdle()
            } catch {
                guard self.parakeet == parakeet else { return }
                self.parakeet = nil
                state = .failed(error.localizedDescription)
                HostApp.log.error("\(model.title, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    struct Written {
        /// As your style and vocabulary have it (`DictationWriting`).
        var text: String
        /// As the model wrote it.
        var heard: String
        /// As the model wrote it, with your vocabulary and no style or lists: what a field of addresses or digits reads.
        var plain: String
        var model: String
    }

    /// A finished recording written down by the picked model, once it's ready: a dictation, Transcribe Again, and a
    /// recording an ended app left all go through here. Picking another model while it waits has that one write it.
    func write(_ recording: [Float]) async throws -> Written {
        writes += 1
        defer {
            writes -= 1
            letGoIfIdle()
        }
        while true {
            prepare()
            let model = model
            do {
                let heard: String
                if let parakeet { heard = try await parakeet.value.dictate(recording) } else { heard = try await AppleSpeech.write(recording) }
                return Written(text: DictationWriting.typed(heard), heard: heard, plain: DictationWriting.plain(heard), model: model.title)
            } catch {
                guard self.model != model else { throw error }
            }
        }
    }
}

extension VoiceModel {
    /// Lets go of a Parakeet that loads again in a moment while nothing needs it: the microphone is off and nothing is
    /// being written, so it isn't held in memory between dictations.
    private func letGoIfIdle() {
        guard !micIsOn, writes == 0, model.reloadsQuickly, state == .ready, parakeet != nil else { return }
        parakeet = nil
    }
}

extension AsrManager {
    /// Whether the encoder runs on the Neural Engine, from how long it takes over a second of silence, which it pads to
    /// its 15-second window: on the iPhone Duo about 0.1 s there, and 1.5 s on the CPU.
    func onNeuralEngine() async throws -> Bool {
        let began = ContinuousClock.now
        _ = try await write([Float](repeating: 0, count: ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)))
        return ContinuousClock.now - began < .seconds(0.5)
    }
}

/// Apple's SpeechTranscriber (the iOS 26 model, not the older one behind the system's dictation key), else the dictation
/// model with punctuation.
nonisolated enum AppleSpeech {
    static func write(_ recording: [Float]) async throws -> String {
        let (module, heard) = try await transcriber()
        defer { heard.cancel() }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw Unsupported() }
        guard let sound = converted(recording, to: format) else { throw Unconvertible() }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) { try await request.downloadAndInstall() }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.start(inputSequence: stream)
        input.yield(AnalyzerInput(buffer: sound))
        input.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await heard.value.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func converted(_ recording: [Float], to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: Recording.format, frameCapacity: AVAudioFrameCount(recording.count)),
              let converter = AVAudioConverter(from: Recording.format, to: format),
              let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(recording.count) * format.sampleRate / 16_000) + 1)
        else { return nil }
        buffer.frameLength = buffer.frameCapacity
        recording.withUnsafeBufferPointer { buffer.floatChannelData?[0].update(from: $0.baseAddress!, count: recording.count) }
        nonisolated(unsafe) var fed = false
        converter.convert(to: converted, error: nil) { _, status in
            status.pointee = fed ? .endOfStream : .haveData
            defer { fed = true }
            return fed ? nil : buffer
        }
        return converted
    }

    private struct Unsupported: LocalizedError {
        var errorDescription: String? { "Voice typing doesn't support this iPhone's language yet." }
    }

    private struct Unconvertible: LocalizedError {
        var errorDescription: String? { "This recording can't be read by Apple's model." }
    }
}
