import UIKit
import KeyboardCore

open class HexKeyboardViewController: UIInputViewController {
    open var hapticsEnabled: Bool { hasFullAccess && engine.settings.haptics }

    private let keyboardView = KeyboardView()
    private let emojiView = EmojiKeyboardView()
    private var dictation = Dictation.Status()
    private var micIsOn = false
    private var dictationTokens: [Int32] = []
    private let suggestionBar = SuggestionBar()
    private lazy var document = ProxyDocument { [unowned self] in textDocumentProxy }
    private var engine = TypingEngine()
    private lazy var barHeightConstraint = suggestionBar.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keyboardHeightConstraint = keyboardView.heightAnchor.constraint(equalToConstant: 0)
    private var deleteRepeat: DeleteRepeat?
    private let haptics = KeyHaptics()

    override open func loadView() {
        inputView = KeyboardInputView(frame: .zero, inputViewStyle: .default)
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        [suggestionBar, keyboardView, emojiView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
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
            emojiView.topAnchor.constraint(equalTo: view.topAnchor),
            emojiView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emojiView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emojiView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        emojiView.isHidden = true
        emojiView.onEvent = { [unowned self] in handle($0) }
        suggestionBar.onMic = { [unowned self] in toggleVoice() }
        suggestionBar.onMicHold = { [unowned self] in
            feedback(.other)
            Dictation.send(.stop)
        }
        engine.defersSuggestions = true
        keyboardView.onEvent = { [unowned self] in handle($0) }
        suggestionBar.onSelect = { [unowned self] in
            feedback(.input)
            engine.accept($0, in: document)
            render()
        }
        suggestionBar.onEmoji = { [unowned self] in
            feedback(.input)
            engine.accept(emoji: $0, in: document)
            render()
        }
        engine.corrector = Corrector(source: Lexicon.english, phrases: .english)
        Task { [weak self] in
            let catalog = await Task.detached(priority: .userInitiated) { EmojiCatalog.english }.value
            self?.engine.emojiCatalog = catalog
            self?.engine.suggestionsChanged()
            self?.render()
        }
        keyboardView.resolve = { [unowned self] grid, point in engine.key(atX: point.x, y: point.y, in: grid) }
        keyboardView.onGrid = { [unowned self] in engine.use($0) }
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

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        TouchTrace.shared.layout(view)
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        engine.settings = SettingsStore.load(sharing: hasFullAccess)
        engine.corrector?.memory = MemoryStore.load()
        engine.emojiHistory = MemoryStore.loadEmoji()
        if hasFullAccess, dictationTokens.isEmpty {
            dictationTokens = [
                Dictation.observe(.changed) { [weak self] in self?.dictationChanged() },
                Dictation.observeLevel { [weak self] in self?.suggestionBar.hear($0) },
            ]
            dictationChanged()
        }
        engine.suggestionsChanged()
        keyboardView.characterPreview = engine.settings.characterPreview
        syncWithDocument()
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if hapticsEnabled { haptics.start() }
        stopSystemGesturesDelayingTouches()
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
        haptics.stop()
        TouchTrace.shared.flush()
        if let memory = engine.corrector?.memory { MemoryStore.save(memory, sharing: hasFullAccess) }
        MemoryStore.save(engine.emojiHistory)
        dictationTokens.forEach(Dictation.stopObserving)
        dictationTokens = []
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

    /// The bar's height, or above the emoji keyboard's keys, the search field and what it finds.
    private func barHeight(_ metrics: KeyboardMetrics) -> CGFloat {
        let bar: CGFloat = switch (device, engine.showsSuggestions || mic != nil || dictation.failure != nil) {
        case (.phone, _): 38
        case (_, true): 36
        case (_, false): 0
        }
        guard engine.showsEmoji else { return bar }
        return engine.emojiQuery == nil ? bar + EmojiKeyboardView.fieldSpan : EmojiKeyboardView.searchHeight(metrics)
    }

    /// The bar's mic shows while the app keeps the microphone on or listens.
    private var mic: MicButton.Phase? {
        switch dictation.state {
        case .listening: .listening
        case .transcribing: .transcribing
        case .idle: micIsOn ? .on : nil
        }
    }

    private func render() {
        let device = device
        let context = engine.layout(on: device, showsGlobe: needsInputModeSwitchKey, isLandscape: screenSize.width > screenSize.height)
        let layout = Layouts.layout(for: context)
        let metrics = KeyboardMetrics.for(device, width: screenSize.width, height: screenSize.height, style: .current, oneHanded: context.oneHanded)
        keyboardView.menu = (context.menuKey(in: layout), context.menu)
        keyboardView.update(layout: layout, signature: context.signature, metrics: metrics, faces: engine.faces(on: device), theme: theme)
        suggestionBar.maximumSlotWidth = device == .phone ? .infinity : 154.5
        suggestionBar.keyInset = metrics.sideInset
        suggestionBar.update(mic: mic, notice: dictation.failure, theme: theme)
        renderSuggestions()
        if engine.showsEmoji {
            emojiView.update(history: engine.emojiHistory, opening: emojiView.isHidden, query: engine.emojiQuery, theme: theme, metrics: metrics)
        }
        emojiView.isHidden = !engine.showsEmoji
        keyboardView.isHidden = engine.showsEmoji && engine.emojiQuery == nil
        suggestionBar.isHidden = engine.showsEmoji

        let height = metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow)
        if keyboardHeightConstraint.constant != height { keyboardHeightConstraint.constant = height }
        let bar = barHeight(metrics)
        if barHeightConstraint.constant != bar { barHeightConstraint.constant = bar }
    }

    private var theme: KeyboardTheme {
        KeyboardTheme.current(for: traitCollection, appearance: textDocumentProxy.keyboardAppearance)
    }

    private var ranking = false

    private func renderSuggestions() {
        guard engine.suggestionsAreStale else {
            return suggestionBar.update(engine.suggestions, emoji: engine.emojiSuggestions, enabled: engine.showsSuggestions, theme: theme)
        }
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
        renderSuggestions()
    }

    private func handle(_ event: KeyboardEvent) {
        switch event {
        case .down(let key, _):
            feedback(Self.haptic(for: key))
            if key.action == .delete { startDeleteRepeat() }
            if dictation.failure != nil { clearFailure() }
        case .up(let key) where key.action == .delete:
            deleteRepeat = nil
        case .trigger(let key) where key.action == .dismiss:
            return dismissKeyboard()
        case .trigger(let key) where key.action == .nextKeyboard:
            return advanceToNextInputMode()
        case .type:
            TouchTrace.shared.mark("typed")
        case .oneHanded(let hand), .pick(.hand(let hand)):
            SettingsStore.set(hand, sharing: hasFullAccess)
        case .pick(.voice):
            toggleVoice()
        default:
            break
        }
        if engine.handle(event, in: document) { render() }
    }

    /// Stops a dictation in progress, so what was heard is typed. Otherwise starts one: in place while the app keeps the
    /// microphone on, or by opening the app, since a keyboard can't use the microphone and iOS starts a recording only
    /// in an app in front. Apps can't be opened from a keyboard through public API, so this goes through the responder
    /// chain to the host's UIApplication, as voice keyboards do.
    private func toggleVoice() {
        guard hasFullAccess else {
            dictation = Dictation.Status(failure: "Voice needs Allow Full Access in Settings › Apps › Hex › Keyboards")
            return render()
        }
        switch dictation.state {
        case .listening: return Dictation.send(.finish)
        case .transcribing: return
        case .idle: break
        }
        if dictation.failure != nil { clearFailure() }
        micIsOn = Dictation.micIsOn
        if micIsOn { return Dictation.send(.start) }
        render()
        var responder: UIResponder? = self
        while let next = responder {
            if let application = next as? UIApplication { return application.open(Dictation.url) }
            responder = next.next
        }
    }

    /// The app listened, or stopped: type what it heard, once.
    private func dictationChanged() {
        var status = Dictation.status
        if let heard = status.heard {
            status.heard = nil
            Dictation.publish(status)
            engine.handle(.dictated(heard), in: document)
        }
        dictation = status
        micIsOn = Dictation.micIsOn
        render()
    }

    private func clearFailure() {
        dictation.failure = nil
        if hasFullAccess { Dictation.publish(dictation) }
        render()
    }

    private func startDeleteRepeat() {
        deleteRepeat = DeleteRepeat { [unowned self] words in
            if words { engine.deleteWord(in: document) } else { engine.perform(.delete, in: document) }
            feedback(words ? .deletionRapid : .deletionRepeat)
            render()
        }
    }

    private func stopSystemGesturesDelayingTouches() {
        view.window?.gestureRecognizers?.forEach {
            $0.delaysTouchesBegan = false
            $0.delaysTouchesEnded = false
        }
    }

    private func feedback(_ haptic: KeyHaptics.Kind) {
        if engine.settings.sound { UIDevice.current.playInputClick() }
        if hapticsEnabled { haptics.play(haptic) }
    }

    private static func haptic(for key: Key) -> KeyHaptics.Kind {
        switch key.action {
        case .character: .input
        case .space, .return, .tab: .separator
        case .delete: .deletion
        default: .other
        }
    }
}

private extension Corrector {
    func learn(_ lexicon: UILexicon) {
        let entries = lexicon.entries
        setReplacements(entries.filter { $0.userInput != $0.documentText }.map { ($0.userInput, $0.documentText) })
        setNames(entries.filter { $0.userInput == $0.documentText }.map(\.documentText))
    }
}
