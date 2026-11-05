import Foundation

/// The one piece of the app's KeyboardStore that `Parakeet.swift` reads. The bench has no App Group, so its Parakeets
/// load from FluidAudio's own folder.
public enum AppGroup {
    public static let library: URL? = nil
}
