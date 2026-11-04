/// The few operations of the network, over flat float buffers laid out step by step (a step's channels contiguous),
/// eight channels at a time.
enum Kernel {
    typealias Vector = SIMD8<Float>

    private static func load(_ pointer: UnsafePointer<Float>, _ at: Int) -> Vector {
        UnsafeRawPointer(pointer + at).loadUnaligned(as: Vector.self)
    }

    private static func store(_ value: Vector, _ pointer: UnsafeMutablePointer<Float>, _ at: Int) {
        UnsafeMutableRawPointer(pointer + at).storeBytes(of: value, as: Vector.self)
    }

    /// `out[r] = bias + x[r] · weights` for each row, where `weights` holds a row of `outputs` per input.
    static func matmul(_ x: UnsafePointer<Float>, rows: Int, inputs: Int, _ weights: UnsafeRawPointer, _ bias: UnsafeRawPointer,
                       outputs: Int, into out: UnsafeMutablePointer<Float>) {
        let stride = outputs * 4
        for o in Swift.stride(from: 0, to: outputs, by: 8) {
            let start = bias.loadUnaligned(fromByteOffset: o * 4, as: Vector.self)
            var r = 0
            while r + 4 <= rows {
                var a0 = start, a1 = start, a2 = start, a3 = start
                let x0 = x + r * inputs, x1 = x0 + inputs, x2 = x1 + inputs, x3 = x2 + inputs
                var w = weights + o * 4
                for i in 0..<inputs {
                    let wv = w.loadUnaligned(as: Vector.self)
                    a0 += x0[i] * wv
                    a1 += x1[i] * wv
                    a2 += x2[i] * wv
                    a3 += x3[i] * wv
                    w += stride
                }
                store(a0, out, r * outputs + o)
                store(a1, out, (r + 1) * outputs + o)
                store(a2, out, (r + 2) * outputs + o)
                store(a3, out, (r + 3) * outputs + o)
                r += 4
            }
            while r < rows {
                var a = start
                let row = x + r * inputs
                var w = weights + o * 4
                for i in 0..<inputs {
                    a += row[i] * w.loadUnaligned(as: Vector.self)
                    w += stride
                }
                store(a, out, r * outputs + o)
                r += 1
            }
        }
    }

    static func hardswish(_ x: UnsafeMutablePointer<Float>, _ count: Int) {
        for i in Swift.stride(from: 0, to: count, by: 8) { store(Math.hardswish(load(x, i)), x, i) }
    }

    static func sigmoid(_ x: UnsafeMutablePointer<Float>, _ count: Int) {
        for i in Swift.stride(from: 0, to: count, by: 8) { store(Math.sigmoid(load(x, i)), x, i) }
    }

    /// A convolution of each channel by its own taps along the steps, zero-padded to keep their number.
    static func depthwise(_ x: UnsafePointer<Float>, steps: Int, channels: Int, taps: Int, dilation: Int, _ weights: UnsafePointer<Float>,
                          _ bias: UnsafePointer<Float>?, into out: UnsafeMutablePointer<Float>) {
        for t in 0..<steps {
            for c in Swift.stride(from: 0, to: channels, by: 8) {
                var sum = bias.map { load($0, c) } ?? Vector()
                for k in 0..<taps {
                    let source = t + (k - taps / 2) * dilation
                    if source >= 0 && source < steps { sum += load(weights, k * channels + c) * load(x, source * channels + c) }
                }
                store(sum, out, t * channels + c)
            }
        }
    }

    /// The first half of each step's `2 * width` channels through a sigmoid, times the second half.
    static func gate(_ x: UnsafePointer<Float>, steps: Int, width: Int, into out: UnsafeMutablePointer<Float>) {
        for t in 0..<steps {
            for c in Swift.stride(from: 0, to: width, by: 8) {
                store(Math.sigmoid(load(x, t * 2 * width + c)) * load(x, t * 2 * width + width + c), out, t * width + c)
            }
        }
    }

    /// Global response normalization: each channel scaled by how strong it is over the steps next to the mean strength.
    static func normalize(_ x: UnsafeMutablePointer<Float>, steps: Int, width: Int, gamma: UnsafePointer<Float>, beta: UnsafePointer<Float>,
                          scratch: UnsafeMutablePointer<Float>) {
        for c in Swift.stride(from: 0, to: width, by: 8) {
            var energy = Vector()
            for t in 0..<steps {
                let v = load(x, t * width + c)
                energy += v * v
            }
            store((energy / Float(steps) + 1e-6).squareRoot(), scratch, c)
        }
        var mean: Float = 0
        for c in 0..<width { mean += scratch[c] }
        mean = mean / Float(width) + 1e-6
        for c in Swift.stride(from: 0, to: width, by: 8) {
            let factor = load(gamma, c) * load(scratch, c) / mean + 1, shift = load(beta, c)
            for t in 0..<steps { store(load(x, t * width + c) * factor + shift, x, t * width + c) }
        }
    }

    static func mean(_ x: UnsafePointer<Float>, steps: Int, width: Int, into out: UnsafeMutablePointer<Float>) {
        for c in Swift.stride(from: 0, to: width, by: 8) {
            var sum = Vector()
            for t in 0..<steps { sum += load(x, t * width + c) }
            store(sum / Float(steps), out, c)
        }
    }

    /// `x * scale + residual`, the scale one per channel.
    static func scaleAndAdd(_ x: UnsafePointer<Float>, steps: Int, width: Int, scale: UnsafePointer<Float>, residual: UnsafePointer<Float>,
                            into out: UnsafeMutablePointer<Float>) {
        for t in 0..<steps {
            for c in Swift.stride(from: 0, to: width, by: 8) {
                store(load(x, t * width + c) * load(scale, c) + load(residual, t * width + c), out, t * width + c)
            }
        }
    }

    static func layerNorm(_ x: UnsafeMutablePointer<Float>, steps: Int, width: Int, _ weight: UnsafePointer<Float>, _ bias: UnsafePointer<Float>) {
        for t in 0..<steps {
            let row = x + t * width
            var sum = Vector()
            for c in Swift.stride(from: 0, to: width, by: 8) { sum += load(row, c) }
            let mean = sum.sum() / Float(width)
            var spread = Vector()
            for c in Swift.stride(from: 0, to: width, by: 8) {
                let d = load(row, c) - mean
                spread += d * d
            }
            let scale = 1 / (spread.sum() / Float(width) + 1e-5).squareRoot()
            for c in Swift.stride(from: 0, to: width, by: 8) { store((load(row, c) - mean) * scale * load(weight, c) + load(bias, c), row, c) }
        }
    }
}
