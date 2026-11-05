import KeyboardCore
import SwiftUI
import UIKit

/// The app's look, after Raycast's iOS app (docs/design.md, "The app"): a black page, near-black cards with a hairline
/// edge, gray sentence-case headers, and white pills for what's picked.
enum AppStyle {
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
    static func display(_ size: CGFloat, weight: UIFont.Weight = .bold) -> Font { Font(AppStyle.display(size, weight: weight)) }
}

extension Color {
    static let appPage = Color(AppStyle.page)
    static let appCard = Color(AppStyle.card)
    static let appPressed = Color(AppStyle.pressed)
    static let appEdge = Color(AppStyle.edge)
    static let appDivider = Color(AppStyle.divider)
    static let appSecondary = Color(AppStyle.secondary)
    static let appPill = Color(AppStyle.pill)
    static let appPillLabel = Color(AppStyle.pillLabel)
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
