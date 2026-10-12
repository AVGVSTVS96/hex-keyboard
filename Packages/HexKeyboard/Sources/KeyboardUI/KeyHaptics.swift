import CoreHaptics
import Foundation

/// Plays the system keyboard's haptics on an engine the keyboard owns.
///
/// UIKit's feedback generators share one engine per process that suspends itself when a host goes to the background
/// and only wakes on that host's next foreground notification, so a keyboard that hops between hosts runs its own.
final class KeyHaptics {
    /// Apple's keyboard patterns are Core Haptics library entries (`CHHapticPatternLibraryKeyKeyboard…`) of one
    /// transient each, plus a click sound. These are their haptic values, exported on iOS 27 (iPhone 16 Pro Max).
    enum Kind: CaseIterable {
        case input, separator, deletion, deletionRepeat, deletionRapid, other

        var intensity: Float {
            switch self {
            case .input: 0.51
            case .separator: 0.43
            case .deletion: 0.45
            case .deletionRepeat: 0.35
            case .deletionRapid: 0.4
            case .other: 0.49
            }
        }

        var sharpness: Float {
            switch self {
            case .input: 0.31
            case .separator: 0.64
            case .deletion, .deletionRepeat, .deletionRapid: 0.313
            case .other: 0.229
            }
        }

        var pattern: CHHapticPattern? {
            try? CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ], relativeTime: 0),
            ], parameters: [])
        }
    }

    private var engine: CHHapticEngine?
    private var players: [Kind: CHHapticPatternPlayer] = [:]
    private var applePlayers: [Kind: CHHapticPatternPlayer] = [:]
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

    func play(_ kind: Kind, apple: Bool = false) {
        start()
        try? (apple ? applePlayers : players)[kind]?.start(atTime: CHHapticTimeImmediate)
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
                self.applePlayers = Self.applePlayers(on: engine)
                self.start()
            }
        }
        players = Self.players(on: engine)
        applePlayers = Self.applePlayers(on: engine)
        return engine
    }

    private static func applePlayers(on engine: CHHapticEngine) -> [Kind: CHHapticPatternPlayer] {
        let names: [Kind: String] = [.input: "InputText", .separator: "InputSeparator", .deletion: "Deletion", .deletionRepeat: "DeletionRepeat", .deletionRapid: "DeletionRapid", .other: "Other"]
        let selector = NSSelectorFromString("patternForKey:error:")
        var players: [Kind: CHHapticPatternPlayer] = [:]
        for (kind, name) in names {
            guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CHHapticPatternLibraryKeyKeyboard\(name)") else { continue }
            let key = symbol.assumingMemoryBound(to: NSString.self).pointee
            let pattern = (CHHapticPattern.self as AnyObject).perform(selector, with: key, with: nil)?.takeUnretainedValue() as? CHHapticPattern
            if let pattern, let player = try? engine.makePlayer(with: pattern) { players[kind] = player } else { TouchTrace.shared.mark("haptics no apple \(name)") }
        }
        return players
    }

    private static func players(on engine: CHHapticEngine) -> [Kind: CHHapticPatternPlayer] {
        var players: [Kind: CHHapticPatternPlayer] = [:]
        for kind in Kind.allCases {
            if let pattern = kind.pattern, let player = try? engine.makePlayer(with: pattern) { players[kind] = player }
        }
        return players
    }
}
