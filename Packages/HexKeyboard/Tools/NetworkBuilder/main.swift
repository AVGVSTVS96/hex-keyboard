import Foundation
import KeyboardCore

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("usage: NetworkBuilder <vocab.txt> <weights.f32> <out.network>")
    exit(1)
}
let vocabulary = try String(contentsOfFile: arguments[1], encoding: .utf8).split(separator: "\n").map(String.init)
let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
var read = 0
@MainActor func take(_ count: Int) -> [Float] {
    defer { read += count }
    return Array(floats[read..<read + count])
}
@MainActor func matrix(_ rows: Int, _ columns: Int) -> [[Float]] { (0..<rows).map { _ in take(columns) } }
let header = take(2).map(Int.init)
let (width, hidden) = (header[0], header[1])
let network = Network(vocabulary: vocabulary, embedding: matrix(vocabulary.count, width), input: matrix(4 * hidden, width),
                      recurrent: matrix(4 * hidden, hidden), gates: take(4 * hidden), projection: matrix(width, hidden),
                      projectionBias: take(width), output: take(vocabulary.count))
precondition(read == floats.count)
try Data(network.bytes).write(to: URL(fileURLWithPath: arguments[3]))
print("\(vocabulary.count) words, \(network.bytes.count) bytes")
