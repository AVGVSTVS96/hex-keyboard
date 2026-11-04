extension Swipe {
    /// What the network says at each of its 32 steps: ln P of each letter a–z and of a blank, in that order, row by row.
    public struct Emissions: Sendable {
        public static let steps = Swipe.steps, classes = Swipe.classes
        public let values: [Float]

        public subscript(step: Int, letter: Int) -> Float { values[step * Self.classes + letter] }
    }

    /// The encoder's output for a path on a layout, then the decoder's correction of it when `refined`. `nil` for a
    /// path of fewer than two points.
    public func emissions(of path: [SwipePoint], on layout: SwipeLayout, refined: Bool = true) -> Emissions? {
        guard path.count >= 2 else { return nil }
        let (x, y) = layout.resampled(path)
        return bytes.withUnsafeBytes { raw in
            let scratch = Scratch()
            let joint = encode(x: x, y: y, layout: layout, scratch, raw)
            let out = refined ? refine(joint, scratch, raw) : joint
            return Emissions(values: (0..<Self.steps).flatMap { step in
                (0..<Self.classes).map { out[step * (refined ? Self.headWidth : Self.decoderInputs) + $0] }
            })
        }
    }

    final class Scratch {
        static let capacity = 160_000
        let base = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        private var used = 0

        init() { base.initialize(repeating: 0, count: Self.capacity) }
        deinit { base.deallocate() }

        func take(_ count: Int) -> UnsafeMutablePointer<Float> {
            defer { used += (count + 7) / 8 * 8 }
            precondition(used + count <= Self.capacity)
            return base + used
        }
    }

    /// Steps 0..<32 of the decoder's input: log-probabilities of the classes (a–z, blank), the 64 coefficients, the gate.
    func encode(x: [Float], y: [Float], layout: SwipeLayout, _ scratch: Scratch, _ raw: UnsafeRawBufferPointer) -> UnsafeMutablePointer<Float> {
        let steps = Self.inputSteps
        func vector(_ name: String) -> UnsafePointer<Float> { tensor(name, in: raw).assumingMemoryBound(to: Float.self) }

        let features = scratch.take(steps * 8)
        let vx = scratch.take(steps), vy = scratch.take(steps), ax = scratch.take(steps), ay = scratch.take(steps)
        let angle = scratch.take(steps), curvature = scratch.take(steps)
        x.withUnsafeBufferPointer { x in
            y.withUnsafeBufferPointer { y in
                Self.savitzkyGolay(x.baseAddress!, vector("encoder.savgol_d1_x_weight"), vx)
                Self.savitzkyGolay(y.baseAddress!, vector("encoder.savgol_d1_y_weight"), vy)
                Self.savitzkyGolay(x.baseAddress!, vector("encoder.savgol_d2_x_weight"), ax)
                Self.savitzkyGolay(y.baseAddress!, vector("encoder.savgol_d2_y_weight"), ay)
                var turns = 0.0, previous = 0.0
                for t in 0..<steps {
                    let current = Math.atan2(Double(vy[t]), Double(vx[t]))
                    if t > 0 {
                        let step = current - previous
                        if step > Double.pi { turns -= 2 * Double.pi } else if step < -Double.pi { turns += 2 * Double.pi }
                    }
                    previous = current
                    angle[t] = Float(current + turns)
                }
                Self.savitzkyGolay(angle, vector("encoder.savgol_d1_curv_weight"), curvature)
                for t in 0..<steps {
                    let row = features + t * 8
                    row[0] = x[t]
                    row[1] = y[t]
                    row[2] = vx[t]
                    row[3] = vy[t]
                    row[4] = ax[t]
                    row[5] = ay[t]
                    row[6] = (vx[t] * vx[t] + vy[t] * vy[t] + 1e-8).squareRoot()
                    row[7] = min(max(curvature[t], -2), 2)
                }
            }
        }

        let taps = Self.kernel, half = taps / 2
        let columns = scratch.take(steps * taps * 8)
        for t in 0..<steps {
            for k in 0..<taps {
                let source = t + k - half, target = columns + t * taps * 8 + k * 8
                if source >= 0 && source < steps { target.update(from: features + source * 8, count: 8) } else { target.update(repeating: 0, count: 8) }
            }
        }
        var h = scratch.take(steps * Self.hidden)
        Kernel.matmul(columns, rows: steps, inputs: taps * 8, tensor("encoder.backbone_input_conv_weight", in: raw),
                      tensor("encoder.backbone_input_conv_bias", in: raw), outputs: Self.hidden, into: h)
        Kernel.hardswish(h, steps * Self.hidden)

        var other = scratch.take(steps * Self.hidden)
        let depthwise = scratch.take(steps * Self.hidden), expanded = scratch.take(steps * 4 * Self.hidden)
        let gated = scratch.take(steps * Self.wide), projected = scratch.take(steps * Self.hidden)
        let norm = scratch.take(Self.wide), pooled = scratch.take(Self.hidden), squeezed = scratch.take(Self.hidden / 4)
        for b in 0..<Self.blocks {
            let block = "encoder.backbone_blocks_\(b)_"
            Kernel.depthwise(h, steps: steps, channels: Self.hidden, taps: taps, dilation: Self.dilations[b],
                             vector(block + "dwconv_weight"), vector(block + "dwconv_bias"), into: depthwise)
            Kernel.matmul(depthwise, rows: steps, inputs: Self.hidden, tensor(block + "pwconv1_weight", in: raw),
                          tensor(block + "pwconv1_bias", in: raw), outputs: 4 * Self.hidden, into: expanded)
            Kernel.gate(expanded, steps: steps, width: Self.wide, into: gated)
            Kernel.normalize(gated, steps: steps, width: Self.wide, gamma: vector(block + "grn_gamma"), beta: vector(block + "grn_beta"), scratch: norm)
            Kernel.matmul(gated, rows: steps, inputs: Self.wide, tensor(block + "pwconv2_weight", in: raw),
                          tensor(block + "pwconv2_bias", in: raw), outputs: Self.hidden, into: projected)
            Kernel.mean(projected, steps: steps, width: Self.hidden, into: pooled)
            Kernel.matmul(pooled, rows: 1, inputs: Self.hidden, tensor(block + "se_fc1_weight", in: raw),
                          tensor(block + "se_fc1_bias", in: raw), outputs: Self.hidden / 4, into: squeezed)
            for i in 0..<Self.hidden / 4 { squeezed[i] = max(squeezed[i], 0) }
            Kernel.matmul(squeezed, rows: 1, inputs: Self.hidden / 4, tensor(block + "se_fc2_weight", in: raw),
                          tensor(block + "se_fc2_bias", in: raw), outputs: Self.hidden, into: pooled)
            Kernel.sigmoid(pooled, Self.hidden)
            Kernel.scaleAndAdd(projected, steps: steps, width: Self.hidden, scale: pooled, residual: h, into: other)
            swap(&h, &other)
        }

        let adapted = scratch.take(Self.steps * Self.wide)
        Kernel.matmul(h, rows: Self.steps, inputs: 2 * Self.hidden, tensor("encoder.adapter_0_weight", in: raw),
                      tensor("encoder.adapter_0_bias", in: raw), outputs: Self.wide, into: adapted)
        let gates = scratch.take(Self.steps * 8)
        Kernel.matmul(adapted, rows: Self.steps, inputs: Self.wide, tensor("encoder.spatial_head_lambda_proj_weight", in: raw),
                      tensor("encoder.spatial_head_lambda_proj_bias", in: raw), outputs: 8, into: gates)
        let joint = scratch.take(Self.steps * Self.decoderInputs)
        let coefficients = scratch.take(Self.steps * Self.coefficients)
        Kernel.matmul(adapted, rows: Self.steps, inputs: Self.wide, tensor("encoder.spatial_head_coeff_proj_weight", in: raw),
                      tensor("encoder.spatial_head_coeff_proj_bias", in: raw), outputs: Self.coefficients, into: coefficients)

        let basis = Self.basis(layout)
        var logits = [Float](repeating: 0, count: Self.letters)
        for t in 0..<Self.steps {
            let gate = Math.sigmoid(gates[t * 8])
            let c = coefficients + t * Self.coefficients
            for k in 0..<Self.letters {
                var sum: Float = 0
                for j in 0..<Self.coefficients { sum += c[j] * basis[k * Self.coefficients + j] }
                logits[k] = sum
            }
            let high = logits.max()!
            var total: Float = 0
            for k in 0..<Self.letters { total += Math.exp(SIMD8(repeating: logits[k] - high))[0] }
            let letterOffset = Float(Math.log(Double(max(gate, 1e-7)))) - high - Float(Math.log(Double(total)))
            let row = joint + t * Self.decoderInputs
            for k in 0..<Self.letters { row[k] = max(logits[k] + letterOffset, -100) }
            row[Self.letters] = max(Float(Math.log(Double(max(1 - gate, 1e-7)))), -100)
            (row + Self.classes).update(from: c, count: Self.coefficients)
            row[Self.classes + Self.coefficients] = gate
        }
        return joint
    }

    static func savitzkyGolay(_ input: UnsafePointer<Float>, _ kernel: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>) {
        for t in 0..<inputSteps {
            var sum: Float = 0
            for k in 0..<Self.kernel { sum.addProduct(kernel[k], input[min(max(t + k - Self.kernel / 2, 0), inputSteps - 1)]) }
            out[t] = sum
        }
    }

    /// Each key's row of the cosine basis, `cos(π u x) cos(π v y)` over u, v < 8, u-major.
    static func basis(_ layout: SwipeLayout) -> [Float] {
        var basis: [Float] = []
        for center in layout.centers {
            let cx = (0..<frequencies).map { Float(Math.cos(Double.pi * Double($0) * center.x)) }
            let cy = (0..<frequencies).map { Float(Math.cos(Double.pi * Double($0) * center.y)) }
            for u in 0..<frequencies { for v in 0..<frequencies { basis.append(cx[u] * cy[v]) } }
        }
        return basis
    }

    /// The decoder over `joint`: 32 steps of 32 floats, the first 27 its log-probabilities.
    func refine(_ joint: UnsafeMutablePointer<Float>, _ scratch: Scratch, _ raw: UnsafeRawBufferPointer) -> UnsafeMutablePointer<Float> {
        let steps = Self.steps, width = Self.decoderWidth, down = Self.bottleneck
        func vector(_ name: String) -> UnsafePointer<Float> { tensor(name, in: raw).assumingMemoryBound(to: Float.self) }
        var x = scratch.take(steps * width), next = scratch.take(steps * width)
        Kernel.matmul(joint, rows: steps, inputs: Self.decoderInputs, tensor("decoder.input_proj_weight", in: raw),
                      tensor("decoder.input_proj_bias", in: raw), outputs: width, into: x)
        Kernel.layerNorm(x, steps: steps, width: width, vector("decoder.input_norm_weight"), vector("decoder.input_norm_bias"))
        let projected = scratch.take(steps * down), memory = scratch.take(steps * down), previous = scratch.take(steps * down)
        let lifted = scratch.take(steps * width)
        for b in 0..<Self.decoderBlocks {
            let block = "decoder.blocks_\(b)_"
            Kernel.matmul(x, rows: steps, inputs: width, tensor(block + "project_down_weight", in: raw),
                          tensor(block + "project_down_bias", in: raw), outputs: down, into: projected)
            Kernel.depthwise(projected, steps: steps, channels: down, taps: Self.memory, dilation: 1, vector(block + "memory_weight"), nil, into: memory)
            for i in 0..<steps * down {
                projected[i] += memory[i] + previous[i]
                previous[i] = projected[i]
            }
            Kernel.matmul(projected, rows: steps, inputs: down, tensor(block + "project_up_weight", in: raw),
                          tensor(block + "project_up_bias", in: raw), outputs: width, into: lifted)
            Kernel.hardswish(lifted, steps * width)
            for i in 0..<steps * width { next[i] = lifted[i] + x[i] }
            swap(&x, &next)
        }
        Kernel.layerNorm(x, steps: steps, width: width, vector("decoder.output_norm_weight"), vector("decoder.output_norm_bias"))
        let out = scratch.take(steps * Self.headWidth)
        Kernel.matmul(x, rows: steps, inputs: width, tensor("decoder.ctc_head_weight", in: raw),
                      tensor("decoder.ctc_head_bias", in: raw), outputs: Self.headWidth, into: out)
        for t in 0..<steps {
            let row = out + t * Self.headWidth
            for k in 0..<Self.classes { row[k] += joint[t * Self.decoderInputs + k] }
            let high = (0..<Self.classes).map { row[$0] }.max()!
            var total: Float = 0
            for k in 0..<Self.classes { total += Math.exp(SIMD8(repeating: row[k] - high))[0] }
            let shift = high + Float(Math.log(Double(total)))
            for k in 0..<Self.classes { row[k] -= shift }
        }
        return out
    }
}
