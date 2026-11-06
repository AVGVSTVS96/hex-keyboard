import UIKit

/// The recording: the time so far, then bars that trace your voice, newest on the right, each as bright as it was loud,
/// the older ones fading out to the left. Each level the app publishes enters at the right edge and the bars glide left
/// one place in the time the app took to hear it, so they move at the speed of the recording, never on a timer of the
/// keyboard's own. While dictations wait for the model, it counts them at its right. In the bar it lies over the mic's
/// capsule, masked to it, or on its own where the mic is the Record Key, `insets` in from its ends.
final class Waveform: UIView {
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
        time.accessibilityIdentifier = "iikb.time"
        saved.font = .systemFont(ofSize: 15, weight: .medium)
        saved.textAlignment = .right
        saved.accessibilityIdentifier = "iikb.saved"
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

    /// Squeeze: the stopped bars rush right into the stop as the capsule springs after them.
    func rush() {
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.strip.transform = self.strip.transform.translatedBy(x: self.track.bounds.width * 0.7, y: 0)
            self.alpha = 0
        }
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
            strip.bounds = CGRect(x: 0, y: 0, width: 1, height: bounds.height)
            strip.center = CGPoint(x: 0.5, y: bounds.midY)
            for (index, bar) in bars.enumerated() { bar.view.frame = frame(of: index) }
        }
        if refilling { UIView.performWithoutAnimation { strip.transform = slid } } else { strip.transform = slid }
    }
}
