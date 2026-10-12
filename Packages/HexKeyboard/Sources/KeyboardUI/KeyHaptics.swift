import CoreHaptics
import Foundation

/// Plays Apple's own keyboard haptics on an engine the keyboard owns.
///
/// The system keyboard plays Core Haptics library patterns (`CHHapticPatternLibraryKeyKeyboard…`), loaded with the
/// private `+[CHHapticPattern patternForKey:error:]` (UIKitCore's `_UIKBFeedbackGenerator`, iOS 26.1). When that
/// isn't there, a light transient stands in. UIKit's feedback generators share one engine per process that suspends
/// itself when a host goes to the background and only wakes on the host's next foreground notification, so a
/// keyboard that hops between hosts runs its own engine instead.
final class KeyHaptics {
    enum Kind: String, CaseIterable {
        case input = "InputText"
        case separator = "InputSeparator"
        case deletion = "Deletion"
        case deletionRepeat = "DeletionRepeat"
        case deletionRapid = "DeletionRapid"
        case other = "Other"
    }

    private var engine: CHHapticEngine?
    private var players: [Kind: CHHapticPatternPlayer] = [:]
    private var running = false

    func start() {
        if engine == nil { engine = makeEngine() }
        guard let engine, !running else { return }
        running = (try? engine.start()) != nil
    }

    func stop() {
        engine?.stop()
        running = false
    }

    func play(_ kind: Kind) {
        start()
        try? players[kind]?.start(atTime: CHHapticTimeImmediate)
    }

    private func makeEngine() -> CHHapticEngine? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = try? CHHapticEngine() else { return nil }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        engine.stoppedHandler = { @Sendable [weak self] reason in
            Task { @MainActor in
                self?.running = false
                TouchTrace.shared.mark("haptics stopped \(reason.rawValue)")
            }
        }
        engine.resetHandler = { @Sendable [weak self] in
            Task { @MainActor in
                guard let self, let engine = self.engine else { return }
                TouchTrace.shared.mark("haptics reset")
                self.running = false
                self.players = Self.players(on: engine)
                self.start()
            }
        }
        players = Self.players(on: engine)
        return engine
    }

    private static func players(on engine: CHHapticEngine) -> [Kind: CHHapticPatternPlayer] {
        var players: [Kind: CHHapticPatternPlayer] = [:]
        for kind in Kind.allCases {
            let system = systemPattern(kind)
            if system == nil { TouchTrace.shared.mark("haptics fallback \(kind.rawValue)") }
            if let pattern = system ?? fallback, let player = try? engine.makePlayer(with: pattern) { players[kind] = player }
        }
        return players
    }

    private static func systemPattern(_ kind: Kind) -> CHHapticPattern? {
        let selector = NSSelectorFromString("patternForKey:error:")
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CHHapticPatternLibraryKeyKeyboard\(kind.rawValue)"),
              CHHapticPattern.responds(to: selector)
        else { return nil }
        let key = symbol.assumingMemoryBound(to: NSString.self).pointee
        return (CHHapticPattern.self as AnyObject).perform(selector, with: key, with: nil)?.takeUnretainedValue() as? CHHapticPattern
    }

    private static let fallback = try? CHHapticPattern(events: [
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
        ], relativeTime: 0),
    ], parameters: [])
}
