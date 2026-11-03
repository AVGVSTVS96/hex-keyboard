import UIKit
import KeyboardCore

open class HexKeyboardViewController: UIInputViewController {
    open var hapticsEnabled: Bool { hasFullAccess && engine.settings.haptics != .off }

    private let keyboardView = KeyboardView()
    private var dictation = Dictation.Status()
    private var micIsOn = false
    private var dictationTokens: [Int32] = []
    private let suggestionBar = SuggestionBar()
    private let panelView = PanelView()
    private let toolbarView = UIView()
    private var toolbar = KeyboardMetrics.phone(width: 390).toolbar
    private lazy var emojiPanel: EmojiPanel = {
        let panel = EmojiPanel()
        panel.onPick = { [unowned self] emoji, base in
            feedback(.input)
            handle(.emoji(emoji, base: base))
        }
        panel.history = { [unowned self] in engine.emojiHistory }
        return panel
    }()
    private lazy var gifPanel: GifPanel? = Klipy.shared.map { klipy in
        let panel = GifPanel(klipy: klipy)
        panel.fullAccess = { [unowned self] in hasFullAccess }
        panel.onCopied = { [unowned self] in clipboard.skip(changeCount: $0) }
        panel.onTurnOn = { [unowned self] in open(HexLink.settings) }
        panel.changed = { [unowned self] in render() }
        panel.clearSearch = { [unowned self] in handle(.panel(.gif)) }
        return panel
    }
    private lazy var clipboardPanel: ClipboardPanel = {
        let panel = ClipboardPanel(store: clipboard)
        panel.fullAccess = { [unowned self] in hasFullAccess }
        panel.onPaste = { [unowned self] in
            feedback(.input)
            handle(.paste($0))
        }
        panel.onTurnOn = { [unowned self] in open(HexLink.settings) }
        panel.changed = { [unowned self] in render() }
        return panel
    }()
    /// The panels this keyboard has, in the tools' order. GIFs need a KLIPY key built in.
    private lazy var panels: [Panel: PanelContent] = [.emoji: emojiPanel, .gif: gifPanel, .clipboard: clipboardPanel].compactMapValues { $0 }
    private lazy var document = ProxyDocument { [unowned self] in textDocumentProxy }
    private var engine = TypingEngine()
    private lazy var toolbarHeightConstraint = toolbarView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keyboardHeightConstraint = keyboardView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keysMinimumConstraint = keyboardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
    private var deleteRepeat: DeleteRepeat?
    private let haptics = KeyHaptics()
    private let clipboard = ClipboardStore(backup: ClipboardStore.own)
    private let sources = Sources()

