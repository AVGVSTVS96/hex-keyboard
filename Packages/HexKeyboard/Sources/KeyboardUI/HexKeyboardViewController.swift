import UIKit
import KeyboardCore

open class HexKeyboardViewController: UIInputViewController {
    open var hapticsEnabled: Bool { false }

    private let keyboardView = KeyboardView()
    private let suggestionBar = SuggestionBar()
    private lazy var document = ProxyDocument { [unowned self] in textDocumentProxy }
    private var engine = TypingEngine()
    private lazy var barHeightConstraint = suggestionBar.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keyboardHeightConstraint = keyboardView.heightAnchor.constraint(equalToConstant: 0)
    private var deleteRepeat: DeleteRepeat?
    private var haptics: UIImpactFeedbackGenerator?

    override open func loadView() {
        inputView = KeyboardInputView(frame: .zero, inputViewStyle: .default)
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(suggestionBar)
        view.addSubview(keyboardView)
        suggestionBar.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        keyboardHeightConstraint.priority = .required - 1
        NSLayoutConstraint.activate([
            suggestionBar.topAnchor.constraint(equalTo: view.topAnchor),
            suggestionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barHeightConstraint,
            keyboardView.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyboardHeightConstraint,
        ])
        keyboardView.onEvent = { [unowned self] in handle($0) }
        suggestionBar.onSelect = { [unowned self] in
            feedback()
            engine.accept($0, in: document)
            render()
        }
        engine.corrector = Corrector(source: TextCheckerSource(language: primaryLanguage ?? "en-US"))
        Task { [weak self] in
            guard let lexicon = await self?.requestSupplementaryLexicon() else { return }
            self?.engine.corrector?.learn(lexicon)
            self?.syncWithDocument()
        }
        keyboardView.globeTarget = { [unowned self] control in
            control.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.render() }
        syncWithDocument()
    }

    override open func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        render()
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        engine.settings = SettingsStore.load()
        engine.corrector?.memory = MemoryStore.load()
        keyboardView.characterPreview = engine.settings.characterPreview
        syncWithDocument()
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let memory = engine.corrector?.memory { MemoryStore.save(memory) }
    }

    override open func selectionDidChange(_ textInput: UITextInput?) {
        syncWithDocument()
    }

    override open func textDidChange(_ textInput: UITextInput?) {
        syncWithDocument()
    }

    private func syncWithDocument() {
        engine.update(InputTraits(textDocumentProxy))
        engine.documentChanged(document)
        render()
    }

    private var screenSize: CGSize {
        view.window?.windowScene?.screen.bounds.size ?? view.bounds.size
    }

    private var device: DeviceClass {
        let shortSide = min(screenSize.width, screenSize.height)
        guard traitCollection.userInterfaceIdiom == .pad else { return shortSide >= 600 ? .compactPad : .phone }
        return shortSide >= 1000 ? .largePad : shortSide < 800 ? .compactPad : .pad
    }

    private var metrics: KeyboardMetrics { .for(device, size: screenSize) }

    private var barHeight: CGFloat {
        switch (device, engine.showsSuggestions) {
        case (.phone, _): 27
        case (_, true): 36
        case (_, false): 0
        }
    }

    private func render() {
        let device = device
        let layout = Layouts.layout(for: LayoutContext(
            device: device,
            layer: engine.layer,
            kind: engine.traits.kind,
            showsGlobe: needsInputModeSwitchKey,
            isLandscape: screenSize.width > screenSize.height
        ))
        let metrics = metrics
        let theme = KeyboardTheme.current(for: traitCollection, appearance: textDocumentProxy.keyboardAppearance)
        let faces = KeyFaceContext(
            device: device,
            layer: engine.layer,
            kind: engine.traits.kind,
            shift: engine.shift,
            returnKind: engine.traits.returnKind,
            returnEnabled: !engine.traits.returnRequiresText || textDocumentProxy.hasText
        )
        keyboardView.update(layout: layout, metrics: metrics, faces: faces, theme: theme)
        suggestionBar.update(engine.suggestions, enabled: engine.showsSuggestions, theme: theme)

        let height = metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow)
        if keyboardHeightConstraint.constant != height { keyboardHeightConstraint.constant = height }
        if barHeightConstraint.constant != barHeight { barHeightConstraint.constant = barHeight }
    }

    private func handle(_ event: KeyboardEvent) {
        switch event {
        case .down(let key, let tapCount):
            feedback()
            switch key.action {
            case .shift:
                engine.pressShift(doubleTap: tapCount == 2)
            case .capsLock:
                engine.perform(.capsLock, in: document)
            case .delete:
                engine.perform(.delete, in: document)
                deleteRepeat = DeleteRepeat { [unowned self] words in
                    if words { engine.deleteWord(in: document) } else { engine.perform(.delete, in: document) }
                    feedback()
                    render()
                }
            case .layer(let layer):
                engine.perform(.layer(layer), in: document)
            default:
                return
            }
        case .up(let key):
            switch key.action {
            case .delete: deleteRepeat = nil
            case .shift: engine.releaseShift(in: document)
            default: return
            }
        case .type(let key, let text, let point):
            let tap = Tap(x: point.x, y: point.y, key: text)
            engine.perform(key.action == .space ? .space : .character(text), in: document, tap: tap)
        case .slideTyped(_, let text):
            let layer = engine.layer
            engine.perform(.character(text), in: document)
            if engine.layer == layer { engine.perform(.layer(.letters), in: document) }
        case .trigger(let key):
            switch key.action {
            case .return, .tab: engine.perform(key.action, in: document)
            case .dismiss: dismissKeyboard()
            case .nextKeyboard: advanceToNextInputMode()
            default: return
            }
        case .cursor(let offset):
            document.moveCursor(by: offset)
        case .trackpad(let active):
            if active { return }
            engine.documentChanged(document)
        }
        render()
    }

    private func feedback() {
        if engine.settings.sound { UIDevice.current.playInputClick() }
        guard hapticsEnabled else { return }
        if haptics == nil { haptics = UIImpactFeedbackGenerator(style: .light, view: view) }
        haptics?.impactOccurred()
    }
}
