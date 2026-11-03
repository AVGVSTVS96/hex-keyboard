import KeyboardCore
import KeyboardUI
import SwiftUI
import UIKit

/// The app wears the keyboard's colors (docs/design.md, "The app"): the backdrop iOS draws behind the keyboard behind
/// every screen, and the key fill on every card and row, so the app looks like the keys it sets up.
enum HexStyle {
    static let backdrop = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0x22 / 255, alpha: 1) : UIColor(red: 0xE2 / 255, green: 0xE3 / 255, blue: 0xE8 / 255, alpha: 1) }
    static let card = dynamic(\.key)
    static let pressed = dynamic(\.keyPressed)
    static let divider = dynamic(\.candidateDivider)
    static let secondary = dynamic(\.candidate)
    static let shadow = dynamic(\.shadow)

    static let cardRadius: CGFloat = 16

    private static func dynamic(_ role: any KeyPath<KeyboardTheme, RGBA> & Sendable) -> UIColor {
        UIColor { traits in
            let style: KeyboardStyle = if #available(iOS 27, *) { .ios27 } else { .ios26 }
            let color = (traits.userInterfaceStyle == .dark ? KeyboardTheme.dark(style) : KeyboardTheme.light(style))[keyPath: role]
            return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        }
    }

    /// A UIKit view as a card: the key fill, rounded, with the keys' 1pt shadow in light mode.
    static func makeCard(_ view: UIView) {
        view.backgroundColor = card
        view.layer.cornerRadius = cardRadius
        view.layer.cornerCurve = .continuous
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 0
        view.layer.shadowOpacity = 1
        let paint = { (view: UIView) in
            view.layer.shadowColor = view.traitCollection.userInterfaceStyle == .dark ? UIColor.clear.cgColor : shadow.resolvedColor(with: view.traitCollection).cgColor
        }
        paint(view)
        view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UIView, _) in paint(view) }
    }
}

extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

extension Color {
    static let hexBackdrop = Color(HexStyle.backdrop)
    static let hexCard = Color(HexStyle.card)
    static let hexSecondary = Color(HexStyle.secondary)
    static let hexDivider = Color(HexStyle.divider)
}

extension View {
    /// A list in the keyboard's colors: the backdrop behind, the key fill on its rows, and the pressed key's fill on
    /// the row a sidebar has selected.
    func hexList(selected: Bool = false) -> some View {
        listRowBackground(selected ? Color(HexStyle.pressed) : Color.hexCard)
    }

    func hexBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.hexBackdrop)
    }
}

/// A list beside a page only where both fit, 800 points and wider: iOS calls the open iPhone Duo on its side (669 wide)
/// regular too, and would lay the list over the page there.
struct SplitWhenWide<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            content.environment(\.horizontalSizeClass, proxy.size.width >= 800 ? .regular : .compact)
        }
    }
}

/// A white SF Symbol on a colored rounded square, as Settings draws its rows.
struct Glyph: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size / 2, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size / 4, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A press that looks like a key's: the card takes the pressed fill.
struct KeyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Color(HexStyle.pressed).opacity(configuration.isPressed ? 0.35 : 0).clipShape(.rect(cornerRadius: HexStyle.cardRadius, style: .continuous)))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// What iOS keeps for Hex in Settings › Apps › Hex, as far as Hex can tell, read again whenever Hex comes forward.
@Observable final class HexStatus {
    static let shared = HexStatus()

    private(set) var isAdded = false
    private(set) var fullAccess = false
    /// Nil until the keyboard has tried reading the clipboard with Full Access.
    private(set) var pasteAllowed: Bool?

    var isSetUp: Bool { isAdded && fullAccess && pasteAllowed == true }

    private init() {
        refresh()
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { HexStatus.shared.refresh() }
        }
    }

    func refresh() {
        isAdded = (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] ?? []).contains("com.shahidy.hexkeyboard.keyboard")
        fullAccess = SettingsStore.fullAccessSeen
        pasteAllowed = SettingsStore.pasteAllowed
    }

    var summary: String {
        guard isAdded else { return "Not added yet" }
        return fullAccess ? "On, with Full Access" : "On, without Full Access"
    }

    static func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}

/// A card in the key fill, with the keys' 1pt shadow in light mode.
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.hexCard, in: .rect(cornerRadius: HexStyle.cardRadius, style: .continuous))
            .shadow(color: scheme == .light ? Color(HexStyle.shadow) : .clear, radius: 0, y: 1)
    }
}

/// The app icon's mark, drawn: a hexagon around five keys, white on near-black in light and dark.
struct HexMark: View {
    var size: CGFloat

    var body: some View {
        Canvas { context, size in
            let side = size.width
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var hexagon = Path()
            for corner in 0 ..< 6 {
                let angle = CGFloat(corner) * .pi / 3 - .pi / 2
                let point = CGPoint(x: center.x + side * 0.31 * cos(angle), y: center.y + side * 0.31 * sin(angle))
                corner == 0 ? hexagon.move(to: point) : hexagon.addLine(to: point)
            }
            hexagon.closeSubpath()
            context.stroke(hexagon, with: .color(.white), style: StrokeStyle(lineWidth: side * 0.055, lineJoin: .round))
            let key = side * 0.052, gap = side * 0.082
            for (row, count) in [3, 2].enumerated() {
                for column in 0 ..< count {
                    let x = center.x + (CGFloat(column) - CGFloat(count - 1) / 2) * gap - key / 2
                    let y = center.y + (CGFloat(row) - 0.5) * gap - key / 2
                    context.fill(Path(roundedRect: CGRect(x: x, y: y, width: key, height: key), cornerRadius: key * 0.22), with: .color(.white))
                }
            }
        }
        .frame(width: size, height: size)
        .background(Color(white: 0.07), in: .rect(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }
}
