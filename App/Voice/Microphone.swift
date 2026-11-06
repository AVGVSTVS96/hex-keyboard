import AVFoundation
import KeyboardStore
import Observation
import UIKit

/// The microphone, recording a dictation as a `Recording`: 16 kHz, kept in memory and written to its file as
/// it's heard. It knows nothing of the models that write recordings down, so nothing about them can hold up a
/// recording. While it's on it holds the App Group's mic lock, which tells the keyboard the app is there to dictate.
@Observable @MainActor final class Microphone {
    private var engine = AVAudioEngine()
    private let feed = Feed()
    private var lock: Int32?
    /// The way the engine hears between dictations when it may compare them (`Capture`), drawn as the microphone opens
    /// and by `next`; nil where it can't.
    private var planned: Capture?
    /// The way the recording being made is heard, nil when it isn't compared or a restart changed the way mid-recording.
    private var recordingAs: Capture?
    /// Another app took the microphone (a call), or the engine couldn't be started again after a change under it.
    var onLost: () -> Void = {}
    /// A speaker or headphones connected while voice processing holds the sound on the iPhone, which can't hand it over
    /// while the microphone is on.
    var onSpeaker: () -> Void = {}
    var onLevel: (_ loudness: Float, _ recorded: Double) -> Void = { _, _ in }

