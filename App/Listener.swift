import AVFoundation
import KeyboardUI
import UIKit

/// The microphone behind the keyboard's voice typing, handing what it hears to the `VoiceModel`'s transcription, all on
/// the iPhone. After you dictate it keeps the microphone on for as long as Keep Mic On says, so the keyboard can start
/// the next dictation (`start`) without opening the app, which is the only place iOS lets a recording begin.
@MainActor final class Listener {
    static let shared = Listener()

    private let engine = AVAudioEngine()
    private let feed = Feed()
    private var micLock: Int32?
    private var micOff: Task<Void, Never>?
    private var transcription: (any Transcription)?
    private var tokens: [Int32] = []
    private var started = Date.now
    private var listened: Double = 0
    private var recording: [Float] = []
    private var mic: String?
    private(set) var state = Dictation.State.idle
    var onChange: (() -> Void)?
    var onLevel: ((Float) -> Void)?

    private init() {
        tokens = [
            Dictation.observe(.finish) { Task { await Listener.shared.finish() } },
            Dictation.observe(.start) {
                guard Listener.shared.micLock != nil else { return }
                Task { await Listener.shared.start() }
            },
            Dictation.observe(.stop) { Task { await Listener.shared.turnMicOff() } },
        ]
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            guard note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { await Listener.shared.turnMicOff() }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            Task { @MainActor in
                guard !Listener.shared.engine.isRunning else { return }
                await Listener.shared.turnMicOff()
            }
        }
    }

    /// Returns once the microphone is recording, the one step iOS allows only in the foreground.
    func start() async {
        guard state == .idle else { return }
        micOff?.cancel()
        set(.listening)
        started = .now
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw Failure.microphone }
            let transcription = try await VoiceModel.shared.transcription()
            self.transcription = transcription
            try openMic()
            mic = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
            switch state {
            case .listening:
                let natural = engine.inputNode.outputFormat(forBus: 0)
                guard feed.start(from: natural, into: transcription) else {
                    HostApp.log.error("no converter from the mic's \(natural, privacy: .public) to \(transcription.format?.description ?? "", privacy: .public)")
                    throw Failure.language
                }
            case .transcribing: await deliver(transcription)
            case .idle: await cancel(transcription)
            }
        } catch {
            await fail(error)
        }
    }

    private func fail(_ error: any Error) async {
        _ = feed.stop()
        closeMic()
        if let transcription { await cancel(transcription) }
        set(.idle, failure: (error as? Failure)?.description ?? error.localizedDescription)
    }

    /// Stops listening and hands the keyboard everything heard, once the transcription is ready if it isn't yet.
    func finish() async {
        guard state == .listening else { return }
        recording = feed.stop()
        listened = Date.now.timeIntervalSince(started)
        set(.transcribing)
        if let transcription { await deliver(transcription) } else { keepMicOn() }
    }

    /// Types what was heard, unless you cancelled or started another dictation meanwhile. The microphone stays on until
    /// then, since its lock is how the keyboard knows the app is still writing.
    private func deliver(_ transcription: any Transcription) async {
        let (recording, mic) = (recording, mic)
        let background = UIApplication.shared.beginBackgroundTask()
        defer {
            keepMicOn()
            UIApplication.shared.endBackgroundTask(background)
        }
        let writer = writer(for: transcription)
        if writer !== transcription { await transcription.cancel() }
        let text: String
        do {
            text = try await writer.text(of: recording)
        } catch {
            guard transcription === self.transcription else { return }
            self.transcription = nil
            return set(.idle, failure: error.localizedDescription)
        }
        guard transcription === self.transcription else { return }
        self.transcription = nil
        set(.idle, heard: text)
        Transcripts.shared.add(text, at: started, seconds: listened, typed: true, model: writer.model, mic: mic, recording: recording)
        HostApp.log.notice("\(writer.model, privacy: .public) wrote \(self.listened, format: .fixed(precision: 1))s down in \(Date.now.timeIntervalSince(self.started) - self.listened, format: .fixed(precision: 2))s")
    }

    /// Apple's model stands in while the picked Parakeet loads; if it loaded while you talked, it writes the recording.
    private func writer(for transcription: any Transcription) -> any Transcription {
        guard transcription is SpeechTranscription, let loaded = VoiceModel.shared.loaded else { return transcription }
        return loaded
    }

    /// Types nothing. What was said while listening is still written down, for Transcripts.
    func cancel() async {
        guard state != .idle else { return }
        let recording = feed.stop()
        let (transcription, started, wasListening) = (transcription, started, state == .listening)
        self.transcription = nil
        set(.idle)
        keepMicOn()
        guard let transcription else { return }
        guard wasListening else { return await transcription.cancel() }
        let background = UIApplication.shared.beginBackgroundTask()
        defer { UIApplication.shared.endBackgroundTask(background) }
        guard let text = try? await transcription.text(of: recording) else { return }
        Transcripts.shared.add(text, at: started, seconds: Date.now.timeIntervalSince(started), typed: false, model: transcription.model, mic: mic, recording: recording)
    }

    private func cancel(_ transcription: any Transcription) async {
        if transcription === self.transcription { self.transcription = nil }
        await transcription.cancel()
    }

    /// Starts Keep Mic On's countdown over, or turns the microphone off now when it's Off.
    func keepMicOn() {
        micOff?.cancel()
        guard micLock != nil, state != .listening else { return }
        let seconds = SettingsStore.keepMicOn
        guard seconds > 0 else { return closeMic() }
        guard seconds != Dictation.micForever else { return }
        micOff = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, state != .listening else { return }
            closeMic()
        }
    }

    /// You held the keyboard's mic, another app took the microphone (a call), or the route changed under the engine:
    /// keep what was heard, and leave the microphone off so the next dictation opens the app and starts it afresh.
    func turnMicOff() async {
        guard micLock != nil else { return }
        await finish()
        closeMic()
    }

    private func set(_ state: Dictation.State, heard: String? = nil, failure: String? = nil) {
        self.state = state
        Dictation.publish(Dictation.Status(state: state, heard: heard.flatMap { $0.isEmpty ? nil : $0 }, failure: failure))
        onChange?()
    }

    /// Mixes with whatever else is playing, so music keeps going while you talk.
    private func openMic() throws {
        guard micLock == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)
        let node = engine.inputNode
        node.installTap(onBus: 0, bufferSize: 4096, format: node.outputFormat(forBus: 0), block: Self.tap(feed) { level in
            Dictation.publish(level: level)
            Task { @MainActor in Listener.shared.onLevel?(level) }
        })
        engine.prepare()
        do {
            try engine.start()
        } catch {
            node.removeTap(onBus: 0)
            throw error
        }
        micLock = Dictation.lockMic() ?? -1
        Dictation.send(.changed)
    }

    private func closeMic() {
        micOff?.cancel()
        micOff = nil
        guard let micLock else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if micLock >= 0 { Dictation.unlockMic(micLock) }
        self.micLock = nil
        Dictation.send(.changed)
    }

    /// Runs on the audio thread: hands each buffer to the dictation in progress, if there is one, and says how loud it was.
    nonisolated private static func tap(_ feed: Feed, level: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            guard feed.yield(buffer) else { return }
            if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                let frames = Int(buffer.frameLength)
                var sum: Float = 0
                for index in 0 ..< frames { sum += samples[index] * samples[index] }
                level((sum / Float(frames)).squareRoot())
            }
        }
    }

    private enum Failure: Error, CustomStringConvertible {
        case microphone, language

        var description: String {
            switch self {
            case .microphone: "Hex needs the microphone. Turn it on in Settings › Apps › Hex."
            case .language: "Voice typing doesn't support this iPhone's language yet."
            }
        }
    }
}

