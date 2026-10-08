import UIKit
import KeyboardUI

enum Playground: String {
    case system, hex

    private static var defaults: UserDefaults { .standard }

    static var current: Playground? { defaults.string(forKey: "HexPlayground").flatMap(Playground.init) }
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

final class PlaygroundTextView: UITextView {
    private lazy var keyboard: UIInputViewController? = Playground.current == .hex ? HexKeyboardViewController() : nil

    override var inputViewController: UIInputViewController? { keyboard }
}
