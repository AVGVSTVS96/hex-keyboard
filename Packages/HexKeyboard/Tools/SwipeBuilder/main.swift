import Foundation
import KeyboardCore

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("usage: SwipeBuilder <weights.txt> <weights.f32> <out.swipe>")
    exit(1)
}
let manifest = try String(contentsOfFile: arguments[1], encoding: .utf8).split(separator: "\n")
let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
var tensors: [String: [Float]] = [:]
var read = 0
for line in manifest {
    let parts = line.split(separator: " ")
    let count = parts.dropFirst().reduce(1) { $0 * Int($1)! }
    tensors[String(parts[0])] = Array(floats[read..<read + count])
    read += count
}
precondition(read == floats.count)
let swipe = Swipe(tensors: tensors)
try Data(swipe.bytes).write(to: URL(fileURLWithPath: arguments[3]))
print("\(tensors.count) tensors, \(swipe.bytes.count) bytes")
