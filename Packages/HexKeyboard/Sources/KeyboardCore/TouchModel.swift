/// Where your taps for each key really land, learned from every labeled tap.
///
/// Each key's taps are a 2D Gaussian with unknown mean and covariance under a Normal-Inverse-Wishart prior, so every
/// labeled tap is a closed-form conjugate update and the likelihood of a new tap is the posterior predictive
/// Student-t. The prior is the key as drawn: centered on it, worth one tap (κ₀ = 1), and with the weakest Wishart
/// (ν₀ = 4, the least that gives an expected spread) whose expected spread puts the drawn key cell at ±2σ. A key
/// you've tapped twice barely moves; after a few dozen taps it's yours.
///
/// Offsets are in key cells, so a model survives small width changes; each layout signature (device class,
/// orientation, layer) keeps its own keys.
public struct TouchModel: Codable, Hashable, Sendable {
    private var layouts: [String: [String: Touches]] = [:]

    static let priorSpread = 0.25

    public init() {}

    public var isEmpty: Bool { layouts.isEmpty }

    public func taps(for label: String, on grid: KeyGrid) -> Int {
        Int(layouts[grid.signature]?[label]?.count ?? 0)
    }

    public mutating func learn(_ samples: some Sequence<TapSample>, on grid: KeyGrid) {
        for sample in samples {
            guard let frame = grid.frame(of: sample.intended) else { continue }
            let (u, v) = Self.offset(x: sample.tap.x, y: sample.tap.y, in: grid.cell(of: frame))
            layouts[grid.signature, default: [:]][sample.intended, default: Touches()].add(u, v)
        }
    }

    /// The learned center of a key's taps, in key cells from the drawn center.
    public func center(of label: String, on grid: KeyGrid) -> (x: Double, y: Double) {
        let posterior = Posterior(layouts[grid.signature]?[label] ?? Touches())
        return (posterior.mean.x, posterior.mean.y)
    }

    /// Log density, per square point, of a tap at (x, y) when you meant the key labeled `label`.
    public func logLikelihood(x: Double, y: Double, for label: String, on grid: KeyGrid) -> Double? {
        guard let frame = grid.frame(of: label) else { return nil }
        return logLikelihood(x: x, y: y, cell: grid.cell(of: frame), touches: layouts[grid.signature]?[label])
    }

    func logLikelihood(x: Double, y: Double, cell: Rect, touches: Touches?) -> Double {
        let (u, v) = Self.offset(x: x, y: y, in: cell)
        return Posterior(touches ?? Touches()).logPredictive(u, v) - Math.log(cell.width * cell.height)
    }

    func touches(for label: String, signature: String) -> Touches? {
        layouts[signature]?[label]
    }

    static func offset(x: Double, y: Double, in cell: Rect) -> (Double, Double) {
        ((x - cell.midX) / cell.width, (y - cell.midY) / cell.height)
    }
}

struct Touches: Codable, Hashable, Sendable {
    private(set) var count = 0.0
    private(set) var meanX = 0.0, meanY = 0.0
    private(set) var scatterXX = 0.0, scatterXY = 0.0, scatterYY = 0.0

    mutating func add(_ x: Double, _ y: Double) {
        count += 1
        let dx = x - meanX, dy = y - meanY
        meanX += dx / count
        meanY += dy / count
        scatterXX += dx * (x - meanX)
        scatterXY += dx * (y - meanY)
        scatterYY += dy * (y - meanY)
    }
}

struct Posterior {
    let mean: (x: Double, y: Double)
    let dof: Double
    let xx, xy, yy: Double

    init(_ touches: Touches) {
        let n = touches.count
        let kappa = 1 + n, nu = 4 + n
        let prior = TouchModel.priorSpread * TouchModel.priorSpread
        let shrink = n / kappa
        mean = (shrink * touches.meanX, shrink * touches.meanY)
        let psiXX = prior + touches.scatterXX + shrink * touches.meanX * touches.meanX
        let psiXY = touches.scatterXY + shrink * touches.meanX * touches.meanY
        let psiYY = prior + touches.scatterYY + shrink * touches.meanY * touches.meanY
        dof = nu - 1
        let scale = (kappa + 1) / (kappa * dof)
        (xx, xy, yy) = (psiXX * scale, psiXY * scale, psiYY * scale)
    }

    func logPredictive(_ u: Double, _ v: Double) -> Double {
        let determinant = xx * yy - xy * xy
        let du = u - mean.x, dv = v - mean.y
        let distance = (yy * du * du - 2 * xy * du * dv + xx * dv * dv) / determinant
        return -Math.log(2 * Double.pi) - Math.log(determinant) / 2 - (dof / 2 + 1) * Math.log1p(distance / dof)
    }
}
