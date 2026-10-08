import UIKit

enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    static var focus: Bool { defaults.bool(forKey: "HexFocus") }
    static var landscape: Bool { defaults.string(forKey: "HexOrientation") == "landscape" }

    static func configure(_ field: UITextView) {
        if let type = defaults.object(forKey: "HexKeyboardType") as? Int, let value = UIKeyboardType(rawValue: type) {
            field.keyboardType = value
        }
        if let type = defaults.object(forKey: "HexReturnKey") as? Int, let value = UIReturnKeyType(rawValue: type) {
            field.returnKeyType = value
        }
        if let text = defaults.string(forKey: "HexText") { field.text = text }
    }
}
