import AVFoundation
import KeyboardUI
import UIKit

/// Voice typing, in two steps that never wait on each other: the `Microphone` records a dictation the moment you ask,
/// and once you stop, the `VoiceModel` writes its finished `Recording` down, whatever state it was in when you started.
/// Dictations still being written are typed in the order you said them. After you dictate the microphone stays on for
/// as long as Keep Mic On says, so the keyboard can start the next dictation (`start`) without opening the app, which
/// is the only place iOS lets a recording begin.
@MainActor final class Listener {
    static let shared = Listener()

    private let microphone = Microphone()
    private var micOff: Task<Void, Never>?
    private var tokens: [Int32] = []
    private var recording: Take?
    /// The last words of `recording`, still coming in after you stopped.
    private var tail: Task<[Float], Never>?
    /// Recorded and not yet written, oldest first.
    private var writing: [Take] = []
    /// The last of `writing`, which each dictation waits for before it's written, so they're typed in order.
    private var written: Task<Void, Never>?
    /// You held the keyboard's mic: it goes off once what you said is written down, keeping Hex running till then.
    private var micOffOnceWritten = false
    /// Why the last dictation couldn't be made or written down, for the app's screen.
    private(set) var failure: (title: String, reason: String)?
    var onChange: (() -> Void)?
    var onLevel: ((Float) -> Void)?

    var isMicOn: Bool { microphone.isOn }
    var isListening: Bool { recording != nil && tail == nil }
    var isWriting: Bool { !writing.isEmpty }

    private init() {
        microphone.onLost = { Task { await Listener.shared.lose() } }
        microphone.onLevel = { level, recorded in
            Listener.shared.recording?.recorded = recorded
            Listener.shared.onLevel?(level)
        }
        VoiceModel.shared.onState = {
            guard Listener.shared.isWriting, VoiceModel.shared.waiting != Dictation.status.waiting else { return }
            Listener.shared.publish()
        }
        tokens = [
            Dictation.observe(.finish) { keyboard in Task { await Listener.shared.finish(in: keyboard) } },
            Dictation.observe(.start) {
                guard Listener.shared.microphone.isOn else { return }
                Task { await Listener.shared.start() }
            },
            Dictation.observe(.stop) { keyboard in Task { await Listener.shared.turnMicOff(in: keyboard) } },
        ]
    }

