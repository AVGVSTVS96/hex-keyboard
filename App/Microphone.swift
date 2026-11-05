import AVFoundation
import KeyboardUI
import Observation

/// The iPhone's microphone, recording a dictation as a `Recording`: 16 kHz, kept in memory and written to its file as
/// it's heard. It knows nothing of the models that write recordings down, so nothing about them can hold up a
/// recording. While it's on it holds the App Group's mic lock, which tells the keyboard the app is there to dictate.
@Observable @MainActor final class Microphone {
    private let engine = AVAudioEngine()
    private let feed = Feed()
    private var lock: Int32?
    /// Another app took the microphone (a call), or the route changed under the engine.
    var onLost: () -> Void = {}
    var onLevel: (_ loudness: Float, _ recorded: Double) -> Void = { _, _ in }

    init() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.onLost() }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.engine.isRunning else { return }
                self.onLost()
            }
        }
    }

    var isOn: Bool { lock != nil }

    /// The input recording now, as iOS names it.
    var input: String? { AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName }

    /// Mixes with whatever else is playing, so music keeps going while you talk. While any app records, iOS mutes every
    /// app's haptics, the keyboard's included, unless the recording session allows them. It hears through Apple's voice
    /// processing, which picks up your voice from all of the iPhone's microphones as a call does: from one microphone,
    /// the folded iPhone Duo in portrait lost his voice for seconds at a time, 12% of the time, leaving a low rumble
    /// that Parakeet writes as nothing.
    func open() throws {
        guard lock == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)
        let node = engine.inputNode
        if !node.isVoiceProcessingEnabled, (try? node.setVoiceProcessingEnabled(true)) != nil {
            node.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        }
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        let heard = node.outputFormat(forBus: 0)
        guard heard.sampleRate > 0, heard.channelCount > 0 else { throw Unrecordable(format: heard.description) }
        node.installTap(onBus: 0, bufferSize: 4096, format: nil, block: Self.tap(feed) { [weak self] level, recorded in
            Dictation.publish(level: level, recorded: recorded)
            Task { @MainActor in self?.onLevel(level, recorded) }
        })
        engine.prepare()
        do {
            try engine.start()
        } catch {
            node.removeTap(onBus: 0)
            throw error
        }
        lock = Dictation.lockMic() ?? -1
        Dictation.send(.changed)
    }

    func close() {
        guard let lock else { return }
        _ = feed.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if lock >= 0 { Dictation.unlockMic(lock) }
        self.lock = nil
        Dictation.send(.changed)
    }

    /// Records from the next sound on into `url`.
    func record(to url: URL) {
        feed.start(file: url)
        Dictation.publish(level: 0, recorded: 0)
    }

    /// Everything recorded since `record`, through your last word (`Feed.stopOnceQuiet`).
    func stop() async -> [Float] {
        engine.isRunning ? await feed.stopOnceQuiet() : feed.stop()
    }

    /// Everything recorded since `record`, up to now.
    func cut() -> [Float] {
        feed.stop()
    }

    /// Runs on the audio thread: hands each buffer to the recording, if there is one, and says how loud it was and how
    /// long the recording is now.
    nonisolated private static func tap(_ feed: Feed, level: @escaping @Sendable (Float, Double) -> Void) -> AVAudioNodeTapBlock {
        return { buffer, time in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0 ..< frames { sum += samples[index] * samples[index] }
            let loudness = (sum / Float(frames)).squareRoot()
            if let recorded = feed.yield(buffer, at: time, loudness: loudness) { level(loudness, recorded) }
        }
    }
}

nonisolated private struct Unrecordable: LocalizedError {
    let format: String
    var errorDescription: String? { "iikb can't record from this microphone (\(format))." }
}

/// Where the microphone's buffers go: into the `Recording` while one is being made, nowhere while the microphone is
/// only being kept on. The audio thread reads it and the main thread swaps it, under a lock.
nonisolated private final class Feed: @unchecked Sendable {
    private let lock = NSLock()
    private var recorder: AVAudioConverter?
    private var recording: [Float] = []
    private var file: Recording.File?
    private var loudness: [Float] = []
    private var stopped: UInt64?
    private var ended: CheckedContinuation<[Float], Never>?

    func start(file url: URL) {
        lock.withLock {
            recorder = nil
            recording = []
            file = Recording.File(url)
            loudness = []
        }
    }

    /// Everything heard since `start`.
    func stop() -> [Float] {
        let (recording, ended) = lock.withLock { take() }
        ended?.resume(returning: recording)
        return recording
    }

    /// Everything heard since `start`, through the moment of the stop by the clock the microphone stamps its sound with,
    /// and on until you're quiet, since a stop tapped as you finish speaking lands on your last word. A room that never
    /// gets quiet, or a microphone that stops sending, ends it a second after the stop.
    @MainActor func stopOnceQuiet() async -> [Float] {
        guard lock.withLock({ file != nil }) else { return stop() }
        let stopped = mach_absolute_time()
        let loud = Task {
            guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            _ = self.stop()
        }
        defer { loud.cancel() }
        return await withCheckedContinuation { ended in
            lock.withLock { (self.stopped, self.ended) = (stopped, ended) }
        }
    }

    /// How many seconds the recording holds with the buffer, nil when there's no recording to take it.
    func yield(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime, loudness level: Float) -> Double? {
        let (took, done) = lock.withLock { () -> (Double?, ([Float], CheckedContinuation<[Float], Never>?)?) in
            guard file != nil else { return (nil, nil) }
            if recorder?.inputFormat != buffer.format { recorder = AVAudioConverter(from: buffer.format, to: Recording.format) }
            if let recorder, let converted = Self.convert(buffer, with: recorder), let channel = converted.floatChannelData?[0] {
                let samples = UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))
                recording.append(contentsOf: samples)
                file?.append(samples)
            }
            loudness.append(level)
            let recorded = Double(recording.count) / Recording.format.sampleRate
            let length = AVAudioTime.hostTime(forSeconds: Double(buffer.frameLength) / buffer.format.sampleRate)
            guard let stopped, !time.isHostTimeValid || time.hostTime + length >= stopped && isQuiet(level) else { return (recorded, nil) }
            return (recorded, take())
        }
        if let (recording, ended) = done { ended?.resume(returning: recording) }
        return took
    }

    private func take() -> ([Float], CheckedContinuation<[Float], Never>?) {
        file?.close()
        defer {
            file = nil
            recorder = nil
            recording = []
            loudness = []
            stopped = nil
            ended = nil
        }
        return (recording, ended)
    }

    /// Nearer the room than your voice, as this recording's quietest tenth and loudest twentieth of the sound have them.
    private func isQuiet(_ level: Float) -> Bool {
        let sorted = loudness.sorted()
        return level * level <= sorted[sorted.count / 10] * sorted[sorted.count * 19 / 20]
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
