import AVFoundation
import KeyboardUI
import Observation
import UIKit

extension PickedMicrophone {
    /// A Bluetooth device's microphone has another UID than its speaker's, so it's known by the name they share.
    func isSame(as other: PickedMicrophone) -> Bool {
        uid == other.uid || kind == .bluetooth && other.kind == .bluetooth && name == other.name
    }

    /// iOS names the iPhone's own "iPhone Microphone", though it's several.
    @MainActor var title: String { kind == .iPhone ? UIDevice.current.model : name }

    func matches(_ port: AVAudioSessionPortDescription) -> Bool {
        isSame(as: PickedMicrophone(port))
    }

    init(_ port: AVAudioSessionPortDescription) {
        self.init(uid: port.uid, name: port.portName, kind: Self.kind(of: port))
    }

    static func kind(of port: AVAudioSessionPortDescription) -> Kind {
        switch port.portType {
        case .builtInMic: .iPhone
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE: .bluetooth
        default: .other
        }
    }
}

/// The microphones to pick from, as connected now: the iPhone's, wired and USB ones the session lists, and Bluetooth
/// devices the iPhone is sending sound to. The session lists microphones only in a recording category, so reading sets
/// the microphone's, which changes nothing until it's active; it lists a Bluetooth microphone only while it allows one,
/// which would put speakers on a call, so reading never allows one. The picked one is always there, connected or not.
@Observable @MainActor final class MicrophoneChoices {
    static let shared = MicrophoneChoices()

    private(set) var connected: [PickedMicrophone] = []
    private(set) var picked = SettingsStore.microphone

    private init() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MicrophoneChoices.shared.reload() }
        }
        reload()
    }

    /// Everything to show: the connected, then the picked one if it's away.
    var all: [PickedMicrophone] {
        connected + [picked].compactMap { $0 }.filter(isAway)
    }

    func reload() {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord { try? session.setCategory(.playAndRecord, options: Microphone.options) }
        let ports = (session.availableInputs ?? []) + session.currentRoute.inputs + session.currentRoute.outputs.filter { PickedMicrophone.kind(of: $0) == .bluetooth }
        connected = ports.map(PickedMicrophone.init)
            .reduce(into: []) { found, microphone in if !found.contains(where: microphone.isSame) { found.append(microphone) } }
            .sorted { ($0.kind == .iPhone ? 0 : 1, $0.name) < ($1.kind == .iPhone ? 0 : 1, $1.name) }
        picked = SettingsStore.microphone
    }

    func pick(_ microphone: PickedMicrophone?) {
        SettingsStore.microphone = microphone
        picked = microphone
        Listener.shared.microphoneChanged()
    }

    func isPicked(_ microphone: PickedMicrophone) -> Bool {
        picked?.isSame(as: microphone) ?? false
    }

    func isAway(_ microphone: PickedMicrophone) -> Bool {
        !connected.contains(where: microphone.isSame)
    }
}
