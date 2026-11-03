import UIKit
import KeyboardCore

/// Apple's three suggestions with the word's emoji (as many as fit, and the rest a swipe left away), a round mic at the
/// right end that starts and stops dictation, and the tools at the left end, all placed by `BarLayout`. While the app
/// listens, the suggestions give way to a waveform of your voice and the time so far.
final class SuggestionBar: UIView {
    var onSelect: (Suggestion) -> Void = { _ in }
    var onEmoji: (String) -> Void = { _ in }
    var onMic: () -> Void = {}
    var onMicHold: () -> Void = {}
    var onNotice: () -> Void = {}
    var onTool: (Panel) -> Void = { _ in }
    var maximumSlotWidth = CGFloat.infinity { didSet { setNeedsLayout() } }
    /// The keys block's edges.
    var block = (minX: CGFloat(0), maxX: CGFloat(0)) { didSet { if block != oldValue { setNeedsLayout() } } }
    /// How far the screen reaches past each side of the keyboard's window, and the gap from the bar to the keys.
    var screenInset = CGFloat(0) { didSet { if screenInset != oldValue { setNeedsLayout() } } }
    var topInset = CGFloat(0) { didSet { if topInset != oldValue { setNeedsLayout() } } }
    var toolbar = KeyboardMetrics.phone(width: 390).toolbar { didSet { if toolbar != oldValue { setNeedsLayout() } } }

    private let slots = (0..<3).map { SuggestionSlot(index: $0) }
    private let dividers = (0..<2).map { _ in UIView() }
    private var emoji: [EmojiPick] = []
    private let strip = ButtonScrollView()
    private var tools: [ToolButton] = []
    private let more = UIButton(type: .system)
    private let mic = MicButton()
    private let waveform = Waveform()
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
        more.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        more.transform = CGAffineTransform(rotationAngle: .pi / 2)
        more.showsMenuAsPrimaryAction = true
        more.isHidden = true
        more.accessibilityIdentifier = "hex.more"
        more.accessibilityLabel = "More"
        addSubview(more)
        strip.alwaysBounceHorizontal = false
        strip.accessibilityIdentifier = "hex.suggestion.emoji"
        addSubview(strip)
        mic.addAction(UIAction { [unowned self] _ in onMic() }, for: .touchUpInside)
        mic.onHold = { [unowned self] in onMicHold() }
        addSubview(waveform)
        addSubview(mic)
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
        more.tintColor = theme.label.ui
        refresh()
    }

    /// `notice` (why voice couldn't start, or a source's hint) stands in for the suggestions. Tapping it dismisses it.
    /// `listeningSince` is when the app started listening, for the time beside the waveform; `saved` are the lengths of
    /// the dictations recorded and still to be written, and `waitingFor` what they wait for while the model gets ready.
    func update(mic: MicButton.Phase, listeningSince: Date?, saved: [Double], waitingFor: String?, notice: String?, theme: KeyboardTheme) {
        self.mic.show(mic, theme: theme)
        waveform.show(mic, since: listeningSince, saved: saved, waitingFor: waitingFor, theme: theme)
        self.notice.text = notice
        self.notice.textColor = theme.candidate.ui
        noticed = notice != nil
        refresh()
    }

    /// The tools at the bar's left, where there's no pill row for them.
    func update(tools panels: [Panel], theme: KeyboardTheme) {
        if panels != tools.map(\.panel) {
            tools.forEach { $0.removeFromSuperview() }
            tools = panels.map { panel in
                let tool = ToolButton(panel: panel)
                tool.addAction(UIAction { [unowned self] _ in onTool(panel) }, for: .touchUpInside)
                addSubview(tool)
                return tool
            }
            setNeedsLayout()
        }
        tools.forEach { $0.theme = theme }
    }

    /// The More button at the far left, before the tools, its dots upright.
    func update(more menu: UIMenu?) {
        more.menu = menu
        if more.isHidden != (menu == nil) {
            more.isHidden = menu == nil
            setNeedsLayout()
        }
    }

    func hear(_ level: Float) {
        waveform.hear(level)
    }

    @objc private func tapNotice() {
        onNotice()
    }

    private var recording: Bool { mic.phase == .listening || mic.phase == .writing }

    private func refresh() {
        let quiet = !enabled || noticed || recording
        notice.isHidden = !noticed || recording
        waveform.isHidden = !recording
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

    /// The bar's bottom edge goes nowhere, so a reach for the top row never picks a suggestion.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        point.y < bounds.height - Toolbar.deadEdge && super.point(inside: point, with: event)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        let layout = BarLayout(
            toolbar, width: bounds.width, screenInset: screenInset, block: (block.minX, block.maxX), topInset: topInset,
            tools: tools.count, more: !more.isHidden, emoji: emoji.count, maximumSlot: maximumSlotWidth
        )
        mic.frame = CGRect(layout.mic)
        for (tool, frame) in zip(tools, layout.tools) { tool.frame = CGRect(frame) }
        if let cell = layout.more.map({ CGRect($0) }) {
            more.bounds = CGRect(x: 0, y: 0, width: cell.height, height: cell.width)
            more.center = CGPoint(x: cell.midX, y: cell.midY)
        }
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
        waveform.frame = row.insetBy(dx: 4, dy: 0)
        notice.frame = row.insetBy(dx: 4, dy: 0)
    }
}

