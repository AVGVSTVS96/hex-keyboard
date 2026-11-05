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

/// How loud the app heard you, from its published level, 0 for quiet to 1 for loud.
private func loudness(_ level: Float) -> CGFloat {
    CGFloat(min(max((20 * log10(max(level, 1e-6)) + 55) / 40, 0), 1))
}

/// Motion that follows your voice, a quick spring with no bounce, so each level carries on from the last mid-flight.
private func follow(duration: TimeInterval = 0.18, _ changes: @escaping () -> Void) {
    UIView.animate(springDuration: duration, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
}

/// A change of state, slower than following your voice, and still interruptible.
private func settle(bounce: CGFloat = 0, _ changes: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
    UIView.animate(springDuration: 0.35, bounce: bounce, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes, completion: completion)
}

/// The mic growing into the recording, with a little give, or shrinking back without: the capsule, its color, its
/// glyphs and the cancel button it lets out all move on this one spring, so they never drift apart.
private func morph(growing: Bool, _ changes: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
    UIView.animate(
        springDuration: growing ? 0.45 : 0.35, bounce: growing ? 0.12 : 0, options: [.beginFromCurrentState, .allowUserInteraction],
        animations: changes, completion: completion
    )
}

/// The bar's mic: a round button, white on dark and black on light, with a green dot while the app keeps the
/// microphone on. While it listens it turns record red and grows into a capsule over the suggestions, which holds the
/// recording, with a white stop where the mic was and a soft red halo that swells as you talk; while the
/// app writes a dictation down a spinner takes the glyph's place, and a tap still starts the next one. Tap to start or
/// stop; only the app turns the microphone off.
final class MicButton: UIControl {
    enum Phase { case off, on, listening, writing }

    /// The face's corner radius, where it takes a key's shape; otherwise round.
    var corner: CGFloat? { didSet { setNeedsLayout() } }
    /// Whether a halo swells around it with your voice while it listens: in the bar, never as the Record Key, whose
    /// neighbors sit too close.
    var breathes = false
    private(set) var phase = Phase.off
    private let halo = UIView()
    private let face = UIView()
    private let glyph = UIImageView()
    private let stop = UIImageView()
    private let dot = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var theme = KeyboardTheme.lightCurrent
    private var glyphSide: CGFloat = 0
    private var voice: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "hex.mic"
        isAccessibilityElement = true
        accessibilityTraits = .button
        for view in [halo, face] { view.layer.cornerCurve = .continuous }
        for view in [halo, face, glyph, stop, dot, spinner] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        halo.alpha = 0
        stop.alpha = 0
        stop.tintColor = .white
        for view in [glyph, stop] { view.contentMode = .center }
        dot.backgroundColor = UIColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
        spinner.hidesWhenStopped = false
        spinner.alpha = 0
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

    /// Into or out of listening it moves on `morph`, the spring the bar grows it on; otherwise it settles.
    func show(_ phase: Phase, theme: KeyboardTheme) {
        let old = self.phase
        self.phase = phase
        self.theme = theme
        accessibilityLabel = phase == .listening ? "Stop Dictating" : "Dictate"
        accessibilityValue = switch phase {
        case .on: "Mic On"
        case .writing: "Writing"
        case .off, .listening: nil
        }
        if phase != .listening { voice = 0 }
        if phase == .writing { spinner.startAnimating() }
        let done: (Bool) -> Void = { _ in if self.phase != .writing { self.spinner.stopAnimating() } }
        guard phase != old, window != nil else {
            refresh()
            return done(true)
        }
        if (phase == .listening) != (old == .listening) {
            morph(growing: phase == .listening, { self.refresh() }, completion: done)
        } else {
            settle({ self.refresh() }, completion: done)
        }
    }

    /// The halo swells with your voice, on a softer spring than the bars, so it breathes rather than flickers.
    func hear(_ level: Float) {
        guard phase == .listening, breathes else { return }
        voice = loudness(level)
        follow(duration: 0.32) { self.layoutHalo() }
    }

    /// The glyphs never change color: the mic's waveform shrinks away in its own color as the stop, always white,
    /// grows in its place, so neither flashes against the face while it turns red.
    private func refresh() {
        let listening = phase == .listening, idle = phase == .off || phase == .on
        face.backgroundColor = listening ? theme.record.ui : theme.mic.ui
        halo.backgroundColor = theme.record.ui
        halo.alpha = listening && breathes ? 0.2 : 0
        glyph.tintColor = theme.micGlyph.ui
        glyph.alpha = idle ? 1 : 0
        glyph.transform = idle ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        stop.alpha = listening ? 1 : 0
        stop.transform = listening ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        dot.alpha = phase == .on ? 1 : 0
        dot.transform = phase == .on ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        spinner.color = theme.micGlyph.ui
        spinner.alpha = phase == .writing ? 1 : 0
        spinner.transform = CGAffineTransform(scaleX: phase == .writing ? 0.75 : 0.5, y: phase == .writing ? 0.75 : 0.5)
        layoutHalo()
    }

    /// The glyphs in proportion with the circle (the waveform 15 points in a 28 one, the stop 12), and no bigger than 17
    /// and 13 in the Record Key's key.
    private static func symbol(_ name: String, side: CGFloat, ratio: CGFloat, largest: CGFloat) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: min((side * ratio).rounded(), largest), weight: .semibold))
    }

    /// The circle is smaller than a fingertip; taps a little around it still reach it.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    /// The glyphs, spinner and dot sit in the square at the right end of the capsule, or in the middle of a circle or key.
    override func layoutSubviews() {
        super.layoutSubviews()
        face.frame = bounds
        face.layer.cornerRadius = corner ?? bounds.height / 2
        let side = min(bounds.width, bounds.height)
        let end = CGRect(x: bounds.width > bounds.height * 1.5 ? bounds.width - side : (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        if glyphSide != side, side > 0 {
            glyphSide = side
            glyph.image = Self.symbol("waveform", side: side, ratio: 0.54, largest: 17)
            stop.image = Self.symbol("stop.fill", side: side, ratio: 0.43, largest: 13)
        }
        for view in [glyph, stop] {
            view.bounds.size = end.size
            view.center = CGPoint(x: end.midX, y: end.midY)
        }
        spinner.center = CGPoint(x: end.midX, y: end.midY)
        let dotSide: CGFloat = 6
        dot.bounds = CGRect(x: 0, y: 0, width: dotSide, height: dotSide)
        dot.center = CGPoint(x: end.maxX - dotSide / 2 - end.width * 0.04, y: end.minY + end.width * 0.04 + dotSide / 2)
        dot.layer.cornerRadius = dotSide / 2
        layoutHalo()
    }

    /// The halo hugs the capsule, a point out when you're quiet and four when you're loud.
    private func layoutHalo() {
        let out = phase == .listening ? 1 + 3 * voice : 0
        halo.bounds.size = CGSize(width: bounds.width + 2 * out, height: bounds.height + 2 * out)
        halo.center = CGPoint(x: bounds.midX, y: bounds.midY)
        halo.layer.cornerRadius = (corner ?? bounds.height / 2) + out
    }
}

/// The cancel button beside the recording: an x in a gray circle the mic's size, which gives under your finger as the
/// mic does. `SuggestionBar` moves it, out of the mic and back.
private final class CancelButton: UIControl {
    private let face = UIView()
    private let glyph = UIImageView()
    private var glyphSide: CGFloat = 0

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
        isHidden = true
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

    /// The x as heavy as the stop beside it and in the same proportion: 11 points in a 28 circle.
    override func layoutSubviews() {
        super.layoutSubviews()
        face.bounds = bounds
        face.center = CGPoint(x: bounds.midX, y: bounds.midY)
        face.layer.cornerRadius = bounds.height / 2
        glyph.frame = bounds
        let side = min(bounds.width, bounds.height)
        guard side != glyphSide, side > 0 else { return }
        glyphSide = side
        glyph.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: (side * 0.39).rounded(), weight: .semibold))
    }
}

