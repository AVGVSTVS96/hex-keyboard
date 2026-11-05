import UIKit
import KeyboardStore
import KeyboardCore
import KeyboardEnglish
import KeyboardUI

open class FullKeyboardViewController: UIInputViewController {
    open var hapticsEnabled: Bool { hasFullAccess && engine.settings.haptics != .off }

    private let keyboardView = KeyboardView()
    private var dictation = Dictation.Status()
    private var micIsOn = false
    /// How much the app has recorded of the dictation it's making, in seconds.
    private var recorded: Double = 0
    private var observers: [Int32] = []
    /// Who this keyboard is to the app, new each time it appears: dictations you stop here are typed here.
    private var keyboard = UInt64.random(in: 1 ... .max)
    /// What the app told you about a dictation, or why copy or paste couldn't, until you tap it or a key.
    private var notice: String?
    /// The clipboard's tray is out of its button (docs/design.md, "The tools"), until one of its tools is used or a key
    /// is touched.
    private var trayOut = false
    private let suggestionBar = SuggestionBar()
    /// The record button in the bottom row, where Settings › Layout › Record Key puts it in the globe's place.
    private let keyMic = MicButton()
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
        panel.app = { [unowned self] in hostApp }
        panel.onCopied = { [unowned self] in clipboard.skip(changeCount: $0) }
        panel.onTurnOn = { [unowned self] in open(AppLink.settings) }
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
        panel.onTurnOn = { [unowned self] in open(AppLink.settings) }
        panel.changed = { [unowned self] in render() }
        panel.length = { [unowned self] in engine.settings.clipboardLength }
        panel.onTranscripts = { [unowned self] in open(.transcripts) }
        return panel
    }()
    private lazy var transcriptsPanel: TranscriptsPanel = {
        let panel = TranscriptsPanel()
        panel.fullAccess = { [unowned self] in hasFullAccess }
        panel.onPaste = { [unowned self] in
            feedback(.input)
            handle(.paste($0))
        }
        panel.onTurnOn = { [unowned self] in open(AppLink.settings) }
        panel.onClipboard = { [unowned self] in open(.clipboard) }
        return panel
    }()
    /// The panels this keyboard has, in the tools' order. GIFs need a KLIPY key built in.
    private lazy var panels: [Panel: PanelContent] = [.emoji: emojiPanel, .gif: gifPanel, .clipboard: clipboardPanel, .transcripts: transcriptsPanel].compactMapValues { $0 }
    private lazy var document = ProxyDocument { [unowned self] in textDocumentProxy }
    private var engine = TypingEngine()
    private var typingLog = TypingLog()
    private let memoryStore = MemoryStore()
    private lazy var toolbarHeightConstraint = toolbarView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keyboardHeightConstraint = keyboardView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keysMinimumConstraint = keyboardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
    private var deleteRepeat: DeleteRepeat?
    private let haptics = KeyHaptics()
    private let clipboard = ClipboardStore(backup: ClipboardStore.own)
    private let sources = Sources()
    private var hostApp: String?
    /// The field the keyboard is typing in (`documentIdentifier`), so dictations end with the field they were typed in,
    /// and the next keyboard in the same field goes on following them.
    private var field: String?

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
        suggestionBar.onTool = { [unowned self] in tool($0) }
        suggestionBar.onEdit = { [unowned self] in edit($0) }
        panelView.onClose = { [unowned self] in handle(.panel(nil)) }
        panelView.onClear = { [unowned self] in handle(.panel(engine.panel)) }
        suggestionBar.onNotice = { [unowned self] in
            if notice != nil { notice = nil } else { sources.dismissHint() }
            render()
        }
        sources.onHint = { [unowned self] in render() }
        suggestionBar.onCancel = { [unowned self] in
            feedback(.other)
            Dictation.send(.cancel)
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
        engine.corrector = Corrector(source: Lexicon.english, network: .current)
        engine.swipeModel = .english
        Task { [weak self] in
            let catalog = await Task.detached(priority: .userInitiated) { EmojiCatalog.english }.value
            self?.engine.emojiCatalog = catalog
            self?.engine.suggestionsChanged()
            self?.render()
        }
        keyboardView.resolve = { [unowned self] grid, point in engine.key(atX: point.x, y: point.y, in: grid) }
        keyboardView.onGrid = { [unowned self] grid in
            engine.use(grid)
            suggestionBar.keys = (grid.rows.first ?? []).map { (minX: $0.frame.x, maxX: $0.frame.x + $0.frame.width) }
            let keyed = grid.rows.joined().contains { $0.key.action == .dictate }
            suggestionBar.micInBar = !keyed
            keyMic.isHidden = !keyed
        }
        keyMic.addAction(UIAction { [unowned self] _ in suggestionBar.onMic() }, for: .touchUpInside)
        keyboardView.micKey = keyMic
        keyboardView.advance = { [unowned self] step in HostLayout.width(of: engine.character(crossedBy: step)) }
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
        isShown = true
        KeyboardHost.appeared()
        updateHost()
        keyboard = .random(in: 1 ... .max)
        memoryStore.refresh { [weak self] memory in
            self?.engine.corrector?.changeMemory { $0 = memory }
            self?.engine.suggestionsChanged()
            self?.render()
        }
        engine.emojiHistory = MemoryStore.loadEmoji()
        engine.emojiHistory.app = hostApp
        loadSettings()
        if hasFullAccess { clipboard.catchUp() }
        if observers.isEmpty {
            observers = [SettingsStore.observe { [weak self] in self?.settingsChanged() }]
            if hasFullAccess {
                observers += [
                    Dictation.observe(.appeared) { [weak self] keyboard in
                        guard let self, keyboard != self.keyboard else { return }
                        self.observers.forEach(Dictation.stopObserving)
                        self.observers = []
                    },
                    Dictation.observe(.changed) { [weak self] in self?.dictationChanged() },
                    Dictation.observeLevel { [weak self] level, recorded in
                        self?.recorded = recorded
                        self?.suggestionBar.hear(level, recorded: recorded)
                    },
                ]
                Dictation.send(.appeared, from: keyboard)
                dictationChanged()
            }
        }
        if hasFullAccess { sources.reload() }
        syncWithDocument()
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateHost()
        syncWithDocument()
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
        isShown = false
        engine.endSession()
        keepDictations()
        Dictation.keep(engine.takeDraft(), in: field)
        field = nil
        engine.handle(.panel(nil), in: document)
        trayOut = false
        haptics.stop()
        TouchTrace.shared.flush()
        saveMemory()
        saveTyping()
        MemoryStore.save(engine.emojiHistory)
        if hasFullAccess { MemoryStore.queue.async { Backup.sync(Backup.keyboard + Backup.group) } }
        observers.forEach(Dictation.stopObserving)
        observers = []
    }

    private func loadSettings() {
        engine.settings = SettingsStore.load(sharing: hasFullAccess)
        engine.emojiHistory.skinTone = engine.settings.skinTone
        haptics.strength = Float(engine.settings.haptics.strength)
        keyboardView.characterPreview = engine.settings.characterPreview
        engine.suggestionsChanged()
    }

    /// The app kept new settings while the keyboard is up, as beside it on the open iPhone Duo.
    private func settingsChanged() {
        loadSettings()
        if hapticsEnabled { haptics.start() }
        render()
    }

    override open func selectionDidChange(_ textInput: UITextInput?) {
        updateHost()
        syncWithDocument()
    }

    override open func textDidChange(_ textInput: UITextInput?) {
        updateHost()
        syncWithDocument()
    }

    private func updateHost() {
        let app = KeyboardHost.app(of: self)
        guard app != hostApp else { return }
        engine.changeApp(app)
        hostApp = app
        engine.emojiHistory.app = app
        engine.suggestionsChanged()
    }

    private func syncWithDocument() {
        engine.update(InputTraits(textDocumentProxy))
        if textDocumentProxy.field != field {
            field = textDocumentProxy.field
            engine.leaveField()
            if let kept = Dictation.takeDraft() {
                if let field, kept.field == field { engine.resume(kept.draft) } else { Dictation.leave(kept.draft.outcomes(sent: false)) }
            }
            keepDictations()
        }
        let known = engine.text.before.count
        let report = engine.documentChanged(document)
        if report == .changed { tellSources(.app) }
        if report == .changed, engine.text.isEmpty {
            saveMemory()
            saveTyping()
            keepDictations()
        }
        TouchTrace.shared.record(report, host: textDocumentProxy.documentContextBeforeInput?.count ?? 0, known: known)
        render()
    }

    /// When the keyboard goes away and when a message is sent, so what was learned outlives the keyboard being ended.
    private func saveMemory() {
        if let memory = engine.corrector?.memory { memoryStore.save(memory, sharing: hasFullAccess) }
    }

    private func keepDictations() {
        Dictation.leave(engine.takeDictations())
    }

    private func saveTyping() {
        noteTyping()
        TypingStats.save(typingLog.take(), sharing: hasFullAccess)
    }

    /// Notes what typing did, in the hour and app it happened in: the engine's tally changes only as you type.
    private func noteTyping() {
        let now = Date.now
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: now)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        typingLog.note(engine.tally, at: ProcessInfo.processInfo.systemUptime, day: day, hour: parts.hour ?? 0, app: hostApp ?? "")
    }

    private var screenSize: CGSize {
        view.window?.windowScene?.screen.bounds.size ?? view.bounds.size
    }

    private var device: DeviceClass {
        DeviceClass(isPad: traitCollection.userInterfaceIdiom == .pad, shortSide: min(screenSize.width, screenSize.height))
    }

    /// The iPhone Duo draws no globe under a third-party keyboard, yet its iOS 27.1 simulator says none is needed, so
    /// on its screens (the only iPhones over 440pt on the short side) iikb always offers the next keyboard.
    private var showsGlobe: Bool {
        needsInputModeSwitchKey || (device == .phone && Duo.isDuo(short: min(screenSize.width, screenSize.height)))
    }

    private var mic: MicButton.Phase {
        if dictation.listening { return .listening }
        if !dictation.writing.isEmpty { return .writing }
        return micIsOn ? .on : .off
    }

    /// What a source sees: the field's text as the keyboard knows it, with Full Access, outside password and code fields.
    private func tellSources(_ author: FieldUpdate.Author) {
        guard hasFullAccess, !textDocumentProxy.isPrivate, let field = textDocumentProxy.field else { return }
        sources.observe(FieldUpdate(
            field: field, before: engine.text.before, after: engine.text.after ?? "", by: author, traits: engine.traits,
            at: Date().timeIntervalSince1970, app: hostApp
        ))
    }

    private var hint: String? {
        guard hasFullAccess, let field = textDocumentProxy.field else { return nil }
        return sources.hint(for: field, app: hostApp)
    }

    private func render() {
        guard isShown else { return }
        tellSources(.keyboard)
        noteTyping()
        let device = device
        let screen = Size(width: screenSize.width, height: screenSize.height)
        let keys = KeyboardGeometry(engine.layout(on: device, screen: screen, showsGlobe: showsGlobe), screen: screen, window: view.bounds.width, style: .current)
        let (context, layout, height) = (keys.context, keys.layout, keys.height)
        var metrics = keys.metrics
        let wanted = metrics.toolbar.showing(engine.panel, compact: engine.settings.compactPanels)
        let ask = engine.panel == nil ? wanted.height : wanted.panelHeight
        let room = view.bounds.height
        metrics.toolbar = wanted
        if ask == toolbarHeightConstraint.constant, height == keyboardHeightConstraint.constant, room > 0 {
            if engine.panel != nil { metrics.toolbar = wanted.fitting(room - height) }
            metrics = metrics.filling(room - ask, rows: layout.rows.count, hasNumberRow: layout.hasNumberRow)
        }
        if toolbarHeightConstraint.constant != ask { toolbarHeightConstraint.constant = ask }
        keyboardView.slidesToType = engine.settings.slideToType && engine.panel == nil
        keyboardView.menu = (context.menuKeys(in: layout), context.menu, context.menuPick)
        keyboardView.update(layout: layout, signature: context.signature, metrics: metrics, faces: engine.faces(on: device), theme: theme)
        renderToolbar(metrics, device: device)
        let more = context.showsMoreButton ? [context.menuPick] + context.layoutPicks + context.moreMenu : []
        if more != shownMore {
            shownMore = more
            suggestionBar.update(more: more.isEmpty ? nil : moreMenu(context))
        }
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
        let tools = Panel.tools.filter { panels[$0] != nil && ($0 != .emoji || engine.settings.emojiKey && device != .phone) }
        let panel = engine.panel.flatMap { panels[$0] }
        panelView.open(panel)
        panelView.isHidden = panel == nil
        suggestionBar.isHidden = panel != nil
        panelView.block = block
        suggestionBar.toolbar = toolbar
        suggestionBar.maximumSlotWidth = device == .phone ? .infinity : 154.5
        suggestionBar.update(tools: tools, theme: theme)
        suggestionBar.update(edits: trayOut && panel == nil ? edits : nil, theme: theme)
        suggestionBar.update(mic: mic, recorded: recorded, saved: dictation.writing, waitingFor: dictation.waiting, notice: notice ?? hint, theme: theme)
        keyMic.show(mic, theme: theme)
        if panel != nil { panelView.show(query: engine.query, theme: theme, metrics: metrics) }
    }

    /// The bar's More button, on every screen: the layouts holding 123 offers where there are any, then the next
    /// keyboard and iikb's settings.
    private func moreMenu(_ context: LayoutContext) -> UIMenu {
        let action = { [unowned self] (item: KeyboardEvent) in
            UIAction(title: item.title, image: UIImage(systemName: item.symbol), state: item == context.menuPick ? .on : .off) { _ in
                self.handle(item)
            }
        }
        let picks = context.layoutPicks
        return UIMenu(children: [UIMenu(options: .displayInline, children: picks.map(action))] + context.moreMenu.dropFirst(picks.count).map(action))
    }

    private func open(_ panel: Panel) {
        feedback(.other)
        handle(.panel(panel))
    }

    /// A tool in the bar opens its panel, but the clipboard's lets out its tray first.
    private func tool(_ panel: Panel) {
        guard panel == .clipboard else { return open(panel) }
        feedback(.other)
        trayOut.toggle()
        render()
    }

    /// What the tray can do now. Without Full Access a keyboard can't reach the clipboard, so every edit is offered and
    /// a tap says why it can't.
    private var edits: SuggestionBar.Edits {
        guard hasFullAccess else { return .init(cut: true, copy: true, paste: true) }
        let selected = !selection.isEmpty
        return .init(cut: selected, copy: selected, paste: UIPasteboard.general.hasStrings)
    }

    private var selection: String {
        let selected = textDocumentProxy.selectedText ?? ""
        return selected.isEmpty ? engine.text.selected : selected
    }

    /// One of the tray's tools, after which it tucks back in. What you copy or cut joins the clipboard's history.
    private func edit(_ edit: SuggestionBar.Edit) {
        trayOut = false
        switch edit {
        case .history: return open(.clipboard)
        case .transcripts: return open(.transcripts)
        case .cut, .copy, .paste: feedback(.other)
        }
        guard hasFullAccess else {
            notice = "Copy and paste need Allow Full Access in Settings › Apps › iikb › Keyboards"
            return render()
        }
        if edit == .paste {
            guard let text = UIPasteboard.general.string else {
                notice = "To paste, set Settings › Apps › iikb › Paste from Other Apps to Allow"
                return render()
            }
            return handle(.paste(text))
        }
        let text = selection
        if !text.isEmpty {
            UIPasteboard.general.string = text
            clipboard.catchUp()
            if edit == .cut { engine.perform(.delete, in: document) }
        }
        render()
    }

    private var theme: KeyboardTheme {
        KeyboardTheme.current(for: traitCollection, appearance: textDocumentProxy.keyboardAppearance, settings: engine.settings)
    }

    private var ranking = false
    /// From viewWillAppear to viewWillDisappear. Once the keyboard goes away the text document proxy is torn down while
    /// this controller lives on, and reading it then crashes, so a ranking job or load that finishes later draws nothing.
    private var isShown = false
    /// What the More menu was made from, so it's made again only when that changes.
    private var shownMore: [KeyboardEvent] = []

    private func renderSuggestions() {
        guard isShown else { return }
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
            if notice != nil || trayOut {
                notice = nil
                trayOut = false
                render()
            }
        case .up(let key) where key.action == .delete:
            deleteRepeat = nil
        case .trigger(let key) where key.action == .dismiss:
            return dismissKeyboard()
        case .trigger(let key) where key.action == .nextKeyboard:
            return advanceToNextInputMode()
        case .trigger(let key) where key.action == .dictate:
            return toggleVoice()
        case .type:
            TouchTrace.shared.mark("typed")
        case .oneHanded(let hand), .pick(let hand):
            SettingsStore.set(hand, sharing: hasFullAccess)
        case .split(let split):
            SettingsStore.set(split, for: \.split, sharing: hasFullAccess)
        case .settings:
            open(AppLink.keyboard)
        case .panel:
            trayOut = false
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

    /// Stops a dictation in progress, so what was heard is typed. Otherwise starts one, even while the last is still
    /// being written: in place while the app keeps the microphone on, or by opening the app, since a keyboard can't use
    /// the microphone and iOS starts a recording only in an app in front.
    private func toggleVoice() {
        guard hasFullAccess else {
            notice = "Voice needs Allow Full Access in Settings › Apps › iikb › Keyboards"
            return render()
        }
        updateHost()
        trayOut = false
        Dictation.host = hostApp
        if dictation.listening { return Dictation.send(.finish, from: keyboard) }
        notice = nil
        micIsOn = Dictation.micIsOn
        if micIsOn { return Dictation.send(.start) }
        render()
        open(Dictation.Request(host: hostApp).url)
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

    /// The app listened, or left notes: types what you said in this keyboard, once each, and says so when what you
    /// said in a keyboard that has since closed isn't typed here. A status without the app's microphone lock was left by
    /// an app that ended mid-dictation, so the mic starts a new one.
    private func dictationChanged() {
        var status = Dictation.status
        micIsOn = Dictation.micIsOn
        if !micIsOn { (status.listening, status.writing, status.waiting) = (false, [], nil) }
        dictation = status
        recorded = Dictation.level.recorded
        for (file, note) in Dictation.notes where Dictation.take(file) {
            switch note {
            case .heard(let text, let plain, let keyboard, let id) where keyboard == nil || keyboard == self.keyboard:
                engine.handle(.dictated(text, plain: plain, id: textDocumentProxy.isPrivate ? nil : id?.uuidString), in: document)
            case .heard:
                notice = "Not typed here: it’s in iikb › Transcripts"
            case .notice(let notice):
                self.notice = notice
            }
        }
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
