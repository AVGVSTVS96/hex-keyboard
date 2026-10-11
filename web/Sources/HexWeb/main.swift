import JavaScriptKit
import KeyboardCore

@JS final class Keyboard {
    private var engine = TypingEngine()
    private let document: WebDocument
    private var layout = KeyboardLayout(rows: [])
    private var grid = KeyGrid()
    private var offsets: [Int] = []
    private var width = 402.0
    private var height = 874.0
    private var dark = false
    private let style = KeyboardStyle.ios26

    @JS init(lexicon: JSUint8Array, document: JSObject) {
        self.document = WebDocument(document)
        let bytes = [UInt8](unsafeUninitializedCapacity: lexicon.length) { buffer, count in
            lexicon.copyMemory(to: buffer)
            count = lexicon.length
        }
        engine.corrector = Lexicon(bytes: bytes).map { Corrector(source: $0) }
        engine.documentChanged(self.document)
        render()
    }

    @JS func resize(width: Double, height: Double, dark: Bool) {
        self.width = width
        self.height = height
        self.dark = dark
        render()
    }

    @JS func frame() -> Frame {
        render()
        let metrics = metrics
        let faces = faceContext
        let theme = dark ? KeyboardTheme.dark(style) : KeyboardTheme.light(style)
        let uppercase = engine.shift.isUppercase
        let caps = grid.rows.joined().map { key, frame in
            let face = KeyFace(key, trailing: frame.midX > width / 2, context: faces)
            let typed = key.text(shifted: uppercase)
            return Cap(
                x: frame.x, y: frame.y, width: frame.width, height: frame.height,
                face: face.content.kind, label: face.content.value,
                secondary: face.secondary, secondaryDimmed: face.secondaryIsDimmed,
                align: face.alignment.name, prominent: face.isProminent,
                action: key.action.name, isInput: key.isInput,
                typed: typed, shown: typed.map { uppercase ? $0.uppercased() : $0 },
                alternates: key.alternates.map { uppercase ? $0.uppercased() : $0 }
            )
        }
        return Frame(
            layout: grid.signature,
            width: width,
            height: metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow),
            showsSuggestions: engine.showsSuggestions,
            caps: caps,
            chips: engine.suggestions.map { Chip(text: $0.kind == .literal ? "“\($0.text)”" : $0.text, correction: $0.kind == .correction) },
            look: Look(metrics: metrics, theme: theme, style: style)
        )
    }

    @JS func resolve(x: Double, y: Double) -> Int {
        guard let index = engine.key(atX: x, y: y, in: grid, document: document) else { return -1 }
        return offsets[index.row] + index.key
    }

    @JS func down(index: Int, tapCount: Int) {
        guard let key = key(at: index) else { return }
        switch key.action {
        case .shift: engine.pressShift(doubleTap: tapCount == 2)
        case .capsLock: engine.perform(.capsLock, in: document)
        case .delete: engine.perform(.delete, in: document)
        case .layer(let layer): engine.perform(.layer(layer), in: document)
        default: break
        }
    }

    @JS func up(index: Int) {
        if key(at: index)?.action == .shift { engine.releaseShift(in: document) }
    }

    @JS func type(index: Int, text: String, x: Double, y: Double) {
        guard let key = key(at: index) else { return }
        let tap = Tap(x: x, y: y, key: text)
        engine.perform(key.action == .space ? .space : .character(text), in: document, tap: tap)
    }

    @JS func slideTyped(text: String) {
        let layer = engine.layer
        engine.perform(.character(text), in: document)
        if engine.layer == layer { engine.perform(.layer(.letters), in: document) }
    }

    @JS func trigger(index: Int) {
        guard let key = key(at: index) else { return }
        if key.action == .return || key.action == .tab { engine.perform(key.action, in: document) }
    }

    @JS func repeatDelete(words: Bool) {
        if words { engine.deleteWord(in: document) } else { engine.perform(.delete, in: document) }
    }

    @JS func select(suggestion index: Int) {
        guard engine.suggestions.indices.contains(index) else { return }
        engine.accept(engine.suggestions[index], in: document)
    }

    @JS func cursor(offset: Int) {
        document.moveCursor(by: offset)
    }

    @JS func documentChanged() {
        engine.documentChanged(document)
    }

    @JS func endSession() {
        engine.endSession()
    }

    private var metrics: KeyboardMetrics {
        .for(.phone, width: width, height: height)
    }

    private var context: LayoutContext {
        LayoutContext(device: .phone, layer: engine.layer, kind: engine.traits.kind, isLandscape: width > height)
    }

    private var faceContext: KeyFaceContext {
        KeyFaceContext(
            device: .phone, layer: engine.layer, kind: engine.traits.kind, shift: engine.shift,
            returnKind: engine.traits.returnKind,
            returnEnabled: !engine.traits.returnRequiresText || !(document.textBeforeInput ?? "").isEmpty || !(document.textAfterInput ?? "").isEmpty
        )
    }

    private func render() {
        let context = context
        layout = Layouts.layout(for: context)
        grid = KeyGrid(layout, width: width, metrics: metrics.grid, signature: LayoutContext(device: .phone, layer: engine.layer, isLandscape: width > height).signature)
        offsets = grid.rows.reduce(into: [0]) { $0.append($0.last! + $1.count) }
        guard let corrector = engine.corrector, engine.layer == .letters else { return }
        if grid.signature != corrector.grid.signature { engine.endSession() }
        corrector.grid = grid
    }

    private func key(at index: Int) -> Key? {
        guard let row = offsets.lastIndex(where: { $0 <= index }), row < grid.rows.count, index - offsets[row] < grid.rows[row].count else { return nil }
        return grid.rows[row][index - offsets[row]].key
    }
}

final class WebDocument: TextDocument {
    private let object: JSObject

    init(_ object: JSObject) {
        self.object = object
    }

    var textBeforeInput: String? { object.before!().string }
    var textAfterInput: String? { object.after!().string }
    func insert(_ text: String) { _ = object.insert!(text) }
    func deleteBackward(_ count: Int) { _ = object.deleteBackward!(count) }
    func moveCursor(by offset: Int) { _ = object.moveCursor!(offset) }
}