/// The recording: the time so far, then bars that trace your voice, newest on the right, each as bright as it was loud,
/// the older ones fading out to the left. Each level the app publishes enters at the right edge and the bars glide left
/// one place in the time the app took to hear it, so they move at the speed of the recording, never on a timer of the
/// keyboard's own. While dictations wait for the model, it counts them at its right. In the bar it lies over the mic's
/// capsule, masked to it, or on its own where the mic is the Record Key, `insets` in from its ends.
private final class Waveform: UIView {
    private static let pitch: CGFloat = 5
    private static let barWidth: CGFloat = 2.5
    var insets: (leading: CGFloat, trailing: CGFloat) = (0, 0) {
        didSet { if insets != oldValue { setNeedsLayout() } }
    }
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
    private let saved = UILabel()
    private var recorded: Double = 0
    private var phase = MicButton.Phase.off
    private var tint = UIColor.white

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        time.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        time.accessibilityIdentifier = "hex.time"
        saved.font = .systemFont(ofSize: 15, weight: .medium)
        saved.textAlignment = .right
        saved.accessibilityIdentifier = "hex.saved"
        saved.alpha = 0
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        track.layer.mask = fade
        track.addSubview(strip)
        for view in [time, track, saved] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `saved` is how many dictations wait for the model while you talk. A new recording starts from quiet bars and
    /// comes in as the capsule uncovers it; a stopped one holds still and goes quickly, under the shrinking capsule.
    func show(_ phase: MicButton.Phase, recorded: Double, saved count: Int, tint: UIColor) {
        let started = phase == .listening && self.phase != .listening
        let stopped = phase != .listening && self.phase == .listening
        if stopped { freeze() }
        if started { heard = 0 }
        self.phase = phase
        self.recorded = recorded
        if phase == .listening { self.tint = tint }
        let counted = count > 0 && phase == .listening
        let text = count > 0 ? "\(count) saved" : saved.text
        let recounted = counted != (saved.alpha > 0) || text != saved.text
        saved.text = text
        saved.textColor = self.tint.withAlphaComponent(0.9)
        time.textColor = self.tint.withAlphaComponent(0.9)
        tick()
        guard window != nil else {
            alpha = phase == .listening ? 1 : 0
            saved.alpha = counted ? 1 : 0
            return layoutContent()
        }
        if started {
            UIView.performWithoutAnimation {
                saved.alpha = counted ? 1 : 0
                layoutContent()
            }
            UIView.animate(withDuration: 0.25, delay: 0.05, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) { self.alpha = 1 }
        } else if stopped {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) { self.alpha = 0 }
        } else if recounted {
            settle {
                self.saved.alpha = counted ? 1 : 0
                self.layoutContent()
            }
        }
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

