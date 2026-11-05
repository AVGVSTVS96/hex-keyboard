import UIKit
import KeyboardCore

/// Apple's three suggestions with the word's emoji (as many as fit, and the rest a swipe left away), a round mic at the
/// right end that starts and stops dictation, and the tools at the left end, all placed on the top row's keys by
/// `BarLayout`. While the app listens, the mic grows into a red capsule over the suggestions holding the time so far and
/// the waveform of your voice, and lets out a cancel button before it. Once you stop, dictations still waiting for the
/// model stack as cards in its place.
final class SuggestionBar: UIView {
    var onSelect: (Suggestion) -> Void = { _ in }
    var onEmoji: (String) -> Void = { _ in }
    var onMic: () -> Void = {}
    var onCancel: () -> Void = {}
    var onNotice: () -> Void = {}
    var onTool: (Panel) -> Void = { _ in }
    var maximumSlotWidth = CGFloat.infinity { didSet { setNeedsLayout() } }
    /// The top row's keys, left to right, as their edges.
    var keys: [(minX: Double, maxX: Double)] = [] {
        didSet { if !keys.elementsEqual(oldValue, by: ==) { setNeedsLayout() } }
    }
    var toolbar = KeyboardMetrics.phone(width: 390).toolbar { didSet { if toolbar != oldValue { setNeedsLayout() } } }
    /// Whether the mic sits at the bar's right, or in the bottom row (Settings › Layout › Record Key), where the bar
    /// has none and the recording runs as the bar's own waveform.
    var micInBar = true {
        didSet {
            guard micInBar != oldValue else { return }
            mic.isHidden = !micInBar
            waveform.mask = micInBar ? capsule : nil
            setNeedsLayout()
        }
    }

    private let slots = (0..<3).map { SuggestionSlot(index: $0) }
    private let dividers = (0..<2).map { _ in UIView() }
    private var emoji: [EmojiPick] = []
    private let strip = ButtonScrollView()
    private var tools: [(panel: Panel, button: BarButton)] = []
    private let more = BarButton("More", draw: Panel.moreGlyph)
    private let mic = MicButton()
    private let cancel = CancelButton()
    private let waveform = Waveform()
    /// The waveform's mask in the bar: the mic's own shape, moved with it, so the recording shows only inside the red.
    private let capsule = UIView()
    private let stack = PendingStack()
    private let notice = UILabel()
    private var emojiBeside = false
    private var enabled = true
    private var noticed = false
    private var theme = KeyboardTheme.lightCurrent

