import UIKit
import KeyboardCore

extension KeyboardStyle {
    static var current: KeyboardStyle {
        if #available(iOS 27, *) { .ios27 } else { .ios26 }
    }
}

extension KeyboardTheme {
    static let lightCurrent = KeyboardTheme.light(.current)
    static let darkCurrent = KeyboardTheme.dark(.current)

    static func current(for traits: UITraitCollection, appearance: UIKeyboardAppearance?) -> KeyboardTheme {
        appearance == .dark || traits.userInterfaceStyle == .dark ? darkCurrent : lightCurrent
    }
}

extension KeyboardMetrics {
    // iOS 27 moved the system keyboard's rows 7pt lower, but a third-party keyboard's area still ends where it did on iOS 26, so we can only follow it 3pt.
    static func `for`(_ device: DeviceClass, size: CGSize) -> KeyboardMetrics {
        .for(device, width: size.width, height: size.height, systemBottomShift: KeyboardStyle.current == .ios27 ? 3 : 0)
    }
}

extension RGBA {
    var ui: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
}
