import UIKit

struct KeyboardTheme {
    let key: UIColor
    let keyPressed: UIColor
    let label: UIColor
    let secondaryLabel: UIColor
    let prominent: UIColor
    let prominentLabel: UIColor
    let selection: UIColor
    let selectionLabel: UIColor
    let shadow: UIColor

    static func current(for traits: UITraitCollection, appearance: UIKeyboardAppearance?) -> KeyboardTheme {
        appearance == .dark || traits.userInterfaceStyle == .dark ? dark : light
    }

    private static var selectsInBlue: Bool { !isIOS27 }
    static var dimsKeyUnderAccents: Bool { isIOS27 }

    private static var isIOS27: Bool {
        if #available(iOS 27, *) { true } else { false }
    }

    static let light = KeyboardTheme(
        key: .white,
        keyPressed: UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1),
        label: .black,
        secondaryLabel: UIColor(white: 0, alpha: 0.32),
        prominent: .systemBlue,
        prominentLabel: .white,
        selection: selectsInBlue ? .systemBlue : UIColor(red: 226 / 255, green: 228 / 255, blue: 232 / 255, alpha: 1),
        selectionLabel: selectsInBlue ? .white : .black,
        shadow: UIColor(white: 0, alpha: 0.18)
    )

    static let dark = KeyboardTheme(
        key: UIColor(white: 61 / 255, alpha: 1),
        keyPressed: UIColor(white: 0.42, alpha: 1),
        label: .white,
        secondaryLabel: UIColor(white: 1, alpha: 0.4),
        prominent: .systemBlue,
        prominentLabel: .white,
        selection: selectsInBlue ? .systemBlue : UIColor(white: 0.36, alpha: 1),
        selectionLabel: .white,
        shadow: UIColor(white: 0, alpha: 0.5)
    )
}