    override init(frame: CGRect) {
        super.init(frame: frame)
        for slot in slots {
            slot.addAction(UIAction { [unowned self, unowned slot] _ in
                if let suggestion = slot.suggestion { onSelect(suggestion) }
            }, for: .touchUpInside)
            slot.onHighlight = { [unowned self] in refreshDividers() }
            addSubview(slot)
        }
        dividers.forEach(addSubview)
        more.showsMenuAsPrimaryAction = true
        more.isHidden = true
        more.accessibilityIdentifier = "hex.more"
        addSubview(more)
        strip.alwaysBounceHorizontal = false
        strip.accessibilityIdentifier = "hex.suggestion.emoji"
        addSubview(strip)
        mic.addAction(UIAction { [unowned self] _ in onMic() }, for: .touchUpInside)
        cancel.addAction(UIAction { [unowned self] _ in onCancel() }, for: .touchUpInside)
        mic.breathes = true
        capsule.backgroundColor = .black
        capsule.layer.cornerCurve = .continuous
        waveform.mask = capsule
        for view in [stack, cancel, mic, waveform] { addSubview(view) }
        notice.isHidden = true
        notice.font = .systemFont(ofSize: 15)
        notice.textAlignment = .center
        notice.adjustsFontSizeToFitWidth = true
        notice.minimumScaleFactor = 0.7
        notice.lineBreakMode = .byTruncatingTail
        notice.accessibilityIdentifier = "hex.notice"
        notice.isUserInteractionEnabled = true
        notice.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapNotice)))
        addSubview(notice)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ suggestions: [Suggestion], emoji: [String], enabled: Bool, theme: KeyboardTheme) {
        self.enabled = enabled
        self.theme = theme
        for (index, slot) in slots.enumerated() {
            slot.configure(suggestions.indices.contains(index) ? suggestions[index] : nil, theme: theme)
        }
        if emoji != self.emoji.map(\.emoji) {
            self.emoji.forEach { $0.removeFromSuperview() }
            self.emoji = emoji.enumerated().map { index, emoji in
                let pick = EmojiPick(emoji: emoji, index: index)
                pick.addAction(UIAction { [unowned self] _ in onEmoji(emoji) }, for: .touchUpInside)
                pick.onHighlight = { [unowned self] in refreshDividers() }
                strip.addSubview(pick)
                return pick
            }
            strip.contentOffset = .zero
            setNeedsLayout()
        }
        self.emoji.forEach { $0.theme = theme }
        dividers.forEach { $0.backgroundColor = theme.candidateDivider.ui }
        more.theme = theme
        refresh()
    }

    /// `notice` (why voice couldn't start, or a source's hint) stands in for the suggestions. Tapping it dismisses it.
    /// `recorded` is how many seconds the app has recorded, for the time beside the waveform; `saved` are the lengths of
    /// the dictations recorded and still to be written, and `waitingFor` what they wait for while the model gets ready.
    func update(mic: MicButton.Phase, recorded: Double, saved: [Double], waitingFor: String?, notice: String?, theme: KeyboardTheme) {
        let grows = (mic == .listening) != (self.mic.phase == .listening)
        if mic == .listening { cancel.isHidden = false }
        self.mic.show(mic, theme: theme)
        cancel.paint(theme)
        waveform.show(mic, recorded: recorded, saved: waitingFor == nil ? 0 : saved.count, tint: micInBar ? .white : theme.label.ui)
        stack.show(mic, saved: saved, waitingFor: waitingFor, theme: theme)
        self.notice.text = notice
        self.notice.textColor = theme.candidate.ui
        noticed = notice != nil
        refresh()
        guard grows else { return }
        setNeedsLayout()
        guard window != nil else {
            cancel.isHidden = mic != .listening
            return
        }
        morph(growing: mic == .listening, { self.layoutIfNeeded() }) { _ in
            if self.mic.phase != .listening { self.cancel.isHidden = true }
        }
    }

    /// The tools at the bar's left, where there's no pill row for them.
    func update(tools panels: [Panel], theme: KeyboardTheme) {
        if panels != tools.map(\.panel) {
            tools.forEach { $0.button.removeFromSuperview() }
            tools = panels.map { panel in
                let tool = BarButton(panel.title, draw: panel.icon)
                tool.accessibilityIdentifier = "hex.tool.\(panel)"
                tool.addAction(UIAction { [unowned self] _ in onTool(panel) }, for: .touchUpInside)
                addSubview(tool)
                return (panel, tool)
            }
            setNeedsLayout()
        }
        tools.forEach { $0.button.theme = theme }
    }

    /// The More button at the far left, before the tools.
    func update(more menu: UIMenu?) {
        more.menu = menu
        if more.isHidden != (menu == nil) {
            more.isHidden = menu == nil
            setNeedsLayout()
        }
    }

    func hear(_ level: Float, recorded: Double) {
        waveform.hear(level, recorded: recorded)
        mic.hear(level)
    }

    /// While you dictate, the cancel button sits in its place, before the recording. Otherwise it waits tucked at half
    /// its size behind the mic, so as the mic grows it comes out from under the capsule's leading edge and rides out to
    /// its place on the same spring, and tucks back in as the capsule shrinks; it's hidden only once it's behind. Where
    /// the mic is the Record Key, it fades in and out in its place.
    private func placeCancel(_ place: CGRect, behind mic: CGRect?) {
        let listening = self.mic.phase == .listening
        let tucked = listening ? nil : mic
        cancel.bounds.size = place.size
        cancel.center = CGPoint(x: (tucked ?? place).midX, y: (tucked ?? place).midY)
        let scale: CGFloat = listening ? 1 : mic == nil ? 0.9 : 0.5
        cancel.transform = CGAffineTransform(scaleX: scale, y: scale)
        cancel.alpha = listening || mic != nil ? 1 : 0
    }

    @objc private func tapNotice() {
        onNotice()
    }

    private var recording: Bool { mic.phase == .listening || mic.phase == .writing }

    private func refresh() {
        let quiet = !enabled || noticed || recording
        notice.isHidden = !noticed || recording
        cancel.shows = mic.phase == .listening
        slots.forEach { $0.isHidden = quiet }
        strip.isHidden = quiet || emoji.isEmpty
        emoji.forEach { $0.isHidden = quiet }
        if !emoji.isEmpty, !emojiBeside { slots[slots.count - 1].isHidden = true }
        refreshDividers()
    }

    /// A divider shows only between two things shown without a pill.
    private func refreshDividers() {
        func hidesDivider(_ index: Int, leading: Bool) -> Bool {
            if index == slots.count - 1, !emojiBeside, let pick = leading ? emoji.first : emoji.last { return pick.isHidden || pick.isHighlighted }
            return slots[index].isHidden || slots[index].showsPill
        }
        for (index, divider) in dividers.enumerated() {
            divider.isHidden = hidesDivider(index, leading: false) || hidesDivider(index + 1, leading: true)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        guard !keys.isEmpty else { return }
        let layout = BarLayout(toolbar, keys: keys, tools: tools.count, more: !more.isHidden, mic: micInBar, maximumSlot: maximumSlotWidth)
        let micPlace = CGRect(mic.phase == .listening ? layout.recording : layout.mic ?? layout.recording)
        mic.bounds.size = micPlace.size
        mic.center = CGPoint(x: micPlace.midX, y: micPlace.midY)
        placeCancel(CGRect(layout.cancel), behind: layout.mic.map { CGRect($0) })
        let around = (layout.pitch - toolbar.button) / 2
        let reach = UIEdgeInsets(
            top: -(toolbar.top + (toolbar.bar - toolbar.button) / 2), left: -around,
            bottom: -(toolbar.bar - toolbar.button) / 2, right: -around
        )
        for (tool, frame) in zip(tools, layout.tools) { tool.button.place(CGRect(frame), glyph: toolbar.glyph, reach: reach) }
        if let frame = layout.more { more.place(CGRect(frame), glyph: toolbar.glyph, reach: reach) }
        for (slot, frame) in zip(slots, layout.slots) {
            let minX = CGFloat(frame.x).rounded(scale: scale), maxX = CGFloat(frame.x + frame.width).rounded(scale: scale)
            slot.frame = CGRect(x: minX, y: frame.y, width: maxX - minX, height: frame.height)
        }
        if layout.emojiBeside != emojiBeside {
            emojiBeside = layout.emojiBeside
            refresh()
        }
        let place = CGRect(layout.emoji)
        strip.frame = place
        let pitch = BarLayout.emojiPitch
        let total = pitch * CGFloat(emoji.count)
        let left = max((place.width - total) / 2, 0)
        for (index, pick) in emoji.enumerated() {
            let minX = (left + CGFloat(index) * pitch).rounded(scale: scale)
            let glyph = CGRect(x: minX, y: 0, width: (left + CGFloat(index + 1) * pitch).rounded(scale: scale) - minX, height: place.height)
            let frameMinX = index == 0 ? 0 : glyph.minX
            let frameMaxX = index == emoji.count - 1 ? max(place.width, glyph.maxX) : glyph.maxX
            pick.frame = CGRect(x: frameMinX, y: 0, width: frameMaxX - frameMinX, height: place.height)
            pick.glyph = glyph.offsetBy(dx: -pick.frame.minX, dy: 0)
        }
        strip.contentSize = CGSize(width: max(total, place.width), height: place.height)
        let row = CGRect(x: layout.minX, y: toolbar.top, width: layout.maxX - layout.minX, height: toolbar.bar)
        for (index, divider) in dividers.enumerated() {
            divider.frame = CGRect(x: slots[index].frame.maxX - 0.5, y: row.midY - 14, width: 1, height: 28)
        }
        let span = CGRect(layout.recording)
        if micInBar {
            waveform.frame = span
            waveform.insets = (leading: 12, trailing: span.height)
            capsule.frame = micPlace.offsetBy(dx: -span.minX, dy: -span.minY)
            capsule.layer.cornerRadius = micPlace.height / 2
        } else {
            waveform.frame = CGRect(x: span.minX, y: row.minY, width: span.width, height: row.height)
            waveform.insets = (leading: 0, trailing: 0)
        }
        let waits = layout.mic.map { CGFloat($0.x) - 6 } ?? span.maxX
        stack.frame = CGRect(x: span.minX, y: row.minY, width: max(waits - span.minX, 0), height: row.height)
        notice.frame = row.insetBy(dx: 4, dy: 0)
    }
}

