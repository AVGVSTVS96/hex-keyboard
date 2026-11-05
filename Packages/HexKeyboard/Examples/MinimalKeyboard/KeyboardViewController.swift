import UIKit
import KeyboardCore
import KeyboardUI

/// A keyboard on iikb's engine with a look of its own: Apple's layouts and key sizes on every iPhone and iPad,
/// autocorrect that learns where you tap, and the suggestion bar's top three. Everything it knows is `TypingEngine`'s;
/// this file only draws and forwards touches.
final class KeyboardViewController: UIInputViewController {
    private var engine = TypingEngine()
    private lazy var document = ProxyDocument { [unowned self] in textDocumentProxy }
    private let bar = UIStackView()
    private let keys = KeysView()
    private lazy var barHeight = bar.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keysHeight = keys.heightAnchor.constraint(equalToConstant: 0)
    private var theme = KeyboardTheme.light(.current)
    private var ranking = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // iOS drops touches on fully transparent pixels of a keyboard, so taps between keys need a fill to land on.
        view.backgroundColor = UIColor(white: 0, alpha: 0.001)
        bar.distribution = .fillEqually
        for part in [bar, keys] {
            part.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(part)
        }
        keysHeight.priority = .required - 1
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keys.topAnchor.constraint(equalTo: bar.bottomAnchor),
            keys.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keys.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keys.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            barHeight,
            keysHeight,
        ])
        engine.corrector = Corrector(source: Lexicon.english, network: .english)
        engine.defersSuggestions = true
        keys.resolve = { [unowned self] grid, point in engine.key(atX: point.x, y: point.y, in: grid) }
        keys.onEvent = { [unowned self] in handle($0) }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sync()
    }

    override func textDidChange(_ textInput: UITextInput?) { sync() }

    override func selectionDidChange(_ textInput: UITextInput?) { sync() }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        engine.endSession()
    }

    private func handle(_ event: KeyboardEvent) {
        if case .trigger(let key) = event, key.action == .nextKeyboard { return advanceToNextInputMode() }
        if engine.handle(event, in: document) { render() }
    }

    /// The field the keyboard is in, and its text: the engine adopts what it didn't type itself.
    private func sync() {
        engine.update(InputTraits(textDocumentProxy))
        engine.documentChanged(document)
        render()
    }

    private func render() {
        let screen = view.window?.windowScene?.screen.bounds.size ?? view.bounds.size
        let size = Size(width: screen.width, height: screen.height)
        let device = DeviceClass(isPad: traitCollection.userInterfaceIdiom == .pad, shortSide: min(size.width, size.height))
        let context = engine.layout(on: device, screen: size, showsGlobe: needsInputModeSwitchKey)
        let layout = Layouts.layout(for: context)
        let metrics = KeyboardMetrics.for(context, screen: size, window: view.bounds.width, style: .current)
        let dark = traitCollection.userInterfaceStyle == .dark || textDocumentProxy.keyboardAppearance == .dark
        theme = dark ? .dark(.current) : .light(.current)
        keys.show(KeyGrid(layout, width: view.bounds.width, metrics: metrics.grid, signature: context.signature), faces: engine.faces(on: device), metrics: metrics, theme: theme)
        engine.use(keys.grid)
        barHeight.constant = metrics.toolbar.height
        keysHeight.constant = metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow)
        rank()
    }

    /// Ranks the suggestions off the main thread, so a keystroke never waits for them.
    private func rank() {
        guard engine.suggestionsAreStale else { return showSuggestions() }
        guard !ranking, let job = engine.suggestionJob() else { return }
        ranking = true
        Task.detached(priority: .userInitiated) { [weak self] in
            var job = job
            job.run()
            await self?.finish(job)
        }
    }

    private func finish(_ job: SuggestionJob) {
        ranking = false
        engine.finish(job)
        rank()
    }

    private func showSuggestions() {
        bar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard engine.showsSuggestions else { return }
        for suggestion in engine.suggestions.prefix(3) {
            let button = UIButton(primaryAction: UIAction(title: suggestion.title) { [unowned self] _ in
                engine.accept(suggestion, in: document)
                render()
            })
            button.tintColor = UIColor(theme.candidate)
            bar.addArrangedSubview(button)
        }
    }
}

