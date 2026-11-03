import CoreHaptics
import Foundation

/// Plays the system keyboard's haptics on an engine the keyboard owns.
///
/// UIKit's feedback generators share one engine per process that suspends itself when a host goes to the background
/// and only wakes on that host's next foreground notification, so a keyboard that hops between hosts runs its own.
public final class KeyHaptics {
    /// Apple's keyboard patterns are Core Haptics library entries (`CHHapticPatternLibraryKeyKeyboard…`) of one
    /// transient each, plus a click sound. These are their haptic values, exported on iOS 27 (iPhone 16 Pro Max).
    public enum Kind: CaseIterable, Sendable {
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

        func pattern(strength: Float) -> CHHapticPattern? {
            try? CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, intensity * strength)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ], relativeTime: 0),
            ], parameters: [])
        }
    }

    public init() {}

    private var engine: CHHapticEngine?
    private var players: [Kind: CHHapticPatternPlayer] = [:]
    private var running = false
    /// A share of Apple's intensity (`HapticFeedback.strength`).
    public var strength: Float = 1 {
        didSet {
            guard strength != oldValue, let engine else { return }
            players = Self.players(on: engine, strength: strength)
        }
    }

    public func start() {
        if engine == nil { engine = makeEngine() }
        guard let engine, !running else { return }
        running = (try? engine.start()) != nil
    }

    public func stop() {
        engine?.stop()
        running = false
    }

    public func play(_ kind: Kind) {
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
                self.players = Self.players(on: engine, strength: self.strength)
                self.start()
            }
        }
        players = Self.players(on: engine, strength: strength)
        return engine
    }

    private static func players(on engine: CHHapticEngine, strength: Float) -> [Kind: CHHapticPatternPlayer] {
        var players: [Kind: CHHapticPatternPlayer] = [:]
        for kind in Kind.allCases {
            if let pattern = kind.pattern(strength: strength), let player = try? engine.makePlayer(with: pattern) { players[kind] = player }
        }
        return players
    }
}
