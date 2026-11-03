import KeyboardCore
import KeyboardUI
import SwiftUI
import UIKit

/// The app's look, after Raycast's iOS app (docs/design.md, "The app"): a black page, near-black cards with a hairline
/// edge, gray sentence-case headers, and white pills for what's picked.
enum HexStyle {
    static let page = UIColor { $0.isDark ? .black : rgb(0xF2, 0xF2, 0xF5) }
    static let card = UIColor { $0.isDark ? rgb(0x1C, 0x1C, 0x1E) : .white }
    static let pressed = UIColor { $0.isDark ? rgb(0x2C, 0x2C, 0x2E) : rgb(0xE5, 0xE5, 0xEA) }
    static let edge = UIColor { $0.isDark ? UIColor(white: 1, alpha: 0.07) : UIColor(white: 0, alpha: 0.06) }
    static let divider = UIColor { $0.isDark ? rgb(0x2C, 0x2C, 0x2E) : rgb(0xE3, 0xE3, 0xE8) }
    static let secondary = UIColor { $0.isDark ? rgb(0x8E, 0x8E, 0x93) : rgb(0x6C, 0x6C, 0x70) }
    static let pill = UIColor { $0.isDark ? .white : .black }
    static let pillLabel = UIColor { $0.isDark ? .black : .white }

    static let cardRadius: CGFloat = 22

    /// Helvetica Neue, iikb's display face (brand/BRAND.md), for titles and big numbers; everything else is the system font.
    static func display(_ size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        let name = switch weight {
        case .bold, .heavy, .black, .semibold: "HelveticaNeue-Bold"
        case .medium: "HelveticaNeue-Medium"
        case .light, .thin, .ultraLight: "HelveticaNeue-Light"
        default: "HelveticaNeue"
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// Page titles in the display face, tracked tight as the wordmark is.
    static func applyTitles() {
        let large = display(34)
        let inline = display(17)
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: large, .kern: -0.02 * large.pointSize]
        UINavigationBar.appearance().titleTextAttributes = [.font: inline]
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> UIColor {
        UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    /// A UIKit view as a card.
    static func makeCard(_ view: UIView) {
        view.backgroundColor = card
        view.layer.cornerRadius = cardRadius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        let paint = { (view: UIView) in view.layer.borderColor = edge.resolvedColor(with: view.traitCollection).cgColor }
        paint(view)
        view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UIView, _) in paint(view) }
    }
}

private extension UITraitCollection {
    var isDark: Bool { userInterfaceStyle == .dark }
}

extension Font {
    static func display(_ size: CGFloat, weight: UIFont.Weight = .bold) -> Font { Font(HexStyle.display(size, weight: weight)) }
}

extension Color {
    static let hexPage = Color(HexStyle.page)
    static let hexCard = Color(HexStyle.card)
    static let hexPressed = Color(HexStyle.pressed)
    static let hexEdge = Color(HexStyle.edge)
    static let hexDivider = Color(HexStyle.divider)
    static let hexSecondary = Color(HexStyle.secondary)
    static let hexPill = Color(HexStyle.pill)
    static let hexPillLabel = Color(HexStyle.pillLabel)
}

/// A white SF Symbol on a colored rounded square, as Raycast's More page draws its commands.
struct Glyph: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// What iOS keeps for Hex in Settings › Apps › Hex, read again whenever Hex comes forward, as it does when you come back
/// from Settings.
@Observable final class HexStatus {
    static let shared = HexStatus()

    private(set) var isAdded = false
    private(set) var fullAccess = false
    private(set) var pasteAllowed = false

    var isSetUp: Bool { isAdded && fullAccess && pasteAllowed }

    private init() {
        refresh()
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { HexStatus.shared.refresh() }
        }
    }

    func refresh() {
        isAdded = (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] ?? []).contains("com.shahidy.hexkeyboard.keyboard")
        fullAccess = Self.allowed("kTCCServiceKeyboardNetwork")
        pasteAllowed = Self.allowed("kTCCServicePasteboard")
    }

    /// Asks TCC, where iOS keeps privacy switches, through its private `TCCAccessPreflight`. iOS files the keyboard's Full
    /// Access under the app, and Paste from Other Apps is only granted at Allow, never at Ask.
    private static func allowed(_ service: String) -> Bool {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
        guard let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY), let preflight = dlsym(tcc, "TCCAccessPreflight") else { return false }
        return unsafeBitCast(preflight, to: Preflight.self)(service as CFString, nil) == 0
    }

    var summary: String {
        guard isAdded else { return "Not added yet" }
        return fullAccess ? "On, with Full Access" : "On, without Full Access"
    }

    var color: Color { isAdded ? (fullAccess ? .green : .yellow) : .orange }

    static func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }

    /// Settings › General › Keyboard › Text Replacement, by Settings' own link for it, or iikb's page in Settings when
    /// iOS won't open that.
    static func openTextReplacements() {
        UIApplication.shared.open(URL(string: "App-prefs:General&path=Keyboard/USER_DICTIONARY")!) { opened in
            if !opened { openSettings() }
        }
    }
}

/// The app icon's mark, drawn: iikb flush left on the bottom margin of a black square, as brand/logo/gen.mjs draws it.
struct Mark: View {
    var size: CGFloat

    var body: some View {
        Text("iikb")
            .font(.display(size * 0.37, weight: .bold))
            .tracking(-0.045 * size * 0.37)
            .foregroundStyle(.white)
            .padding(size * 0.13)
            .frame(width: size, height: size, alignment: .bottomLeading)
            .background(.black, in: .rect(cornerRadius: size * 0.225, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