    override open func loadView() {
        inputView = KeyboardInputView(frame: .zero, inputViewStyle: .default)
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        [toolbarView, keyboardView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        [suggestionBar, panelView].forEach(toolbarView.addSubview)
        keysMinimumConstraint.priority = .required - 1
        toolbarHeightConstraint.priority = .required - 2
        keyboardHeightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: view.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarHeightConstraint,
            keyboardView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyboardHeightConstraint,
            keysMinimumConstraint,
        ])
        suggestionBar.onMic = { [unowned self] in toggleVoice() }
        suggestionBar.onTool = { [unowned self] in open($0) }
        panelView.onClose = { [unowned self] in handle(.panel(nil)) }
        panelView.onClear = { [unowned self] in handle(.panel(engine.panel)) }
        suggestionBar.onNotice = { [unowned self] in
            if dictation.failure != nil { return clearFailure() }
            sources.dismissHint()
            render()
        }
        sources.onHint = { [unowned self] in render() }
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
        if hasFullAccess { sources.reload() }
        syncWithDocument()
    }

    override open func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        render()
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width, room = toolbarView.bounds.height
        suggestionBar.frame = CGRect(x: 0, y: max(room - toolbar.height, 0), width: width, height: toolbar.height)
        panelView.frame = CGRect(x: 0, y: max(room - toolbar.panelHeight, 0), width: width, height: toolbar.panelHeight)
        TouchTrace.shared.layout(view)
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        KeyboardHost.appeared()
        engine.settings = SettingsStore.load(sharing: hasFullAccess)
        engine.corrector?.memory = MemoryStore.load()
        engine.emojiHistory = MemoryStore.loadEmoji()
        engine.emojiHistory.skinTone = engine.settings.skinTone
        haptics.strength = Float(engine.settings.haptics.strength)
        if hasFullAccess {
            clipboard.catchUp()
            if !SettingsStore.fullAccessSeen { SettingsStore.fullAccessSeen = true }
        }
        if hasFullAccess, dictationTokens.isEmpty {
            dictationTokens = [
                Dictation.observe(.changed) { [weak self] in self?.dictationChanged() },
                Dictation.observeLevel { [weak self] in self?.suggestionBar.hear($0) },
            ]
            dictationChanged()
        }
        engine.suggestionsChanged()
        keyboardView.characterPreview = engine.settings.characterPreview
        if hasFullAccess { sources.reload() }
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
        engine.handle(.panel(nil), in: document)
        haptics.stop()
        TouchTrace.shared.flush()
        if let memory = engine.corrector?.memory { MemoryStore.save(memory, sharing: hasFullAccess) }
        MemoryStore.save(engine.emojiHistory)
        dictationTokens.forEach(Dictation.stopObserving)
        dictationTokens = []
    }

    override open func selectionDidChange(_ textInput: UITextInput?) {
        KeyboardHost.harvest()
        syncWithDocument()
    }

    override open func textDidChange(_ textInput: UITextInput?) {
        KeyboardHost.harvest()
        syncWithDocument()
    }

    private func syncWithDocument() {
        engine.update(InputTraits(textDocumentProxy))
        let known = engine.text.before.count
        let report = engine.documentChanged(document)
        if report == .changed { tellSources(.app) }
        TouchTrace.shared.record(report, host: textDocumentProxy.documentContextBeforeInput?.count ?? 0, known: known)
        render()
    }

    private var screenSize: CGSize {
        view.window?.windowScene?.screen.bounds.size ?? view.bounds.size
    }

    private var device: DeviceClass {
        let shortSide = min(screenSize.width, screenSize.height)
        guard traitCollection.userInterfaceIdiom == .pad else { return .phone }
        return shortSide >= 1000 ? .largePad : shortSide < 800 ? .compactPad : .pad
    }

    /// The iPhone Duo draws no globe under a third-party keyboard, yet its iOS 27.1 simulator says none is needed, so
    /// on its screens (the only iPhones over 440pt on the short side) Hex always offers the next keyboard.
    private var showsGlobe: Bool {
        needsInputModeSwitchKey || (device == .phone && Duo.isDuo(short: min(screenSize.width, screenSize.height)))
    }

    private var mic: MicButton.Phase {
        switch dictation.state {
        case .listening: .listening
        case .transcribing: .transcribing
        case .idle: micIsOn ? .on : .off
        }
    }

    /// What a source sees: the field's text as the keyboard knows it, with Full Access, outside password and code fields.
    private func tellSources(_ author: FieldUpdate.Author) {
        guard hasFullAccess, !textDocumentProxy.isPrivate, let field = textDocumentProxy.field else { return }
        sources.observe(FieldUpdate(
            field: field, before: engine.text.before, after: engine.text.after ?? "", by: author, traits: engine.traits,
            at: Date().timeIntervalSince1970
        ))
    }

    private var hint: String? {
        guard hasFullAccess, let field = textDocumentProxy.field else { return nil }
        return sources.hint(for: field)
    }

    private func render() {
        tellSources(.keyboard)
        let device = device
        let context = engine.layout(
            on: device, showsGlobe: showsGlobe, isLandscape: screenSize.width > screenSize.height,
            isOpen: Duo.isOpen(short: min(screenSize.width, screenSize.height))
        )
        let layout = Layouts.layout(for: context)
        var metrics = KeyboardMetrics.for(device, width: screenSize.width, height: screenSize.height, style: .current, oneHanded: context.oneHanded, split: context.isSplit)
        if device == .phone, !context.isLandscape { metrics = metrics.fitted(screen: screenSize.width, window: view.bounds.width) }
        let wanted = metrics.toolbar.showing(engine.panel, compact: engine.settings.compactPanels)
        let height = metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow)
        let ask = engine.panel == nil ? wanted.height : wanted.panelHeight
        let room = view.bounds.height
        metrics.toolbar = wanted
        if ask == toolbarHeightConstraint.constant, height == keyboardHeightConstraint.constant, room > 0 {
            if engine.panel != nil { metrics.toolbar = wanted.fitting(room - height) }
            metrics = metrics.filling(room - ask, rows: layout.rows.count, hasNumberRow: layout.hasNumberRow)
        }
        if toolbarHeightConstraint.constant != ask { toolbarHeightConstraint.constant = ask }
        keyboardView.menu = (context.menuKey(in: layout), context.menu, context.menuPick)
        keyboardView.update(layout: layout, signature: context.signature, metrics: metrics, faces: engine.faces(on: device), theme: theme)
        renderToolbar(metrics, device: device)
        suggestionBar.update(more: moreMenu(context))
        renderSuggestions()

        if keyboardHeightConstraint.constant != height {
            keyboardHeightConstraint.constant = height
            keysMinimumConstraint.constant = height
        }
    }

    /// The bar, or the open panel in its place, across the keys block.
    private func renderToolbar(_ metrics: KeyboardMetrics, device: DeviceClass) {
        let width = view.bounds.width
        let block = (minX: CGFloat(metrics.margin.leading + metrics.sideInset), maxX: width - CGFloat(metrics.margin.trailing + metrics.sideInset))
        if metrics.toolbar != toolbar {
            toolbar = metrics.toolbar
            view.setNeedsLayout()
        }
        let tools = Panel.allCases.filter { panels[$0] != nil && ($0 != .emoji || engine.settings.emojiKey && device != .phone) }
        let panel = engine.panel.flatMap { panels[$0] }
        panelView.open(panel)
        panelView.isHidden = panel == nil
        suggestionBar.isHidden = panel != nil
        panelView.block = block
        suggestionBar.block = block
        suggestionBar.screenInset = max((screenSize.width - width) / 2, 0)
        suggestionBar.topInset = metrics.topInset
        suggestionBar.toolbar = toolbar
        suggestionBar.maximumSlotWidth = device == .phone ? .infinity : 154.5
        suggestionBar.update(tools: tools, theme: theme)
        suggestionBar.update(mic: mic, listeningSince: dictation.since, notice: dictation.failure ?? hint, theme: theme)
        if panel != nil { panelView.show(query: engine.query, theme: theme, metrics: metrics) }
        keyboardView.deadTop = panel != nil ? max(metrics.topInset - Toolbar.keysReach, 0) : 0
    }

    /// The bar's More button, on every screen: the layouts holding 123 offers where there are any, then the next
    /// keyboard and Hex's settings.
    private func moreMenu(_ context: LayoutContext) -> UIMenu {
        let action = { (item: KeyboardEvent) in
            UIAction(title: item.title, image: UIImage(systemName: item.symbol), state: item == context.menuPick ? .on : .off) { [unowned self] _ in
                handle(item)
            }
        }
        let picks = context.layoutPicks
        return UIMenu(children: [UIMenu(options: .displayInline, children: picks.map(action))] + context.moreMenu.dropFirst(picks.count).map(action))
    }

    private func open(_ panel: Panel) {
        feedback(.other)
        handle(.panel(panel))
    }

    private var theme: KeyboardTheme {
        KeyboardTheme.current(for: traitCollection, appearance: textDocumentProxy.keyboardAppearance, settings: engine.settings)
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
        case .oneHanded(let hand), .pick(let hand):
            SettingsStore.set(hand, sharing: hasFullAccess)
        case .split(let split):
            SettingsStore.set(split, for: \.split, sharing: hasFullAccess)
        case .settings:
            open(HexLink.keyboard)
        case .nextKeyboard:
            advanceToNextInputMode()
        case .cursorLines:
            let margins = systemMinimumLayoutMargins
            engine.lineLayout = HostLayout(width: view.bounds.width - margins.leading - margins.trailing)
        default:
            break
        }
        if engine.handle(event, in: document) { render() }
    }

    /// Stops a dictation in progress, so what was heard is typed. Otherwise starts one: in place while the app keeps the
    /// microphone on, or by opening the app, since a keyboard can't use the microphone and iOS starts a recording only
    /// in an app in front.
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
        open(Dictation.Request(host: KeyboardHost.app(of: self)).url)
    }

    /// Opens a link from the keyboard. Apps can't be opened from a keyboard through public API, so this goes through
    /// the responder chain to the host's UIApplication, as voice keyboards do.
    private func open(_ url: URL) {
        var responder: UIResponder? = self
        while let next = responder {
            if let application = next as? UIApplication { return application.open(url) }
            responder = next.next
        }
    }

    /// The app listened, or stopped: type what it heard, once. A dictation without the app's microphone lock was left by
    /// an app that ended mid-dictation, so the mic starts a new one.
    private func dictationChanged() {
        var status = Dictation.status
        if let heard = status.heard {
            status.heard = nil
            Dictation.publish(status)
            engine.handle(.dictated(heard), in: document)
        }
        micIsOn = Dictation.micIsOn
        if status.state != .idle, !micIsOn { status.state = .idle }
        dictation = status
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

/// Links into Hex's app.
public enum HexLink {
    /// Opens Settings › Apps › Hex, where Full Access (under Keyboards) and Paste from Other Apps are.
    public static let settings = URL(string: "hexkeyboard://settings")!
    /// Opens Hex's app on its keyboard settings.
    public static let keyboard = URL(string: "hexkeyboard://keyboard")!
}
