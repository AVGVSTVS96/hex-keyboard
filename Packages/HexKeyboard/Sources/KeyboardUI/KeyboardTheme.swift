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
    let candidate: UIColor
    let candidateHighlighted: UIColor
    let candidatePill: UIColor
    let candidateDivider: UIColor

    static func current(for traits: UITraitCollection, appearance: UIKeyboardAppearance?) -> KeyboardTheme {
        appearance == .dark || traits.userInterfaceStyle == .dark ? dark : light
    }

    private static var selectsInBlue: Bool { !isIOS27 }
    static var dimsKeyUnderAccents: Bool { isIOS27 }

    static var isIOS27: Bool {
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
        shadow: UIColor(white: 0, alpha: 0.18),
        candidate: isIOS27 ? .rgb(74, 74, 76) : .rgb(54, 56, 60),
        candidateHighlighted: .rgb(44, 46, 49),
        candidatePill: .rgb(235, 237, 240),
        candidateDivider: .rgb(211, 212, 217)
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
        shadow: UIColor(white: 0, alpha: 0.5),
        candidate: isIOS27 ? .rgb(162, 162, 162) : .rgb(172, 172, 172),
        candidateHighlighted: .white,
        candidatePill: .rgb(115, 115, 115),
        candidateDivider: isIOS27 ? .rgb(49, 49, 51) : .rgb(50, 50, 52)
    )
}

extension UIColor {
    static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }
}
