import Foundation

/// Links into Hex's app.
public enum HexLink {
    /// Opens Settings › Apps › Hex, where Full Access (under Keyboards) and Paste from Other Apps are.
    public static let settings = URL(string: "hexkeyboard://settings")!
    /// Opens Hex's app on its keyboard settings.
    public static let keyboard = URL(string: "hexkeyboard://keyboard")!
}
