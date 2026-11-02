import KeyboardCore
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

    /// A table in the keyboard's colors, for the screens built from table views.
    static func dress(_ table: UITableView) {
        table.backgroundColor = backdrop
        table.separatorColor = divider
    }

    /// A white SF Symbol on a colored rounded square, as Settings draws its rows.
    static func glyph(_ symbol: String, _ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 30, height: 30), cornerRadius: 7.5).fill()
            let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))!
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            let size = image.size
            image.draw(in: CGRect(x: (30 - size.width) / 2, y: (30 - size.height) / 2, width: size.width, height: size.height))
        }
    }

    static func dress(_ cell: UITableViewCell) {
        var background = UIBackgroundConfiguration.listCell()
        background.backgroundColor = card
        cell.backgroundConfiguration = background
    }
}

extension Color {
    static let hexBackdrop = Color(HexStyle.backdrop)
    static let hexCard = Color(HexStyle.card)
    static let hexSecondary = Color(HexStyle.secondary)
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
