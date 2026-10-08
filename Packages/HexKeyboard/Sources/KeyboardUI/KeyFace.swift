import UIKit
import KeyboardCore

struct KeyFace: Equatable {
    enum Content: Equatable {
        case letter(String)
        case text(String)
        case smallText(String)
        case symbol(String)
        case none
    }

    enum Alignment: Equatable {
        case center, bottomLeading, bottomTrailing
    }

    var content: Content
    var secondary: String?
    var secondaryIsDimmed = true
    var alignment: Alignment = .center
    var isProminent = false
}

struct KeyFaceContext {
    var device: DeviceClass
    var layer: KeyboardLayer
    var kind: InputKind
    var shift: ShiftState
    var returnKind: ReturnKind
    var returnEnabled: Bool
}

extension KeyFace {
    init(_ key: Key, trailing: Bool, context: KeyFaceContext) {
        let isPad = context.device != .phone
        let edge: Alignment = isPad ? (trailing ? .bottomTrailing : .bottomLeading) : .center
        switch key.action {
        case .character(let value):
            let shown = context.shift.isUppercase && value.count == 1 ? value.uppercased() : Self.glyphs[value, default: value]
            self.init(content: value.count == 1 ? .letter(shown) : .text(shown))
            secondary = key.secondary
            secondaryIsDimmed = !key.isPair
        case .space:
            self.init(content: .none)
        case .delete:
            self.init(content: .symbol("delete.left"), alignment: edge)
        case .shift:
            let name = switch context.shift {
            case .off: "shift"
            case .on: "shift.fill"
            case .locked: "capslock.fill"
            }
            self.init(content: .symbol(name), alignment: edge)
        case .capsLock:
            self.init(content: .symbol(context.shift == .locked ? "capslock.fill" : "capslock"), alignment: edge)
        case .return:
            let kind = context.returnKind
            self.init(
                content: kind.symbol.map { .symbol($0) } ?? .text(kind.title),
                alignment: edge,
                isProminent: kind.isProminent && context.returnEnabled
            )
        case .tab:
            self.init(content: .symbol("arrow.right.to.line"), alignment: edge)
        case .layer(let layer):
            let title = context.kind == .url && layer == .numbers && context.device == .phone ? ".?123" : Self.title(for: layer, device: context.device)
            let small = context.device == .phone && context.layer != .letters && layer != .letters
            self.init(content: small ? .smallText(title) : .text(title), alignment: edge)
        case .nextKeyboard:
            self.init(content: .symbol("globe"), alignment: edge)
        case .dismiss:
            self.init(content: .symbol("keyboard.chevron.compact.down"), alignment: edge)
        }
    }

    private static let glyphs = ["\"": "”", "'": "’"]

    private static func title(for layer: KeyboardLayer, device: DeviceClass) -> String {
        switch (layer, device) {
        case (.letters, _): "ABC"
        case (.numbers, .phone), (.numbers, .compactPad): "123"
        case (.numbers, _): ".?123"
        case (.symbols, _): "#+="
        }
    }
}