    /// Returns once the microphone is recording, the one step iOS allows only in the foreground.
    func start() async {
        _ = await tail?.value
        guard recording == nil else { return }
        micOff?.cancel()
        micOffOnceWritten = false
        failure = nil
        let take = Take()
        recording = take
        publish()
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw Failure.microphone }
            guard recording === take else { return }
            try microphone.open()
            VoiceModel.shared.micIsOn = true
            take.mic = microphone.input
            try microphone.record(to: Transcripts.shared.recording(of: take.id))
        } catch {
            recording = nil
            closeMic()
            fail("Couldn’t listen", (error as? Failure)?.description ?? error.localizedDescription)
        }
    }

    /// Has the dictation written down and typed in `keyboard`, the keyboard you stopped it in (nil from the app's
    /// screen, for the next keyboard to show), and returns once your last word is in.
    func finish(in keyboard: UInt64? = nil) async {
        if let take = recording, tail == nil {
            take.keyboard = keyboard
            let tail = Task {
                let sound = await microphone.stop()
                (recording, self.tail) = (nil, nil)
                return sound
            }
            self.tail = tail
            write(take, tail)
        }
        _ = await tail?.value
    }

    /// Types nothing: the dictation being recorded, and any still being written, are kept in Transcripts only.
    func cancel() {
        for take in writing { take.typed = false }
        guard let take = recording, tail == nil else { return publish() }
        let sound = microphone.cut()
        recording = nil
        take.typed = false
        write(take, Task { sound })
    }

    private func write(_ take: Take, _ sound: Task<[Float], Never>) {
        take.stopped = .now
        writing.append(take)
        publish()
        let before = written
        written = Task {
            await before?.value
            await deliver(take, await sound.value)
        }
    }

    /// Writes a dictation down, keeps it in Transcripts, and leaves it for the keyboard to type unless you canceled it.
    /// One that can't be written now is written the next time the app opens, since its recording is still on disk.
    private func deliver(_ take: Take, _ samples: [Float]) async {
        let background = UIApplication.shared.beginBackgroundTask()
        defer { UIApplication.shared.endBackgroundTask(background) }
        let seconds = Double(samples.count) / Recording.format.sampleRate
        do {
            let written = try await VoiceModel.shared.write(samples)
            writing.removeAll { $0 === take }
            Transcripts.shared.add(written.text, heard: written.heard, id: take.id, at: take.started, seconds: seconds, typed: take.typed, model: written.model, mic: take.mic)
            if take.typed, written.text.isEmpty {
                Dictation.leave(.notice("\(written.model) heard nothing: the recording is in iikb › Transcripts"))
            } else if take.typed {
                Dictation.leave(.heard(written.text, keyboard: take.keyboard))
            }
            publish()
            HostApp.log.notice("\(written.model, privacy: .public) wrote \(seconds, format: .fixed(precision: 1))s down \(Date.now.timeIntervalSince(take.stopped), format: .fixed(precision: 2))s after the stop")
        } catch {
            writing.removeAll { $0 === take }
            fail("Couldn’t write it down", "\(error.localizedDescription) The recording is kept, and written down when iikb next opens.")
        }
        keepMicOn()
    }

    /// Starts Keep Mic On's countdown over, or turns the microphone off now when it's Off, once nothing is being
    /// recorded or written. Until then the microphone stays on: that keeps Hex running in the background to write,
    /// and its lock tells the keyboard Hex is still there.
    func keepMicOn() {
        micOff?.cancel()
        guard microphone.isOn, recording == nil, writing.isEmpty else { return }
        let seconds = SettingsStore.keepMicOn
        guard seconds > 0, !micOffOnceWritten else { return closeMic() }
        guard seconds != Dictation.micForever else { return }
        micOff = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, recording == nil, writing.isEmpty else { return }
            closeMic()
        }
    }

    /// You held the keyboard's mic: keep what was heard, typed in `keyboard`, and turn the microphone off once it's
    /// written down, so the next dictation opens the app and starts it afresh.
    func turnMicOff(in keyboard: UInt64?) async {
        guard microphone.isOn else { return }
        await finish(in: keyboard)
        micOffOnceWritten = true
        keepMicOn()
    }

    /// Another app took the microphone (a call), or the route changed under the engine: keep what was heard, and turn
    /// the microphone off now, since it hears nothing more.
    private func lose() async {
        guard microphone.isOn else { return }
        await finish()
        closeMic()
    }

    private func closeMic() {
        micOff?.cancel()
        micOff = nil
        micOffOnceWritten = false
        microphone.close()
        VoiceModel.shared.micIsOn = false
    }

    private func fail(_ title: String, _ reason: String) {
        failure = (title, reason)
        Dictation.leave(.notice(reason))
        publish()
    }

    private func publish() {
        var status = Dictation.Status()
        status.listening = isListening
        status.writing = writing.map(\.recorded)
        status.waiting = VoiceModel.shared.waiting
        Dictation.publish(status)
        onChange?()
    }

    private enum Failure: Error, CustomStringConvertible {
        case microphone

        var description: String {
            switch self {
            case .microphone: "iikb needs the microphone. Turn it on in Settings › Apps › iikb."
            }
        }
    }
}

/// One dictation, from your tap to its transcript.
private final class Take {
    let id = UUID()
    let started = Date.now
    var stopped = Date.now
    var mic: String?
    /// Seconds recorded, as the microphone counts them.
    var recorded: Double = 0
    var typed = true
    /// The keyboard you stopped it in, which types it.
    var keyboard: UInt64?
}
