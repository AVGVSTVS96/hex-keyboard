import UIKit
import KeyboardCore

open class HexKeyboardViewController: UIInputViewController {
    open var hapticsEnabled: Bool { hasFullAccess && engine.settings.haptics }

    private let keyboardView = KeyboardView()
    private let suggestionBar = SuggestionBar()
    private lazy var document = ProxyDocument { [unowned self] in textDocumentProxy }
    private var engine = TypingEngine()
    private lazy var barHeightConstraint = suggestionBar.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keyboardHeightConstraint = keyboardView.heightAnchor.constraint(equalToConstant: 0)
    private var deleteRepeat: DeleteRepeat?
    private lazy var haptics = UIImpactFeedbackGenerator(style: .light, view: view)

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
        engine.defersSuggestions = true
        keyboardView.onEvent = { [unowned self] in handle($0) }
        suggestionBar.onSelect = { [unowned self] in
            feedback()
            engine.accept($0, in: document)
            render()
        }
        let words: any CandidateSource = Lexicon.english ?? TextCheckerSource(language: primaryLanguage ?? "en-US")
        engine.corrector = Corrector(source: words)
        keyboardView.resolve = { [unowned self] grid, point in engine.key(atX: point.x, y: point.y, in: grid) }
        keyboardView.onGrid = { [unowned self] grid in
            guard let corrector = engine.corrector, engine.layer == .letters else { return }
            if grid.signature != corrector.grid.signature { engine.endSession() }
            corrector.grid = grid
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
        engine.suggestionsChanged()
        keyboardView.characterPreview = engine.settings.characterPreview
        syncWithDocument()
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if hapticsEnabled { haptics.prepare() }
        view.window?.gestureRecognizers?.forEach {
            $0.delaysTouchesBegan = false
            $0.delaysTouchesEnded = false
        }
        TouchTrace.shared.watch(view.window)
        Task { [weak self] in
            guard let lexicon = await self?.requestSupplementaryLexicon() else { return }
            self?.engine.corrector?.learn(lexicon)
            self?.engine.suggestionsChanged()
            self?.render()
        }
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        engine.endSession()
        TouchTrace.shared.flush()
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
        let known = engine.text.before.count
        let report = engine.documentChanged(document)
        TouchTrace.shared.record(report, host: textDocumentProxy.documentContextBeforeInput?.count ?? 0, known: known)
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
        let theme = theme
        let faces = KeyFaceContext(
            device: device,
            layer: engine.layer,
            kind: engine.traits.kind,
            shift: engine.shift,
            returnKind: engine.traits.returnKind,
            returnEnabled: !engine.traits.returnRequiresText || !engine.text.before.isEmpty || !(engine.text.after ?? "").isEmpty
        )
        let signature = LayoutContext(device: device, layer: engine.layer, isLandscape: screenSize.width > screenSize.height).signature
        keyboardView.update(layout: layout, signature: signature, metrics: metrics, faces: faces, theme: theme)
        suggestionBar.maximumSlotWidth = device == .phone ? .infinity : 154.5
        renderSuggestions()

        let height = metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow)
        if keyboardHeightConstraint.constant != height { keyboardHeightConstraint.constant = height }
        if barHeightConstraint.constant != barHeight { barHeightConstraint.constant = barHeight }
    }

    private var theme: KeyboardTheme {
        KeyboardTheme.current(for: traitCollection, appearance: textDocumentProxy.keyboardAppearance)
    }

    private var ranking = false

    private func renderSuggestions() {
        guard engine.suggestionsAreStale else {
            return suggestionBar.update(engine.suggestions, enabled: engine.showsSuggestions, theme: theme)
        }
        guard !ranking else { return }
        guard let job = engine.suggestionJob(in: document) else {
            engine.refreshSuggestionsIfNeeded(in: document)
            return renderSuggestions()
        }
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
        renderSuggestions()
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
            TouchTrace.shared.mark("typed")
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
            engine.moveCursor(by: offset, in: document)
        }
        render()
    }

    private func feedback() {
        if engine.settings.sound { UIDevice.current.playInputClick() }
        guard hapticsEnabled else { return }
        haptics.impactOccurred()
        haptics.prepare()
    }
}
