extension Math {
    static func exp(_ x: SIMD8<Float>) -> SIMD8<Float> {
        let x = x.clamped(lowerBound: SIMD8(repeating: -87), upperBound: SIMD8(repeating: 88))
        let k = (x * 1.442_695_04).rounded(.toNearestOrEven)
        let r = x - k * 0.693_359_375 - k * -2.121_944_4e-4
        let p = 1 + r * (1 + r * (0.5 + r * (1.0 / 6 + r * (1.0 / 24 + r * (1.0 / 120 + r * (1.0 / 720))))))
        let scale = unsafeBitCast((SIMD8<Int32>(k, rounding: .toNearestOrEven) &+ 127) &<< 23, to: SIMD8<Float>.self)
        return p * scale
    }

    static func sigmoid(_ x: SIMD8<Float>) -> SIMD8<Float> {
        1 / (1 + exp(-x))
    }

    static func hardswish(_ x: SIMD8<Float>) -> SIMD8<Float> {
        x * (x + 3).clamped(lowerBound: SIMD8(repeating: 0), upperBound: SIMD8(repeating: 6)) / 6
    }

    static func sigmoid(_ x: Float) -> Float {
        sigmoid(SIMD8(repeating: x))[0]
    }

    static func cos(_ x: Double) -> Double {
        let twoPi = 2 * Double.pi
        var x = x - (x / twoPi).rounded() * twoPi
        x = abs(x)
        var sign = 1.0
        if x > Double.pi / 2 {
            x = Double.pi - x
            sign = -1
        }
        let x2 = x * x
        var term = 1.0, sum = 1.0
        for n in stride(from: 2.0, through: 18, by: 2) {
            term *= -x2 / (n * (n - 1))
            sum += term
        }
        return sign * sum
    }

    static func atan2(_ y: Double, _ x: Double) -> Double {
        guard x != 0 || y != 0 else { return 0 }
        let z = min(abs(x), abs(y)) / max(abs(x), abs(y))
        let reduce = z > 0.414_213_562_373_095
        let t = reduce ? (z - 1) / (z + 1) : z
        let t2 = t * t
        var term = t, sum = 0.0
        for n in stride(from: 1.0, through: 31, by: 2) {
            sum += term / n
            term *= -t2
        }
        var angle = reduce ? Double.pi / 4 + sum : sum
        if abs(y) > abs(x) { angle = Double.pi / 2 - angle }
        if x < 0 { angle = Double.pi - angle }
        return y < 0 ? -angle : angle
    }
}