    /// A bar is a dot when you're quiet and at most 16 tall in the 28 capsule, so it keeps 6 clear above and below.
    private func frame(of index: Int) -> CGRect {
        let scale = traitCollection.displayScale
        let tallest = max(min(bounds.height - 12, 18), Self.barWidth)
        let height = (Self.barWidth + (tallest - Self.barWidth) * bars[index].level).rounded(scale: scale)
        let number = heard - bars.count + index
        return CGRect(x: CGFloat(number) * Self.pitch, y: ((bounds.height - height) / 2).rounded(scale: scale), width: Self.barWidth, height: height)
    }

    private func color(_ level: CGFloat) -> UIColor {
        tint.withAlphaComponent(0.5 + 0.5 * level)
    }

    private func tick() {
        time.text = Self.clock(Int(recorded))
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
        let end = bounds.width - insets.trailing
        time.frame = CGRect(x: insets.leading, y: 0, width: 46, height: bounds.height)
        let count = saved.alpha > 0 ? (saved.intrinsicContentSize.width + 10).rounded(.up) : 0
        saved.frame = CGRect(x: end - count, y: 0, width: count, height: bounds.height)
        let start = insets.leading + 48
        let width = max(end - count - start, 0)
        track.frame = CGRect(x: start, y: 0, width: width, height: bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = track.bounds
        fade.locations = [0, 0.35, NSNumber(value: Double(max(1 - 4 / max(width, 1), 0.9))), 1]
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
}

/// Once you stop, the dictations recorded while the model gets ready, as a stack of cards beside what it's doing: the
/// next to be typed in front with its length, up to three more tucked behind it and peeking out 6 to its right, each a
/// little smaller and a solid shade further back, so no card shows through another. A new one slides in behind from
/// the mic's side; the front one lifts away as it's typed, and the next steps forward into its place.
private final class PendingStack: UIView {
    private static let peek: CGFloat = 6
    private static let shades: [Double] = [0, 0.45, 0.7, 0.9]
    private var cards: [Card] = []
    private var lengths: [Double] = []
    private let words = UILabel()
    /// What the model is doing; the words keep its last text as they fade, once it's done.
    private var waitingFor: String?
    private var shows = false
    private var theme = KeyboardTheme.lightCurrent

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        words.font = .systemFont(ofSize: 15)
        words.adjustsFontSizeToFitWidth = true
        words.minimumScaleFactor = 0.7
        words.lineBreakMode = .byTruncatingTail
        words.accessibilityIdentifier = "hex.waiting"
        words.alpha = 0
        addSubview(words)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// It shows while the app writes and the model keeps the saved dictations waiting, and stays up as the model takes
    /// them, until the last is typed.
    func show(_ phase: MicButton.Phase, saved lengths: [Double], waitingFor: String?, theme: KeyboardTheme) {
        let shown = shows
        shows = phase == .writing && !lengths.isEmpty && (waitingFor != nil || shows)
        self.theme = theme
        let reworded = waitingFor != self.waitingFor
        self.waitingFor = waitingFor
        if let waitingFor { words.text = waitingFor }
        words.textColor = theme.candidate.ui
        let restacked = lengths != self.lengths
        if restacked { restack(lengths, animated: window != nil && shown) }
        guard window != nil, shown != shows || (shows && (restacked || reworded)) else { return place() }
        settle { self.place() }
    }

    /// The saved dictations' cards, keeping the ones still waiting: the oldest typed lift away, and the newly saved join
    /// at the back.
    private func restack(_ lengths: [Double], animated: Bool) {
        let typed = self.lengths.count - lengths.count
        if typed > 0, Array(self.lengths.dropFirst(typed)) == lengths {
            let gone = cards.prefix(typed)
            cards.removeFirst(typed)
            if animated {
                UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                    gone.forEach {
                        $0.alpha = 0
                        $0.transform = CGAffineTransform(translationX: 0, y: -8).scaledBy(x: 0.94, y: 0.94)
                    }
                } completion: { _ in gone.forEach { $0.removeFromSuperview() } }
            } else {
                gone.forEach { $0.removeFromSuperview() }
            }
        } else if lengths.starts(with: self.lengths) {
            cards += lengths.dropFirst(self.lengths.count).map { _ in Card(in: self) }
        } else {
            cards.forEach { $0.removeFromSuperview() }
            cards = lengths.map { _ in Card(in: self) }
        }
        self.lengths = lengths
        for (index, card) in cards.enumerated() { card.show(length: lengths[index], index: index) }
        for card in cards.reversed() { bringSubviewToFront(card) }
    }

    /// Everything where the state puts it; hidden, the cards forget their places, so they come in afresh next time.
    private func place() {
        alpha = shows ? 1 : 0
        guard shows else {
            cards.forEach { $0.placed = false }
            words.alpha = 0
            return
        }
        layoutCards()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if shows { layoutCards() }
    }

    /// The cards, centered with what they wait for beside them. A card new to the stack starts where it will be,
    /// nudged toward the mic and a little smaller, so it comes in by moving and growing as much as by fading.
    private func layoutCards() {
        guard let front = cards.first else { return }
        let scale = traitCollection.displayScale
        let height = min(bounds.height - 12, 26)
        let width = front.width
        let stack = width + CGFloat(min(cards.count - 1, Self.shades.count - 1)) * Self.peek
        let wordsWidth = waitingFor == nil ? 0 : min(words.intrinsicContentSize.width.rounded(.up), bounds.width * 0.6)
        let minX = ((bounds.width - stack - (wordsWidth > 0 ? wordsWidth + 10 : 0)) / 2).rounded(scale: scale)
        for (depth, card) in cards.enumerated() {
            let place = min(depth, Self.shades.count - 1)
            let shrink = 1 - 0.08 * CGFloat(place)
            let size = CGSize(width: (width * shrink).rounded(scale: scale), height: (height * shrink).rounded(scale: scale))
            let center = CGPoint(x: minX + width + CGFloat(place) * Self.peek - size.width / 2, y: bounds.midY)
            if !card.placed {
                card.placed = true
                UIView.performWithoutAnimation {
                    card.bounds.size = size
                    card.center = center
                    card.alpha = 0
                    card.backgroundColor = theme.candidatePill.mixed(with: theme.candidateDivider, Self.shades[place]).ui
                    card.transform = CGAffineTransform(translationX: 12, y: 0).scaledBy(x: 0.9, y: 0.9)
                }
            }
            card.bounds.size = size
            card.center = center
            card.transform = .identity
            card.alpha = depth < Self.shades.count ? 1 : 0
            card.backgroundColor = theme.candidatePill.mixed(with: theme.candidateDivider, Self.shades[place]).ui
            card.label.textColor = theme.label.ui
            card.label.alpha = depth == 0 ? 1 : 0
        }
        guard wordsWidth > 0 else {
            words.alpha = 0
            return
        }
        let frame = CGRect(x: minX + stack + 10, y: 0, width: wordsWidth, height: bounds.height)
        if words.alpha == 0 { UIView.performWithoutAnimation { words.frame = frame } } else { words.frame = frame }
        words.alpha = 1
    }
}

/// One saved dictation's card: its length in a pill.
private final class Card: UIView {
    let label = UILabel()
    var placed = false

    init(in stack: UIView) {
        super.init(frame: .zero)
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        addSubview(label)
        alpha = 0
        layer.cornerCurve = .continuous
        stack.addSubview(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    var width: CGFloat { label.intrinsicContentSize.width.rounded(.up) + 20 }

    func show(length: Double, index: Int) {
        label.text = Waveform.clock(max(Int(length.rounded()), 1))
        label.accessibilityIdentifier = "hex.saved.\(index)"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        layer.cornerRadius = bounds.height / 2
    }
}

private extension RGBA {
    func mixed(with other: RGBA, _ amount: Double) -> RGBA {
        RGBA(
            red: red + (other.red - red) * amount, green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount, alpha: alpha + (other.alpha - alpha) * amount
        )
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