    init() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.onLost() }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            Task { @MainActor in
                guard let self, self.isOn, let reason else { return }
                if let picked = SettingsStore.microphone, picked.kind != .iPhone, reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
                    self.restart() // restart: a picked microphone came or went
                }
                if reason == .newDeviceAvailable, self.engine.inputNode.isVoiceProcessingEnabled { self.onSpeaker() }
            }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isOn, !self.engine.isRunning else { return }
                self.restart() // restart: iOS stopped it
            }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restart(rebuilding: true) } // restart: iOS stopped it
        }
    }

    var isOn: Bool { lock != nil }

    /// The input recording now, as iOS names it.
    var input: String? { AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName }

    /// Whether it hears through Apple's voice processing now, all of the iPhone's microphones together as a call does.
    var voiceProcessing: Bool { engine.inputNode.isVoiceProcessingEnabled }

    /// The way the engine hears now, as `begin` set it up.
    private var way: Capture.Way?

    /// Voice processing passed a dictation's sound as near digital silence while the iPhone's microphone heard speech
    /// (Bassim's Duo, Nov 5: the hardware heard -38 to -53 dB and voice processing passed -78 dB, five openings in a
    /// row, with nothing logged), so it hears without it, on the iPhone's own microphone, until a dictation heard so has
    /// sound. iOS says nothing of it as it happens, and a quiet room comes out of voice processing about as low.
    var skipsVoiceProcessing = false {
        didSet {
            guard skipsVoiceProcessing != oldValue else { return }
            if skipsVoiceProcessing {
                HostApp.log.notice("voice processing gave no sound: hearing without it until a dictation has sound (its input muted \(self.engine.inputNode.isVoiceProcessingInputMuted, privacy: .public), the app's \(AVAudioApplication.shared.isInputMuted, privacy: .public))")
            } else {
                HostApp.log.notice("a dictation had sound: hearing through voice processing again")
                settle()
            }
        }
    }

    /// By default it hears from the iPhone and never from a Bluetooth microphone, which would put a speaker or AirPods on
    /// a call (`.allowBluetoothHFP`), and music would drop to call quality or stop. A microphone picked in Settings is
    /// asked for by `PickedMicrophone.matches` and heard from instead: a Bluetooth one is the only pick that allows
    /// HFP, and only while it's connected; away, the iPhone's hears and the category goes back, and a device coming or
    /// going (`routeChangeNotification`) starts the engine again onto the pick, or, when voice processing still holds
    /// the sound after that, hands it over as without a pick. Mixes with whatever else
    /// is playing, so music keeps going while you talk, wherever it plays. While any app records, iOS mutes every
    /// app's haptics, the keyboard's included, unless the recording session allows them. While the iPhone plays the
    /// sound itself and its own microphones hear, it hears through Apple's voice processing, which picks up your voice
    /// from all of them as a call does: from one microphone, the folded iPhone Duo in portrait lost his voice for
    /// seconds at a time, 12% of the time, leaving a low rumble that Parakeet writes as nothing. Voice processing takes
    /// the sound from a Bluetooth speaker or AirPlay to the iPhone, and music apps pause, so while one plays it hears
    /// from one; a picked outside microphone hears without it. Voice processing's I/O unit renders its output every
    /// cycle, the reference its echo canceling takes away, and with nothing connected there every render failed
    /// (`render err: -1`, 43 a second), so while it's on the output plays the main mixer's silence.
    func open() throws {
        guard lock == nil else { return }
        planned = nil
        do {
            try beginOnAnyEngine()
        } catch {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        lock = Dictation.lockMic() ?? -1
        Dictation.send(.changed)
    }

    /// An engine left from before a media services reset can't start (-50), and a suspended iikb may not hear of the
    /// reset, so a failed start tries once more on a new engine.
    private func beginOnAnyEngine() throws {
        do {
            try begin()
        } catch {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
            engine = AVAudioEngine()
            try begin()
        }
    }

    static let options: AVAudioSession.CategoryOptions = [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker]

    private func begin() throws {
        let session = AVAudioSession.sharedInstance()
        let picked = SettingsStore.microphone
        try session.setCategory(.playAndRecord, options: picked?.kind == .bluetooth ? Self.options.union(.allowBluetoothHFP) : Self.options)
        try session.setActive(true)
        var input = picked.flatMap { picked in session.availableInputs?.first(where: picked.matches) }
        if picked?.kind == .bluetooth, input == nil { try session.setCategory(.playAndRecord, options: Self.options) }
        if picked != nil, input == nil { input = session.availableInputs?.first { $0.portType == .builtInMic } }
        try? session.setPreferredInput(input)
        let node = engine.inputNode
        let recording = feed.isRecording
        if !recording, planned == nil { planned = Capture.draw(session) }
        var way = chosen(session, keeping: recording)
        do {
            try way.pointed.point(session)
        } catch {
            HostApp.log.error("couldn't point at \(way.pointed.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            try? Capture.voiceProcessing.point(session)
            way = Capture.Way(capture: nil, pointed: .voiceProcessing, processing: way.processing || way.capture == .cardioid)
        }
        if node.isVoiceProcessingEnabled != way.processing, (try? node.setVoiceProcessingEnabled(way.processing)) != nil, way.processing {
            node.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        }
        if node.isVoiceProcessingEnabled != way.processing { way = Capture.Way(capture: nil, pointed: way.pointed, processing: node.isVoiceProcessingEnabled) }
        if recording, way.capture != recordingAs { recordingAs = nil }
        self.way = way
        if node.isVoiceProcessingEnabled {
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        } else {
            engine.disconnectNodeInput(engine.outputNode)
        }
        feed.hear(voiceProcessing: node.isVoiceProcessingEnabled)
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
        let route = session.currentRoute.inputs.first
        let source = route?.selectedDataSource
        HostApp.log.notice("hearing \(way.capture?.rawValue ?? "uncompared", privacy: .public), pointed at \(way.pointed.rawValue, privacy: .public), voice processing \(way.processing ? "on" : "off", privacy: .public), from \(route?.portType.rawValue ?? "nothing", privacy: .public) \(source?.dataSourceName ?? "", privacy: .public) \(source?.selectedPolarPattern?.rawValue ?? "", privacy: .public), other audio \(session.isOtherAudioPlaying ? "playing" : "silent", privacy: .public)")
    }

    /// iOS stops the engine when the hardware's format or route changes under it, and every audio object is dead after
    /// the media services reset, the microphone on or off, and another microphone may be picked: starts again into the
    /// same recording, which converts whatever format comes next.
    func restart(rebuilding: Bool = false) {
        if rebuilding {
            engine = AVAudioEngine()
        } else {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        guard isOn else { return }
        do {
            try beginOnAnyEngine()
        } catch {
            onLost()
        }
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

    /// Records from the next sound on into `url`, back in voice processing first when the iPhone's speaker started
    /// playing since the engine started.
    func record(to url: URL) {
        settle()
        recordingAs = way?.capture
        feed.start(file: url)
        Dictation.publish(level: 0, recorded: 0)
    }

    /// Everything recorded since `record`, through your last word (`Feed.stopOnceQuiet`), and the way it was heard.
    func stop() async -> (sound: [Float], heardAs: Capture?) {
        let sound = engine.isRunning ? await feed.stopOnceQuiet() : feed.stop()
        return (sound, heardAs())
    }

    /// Everything recorded since `record`, up to now, and the way it was heard.
    func cut() -> (sound: [Float], heardAs: Capture?) {
        (feed.stop(), heardAs())
    }

    /// The way the recording just stopped was heard, nil when the iPhone's speaker played into one voice processing
    /// didn't hear.
    private func heardAs() -> Capture? {
        defer { recordingAs = nil }
        return recordingAs != .voiceProcessing && Capture.speakerPlays(.sharedInstance()) ? nil : recordingAs
    }

    /// Draws the way the next dictation is heard, and starts the engine again in it when that's another, for a
    /// microphone that stays on between dictations; the restart is done before the next dictation can start.
    func next() {
        guard isOn, !feed.isRecording else { return }
        planned = Capture.draw(.sharedInstance())
        settle()
    }

    /// Starts the engine again, while nothing's recorded and iikb is in front, when it hears another way than it would
    /// start in now. In the background it keeps hearing as it does until the next opening.
    private func settle() {
        guard isOn, !feed.isRecording, Self.inFront, chosen(.sharedInstance(), keeping: false) != way else { return }
        restart() // restart: in front
    }

    /// Whether iikb is in front, the only time it stops and starts the microphone by choice: from the background iOS
    /// refuses the new start, and the microphone went off after every dictation that switched the way it hears
    /// (Bassim's Duo, Nov 6: OSStatus 560557684 pointing it, then the engine's start failing twice).
    static var inFront: Bool { UIApplication.shared.applicationState == .active }

    /// The way the engine would start in now: the recording's own while one runs, else the next one drawn.
    private func chosen(_ session: AVAudioSession, keeping recording: Bool) -> Capture.Way {
        Capture.Way.choose(
            onIPhone: Capture.onIPhone(session), skipping: skipsVoiceProcessing, speakerPlays: Capture.speakerPlays(session),
            mayCompare: Capture.mayCompare(session), offersCardioid: Capture.offersCardioid(session), arm: recording ? way?.capture : planned)
    }

    /// Whether the iPhone's own microphone is the input now.
    var hearsIPhone: Bool { AVAudioSession.sharedInstance().currentRoute.inputs.allSatisfy { $0.portType == .builtInMic } }

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
    /// The format of the buffers coming in, to know when they change.
    private var heard: AVAudioFormat?
    /// Channel 0 of a multichannel buffer, the one signal the level meter and the recording share.
    private var mono: AVAudioPCMBuffer?
    private var voiceProcessing = false
    /// What's been heard since `start`, nil while nothing is being recorded; kept even when its file can't be written.
    private var recording: [Float]?
    private var file: Recording.File?
    private var loudness: [Float] = []
    private var stopped: UInt64?
    private var ended: CheckedContinuation<[Float], Never>?

    var isRecording: Bool { lock.withLock { recording != nil } }

    func hear(voiceProcessing on: Bool) {
        lock.withLock { voiceProcessing = on }
    }

    func start(file url: URL) {
        lock.withLock {
            recorder = nil
            heard = nil
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
        guard lock.withLock({ recording != nil }) else { return stop() }
        let stopped = mach_absolute_time()
        let loud = Task {
            guard (try? await Task.sleep(for: .seconds(1))) != nil else { return } // timer: stop waits for quiet
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
            guard recording != nil else { return (nil, nil) }
            if heard != buffer.format {
                heard = buffer.format
                recorder = nil
                HostApp.log.notice("recording from \(buffer.format.channelCount) channels at \(buffer.format.sampleRate, format: .fixed(precision: 0)) Hz, voice processing \(self.voiceProcessing ? "on" : "off", privacy: .public)")
            }
            let source = channelZero(of: buffer)
            if recorder == nil, let source { recorder = AVAudioConverter(from: source.format, to: Recording.format) }
            if let source, let recorder, let converted = Self.convert(source, with: recorder), let channel = converted.floatChannelData?[0] {
                let samples = UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))
                recording?.append(contentsOf: samples)
                file?.append(samples)
            }
            loudness.append(level)
            let recorded = Double(recording?.count ?? 0) / Recording.format.sampleRate
            let length = AVAudioTime.hostTime(forSeconds: Double(buffer.frameLength) / buffer.format.sampleRate)
            guard let stopped, !time.isHostTimeValid || time.hostTime + length >= stopped && isQuiet(level) else { return (recorded, nil) }
            return (recorded, take())
        }
        if let (recording, ended) = done { ended?.resume(returning: recording) }
        return took
    }

    private func channelZero(of buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        if format.channelCount == 1, !format.isInterleaved { return buffer }
        if mono?.format.sampleRate != format.sampleRate || mono?.frameCapacity ?? 0 < buffer.frameLength {
            mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1).flatMap {
                AVAudioPCMBuffer(pcmFormat: $0, frameCapacity: max(buffer.frameLength, 4096))
            }
        }
        guard let mono, let from = buffer.floatChannelData?[0], let to = mono.floatChannelData?[0] else { return nil }
        let stride = buffer.stride
        for index in 0 ..< Int(buffer.frameLength) { to[index] = from[index * stride] }
        mono.frameLength = buffer.frameLength
        return mono
    }

    private func take() -> ([Float], CheckedContinuation<[Float], Never>?) {
        file?.close()
        defer {
            file = nil
            recorder = nil
            heard = nil
            recording = nil
            loudness = []
            stopped = nil
            ended = nil
        }
        return (recording ?? [], ended)
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
