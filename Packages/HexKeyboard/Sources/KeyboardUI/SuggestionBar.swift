import UIKit
import KeyboardCore

/// Apple's three suggestions with the word's emoji (as many as fit, and the rest a swipe left away), a round mic at the
/// right end that starts and stops dictation, and the tools at the left end, all placed on the top row's keys by
/// `BarLayout`. While the app listens, the mic grows into a red capsule over the suggestions holding the time so far and
/// the waveform of your voice, with a cancel button before it.
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
        addSubview(cancel)
        addSubview(mic)
        addSubview(waveform)
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
        self.mic.show(mic, theme: theme)
        cancel.paint(theme)
        waveform.show(mic, recorded: recorded, saved: saved, waitingFor: waitingFor, tint: mic == .listening && micInBar ? .white : theme.label.ui, theme: theme)
        self.notice.text = notice
        self.notice.textColor = theme.candidate.ui
        noticed = notice != nil
        refresh()
        guard grows, window != nil else { return }
        setNeedsLayout()
        UIView.animate(springDuration: mic == .listening ? 0.45 : 0.35, bounce: mic == .listening ? 0.12 : 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.layoutIfNeeded()
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
    }

    /// While you dictate, the cancel button sits in its place, before the recording. Otherwise it waits shrunk behind
    /// the mic, so as the mic grows into the recording it splits off the capsule's leading edge and rides out to its
    /// place on the same spring, and slides back in when the recording ends, with no fade. Where the mic sits in the
    /// bottom row, it fades in and out in its place.
    private func placeCancel(_ place: CGRect, behind mic: CGRect?) {
        let listening = self.mic.phase == .listening
        let waiting = mic.map { CGPoint(x: $0.midX, y: $0.midY) }
        cancel.bounds.size = place.size
        cancel.center = listening ? CGPoint(x: place.midX, y: place.midY) : waiting ?? CGPoint(x: place.midX, y: place.midY)
        cancel.transform = listening ? .identity : CGAffineTransform(scaleX: waiting == nil ? 0.9 : 0.5, y: waiting == nil ? 0.9 : 0.5)
        cancel.alpha = listening || waiting != nil ? 1 : 0
    }

    @objc private func tapNotice() {
        onNotice()
    }

    private var recording: Bool { mic.phase == .listening || mic.phase == .writing }

    private func refresh() {
        let quiet = !enabled || noticed || recording
        notice.isHidden = !noticed || recording
        waveform.isHidden = !recording
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
        let end = layout.mic.map { CGFloat($0.x) - 6 } ?? CGFloat(layout.recording.x + layout.recording.width)
        let start = CGFloat(layout.recording.x) + 14
        waveform.bounds.size = CGSize(width: max(end - start, 0), height: row.height)
        waveform.center = CGPoint(x: (start + end) / 2, y: row.midY)
        notice.frame = row.insetBy(dx: 4, dy: 0)
    }
}

/// How loud the app heard you, from its published level, 0 for quiet to 1 for loud.
private func loudness(_ level: Float) -> CGFloat {
    CGFloat(min(max((20 * log10(max(level, 1e-6)) + 55) / 40, 0), 1))
}

