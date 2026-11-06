import AVFoundation
import KeyboardStore

/// How the iPhone's own microphones are heard, compared dictation by dictation while Settings › Microphone's Compare
/// Microphones is on (`-compareMicrophones NO` turns it off for a launch): each dictation draws one at random and its
/// transcript keeps which, so the edits made to what each typed score them on the same days, in the same rooms
/// (`scripts/voicehealth.py`). Both hear on more than one microphone, since on one the folded iPhone Duo upright lost
/// seconds of speech at a time. Only on an iPhone that offers a cardioid, with no microphone picked, while its own
/// microphone hears and nothing plays on its speaker, which only voice processing keeps out of what it hears.
nonisolated enum Capture: String, CaseIterable {
    /// Apple's voice processing, as a call: the microphones beamed toward your voice, the speaker's sound taken away and
    /// the room's noise held down, a quiet room to near digital silence.
    case voiceProcessing
    /// A cardioid, which iOS forms from more than one of the microphones, on the front one, toward the face looking at
    /// the screen, in `.measurement` mode, which leaves its signal as heard.
    case cardioid

    var title: String {
        switch self {
        case .voiceProcessing: "Voice Processing"
        case .cardioid: "Front Cardioid"
        }
    }

    static var comparing: Bool {
        UserDefaults.standard.object(forKey: "compareMicrophones") == nil || UserDefaults.standard.bool(forKey: "compareMicrophones")
    }

    /// One of the two at random, nil when this iPhone offers no cardioid.
    static func draw(_ session: AVAudioSession) -> Capture? {
        offersCardioid(session) ? allCases.randomElement() : nil
    }

    static func offersCardioid(_ session: AVAudioSession) -> Bool {
        cardioid(session) != nil
    }

    /// Whether the iPhone's own microphone hears and its sound plays on the iPhone: no picked microphone elsewhere, and
    /// no Bluetooth speaker or AirPlay, whose sound voice processing would take to the iPhone.
    @MainActor static func onIPhone(_ session: AVAudioSession) -> Bool {
        let route = session.currentRoute
        return route.outputs.allSatisfy { [.builtInSpeaker, .builtInReceiver, .headphones].contains($0.portType) }
            && (SettingsStore.microphone == nil || route.inputs.allSatisfy { $0.portType == .builtInMic })
    }

    /// Whether a dictation may be heard either way now: the setting is on, no microphone is picked, the iPhone's own
    /// microphone hears, its sound plays on the iPhone (voice processing hands a Bluetooth speaker's or AirPlay's over to
    /// it), and nothing plays on its speaker.
    @MainActor static func mayCompare(_ session: AVAudioSession) -> Bool {
        let route = session.currentRoute
        return comparing && SettingsStore.microphone == nil && route.inputs.allSatisfy { $0.portType == .builtInMic }
            && route.outputs.allSatisfy { [.builtInSpeaker, .builtInReceiver, .headphones].contains($0.portType) } && !speakerPlays(session)
    }

    /// Another app's sound plays on the iPhone's own speaker, which its microphones hear unless voice processing takes
    /// it away.
    static func speakerPlays(_ session: AVAudioSession) -> Bool {
        session.isOtherAudioPlaying && session.currentRoute.outputs.contains { [.builtInSpeaker, .builtInReceiver].contains($0.portType) }
    }

    /// Points the iPhone's microphone this way: a cardioid on its front microphone, or iOS's own pick of microphone and
    /// pattern, which voice processing then hears through.
    func point(_ session: AVAudioSession) throws {
        try session.setMode(self == .voiceProcessing ? .default : .measurement)
        guard let port = Self.builtIn(session), port.dataSources?.isEmpty == false else { return }
        let source = self == .cardioid ? Self.cardioid(session) : nil
        for other in port.dataSources ?? [] where other != source && other.preferredPolarPattern != nil {
            try? other.setPreferredPolarPattern(nil)
        }
        try source?.setPreferredPolarPattern(.cardioid)
        try port.setPreferredDataSource(source)
    }

    /// How the engine hears: the way compared, if it is, what the iPhone's microphone is pointed at (`point`), and
    /// whether voice processing is on.
    struct Way: Equatable {
        var capture: Capture?
        var pointed: Capture
        var processing: Bool

        /// Voice processing on the iPhone, compared when it may be; without it elsewhere. While voice processing is
        /// skipped (`Microphone.skipsVoiceProcessing`) it hears through the cardioid where there is one, else iOS's
        /// microphone, uncompared, unless the iPhone's speaker plays, which only voice processing keeps out.
        static func choose(onIPhone: Bool, skipping: Bool, speakerPlays: Bool, mayCompare: Bool, offersCardioid: Bool, arm: Capture?) -> Way {
            guard onIPhone else { return Way(capture: nil, pointed: .voiceProcessing, processing: false) }
            if skipping, !speakerPlays { return Way(capture: nil, pointed: offersCardioid ? .cardioid : .voiceProcessing, processing: false) }
            let capture = !skipping && mayCompare ? arm : nil
            return Way(capture: capture, pointed: capture ?? .voiceProcessing, processing: capture != .cardioid)
        }
    }

    private static func builtIn(_ session: AVAudioSession) -> AVAudioSessionPortDescription? {
        session.availableInputs?.first { $0.portType == .builtInMic }
    }

    private static func cardioid(_ session: AVAudioSession) -> AVAudioSessionDataSourceDescription? {
        let sources = builtIn(session)?.dataSources?.filter { $0.supportedPolarPatterns?.contains(.cardioid) == true } ?? []
        return sources.first { $0.orientation == .front } ?? sources.first
    }
}
