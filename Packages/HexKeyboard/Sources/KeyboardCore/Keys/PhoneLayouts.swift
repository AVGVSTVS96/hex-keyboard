enum PhoneLayouts {
    static func layout(for context: LayoutContext) -> KeyboardLayout {
        switch (context.layer, context.isSplit) {
        case (.letters, false): letters(context)
        case (.numbers, false): numbers(context)
        case (.symbols, false): symbols(context)
        case (.letters, true): splitLetters(context)
        case (.numbers, true): split(context, "12345", "67890", "-/:;(", ")$&@\"", layerKey: .symbols)
        case (.symbols, true): split(context, "[]{}#", "%^*+=", "_\\|~<", ">€£¥•", layerKey: .numbers)
        }
    }

    /// Apple's split keyboard on the open Duo: half of each row under each thumb, the middle a gap, and the keys
    /// between the hands (G and V) on both halves.
    private static func splitLetters(_ context: LayoutContext) -> KeyboardLayout {
        let rows = [
            RowItem.keys("qwert") + [.flexible] + RowItem.keys("yuiop"),
            [.spacer(.pitch(0.5))] + RowItem.keys("asdfg") + [.flexible] + RowItem.keys("ghjkl") + [.spacer(.pitch(0.5))],
            [.key(Key(.shift, width: .pitch(1.3))), .spacer(.pitch(0.2))] + RowItem.keys("zxcv") + [.flexible]
                + RowItem.keys("vbnm") + [.spacer(.pitch(0.2)), .key(Key(.delete, width: .pitch(1.3)))],
            splitBottomRow(context, layerKey: .numbers),
        ]
        guard context.showsNumberRow else { return KeyboardLayout(rows: rows) }
        return KeyboardLayout(rows: [RowItem.keys("12345") + [.flexible] + RowItem.keys("67890")] + rows, hasNumberRow: true)
    }

    private static func split(_ context: LayoutContext, _ topLeft: String, _ topRight: String, _ middleLeft: String, _ middleRight: String, layerKey: KeyboardLayer) -> KeyboardLayout {
        let marks = punctuation.map { item -> RowItem in
            guard case .key(var key) = item else { return item }
            key.width = .pitch(1.4)
            return .key(key)
        }
        return KeyboardLayout(rows: [
            RowItem.keys(topLeft) + [.flexible] + RowItem.keys(topRight),
            RowItem.keys(middleLeft) + [.flexible] + RowItem.keys(middleRight),
            [.key(Key(.layer(layerKey), width: .pitch(1.3))), .spacer(.pitch(0.2))] + marks.prefix(3) + [.flexible]
                + marks.suffix(3) + [.spacer(.pitch(0.2)), .key(Key(.delete, width: .pitch(1.3)))],
            splitBottomRow(context, layerKey: .letters),
        ])
    }

    /// Each half five keys wide: the layer and emoji keys and a space bar on the left, a space bar, the field's
    /// own keys and return on the right.
    private static func splitBottomRow(_ context: LayoutContext, layerKey: KeyboardLayer) -> [RowItem] {
        let character = { (value: String) in RowItem.key(Key(.character(value))) }
        let leading = [Key(.layer(layerKey))]
            + (context.showsEmoji ? [Key(.emoji)] : [])
        let leadingSpan = leading.compactMap(\.width.span).reduce(0, +)
        let trailing: [RowItem] = switch context.kind {
        case .email: [character("@"), character(".")]
        case .url: [character("/"), character(".com")]
        case .twitter: [character("@"), character("#")]
        case .webSearch: [character(".")]
        default: []
        }
        let space = { (span: Double) in RowItem.key(Key(.space, width: .pitch(span))) }
        return leading.map(RowItem.key) + [space(5 - leadingSpan), .flexible, space(3.5 - Double(trailing.count))] + trailing
            + [.key(Key(.return, width: .pitch(1.5)))]
    }

    private static func letters(_ context: LayoutContext) -> KeyboardLayout {
        let rows = [
            RowItem.keys("qwertyuiop"),
            [.flexible] + RowItem.keys("asdfghjkl") + [.flexible],
            [.key(Key(.shift, width: .pitch(1.3))), .flexible] + RowItem.keys("zxcvbnm") + [.flexible, .key(Key(.delete, width: .pitch(1.3)))],
            bottomRow(context, layerKey: .numbers),
        ]
        guard context.showsNumberRow else { return KeyboardLayout(rows: rows) }
        return KeyboardLayout(rows: [RowItem.keys("1234567890")] + rows, hasNumberRow: true)
    }

    private static func numbers(_ context: LayoutContext) -> KeyboardLayout {
        KeyboardLayout(rows: [
            RowItem.keys("1234567890"),
            RowItem.keys("-/:;()$&@\""),
            [.key(Key(.layer(.symbols), width: .pitch(1.3))), .flexible] + punctuation + [.flexible, .key(Key(.delete, width: .pitch(1.3)))],
            bottomRow(context, layerKey: .letters),
        ])
    }

    private static func symbols(_ context: LayoutContext) -> KeyboardLayout {
        KeyboardLayout(rows: [
            RowItem.keys("[]{}#%^*+="),
            RowItem.keys("_\\|~<>€£¥•"),
            [.key(Key(.layer(.numbers), width: .pitch(1.3))), .flexible] + punctuation + [.flexible, .key(Key(.delete, width: .pitch(1.3)))],
            bottomRow(context, layerKey: .letters),
        ])
    }

    private static var punctuation: [RowItem] {
        [".", ",", "?", "!", "'"].map { .key(Key(.character($0), width: .pitch(1.4), alternates: Alternates.for($0))) }
    }

    /// Return beside the emoji key, as wide as Raycast's on the open Duo in portrait and landscape.
    private static let raycastReturn = KeyWidth.pitch(1.4)

    private static func bottomRow(_ context: LayoutContext, layerKey: KeyboardLayer) -> [RowItem] {
        let side = context.isLandscape ? 2.0 : 2.5
        let leading: [RowItem] = [.key(Key(.layer(layerKey), width: .pitch(side / 2)))]
        let space = RowItem.key(Key(.space, width: .fill))
        let returnKey = RowItem.key(Key(.return, width: .pitch(side)))
        let emoji: [RowItem] = context.showsEmoji ? [.key(Key(.emoji, width: .pitch(side / 2)))] : []
        let character = { (value: String, width: KeyWidth) in RowItem.key(Key(.character(value), width: width)) }
        switch context.kind {
        case .email:
            return leading + [space, character("@", .pitch(1.25)), character(".", .pitch(1.25)), returnKey]
        case .url:
            return leading + [character(".", .fill), character("/", .fill), character(".com", .fill), returnKey]
        case .twitter:
            return leading + [space, character("@", .pitch(1.25)), character("#", .pitch(1.25)), returnKey]
        case .webSearch:
            return leading + [space, character(".", .input), .key(Key(.return, width: .pitch(1.75)))]
        default:
            guard context.showsEmoji else { return leading + [space, returnKey] }
            return leading + emoji + [space, .key(Key(.return, width: raycastReturn))]
        }
    }
}
