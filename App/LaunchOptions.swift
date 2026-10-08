import UIKit

enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    private static func integer(_ key: String) -> Int? {
        defaults.string(forKey: key).flatMap { Int($0) }
    }

    static var focus: Bool { defaults.bool(forKey: "HexFocus") }
    static var landscape: Bool { defaults.string(forKey: "HexOrientation") == "landscape" }

    static func configure(_ field: UITextView) {
        if let value = integer("HexKeyboardType").flatMap(UIKeyboardType.init) { field.keyboardType = value }
        if let value = integer("HexReturnKey").flatMap(UIReturnKeyType.init) { field.returnKeyType = value }
        if let text = defaults.string(forKey: "HexText") { field.text = text }
    }
}