/// Where the microphone's buffers go while you dictate: into the `Recording`, and converted to what the dictation's
/// model hears as you talk, if it does; nowhere while the microphone is only being kept on. The audio thread reads it
/// and the main thread swaps it, under a lock.
nonisolated private final class Feed: @unchecked Sendable {
    private let lock = NSLock()
    private var recorder: AVAudioConverter?
    private var converter: AVAudioConverter?
    private var transcription: (any Transcription)?
    private var recording: [Float] = []

    func start(from natural: AVAudioFormat, into transcription: any Transcription) -> Bool {
        guard let recorder = AVAudioConverter(from: natural, to: Recording.format) else { return false }
        let converter = transcription.format.flatMap { AVAudioConverter(from: natural, to: $0) }
        guard converter != nil || transcription.format == nil else { return false }
        lock.withLock {
            self.recorder = recorder
            self.converter = converter
            self.transcription = transcription
            recording = []
        }
        return true
    }

    /// Everything heard since `start`.
    func stop() -> [Float] {
        lock.withLock {
            defer {
                recorder = nil
                converter = nil
                transcription = nil
                recording = []
            }
            return recording
        }
    }

    /// Whether a dictation took the buffer.
    func yield(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.withLock {
            guard let recorder, let transcription else { return false }
            if let converted = Self.convert(buffer, with: recorder), let channel = converted.floatChannelData?[0] {
                recording.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            }
            if let converter, let converted = Self.convert(buffer, with: converter) { transcription.hear(converted) }
            return true
        }
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let format = converter.outputFormat
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var fed = false
        converter.convert(to: converted, error: nil) { _, status in
            status.pointee = fed ? .noDataNow : .haveData
            defer { fed = true }
            return fed ? nil : buffer
        }
        return converted
    }
}
