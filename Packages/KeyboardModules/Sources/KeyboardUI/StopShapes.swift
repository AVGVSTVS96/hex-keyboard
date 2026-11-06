import UIKit

/// Drain's liquid: the capsule from its left end `left` to the mic's circle, its tail thinned to `neck` of the
/// capsule's height, as if pulled into the mic through a straw. At `neck` 1 it's the capsule itself.
func liquid(left: CGFloat, mic: CGRect, neck: CGFloat) -> CGPath {
    let radius = mic.height / 2, middle = mic.midY, head = mic.minX, tail = max(head - left, 0), thin = radius * neck
    let path = UIBezierPath()
    path.move(to: CGPoint(x: head + radius, y: mic.minY))
    path.addCurve(
        to: CGPoint(x: left + thin, y: middle - thin),
        controlPoint1: CGPoint(x: head - tail * 0.25, y: mic.minY), controlPoint2: CGPoint(x: head - tail * 0.45, y: middle - thin)
    )
    path.addArc(withCenter: CGPoint(x: left + thin, y: middle), radius: thin, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    path.addCurve(
        to: CGPoint(x: head + radius, y: mic.maxY),
        controlPoint1: CGPoint(x: head - tail * 0.45, y: middle + thin), controlPoint2: CGPoint(x: head - tail * 0.25, y: mic.maxY)
    )
    path.close()
    path.append(UIBezierPath(ovalIn: mic))
    return path.cgPath
}

/// Card's card: the recording's length and a little waveform, in a pill.
final class StopCard: UIView {
    init(length: String, tint: UIColor) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
        let time = UILabel()
        time.text = length
        time.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        time.textColor = tint
        let wave = UIImageView(image: UIImage(systemName: "waveform", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        wave.tintColor = tint.withAlphaComponent(0.85)
        let row = UIStackView(arrangedSubviews: [time, wave])
        row.spacing = 6
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([row.centerXAnchor.constraint(equalTo: centerXAnchor), row.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
