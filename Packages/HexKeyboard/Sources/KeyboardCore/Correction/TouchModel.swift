/// Where your taps for each key really land, learned from every labeled tap.
///
/// Each key's taps are a 2D Gaussian with unknown mean and covariance under a Normal-Inverse-Wishart prior, so every
/// labeled tap is a closed-form conjugate update and the likelihood of a new tap is the posterior predictive
/// Student-t. A key's mean starts at the drawn center, worth one tap (κ₀ = 1). Its spread starts at your spread over
/// all keys of its kind (letters, or the space bar), which itself starts at the drawn key cell being ±2σ; each prior
/// is worth ν₀ = 10 taps, which says people's tap spread is known to about ±30%. So the first taps anywhere teach every
/// key how steady you are, each key's own taps move its center and shape, and nothing has a rate or schedule.
///
/// Offsets are in key cells, so a model survives small width changes; each layout signature (device class,
/// orientation, layer) keeps its own keys.
///
/// `recent` keeps each key's last taps for showing you where they land. The model never reads it, and it holds no
/// order across keys, so it can't spell out what you typed.
public struct TouchModel: Codable, Hashable, Sendable {
    private var layouts: [String: [String: Touches]] = [:]
    private(set) var recent: [String: [String: [Offset]]] = [:]

    static let priorSpread = 0.2
    static let priorWeight = 10.0
    static let recentTaps = 48

    public init() {}

    public init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layouts = try container.decode([String: [String: Touches]].self, forKey: .layouts)
        recent = try container.decodeIfPresent([String: [String: [Offset]]].self, forKey: .recent) ?? [:]
    }

    public var isEmpty: Bool { layouts.isEmpty }

    public func taps(for label: String, on grid: KeyGrid) -> Int {
        Int(layouts[grid.signature]?[label]?.count ?? 0)
    }

    public mutating func learn(_ samples: some Sequence<TapSample>, on grid: KeyGrid) {
        for sample in samples {
            guard let frame = grid.frame(of: sample.intended) else { continue }
            let (u, v) = Self.offset(x: sample.tap.x, y: sample.tap.y, in: grid.cell(of: frame))
            layouts[grid.signature, default: [:]][sample.intended, default: Touches()].add(u, v)
            var taps = recent[grid.signature, default: [:]][sample.intended, default: []]
            taps.append(Offset(x: (u * 1000).rounded() / 1000, y: (v * 1000).rounded() / 1000))
            recent[grid.signature, default: [:]][sample.intended] = Array(taps.suffix(Self.recentTaps))
        }
    }

    /// The layouts you've typed on, most taps first.
    public var signatures: [(signature: String, taps: Int)] {
        layouts.map { ($0.key, Int($0.value.values.reduce(0) { $0 + $1.count })) }.sorted { $0.taps > $1.taps }
    }

    /// The model for one keyboard layout, with the shared spreads worked out once.
    public func layout(_ grid: KeyGrid) -> Layout {
        Layout(grid: grid, keys: layouts[grid.signature] ?? [:])
    }

    public func logLikelihood(x: Double, y: Double, for label: String, on grid: KeyGrid) -> Double? {
        layout(grid).logLikelihood(x: x, y: y, for: label)
    }

    public func center(of label: String, on grid: KeyGrid) -> (x: Double, y: Double) {
        layout(grid).center(of: label)
    }

    static func offset(x: Double, y: Double, in cell: Rect) -> (Double, Double) {
        ((x - cell.midX) / cell.width, (y - cell.midY) / cell.height)
    }

    public struct Layout {
        let grid: KeyGrid
        private(set) var keys: [String: Touches]
        private var letters: Spread
        private var space: Spread

        init(grid: KeyGrid, keys: [String: Touches]) {
            self.grid = grid
            self.keys = keys
            letters = Spread(pooling: keys.lazy.filter { $0.key != " " }.map(\.value))
            space = Spread(pooling: keys[" "].map { [$0] } ?? [])
        }

        /// Learns one tap, as `TouchModel.learn` would on this layout's grid.
        mutating func learn(_ sample: TapSample) {
            guard let frame = grid.frame(of: sample.intended) else { return }
            let (u, v) = TouchModel.offset(x: sample.tap.x, y: sample.tap.y, in: grid.cell(of: frame))
            keys[sample.intended, default: Touches()].add(u, v)
            if sample.intended == " " {
                space = Spread(pooling: keys[" "].map { [$0] } ?? [])
            } else {
                letters = Spread(pooling: keys.lazy.filter { $0.key != " " }.map(\.value))
            }
        }

        /// Log density, per square point, of a tap at (x, y) when you meant the key labeled `label`.
        public func logLikelihood(x: Double, y: Double, for label: String) -> Double? {
            guard let frame = grid.frame(of: label) else { return nil }
            let cell = grid.cell(of: frame)
            let (u, v) = TouchModel.offset(x: x, y: y, in: cell)
            return posterior(label).logPredictive(u, v) - Math.log(cell.width * cell.height)
        }

        /// The learned center of a key's taps, in key cells from the drawn center.
        public func center(of label: String) -> (x: Double, y: Double) {
            posterior(label).mean
        }

        func posterior(_ label: String) -> Posterior {
            Posterior(keys[label] ?? Touches(), spread: label == " " ? space : letters)
        }
    }
}

/// The expected covariance of a group of keys' taps around their own centers, starting from the drawn cell.
struct Spread {
    let xx, xy, yy: Double

    init(pooling keys: some Sequence<Touches>) {
        let weight = TouchModel.priorWeight - 3
        let prior = weight * TouchModel.priorSpread * TouchModel.priorSpread
        var (xx, xy, yy, count) = (prior, 0.0, prior, 0.0)
        for key in keys {
            let shrink = key.count / (1 + key.count)
            xx += key.scatterXX + shrink * key.meanX * key.meanX
            xy += key.scatterXY + shrink * key.meanX * key.meanY
            yy += key.scatterYY + shrink * key.meanY * key.meanY
            count += key.count
        }
        let scale = 1 / (weight + count)
        (self.xx, self.xy, self.yy) = (xx * scale, xy * scale, yy * scale)
    }
}

struct Offset: Codable, Hashable, Sendable {
    var x, y: Double
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

    init(_ touches: Touches, spread: Spread) {
        let n = touches.count
        let kappa = 1 + n, nu = TouchModel.priorWeight + n
        let weight = TouchModel.priorWeight - 3
        let shrink = n / kappa
        mean = (shrink * touches.meanX, shrink * touches.meanY)
        let psiXX = weight * spread.xx + touches.scatterXX + shrink * touches.meanX * touches.meanX
        let psiXY = weight * spread.xy + touches.scatterXY + shrink * touches.meanX * touches.meanY
        let psiYY = weight * spread.yy + touches.scatterYY + shrink * touches.meanY * touches.meanY
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