/// One emoji in the bar's last slot: a tap types it in place of the word. The outer ones also take the slot's
/// margins, so the whole slot answers a tap.
private final class EmojiPick: UIControl {
    let emoji: String
    var glyph = CGRect.zero { didSet { setNeedsLayout() } }
    var onHighlight: () -> Void = {}
    var theme = KeyboardTheme.lightCurrent { didSet { pill.backgroundColor = theme.candidatePill.ui } }
    private let label = UILabel()
    private let pill = UIView()

    init(emoji: String, index: Int) {
        self.emoji = emoji
        super.init(frame: .zero)
        accessibilityIdentifier = "hex.suggestion.emoji.\(index)"
        accessibilityLabel = emoji
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        pill.isUserInteractionEnabled = false
        pill.isHidden = true
        label.text = emoji
        label.font = .systemFont(ofSize: 24)
        label.textAlignment = .center
        addSubview(pill)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            pill.isHidden = !isHighlighted
            onHighlight()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pill.frame = glyph.insetBy(dx: 8 / 3, dy: 2)
        pill.layer.cornerRadius = min(pill.bounds.width, pill.bounds.height) / 2
        label.frame = glyph
    }
}

/// A suggestion: the middle one, which a space would type, in the label color and medium weight, the others in the
/// secondary color.
private final class SuggestionSlot: UIControl {
    private(set) var suggestion: Suggestion?
    var onHighlight: () -> Void = {}
    private let index: Int
    private let label = UILabel()
    private let pill = UIView()
    private var theme = KeyboardTheme.lightCurrent

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        accessibilityIdentifier = "hex.suggestion.\(index)"
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        pill.isUserInteractionEnabled = false
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 17, weight: index == 1 ? .medium : .regular)
        addSubview(pill)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Apple's pills stop 8px (@3x) short of each slot's edge, so neighbors sit 16px apart and the outer ones keep
    /// clear of the keyboard's edge (iOS 27 simulator, held suggestions).
    private static let pillInset: CGFloat = 8 / 3

    var showsPill: Bool { suggestion != nil && (suggestion?.kind == .correction || isHighlighted) }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            refresh()
            onHighlight()
        }
    }

    func configure(_ suggestion: Suggestion?, theme: KeyboardTheme) {
        self.suggestion = suggestion
        self.theme = theme
        label.text = suggestion?.title
        accessibilityLabel = suggestion?.text
        refresh()
        setNeedsLayout()
    }

    private func refresh() {
        pill.isHidden = !showsPill
        pill.backgroundColor = theme.candidatePill.ui
        label.textColor = showsPill ? theme.candidateHighlighted.ui : index == 1 ? theme.label.ui : theme.candidate.ui
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pill.frame = bounds.insetBy(dx: Self.pillInset, dy: 2)
        pill.layer.cornerRadius = pill.bounds.height / 2
        guard let font = label.font else { return }
        let baseline = (bounds.midY + font.capHeight / 2).rounded(scale: traitCollection.displayScale)
        let width = min(label.intrinsicContentSize.width, bounds.width - 8)
        label.frame = CGRect(x: (bounds.width - width) / 2, y: baseline - font.ascender, width: width, height: font.lineHeight)
    }
}
