import UIKit
import KeyboardCore

/// Once you stop, the dictations recorded while the model gets ready, as a stack of cards beside what it's doing: the
/// next to be typed in front with its length, up to three more tucked behind it and peeking out 6 to its right, each a
/// little smaller and a solid shade further back, so no card shows through another. A new one slides in behind from
/// the mic's side; the front one lifts away as it's typed, and the next steps forward into its place.
final class PendingStack: UIView {
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
        words.accessibilityIdentifier = "iikb.waiting"
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
        label.accessibilityIdentifier = "iikb.saved.\(index)"
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
