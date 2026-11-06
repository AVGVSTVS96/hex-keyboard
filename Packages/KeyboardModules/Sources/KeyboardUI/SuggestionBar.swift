import UIKit
import KeyboardCore

/// Apple's three suggestions with the word's emoji (as many as fit, and the rest a swipe left away), a round mic at the
/// right end that starts and stops dictation, and the tools at the left end, all placed on the top row's keys by
/// `BarLayout`. While the app listens, the mic grows into a red capsule over the suggestions holding the time so far and
/// the waveform of your voice, and lets out a cancel button before it. Once you stop, dictations still waiting for the
/// model stack as cards in its place. The clipboard's button grows the same way into a tray of its tools over the
/// suggestions: cut, copy and paste, then its history.
public final class SuggestionBar: UIView {
    /// What the clipboard's tray does.
    public enum Edit: CaseIterable, Sendable {
        case cut, copy, paste, history
    }

    /// Which of the tray's edits can be done now: cut and copy with a selection, paste with text on the clipboard.
    public struct Edits: Equatable, Sendable {
        public var cut, copy, paste: Bool

        public init(cut: Bool, copy: Bool, paste: Bool) {
            self.cut = cut
            self.copy = copy
            self.paste = paste
        }

        func allows(_ edit: Edit) -> Bool {
            switch edit {
            case .cut: cut
            case .copy: copy
            case .paste: paste
            case .history: true
            }
        }
    }

    public var onSelect: (Suggestion) -> Void = { _ in }
    public var onEmoji: (String) -> Void = { _ in }
    public var onMic: () -> Void = {}
    public var onCancel: () -> Void = {}
    public var onNotice: () -> Void = {}
    public var onTool: (Panel) -> Void = { _ in }
    public var onEdit: (Edit) -> Void = { _ in }
    /// How the recording goes back into the mic when you stop (Settings › Appearance).
    public var stopAnimation = StopAnimation.squeeze { didSet { mic.writes = stopAnimation } }
    public var maximumSlotWidth = CGFloat.infinity { didSet { setNeedsLayout() } }
    /// The top row's keys, left to right, as their edges.
    public var keys: [(minX: Double, maxX: Double)] = [] {
        didSet { if !keys.elementsEqual(oldValue, by: ==) { setNeedsLayout() } }
    }
    public var toolbar = KeyboardMetrics.phone(width: 390).toolbar { didSet { if toolbar != oldValue { setNeedsLayout() } } }
    /// Whether the mic sits at the bar's right, or in the bottom row (Settings › Layout › Record Key), where the bar
    /// has none and the recording runs as the bar's own waveform.
    public var micInBar = true {
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
    /// The clipboard's tray while it's out, nil while it's tucked into the clipboard's button.
    private var edits: Edits?
    private let tray = UIView()
    private let trayDivider = UIView()
    private let editButtons: [(edit: Edit, button: BarButton)] = Edit.allCases.map { edit in
        let button = BarButton(edit.title) { UIImage(systemName: edit.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: ($0 * 0.82).rounded(), weight: .medium)) }
        button.accessibilityIdentifier = "iikb.edit.\(edit)"
        return (edit, button)
    }
    private let mic = MicButton()
    private let cancel = CancelButton()
    private let waveform = Waveform()
    /// The waveform's mask in the bar: the mic's own shape, moved with it, so the recording shows only inside the red.
    private let capsule = UIView()
    private let stack = PendingStack()
    private let notice = UILabel()
    private var emojiBeside = false
    /// The recording just cancelled, gone to dust, so the mic comes back in its place instead of shrinking out of it.
    private var dissolving = false
    /// How long the recording ran, for Card's card.
    private var heard: Double = 0
    private var enabled = true
    private var noticed = false
    private var theme = KeyboardTheme.lightCurrent

