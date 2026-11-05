/// FUTO Swipe's encoder and decoder (https://huggingface.co/futo-org/futo-swipe, technical report arXiv 2606.25247),
/// converted to one run of float32s that is read where it lies: a swipe's path in, the log-probability of each
/// letter and of a blank at each of 32 steps out.
///
/// Layout: `HXS1`, the number of floats as a little-endian u32, 8 bytes of zeros, then the float32 tensors of `entries`
/// in order. A matrix is stored input-major (a row per input, so one input's weights to all outputs are contiguous),
/// with its outputs padded with zeros to a multiple of 8; a vector is padded the same way.
public final class Swipe: Sendable {
    public let bytes: Bytes

    static let header: [UInt8] = Array("HXS1".utf8)
    static let dataOffset = 16
    static let inputSteps = 64, steps = 32, letters = 26, classes = 27, hidden = 128, wide = 256
    static let coefficients = 64, frequencies = 8, blocks = 5, dilations = [1, 2, 3, 5, 8], kernel = 7
    static let decoderBlocks = 8, decoderWidth = 256, bottleneck = 64, memory = 15, decoderInputs = 92, headWidth = 32

    struct Entry {
        let name: String
        let shape: [Int]
        let isMatrix: Bool

        static func padded(_ outputs: Int) -> Int { (outputs + 7) / 8 * 8 }

        var count: Int {
            isMatrix ? shape.dropFirst().reduce(1, *) * Self.padded(shape[0]) : Self.padded(shape.reduce(1, *))
        }
    }

    static let entries: [Entry] = {
        var entries: [Entry] = []
        func add(_ name: String, _ shape: [Int], matrix: Bool = false) { entries.append(Entry(name: name, shape: shape, isMatrix: matrix)) }
        for name in ["d1_x", "d1_y", "d2_x", "d2_y", "d1_curv"] { add("encoder.savgol_\(name)_weight", [1, kernel, 1]) }
        add("encoder.backbone_input_conv_weight", [hidden, kernel, 8], matrix: true)
        add("encoder.backbone_input_conv_bias", [hidden])
        for b in 0..<blocks {
            let block = "encoder.backbone_blocks_\(b)_"
            add(block + "dwconv_weight", [1, kernel, hidden])
            add(block + "dwconv_bias", [hidden])
            add(block + "pwconv1_weight", [4 * hidden, 1, hidden], matrix: true)
            add(block + "pwconv1_bias", [4 * hidden])
            add(block + "grn_gamma", [wide])
            add(block + "grn_beta", [wide])
            add(block + "pwconv2_weight", [hidden, 1, wide], matrix: true)
            add(block + "pwconv2_bias", [hidden])
            add(block + "se_fc1_weight", [hidden / 4, hidden], matrix: true)
            add(block + "se_fc1_bias", [hidden / 4])
            add(block + "se_fc2_weight", [hidden, hidden / 4], matrix: true)
            add(block + "se_fc2_bias", [hidden])
        }
        add("encoder.adapter_0_weight", [wide, 2, hidden], matrix: true)
        add("encoder.adapter_0_bias", [wide])
        add("encoder.spatial_head_lambda_proj_weight", [1, wide], matrix: true)
        add("encoder.spatial_head_lambda_proj_bias", [1])
        add("encoder.spatial_head_coeff_proj_weight", [coefficients, wide], matrix: true)
        add("encoder.spatial_head_coeff_proj_bias", [coefficients])
        add("decoder.input_proj_weight", [decoderWidth, decoderInputs], matrix: true)
        add("decoder.input_proj_bias", [decoderWidth])
        for name in ["input_norm_weight", "input_norm_bias"] { add("decoder." + name, [decoderWidth]) }
        for b in 0..<decoderBlocks {
            let block = "decoder.blocks_\(b)_"
            add(block + "project_down_weight", [bottleneck, decoderWidth], matrix: true)
            add(block + "project_down_bias", [bottleneck])
            add(block + "memory_weight", [1, memory, bottleneck])
            add(block + "project_up_weight", [decoderWidth, bottleneck], matrix: true)
            add(block + "project_up_bias", [decoderWidth])
        }
        for name in ["output_norm_weight", "output_norm_bias"] { add("decoder." + name, [decoderWidth]) }
        add("decoder.ctc_head_weight", [classes, decoderWidth], matrix: true)
        add("decoder.ctc_head_bias", [classes])
        return entries
    }()

    static let offsets: [String: Int] = {
        var offsets: [String: Int] = [:], at = dataOffset
        for entry in entries {
            offsets[entry.name] = at
            at += entry.count * 4
        }
        return offsets
    }()

    static var size: Int { dataOffset + entries.reduce(0) { $0 + $1.count } * 4 }

    public convenience init?(bytes: [UInt8]) {
        self.init(bytes: Bytes(bytes))
    }

    public init?(bytes: Bytes) {
        guard bytes.count == Self.size, Array(bytes[0..<4]) == Self.header else { return nil }
        self.bytes = bytes
    }

    func tensor(_ name: String, in raw: UnsafeRawBufferPointer) -> UnsafeRawPointer {
        raw.baseAddress! + Self.offsets[name]!
    }
}

extension Swipe {
    /// Packs the tensors of the converted model, each under the name `scripts/swipe.py extract` gives it and in the
    /// shape it has there: a matrix as (outputs, taps, inputs) or (outputs, inputs).
    public convenience init(tensors: [String: [Float]]) {
        var bytes = Self.header
        for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: ((Self.size - Self.dataOffset) / 4) >> shift)) }
        bytes += Array(repeating: 0, count: 8)
        for entry in Self.entries {
            let values = tensors[entry.name]!
            precondition(values.count == entry.shape.reduce(1, *), entry.name)
            var floats = values + Array(repeating: 0, count: entry.count - values.count)
            if entry.isMatrix {
                let outputs = entry.shape[0], inputs = values.count / outputs, padded = Entry.padded(outputs)
                floats = Array(repeating: 0, count: inputs * padded)
                for o in 0..<outputs {
                    for i in 0..<inputs { floats[i * padded + o] = values[o * inputs + i] }
                }
            }
            for value in floats {
                let bits = value.bitPattern
                for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: bits >> UInt32(shift))) }
            }
        }
        self.init(bytes: bytes)!
    }
}