/// Motion that follows your voice, a quick spring with no bounce, so each level carries on from the last mid-flight.
private func follow(_ changes: @escaping () -> Void) {
    UIView.animate(springDuration: 0.18, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
}

/// A change of state, slower than following your voice, and still interruptible.
private func settle(bounce: CGFloat = 0, _ changes: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
    UIView.animate(springDuration: 0.35, bounce: bounce, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes, completion: completion)
}

/// The bar's mic: a round button, white on dark and black on light, with a green dot while the app keeps the
/// microphone on. While it listens it turns record red and grows into a capsule over the suggestions, which holds the
/// waveform, with a white stop where the mic was; while the app writes a dictation down a spinner takes the glyph's
/// place, and a tap still starts the next one. Tap to start or stop; only the app turns the microphone off.
final class MicButton: UIControl {
    enum Phase { case off, on, listening, writing }

    /// The face's corner radius, where it takes a key's shape; otherwise round.
    var corner: CGFloat? { didSet { setNeedsLayout() } }
    private(set) var phase = Phase.off
    private let face = UIView()
    private let glyph = UIImageView()
    private let dot = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var theme = KeyboardTheme.lightCurrent
    private var glyphSide: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "hex.mic"
        isAccessibilityElement = true
        accessibilityTraits = .button
        face.isUserInteractionEnabled = false
        face.layer.cornerCurve = .continuous
        for view in [face, glyph, dot, spinner] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        glyph.contentMode = .center
        dot.backgroundColor = UIColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
        spinner.hidesWhenStopped = false
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Pressed, it gives by the same 3 points whatever its width.
    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            let scale = isHighlighted ? 1 - 6 / max(bounds.width, 1) : 1
            UIView.animate(springDuration: isHighlighted ? 0.16 : 0.3, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
    }

    func show(_ phase: Phase, theme: KeyboardTheme) {
        let changed = phase != self.phase
        self.phase = phase
        self.theme = theme
        accessibilityLabel = phase == .listening ? "Stop Dictating" : "Dictate"
        accessibilityValue = switch phase {
        case .on: "Mic On"
        case .writing: "Writing"
        case .off, .listening: nil
        }
        if phase == .writing { spinner.startAnimating() }
        if changed, window != nil {
            UIView.transition(with: glyph, duration: 0.2, options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction]) {
                self.glyph.image = self.symbol
            }
            settle({ self.refresh() }) { _ in if self.phase != .writing { self.spinner.stopAnimating() } }
        } else {
            glyph.image = symbol
            if phase != .writing { spinner.stopAnimating() }
            refresh()
        }
    }

    /// The glyph in proportion with the circle (15 points in a 28 one, the stop 12), and no bigger than 17 and 13 in
    /// the Record Key's key.
    private var symbol: UIImage? {
        let listening = phase == .listening
        let side = min(bounds.width, bounds.height) > 0 ? min(bounds.width, bounds.height) : 28
        let size = min((side * (listening ? 0.43 : 0.54)).rounded(), listening ? 13 : 17)
        return UIImage(systemName: listening ? "stop.fill" : "waveform", withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold))
    }

    private func refresh() {
        let listening = phase == .listening
        glyph.tintColor = listening ? .white : theme.micGlyph.ui
        glyph.alpha = phase == .writing ? 0 : 1
        face.backgroundColor = listening ? theme.record.ui : theme.mic.ui
        dot.alpha = phase == .on ? 1 : 0
        dot.transform = phase == .on ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        spinner.color = theme.micGlyph.ui
        spinner.alpha = phase == .writing ? 1 : 0
    }

    /// The circle is smaller than a fingertip; taps a little around it still reach it.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    /// The glyph, spinner and dot sit in the square at the right end of the capsule, or in the middle of a circle or key.
    override func layoutSubviews() {
        super.layoutSubviews()
        face.frame = bounds
        face.layer.cornerRadius = corner ?? bounds.height / 2
        let side = min(bounds.width, bounds.height)
        let end = CGRect(x: bounds.width > bounds.height * 1.5 ? bounds.width - side : (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        if glyphSide != side {
            glyphSide = side
            glyph.image = symbol
        }
        glyph.frame = end
        spinner.center = CGPoint(x: end.midX, y: end.midY)
        spinner.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        let dotSide: CGFloat = 6
        dot.bounds = CGRect(x: 0, y: 0, width: dotSide, height: dotSide)
        dot.center = CGPoint(x: end.maxX - dotSide / 2 - end.width * 0.04, y: end.minY + end.width * 0.04 + dotSide / 2)
        dot.layer.cornerRadius = dotSide / 2
    }
}

/// The cancel button beside the recording: an x in a gray circle the mic's size, which gives under your finger as the
/// mic does. `SuggestionBar` moves it, out of the mic and back.
private final class CancelButton: UIControl {
    private let face = UIView()
    private let glyph = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))

    var shows = false {
        didSet {
            isUserInteractionEnabled = shows
            accessibilityElementsHidden = !shows
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "hex.cancel"
        accessibilityLabel = "Cancel Dictation"
        isAccessibilityElement = true
        accessibilityTraits = .button
        face.isUserInteractionEnabled = false
        glyph.contentMode = .center
        addSubview(face)
        face.addSubview(glyph)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func paint(_ theme: KeyboardTheme) {
        face.backgroundColor = theme.candidatePill.ui
        glyph.tintColor = theme.label.ui
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(springDuration: isHighlighted ? 0.16 : 0.3, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.face.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            }
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        face.bounds = bounds
        face.center = CGPoint(x: bounds.midX, y: bounds.midY)
        face.layer.cornerRadius = bounds.height / 2
        glyph.frame = bounds
    }
}

/// The suggestions' place while the app listens: the time so far, then bars that trace your voice, newest on the
/// right, each as bright as it was loud, the older ones fading out to the left. Each level the app publishes enters at
/// the right edge and the bars glide left one place in the time the app took to hear it, so they move at the speed of
/// the recording, never on a timer of the keyboard's own. Dictations recorded while the model gets ready are saved:
/// while you talk the bar counts them at its right, and once you stop they stack as cards, the next to be typed in
/// front with its length and the rest peeking out behind it, beside what the model is doing; each lifts away as its
/// dictation is typed, and the next steps forward.
private final class Waveform: UIView {
    private static let pitch: CGFloat = 5
    private static let barWidth: CGFloat = 2.5
    private let time = UILabel()
    private let track = UIView()
    private let strip = UIView()
    private let fade = CAGradientLayer()
    /// The bars on screen and just past its left edge, oldest first; the newest is level number `heard - 1`, drawn at
    /// `x = (heard - 1) * pitch` on the strip, which slides left as levels come.
    private var bars: [(view: UIView, level: CGFloat)] = []
    private var heard = 0
    private var lastRecorded: Double = 0
    private var laidWidth: CGFloat = -1
    /// How many are saved while you talk; what they wait for once you stop.
    private let words = UILabel()
    private var showsWords = false
    private var chips: [Chip] = []
    private var lengths: [Double] = []
    private var recorded: Double = 0
    private var phase = MicButton.Phase.off
    /// Stopped, with every dictation saved and waiting for the model: their cards take the bars' place.
    private var waiting = false
    private var theme = KeyboardTheme.lightCurrent
    /// The time's, the bars' and the count's color: white on the mic's red, or the label's where the mic isn't in the bar.
    private var tint = UIColor.white

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        time.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        time.accessibilityIdentifier = "hex.time"
        words.font = .systemFont(ofSize: 15)
        words.adjustsFontSizeToFitWidth = true
        words.minimumScaleFactor = 0.7
        words.lineBreakMode = .byTruncatingTail
        words.accessibilityIdentifier = "hex.saved"
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        track.layer.mask = fade
        track.addSubview(strip)
        for view in [time, track, words] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `lengths` are the saved dictations' lengths in seconds, oldest first, and `waitingFor` what they wait for.
    func show(_ phase: MicButton.Phase, recorded: Double, saved lengths: [Double], waitingFor: String?, tint: UIColor, theme: KeyboardTheme) {
        let started = phase == .listening && self.phase != .listening
        let stopped = phase != .listening && self.phase == .listening
        if phase != .listening, phase != .writing { heard = 0 }
        if phase != .listening, self.phase == .listening { freeze() }
        self.phase = phase
        self.recorded = recorded
        self.theme = theme
        if phase == .listening { self.tint = tint }
        showsWords = waitingFor != nil && !lengths.isEmpty
        let wasWaiting = waiting
        waiting = phase == .writing && !lengths.isEmpty && (showsWords || waiting)
        words.text = waiting ? waitingFor : "\(lengths.count) saved"
        words.textColor = waiting ? theme.candidate.ui : self.tint.withAlphaComponent(0.85)
        time.textColor = self.tint.withAlphaComponent(0.85)
        let restacked = lengths != self.lengths
        if restacked { restack(lengths, animated: wasWaiting && waiting) }
        for chip in chips { chip.paint(theme) }
        tick()
        guard window != nil else { return place() }
        if started {
            UIView.performWithoutAnimation {
                for view in [time, track] {
                    view.alpha = 0
                    view.transform = CGAffineTransform(translationX: 24, y: 0)
                }
            }
            UIView.animate(springDuration: 0.4, bounce: 0, initialSpringVelocity: 0, delay: 0.06, options: [.beginFromCurrentState, .allowUserInteraction]) { self.place() }
        } else if stopped {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) { self.place() }
        } else if wasWaiting != waiting || (waiting && restacked) {
            settle { self.place() }
        } else {
            place()
        }
    }

    /// Everything where the state puts it: the bars with the time, or the cards, and what they wait for.
    private func place() {
        for view in [time, track] {
            view.alpha = phase == .listening ? 1 : 0
            view.transform = .identity
        }
        words.alpha = showsWords ? 1 : 0
        if !waiting {
            for chip in chips {
                chip.alpha = 0
                chip.placed = false
            }
        }
        layoutContent()
    }

    func hear(_ level: Float, recorded: Double) {
        guard phase == .listening, track.bounds.width > 0 else { return }
        let interval = min(max(recorded - lastRecorded, 0.03), 0.25)
        self.recorded = recorded
        lastRecorded = recorded
        let loud = loudness(level)
        let last = bars.last?.level ?? 0
        let level = last + (loud - last) * (loud > last ? 0.7 : 0.35)
        let bar = bars.count > fits + 1 ? bars.removeFirst().view : newBar()
        bars.append((bar, level))
        self.heard += 1
        UIView.performWithoutAnimation {
            bar.transform = .identity
            bar.frame = frame(of: bars.count - 1)
            bar.backgroundColor = color(level)
            bar.transform = CGAffineTransform(scaleX: 1, y: 0.2)
        }
        follow { bar.transform = .identity }
        UIView.animate(withDuration: interval, delay: 0, options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]) {
            self.strip.transform = self.slid
        }
        tick()
    }

    private var fits: Int { Int(track.bounds.width / Self.pitch) }
    private var slid: CGAffineTransform { CGAffineTransform(translationX: track.bounds.width - CGFloat(heard) * Self.pitch + Self.barWidth, y: 0) }

    private func newBar() -> UIView {
        let bar = UIView()
        bar.layer.cornerRadius = Self.barWidth / 2
        strip.addSubview(bar)
        return bar
    }

    /// Where the strip is on screen when the voice stops, so the bars hold still there rather than finish gliding.
    private func freeze() {
        if let shown = strip.layer.presentation() { strip.layer.transform = shown.transform }
        strip.layer.removeAllAnimations()
    }

    /// The bars on a new recording: a row of quiet ones across the track, which your voice pushes out to the left.
    private func refill() {
        bars.forEach { $0.view.removeFromSuperview() }
        heard = fits + 1
        bars = (0..<heard).map { _ in (newBar(), 0) }
        lastRecorded = recorded
    }

    private func frame(of index: Int) -> CGRect {
        let scale = traitCollection.displayScale
        let tallest = min(bounds.height - 18, 20)
        let height = (Self.barWidth + (tallest - Self.barWidth) * bars[index].level).rounded(scale: scale)
        let number = heard - bars.count + index
        return CGRect(x: CGFloat(number) * Self.pitch, y: ((bounds.height - height) / 2).rounded(scale: scale), width: Self.barWidth, height: height)
    }

    private func color(_ level: CGFloat) -> UIColor {
        tint.withAlphaComponent(0.45 + 0.55 * level)
    }

    /// The saved dictations' cards, keeping the ones still waiting: when the oldest are typed they lift away, and a
    /// newly saved one slides in from the mic's side.
    private func restack(_ lengths: [Double], animated: Bool) {
        let typed = self.lengths.count - lengths.count
        var gone: ArraySlice<Chip> = []
        if typed > 0, Array(self.lengths.dropFirst(typed)) == lengths {
            gone = chips.prefix(typed)
            chips.removeFirst(typed)
            if animated {
                UIView.animate(springDuration: 0.25, bounce: 0, options: .beginFromCurrentState) {
                    gone.forEach {
                        $0.alpha = 0
                        $0.transform = CGAffineTransform(translationX: 0, y: -10).scaledBy(x: 0.92, y: 0.92)
                    }
                } completion: { _ in gone.forEach { $0.removeFromSuperview() } }
            } else {
                gone.forEach { $0.removeFromSuperview() }
            }
        } else if lengths.starts(with: self.lengths) {
            chips += lengths.dropFirst(self.lengths.count).map { _ in Chip(in: self) }
        } else {
            chips.forEach { $0.removeFromSuperview() }
            chips = lengths.map { _ in Chip(in: self) }
        }
        self.lengths = lengths
        for (index, chip) in chips.enumerated() {
            chip.show(length: lengths[index], index: index)
        }
        for chip in chips.reversed() + gone { bringSubviewToFront(chip) }
    }

    private func tick() {
        time.text = Self.clock(Int(recorded))
        time.sizeToFit()
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutContent()
    }

    /// The bars are laid out again only when the track's width changes or a recording starts, so a status update
    /// never cuts short their glide.
    private func layoutContent() {
        time.bounds.size = CGSize(width: 44, height: bounds.height)
        time.center = CGPoint(x: 22, y: bounds.midY)
        if waiting { return layoutChips() }
        let saved = showsWords ? (words.intrinsicContentSize.width + 12).rounded(.up) : 0
        words.textAlignment = .right
        words.frame = CGRect(x: bounds.width - saved, y: 0, width: saved, height: bounds.height)
        let width = max(bounds.width - 48 - saved, 0)
        track.bounds.size = CGSize(width: width, height: bounds.height)
        track.center = CGPoint(x: 48 + width / 2, y: bounds.midY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = track.bounds
        fade.locations = [0, 0.4, NSNumber(value: Double(max(1 - 4 / max(width, 1), 0.9))), 1]
        CATransaction.commit()
        let refilling = heard == 0 || bars.count < fits + 1
        if refilling { UIView.performWithoutAnimation { refill() } }
        for bar in bars { bar.view.backgroundColor = color(bar.level) }
        guard refilling || width != laidWidth else { return }
        laidWidth = width
        UIView.performWithoutAnimation {
            strip.frame = CGRect(x: 0, y: 0, width: 1, height: bounds.height)
            for (index, bar) in bars.enumerated() { bar.view.frame = frame(of: index) }
        }
        if refilling { UIView.performWithoutAnimation { strip.transform = slid } } else { strip.transform = slid }
    }

    /// The cards, centered with what they wait for beside them: the oldest in front with its length, up to three more
    /// peeking out to its right, each smaller and fainter than the one before.
    private func layoutChips() {
        guard let front = chips.first else { return }
        let scale = traitCollection.displayScale
        let height = min(bounds.height - 12, 26)
        let width = front.width
        let peeking = min(chips.count - 1, 3)
        let stack = width + CGFloat(peeking) * 5
        let wordsWidth = min(words.intrinsicContentSize.width.rounded(.up), bounds.width * 0.6)
        let row = stack + (showsWords ? wordsWidth + 10 : 0)
        let minX = ((bounds.width - row) / 2).rounded(scale: scale)
        for (depth, chip) in chips.enumerated() {
            let shrink = 1 - 0.1 * CGFloat(min(depth, 4))
            let size = CGSize(width: width * shrink, height: (height * shrink).rounded(scale: scale))
            let maxX = minX + width + CGFloat(min(depth, 4)) * 5
            let frame = CGRect(x: maxX - size.width, y: ((bounds.height - size.height) / 2).rounded(scale: scale), width: size.width, height: size.height)
            if chip.placed {
                chip.frame = frame
            } else {
                chip.placed = true
                UIView.performWithoutAnimation {
                    chip.frame = frame
                    chip.alpha = 0
                    chip.transform = CGAffineTransform(translationX: 16, y: 0).scaledBy(x: 0.9, y: 0.9)
                }
            }
            chip.transform = .identity
            chip.alpha = depth == 0 ? 1 : depth > 3 ? 0 : 0.7 - 0.2 * CGFloat(depth)
            chip.label.alpha = depth == 0 ? 1 : 0
        }
        words.textAlignment = .left
        words.frame = CGRect(x: minX + stack + 10, y: 0, width: wordsWidth, height: bounds.height)
    }
}

/// One saved dictation's card: its length in a pill.
private final class Chip: UIView {
    let label = UILabel()
    var placed = false

    init(in waveform: UIView) {
        super.init(frame: .zero)
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        addSubview(label)
        alpha = 0
        layer.cornerCurve = .continuous
        waveform.addSubview(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    var width: CGFloat { label.intrinsicContentSize.width.rounded(.up) + 18 }

    func show(length: Double, index: Int) {
        label.text = Waveform.clock(max(Int(length.rounded()), 1))
        label.accessibilityIdentifier = "hex.saved.\(index)"
    }

    func paint(_ theme: KeyboardTheme) {
        label.textColor = theme.label.ui
        backgroundColor = theme.candidatePill.ui
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        layer.cornerRadius = bounds.height / 2
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

extension CGRect {
    func rounded(scale: CGFloat) -> CGRect {
        let left = minX.rounded(scale: scale), top = minY.rounded(scale: scale)
        return CGRect(x: left, y: top, width: maxX.rounded(scale: scale) - left, height: maxY.rounded(scale: scale) - top)
    }
}