/// The bar's mic: a round button, white on dark and black on light, with a green dot while the app keeps the
/// microphone on, a red stop button while it listens, and a spinner for its glyph while the app writes a dictation
/// down, when a tap still starts the next one. Tap to start or stop, hold to turn the microphone off.
final class MicButton: UIControl {
    enum Phase { case off, on, listening, writing }

    var onHold: () -> Void = {}
    private(set) var phase = Phase.off
    private let circle = UIView()
    private let glyph = UIImageView()
    private let dot = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var theme = KeyboardTheme.lightCurrent

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "hex.mic"
        isAccessibilityElement = true
        accessibilityTraits = .button
        for view in [circle, glyph, dot, spinner] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        glyph.contentMode = .center
        dot.backgroundColor = UIColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
        hold.minimumPressDuration = 0.5
        addGestureRecognizer(hold)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { refresh() } }
    }

    func show(_ phase: Phase, theme: KeyboardTheme) {
        self.phase = phase
        self.theme = theme
        accessibilityLabel = phase == .listening ? "Stop Dictating" : "Dictate"
        accessibilityValue = switch phase {
        case .on: "Mic On"
        case .writing: "Writing"
        case .off, .listening: nil
        }
        refresh()
    }

    private func refresh() {
        let recording = phase == .listening
        let name = recording ? "stop.fill" : "waveform"
        glyph.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: recording ? 14 : 20, weight: .semibold))
        glyph.tintColor = recording ? .white : theme.micGlyph.ui
        glyph.isHidden = phase == .writing
        circle.backgroundColor = recording ? theme.record.ui : theme.mic.ui
        circle.alpha = isHighlighted ? 0.7 : 1
        dot.isHidden = phase != .on
        spinner.color = theme.micGlyph.ui
        if phase == .writing { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        cancelTracking(with: nil)
        isHighlighted = false
        onHold()
    }

    /// The circle is smaller than a fingertip; taps a little around it still reach it.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -4).contains(point)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        circle.frame = bounds
        circle.layer.cornerRadius = bounds.width / 2
        glyph.frame = bounds
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        spinner.transform = CGAffineTransform(scaleX: 16 / 20, y: 16 / 20)
        let side: CGFloat = 6
        dot.frame = CGRect(x: bounds.maxX - side - bounds.width * 0.08, y: bounds.width * 0.08, width: side, height: side)
        dot.layer.cornerRadius = side / 2
    }
}

/// The suggestions' place while the app listens: the time so far, then bars that trace your voice, newest on the
/// right, each as bright as it was loud, the older ones fading out to the left. Both move only as the app publishes a
/// level, never on a timer of the keyboard's own. Dictations recorded while the model gets ready are saved: while you
/// talk the bar counts them at its right, and once you stop each shows its length beside what the model is doing.
private final class Waveform: UIView {
    private let time = UILabel()
    private let track = UIView()
    private let fade = CAGradientLayer()
    private var bars: [UIView] = []
    private var levels: [CGFloat] = []
    /// How many are saved while you talk; what they wait for once you stop.
    private let words = UILabel()
    private var chips: [UILabel] = []
    private var lengths: [Double] = []
    private var since: Date?
    private var phase = MicButton.Phase.off
    /// Stopped, with every dictation saved and waiting for the model: their chips take the bars' place.
    private var waiting = false
    private var theme = KeyboardTheme.lightCurrent

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        time.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        words.font = .systemFont(ofSize: 15)
        words.adjustsFontSizeToFitWidth = true
        words.minimumScaleFactor = 0.7
        words.lineBreakMode = .byTruncatingTail
        words.accessibilityIdentifier = "hex.saved"
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        fade.locations = [0, 0.4]
        track.layer.mask = fade
        for view in [time, track, words] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `lengths` are the saved dictations' lengths in seconds, oldest first, and `waitingFor` what they wait for.
    func show(_ phase: MicButton.Phase, since: Date?, saved lengths: [Double], waitingFor: String?, theme: KeyboardTheme) {
        if phase != .listening, phase != .writing { levels = levels.map { _ in 0 } }
        self.phase = phase
        self.since = since
        self.theme = theme
        let waits = waitingFor != nil && !lengths.isEmpty
        waiting = phase == .writing && waits
        words.isHidden = !waits
        words.text = waiting ? waitingFor : "\(lengths.count) saved"
        words.textColor = theme.candidate.ui
        time.textColor = theme.candidate.ui
        if lengths != self.lengths {
            self.lengths = lengths
            chips.forEach { $0.removeFromSuperview() }
            chips = lengths.indices.map { index in
                let chip = UILabel()
                chip.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
                chip.textAlignment = .center
                chip.clipsToBounds = true
                chip.accessibilityIdentifier = "hex.saved.\(index)"
                addSubview(chip)
                return chip
            }
        }
        for chip in chips {
            chip.isHidden = !waiting
            chip.textColor = theme.label.ui
            chip.backgroundColor = theme.candidatePill.ui
        }
        time.isHidden = waiting
        track.isHidden = waiting
        alpha = phase == .writing && !waiting ? 0.4 : 1
        tick()
        layoutBars()
        setNeedsLayout()
    }

