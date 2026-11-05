import AVFoundation

/// How the iPhone's own microphones are heard, compared dictation by dictation while Settings › Microphone's Compare
/// Microphones is on (off unless turned on; `-compareMicrophones YES` turns it on for a launch): each dictation draws one at random and its
/// transcript keeps which, so the edits made to what each typed score them on the same days, in the same rooms
/// (`scripts/voicehealth.py`). Only while the iPhone's own microphone hears and nothing plays on its speaker, which
/// only voice processing keeps out of what it hears.
nonisolated enum Capture: String, CaseIterable {
    /// Apple's voice processing, as a call: the microphones beamed toward your voice, the speaker's sound taken away and
    /// the room's noise held down, a quiet room to near digital silence.
    case voiceProcessing
    /// The microphone iOS picks, in `.measurement` mode, which leaves its signal as heard.
    case raw
    /// A cardioid, which iOS forms from more than one of the microphones, on the front one, toward the face looking at
    /// the screen, in `.measurement` mode; only where the iPhone offers one.
    case cardioid

    var title: String {
        switch self {
        case .voiceProcessing: "Voice Processing"
        case .raw: "Raw"
        case .cardioid: "Front Cardioid"
        }
    }

    static var comparing: Bool {
        UserDefaults.standard.bool(forKey: "compareMicrophones")
    }

    /// One of the ways this iPhone offers, at random.
    static func draw(_ session: AVAudioSession) -> Capture {
        allCases.filter { $0 != .cardioid || cardioid(session) != nil }.randomElement() ?? .voiceProcessing
    }

    /// Whether a dictation may be heard any of the ways now: the setting is on, the iPhone's own microphone hears, and
    /// nothing plays on its speaker.
    static func mayCompare(_ session: AVAudioSession) -> Bool {
        let route = session.currentRoute
        return comparing && route.inputs.allSatisfy { $0.portType == .builtInMic }
            && !(session.isOtherAudioPlaying && route.outputs.contains { [.builtInSpeaker, .builtInReceiver].contains($0.portType) })
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

    private static func builtIn(_ session: AVAudioSession) -> AVAudioSessionPortDescription? {
        session.availableInputs?.first { $0.portType == .builtInMic }
    }

    private static func cardioid(_ session: AVAudioSession) -> AVAudioSessionDataSourceDescription? {
        let sources = builtIn(session)?.dataSources?.filter { $0.supportedPolarPatterns?.contains(.cardioid) == true } ?? []
        return sources.first { $0.orientation == .front } ?? sources.first
    }
}