/// The keys, drawn in one pass, and the touches on them as `KeyboardEvent`s.
final class KeysView: UIView {
    var onEvent: (KeyboardEvent) -> Void = { _ in }
    var resolve: (KeyGrid, CGPoint) -> (row: Int, key: Int)? = { grid, point in grid.index(atX: point.x, y: point.y) }
    private(set) var grid = KeyGrid()
    private var faces = KeyFaceContext(device: .phone, layer: .letters, kind: .text, shift: .off, returnKind: .default, returnEnabled: true)
    private var metrics: KeyboardMetrics?
    private var theme = KeyboardTheme.light(.current)
    private var touched: [ObjectIdentifier: (key: Key, frame: Rect, point: CGPoint)] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ grid: KeyGrid, faces: KeyFaceContext, metrics: KeyboardMetrics, theme: KeyboardTheme) {
        (self.grid, self.faces, self.metrics, self.theme) = (grid, faces, metrics, theme)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let metrics else { return }
        for (key, frame) in grid.rows.joined() {
            let face = KeyFace(key, trailing: frame.midX > bounds.midX, context: faces)
            let paint = face.isProminent ? theme.prominentKey : key.isInput ? theme.letterKey : theme.functionKey
            let pressed = touched.values.contains { $0.frame == frame }
            let box = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            UIColor(pressed ? paint.pressedTop : paint.top).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: metrics.cornerRadius).fill()
            draw(face.content, in: box, color: UIColor(paint.label), metrics: metrics)
        }
    }

    private func draw(_ content: KeyFace.Content, in box: CGRect, color: UIColor, metrics: KeyboardMetrics) {
        let text: (String, Double)? = switch content {
        case .letter(let letter): (letter, metrics.letterSize)
        case .text(let label): (label, metrics.labelSize)
        case .smallText(let label): (label, metrics.labelSize * 0.75)
        case .symbol, .none: nil
        }
        if case let (string, size)? = text {
            let label = NSAttributedString(string: string, attributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: color])
            let fit = label.size()
            label.draw(at: CGPoint(x: box.midX - fit.width / 2, y: box.midY - fit.height / 2))
        } else if case .symbol(let name) = content,
                  let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: metrics.symbolSize))?.withTintColor(color) {
            image.draw(at: CGPoint(x: box.midX - image.size.width / 2, y: box.midY - image.size.height / 2))
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            // A finger landing finishes the keys still held, as Apple's keyboard does, so fast typing stays in order.
            for (id, held) in touched where held.key.isInput { lift(id, at: held.point) }
            let point = touch.location(in: self)
            guard let index = resolve(grid, point) else { continue }
            let (key, frame) = grid.rows[index.row][index.key]
            touched[ObjectIdentifier(touch)] = (key, frame, point)
            onEvent(.down(key, tapCount: touch.tapCount))
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { lift(ObjectIdentifier(touch), at: touch.location(in: self)) }
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let held = touched.removeValue(forKey: ObjectIdentifier(touch)) { onEvent(.up(held.key)) }
        }
        setNeedsDisplay()
    }

    /// Types the key a touch went down on, with where it lifted, which is what the touch model learns from.
    private func lift(_ id: ObjectIdentifier, at point: CGPoint) {
        guard let key = touched.removeValue(forKey: id)?.key else { return }
        if let text = key.action == .space ? " " : key.text(shifted: faces.shift.isUppercase) {
            onEvent(.type(key, Tap(x: point.x, y: point.y, key: text)))
        } else {
            onEvent(.trigger(key))
        }
        onEvent(.up(key))
    }
}

private extension UIColor {
    convenience init(_ color: RGBA) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}