    func hear(_ level: Float) {
        guard phase == .listening, !levels.isEmpty else { return }
        let decibels = 20 * log10(max(level, 1e-6))
        let heard = CGFloat(min(max((decibels + 55) / 40, 0), 1))
        let last = levels.last ?? 0
        levels = Array(levels.dropFirst()) + [heard > last ? heard : last + (heard - last) / 2]
        tick()
        layoutBars()
    }

    private func tick() {
        let seconds = since.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
        time.text = Self.clock(seconds)
        time.sizeToFit()
    }

    private static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        time.frame = CGRect(x: 0, y: 0, width: 44, height: bounds.height)
        if waiting { return layoutChips() }
        let saved = words.isHidden ? 0 : (words.intrinsicContentSize.width + 12).rounded(.up)
        words.textAlignment = .right
        words.frame = CGRect(x: bounds.width - saved, y: 0, width: saved, height: bounds.height)
        track.frame = CGRect(x: 48, y: 0, width: max(bounds.width - 48 - saved, 0), height: bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = track.bounds
        CATransaction.commit()
        let fits = Int(track.bounds.width / 6)
        if fits != bars.count {
            bars.forEach { $0.removeFromSuperview() }
            bars = (0..<fits).map { _ in
                let bar = UIView()
                bar.layer.cornerRadius = 1.5
                track.addSubview(bar)
                return bar
            }
            levels = Array(repeating: 0, count: max(fits - levels.count, 0)) + levels.suffix(fits)
        }
        layoutBars()
    }

    /// The saved dictations' chips, oldest first, then what they wait for, centered; the last chip that fits counts
    /// the ones that don't.
    private func layoutChips() {
        let scale = traitCollection.displayScale
        let gap: CGFloat = 6, height = min(bounds.height - 12, 24)
        let wordsWidth = min(words.intrinsicContentSize.width.rounded(.up), bounds.width * 0.6)
        var shown = chips.count
        func widths() -> [CGFloat] {
            chips.prefix(shown).enumerated().map { index, chip in
                chip.text = index == shown - 1 && shown < chips.count ? "+\(chips.count - index)" : Self.clock(max(Int(lengths[index].rounded()), 1))
                return chip.intrinsicContentSize.width.rounded(.up) + 16
            }
        }
        var sizes = widths()
        while shown > 1, sizes.reduce(0, +) + gap * CGFloat(shown - 1) > bounds.width - wordsWidth - 10 {
            shown -= 1
            sizes = widths()
        }
        let row = sizes.reduce(0, +) + gap * CGFloat(shown - 1)
        var x = ((bounds.width - row - 10 - wordsWidth) / 2).rounded(scale: scale)
        for (index, chip) in chips.enumerated() {
            chip.isHidden = index >= shown
            guard index < shown else { continue }
            chip.frame = CGRect(x: x, y: ((bounds.height - height) / 2).rounded(scale: scale), width: sizes[index], height: height)
            chip.layer.cornerRadius = height / 2
            x += sizes[index] + gap
        }
        words.textAlignment = .left
        words.frame = CGRect(x: x - gap + 10, y: 0, width: wordsWidth, height: bounds.height)
    }

    private func layoutBars() {
        let scale = traitCollection.displayScale
        let tallest = min(bounds.height - 12, 24)
        for (index, bar) in bars.enumerated() {
            let level = levels[index]
            let height = (3 + (tallest - 3) * level).rounded(scale: scale)
            bar.frame = CGRect(x: CGFloat(index) * 6, y: ((bounds.height - height) / 2).rounded(scale: scale), width: 3, height: height)
            bar.backgroundColor = theme.label.ui.withAlphaComponent(0.35 + 0.65 * level)
        }
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

extension CGFloat {
    func rounded(scale: CGFloat) -> CGFloat { (self * scale).rounded() / scale }
}