    override public init(frame: CGRect) {
        super.init(frame: frame)
        for slot in slots {
            slot.addAction(UIAction { [unowned self, unowned slot] _ in
                if let suggestion = slot.suggestion { onSelect(suggestion) }
            }, for: .touchUpInside)
            slot.onHighlight = { [unowned self] in refreshDividers() }
            addSubview(slot)
        }
        dividers.forEach(addSubview)
        tray.layer.cornerCurve = .continuous
        tray.layer.shadowOffset = CGSize(width: 0, height: 1)
        tray.layer.shadowRadius = 0
        tray.layer.shadowOpacity = 1
        tray.isUserInteractionEnabled = false
        addSubview(tray)
        addSubview(trayDivider)
        for (edit, button) in editButtons {
            button.addAction(UIAction { [unowned self] _ in onEdit(edit) }, for: .touchUpInside)
            addSubview(button)
        }
        more.showsMenuAsPrimaryAction = true
        more.isHidden = true
        more.accessibilityIdentifier = "iikb.more"
        addSubview(more)
        strip.alwaysBounceHorizontal = false
        strip.accessibilityIdentifier = "iikb.suggestion.emoji"
        addSubview(strip)
        mic.addAction(UIAction { [unowned self] _ in onMic() }, for: .touchUpInside)
        cancel.addAction(UIAction { [unowned self] _ in
            dissolve()
            onCancel()
        }, for: .touchUpInside)
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
        notice.accessibilityIdentifier = "iikb.notice"
        notice.isUserInteractionEnabled = true
        notice.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapNotice)))
        addSubview(notice)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func update(_ suggestions: [Suggestion], emoji: [String], enabled: Bool, theme: KeyboardTheme) {
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
    public func update(mic: MicButton.Phase, recorded: Double, saved: [Double], waitingFor: String?, notice: String?, theme: KeyboardTheme) {
        let grows = (mic == .listening) != (self.mic.phase == .listening)
        let shown = CGRect(x: self.mic.center.x - self.mic.bounds.width / 2, y: self.mic.center.y - self.mic.bounds.height / 2, width: self.mic.bounds.width, height: self.mic.bounds.height)
        if mic == .listening { heard = recorded }
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
        if dissolving, mic != .listening {
            reappear()
            return
        }
        if mic != .listening {
            switch stopAnimation {
            case .squeeze: waveform.rush()
            case .drain: return drain(shown, theme: theme)
            case .card: return lift(shown, theme: theme)
            }
        }
        morph(growing: mic == .listening, { self.layoutIfNeeded() }) { _ in
            if self.mic.phase != .listening { self.cancel.isHidden = true }
        }
    }

    /// The tools at the bar's left, where there's no pill row for them.
    public func update(tools panels: [Panel], theme: KeyboardTheme) {
        if panels != tools.map(\.panel) {
            tools.forEach { $0.button.removeFromSuperview() }
            tools = panels.map { panel in
                let tool = BarButton(panel.title, draw: panel.icon)
                tool.accessibilityIdentifier = "iikb.tool.\(panel)"
                tool.addAction(UIAction { [unowned self] _ in onTool(panel) }, for: .touchUpInside)
                addSubview(tool)
                return (panel, tool)
            }
            setNeedsLayout()
        }
        tools.forEach { $0.button.theme = theme }
    }

    /// The clipboard's tray: out of the clipboard's button while `edits` says what it can do, tucked back in with nil.
    public func update(edits: Edits?, theme: KeyboardTheme) {
        let moves = (edits == nil) != (self.edits == nil)
        if edits != self.edits { setNeedsLayout() }
        self.edits = edits
        tray.backgroundColor = theme.key.ui
        tray.layer.shadowColor = theme.shadow.ui.cgColor
        trayDivider.backgroundColor = theme.candidateDivider.ui
        for (edit, button) in editButtons {
            button.theme = theme
            button.isEnabled = edits?.allows(edit) ?? false
        }
        guard moves, window != nil else { return }
        morph(growing: edits != nil) { self.layoutIfNeeded() }
    }

    /// The More button at the far left, before the tools.
    public func update(more menu: UIMenu?) {
        more.menu = menu
        if more.isHidden != (menu == nil) {
            more.isHidden = menu == nil
            setNeedsLayout()
        }
    }

    public func hear(_ level: Float, recorded: Double) {
        heard = recorded
        waveform.hear(level, recorded: recorded)
        mic.hear(level)
    }

    /// The cancelled recording, its cancel button and capsule, breaks into dust from the cancel button across, and
    /// the mic comes back in its place once the app has stopped; if it still listens once the dust settles, the recording shows again.
    private func dissolve() {
        let parts: [UIView] = micInBar ? [cancel, mic, waveform] : [cancel, waveform]
        let area = parts.map(\.frame).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -2, dy: -2)
        guard let dust = Dust(of: self, in: area, from: cancel.frame.midX) else { return }
        addSubview(dust)
        parts.forEach { $0.alpha = 0 }
        dissolving = true
        dust.play(away: effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1) { [weak self] in
            guard let self, dissolving, mic.phase == .listening else { return }
            dissolving = false
            parts.forEach { $0.alpha = 1 }
        }
    }

    /// Drain and Card start from the bar as it is once stopped, the mic hidden in its place until the recording has left.
    /// The cancel button fades where it was rather than tucking behind a capsule that's gone.
    private func settleUnder() {
        if let ghost = cancel.snapshotView(afterScreenUpdates: false) {
            ghost.frame = cancel.frame
            addSubview(ghost)
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                ghost.alpha = 0
                ghost.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            } completion: { _ in ghost.removeFromSuperview() }
        }
        UIView.performWithoutAnimation { layoutIfNeeded() }
        cancel.isHidden = true
        mic.alpha = 0
    }

    /// Drain: the red pours into the mic, its tail thinning, then a ripple as it lands and the mic comes up in its place.
    private func drain(_ capsule: CGRect, theme: KeyboardTheme) {
        settleUnder()
        let circle = mic.frame
        let red = CAShapeLayer()
        red.fillColor = theme.record.ui.cgColor
        layer.insertSublayer(red, below: waveform.layer)
        let steps = 16
        let paths = (0...steps).map { step -> CGPath in
            let u = CGFloat(step) / CGFloat(steps)
            let along = u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
            let thinning = pow(min(u / 0.65, 1), 3)
            return liquid(left: capsule.minX + (circle.minX - capsule.minX) * along, mic: circle, neck: 1 - 0.78 * thinning)
        }
        let flow = CAKeyframeAnimation(keyPath: "path")
        flow.values = paths
        flow.duration = 0.5
        red.path = paths[steps]
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            let ripple = CAShapeLayer()
            ripple.frame = circle
            ripple.path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: circle.size)).cgPath
            ripple.fillColor = nil
            ripple.strokeColor = theme.record.ui.cgColor
            ripple.lineWidth = 2
            ripple.opacity = 0
            layer.addSublayer(ripple)
            CATransaction.begin()
            CATransaction.setCompletionBlock { ripple.removeFromSuperlayer() }
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 1
            grow.toValue = 1.8
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.6
            fade.toValue = 0
            let spread = CAAnimationGroup()
            spread.animations = [grow, fade]
            spread.duration = 0.5
            spread.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ripple.add(spread, forKey: "ripple")
            CATransaction.commit()
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.mic.alpha = 1
            }
            red.removeFromSuperlayer()
        }
        red.add(flow, forKey: "flow")
        CATransaction.commit()
    }

    /// Card: the recording folds into a card with its length beside the mic, which lifts away off the keyboard's top as
    /// the mic comes back.
    private func lift(_ capsule: CGRect, theme: KeyboardTheme) {
        settleUnder()
        let card = StopCard(length: Waveform.clock(Int(heard)), tint: theme.label.ui)
        card.backgroundColor = theme.record.ui
        card.frame = capsule
        addSubview(card)
        let width: CGFloat = 84
        let rest = CGRect(x: mic.frame.minX - 8 - width, y: capsule.minY, width: width, height: capsule.height)
        UIView.animate(springDuration: 0.42, bounce: 0.1) {
            card.frame = rest
            card.backgroundColor = theme.candidatePill.ui
        }
        UIView.animate(withDuration: 0.4, delay: 0.42, options: [.curveEaseIn]) {
            card.transform = CGAffineTransform(translationX: 0, y: -(rest.maxY + 12))
            card.alpha = 0
        } completion: { _ in card.removeFromSuperview() }
        mic.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        UIView.animate(springDuration: 0.45, bounce: 0.25, delay: 0.3, options: [.allowUserInteraction]) {
            self.mic.alpha = 1
            self.mic.transform = .identity
        }
    }

    private func reappear() {
        dissolving = false
        UIView.performWithoutAnimation { layoutIfNeeded() }
        cancel.isHidden = true
        let returning: [UIView] = slots + dividers + [strip]
        returning.forEach { $0.alpha = 0 }
        mic.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        UIView.animate(springDuration: 0.45, bounce: 0.25, delay: 0.3, options: [.allowUserInteraction]) {
            self.mic.alpha = 1
            self.mic.transform = .identity
        }
        UIView.animate(withDuration: 0.3, delay: 0.35, options: [.curveEaseOut, .allowUserInteraction]) {
            returning.forEach { $0.alpha = 1 }
        }
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

    /// Out, the tray runs from the clipboard's button over the suggestions, its buttons a little apart and History set off
    /// past the divider, closer where the bar is short of room; tucked, it's the button's own circle, its tools shrunk into it. The suggestions fade under it.
    private func placeTray(end: CGFloat, reach: UIEdgeInsets) {
        guard let clip = tools.first(where: { $0.panel == .clipboard })?.button.frame else {
            tray.isHidden = true
            editButtons.forEach { $0.button.isHidden = true }
            return
        }
        let out = edits != nil
        let apart = clip.width * 0.3
        let step = min(clip.width + apart, (end - clip.maxX - apart) / CGFloat(editButtons.count))
        let places = editButtons.indices.map { clip.offsetBy(dx: CGFloat($0 + 1) * step + ($0 == 3 ? apart : 0), dy: 0) }
        let inset = (step - clip.width) / 2
        let around = UIEdgeInsets(top: reach.top, left: -inset, bottom: reach.bottom, right: -inset)
        tray.isHidden = false
        tray.frame = out ? CGRect(x: clip.minX, y: clip.minY, width: places[places.count - 1].maxX - clip.minX, height: clip.height) : clip
        tray.layer.cornerRadius = clip.height / 2
        tray.alpha = out ? 1 : 0
        tools.first { $0.panel == .clipboard }?.button.isOn = out
        for ((_, button), place) in zip(editButtons, places) {
            button.isHidden = false
            button.transform = .identity
            button.place(place, glyph: toolbar.glyph, reach: around)
            button.center = out ? CGPoint(x: place.midX, y: place.midY) : CGPoint(x: clip.midX, y: clip.midY)
            button.transform = out ? .identity : CGAffineTransform(scaleX: 0.4, y: 0.4)
            button.alpha = out ? (button.isEnabled ? 1 : 0.3) : 0
            button.isUserInteractionEnabled = out
        }
        let paste = places[2], history = places[3]
        trayDivider.frame = CGRect(x: ((paste.maxX + history.minX) / 2).rounded(scale: traitCollection.displayScale) - 0.5, y: clip.midY - 8, width: 1, height: 16)
        trayDivider.alpha = out ? 1 : 0
        let under: CGFloat = out ? 0 : 1
        (slots + dividers + [strip, notice, stack] as [UIView]).forEach { $0.alpha = under }
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

    override public func layoutSubviews() {
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
        placeTray(end: CGFloat(layout.mic.map { $0.x - BarLayout.gap } ?? layout.maxX), reach: reach)
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
        accessibilityIdentifier = "iikb.suggestion.emoji.\(index)"
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
        accessibilityIdentifier = "iikb.suggestion.\(index)"
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

extension SuggestionBar.Edit {
    var title: String {
        switch self {
        case .cut: "Cut"
        case .copy: "Copy"
        case .paste: "Paste"
        case .history: "Clipboard History"
        }
    }

    var symbol: String {
        switch self {
        case .cut: "scissors"
        case .copy: "square.on.square"
        case .paste: "doc.on.clipboard"
        case .history: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }
}
