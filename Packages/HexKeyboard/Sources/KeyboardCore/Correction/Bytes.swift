/// Bytes read where they lie: an array's, or a file's mapped into memory. A mapped file stays clean pages the system
/// can drop and read again, where a copy of it in an array is memory the keyboard is charged for, under a tight limit.
public struct Bytes: RandomAccessCollection, @unchecked Sendable {
    private let buffer: UnsafeRawBufferPointer
    private let owner: AnyObject

    /// Bytes that stay valid as long as `owner` lives.
    public init(_ buffer: UnsafeRawBufferPointer, owner: AnyObject) {
        self.buffer = buffer
        self.owner = owner
    }

    public init(_ bytes: [UInt8]) {
        let copy = Copy(bytes)
        self.init(UnsafeRawBufferPointer(copy.buffer), owner: copy)
    }

    func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) -> Result) -> Result {
        body(buffer)
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { buffer.count }
    public subscript(position: Int) -> UInt8 { buffer[position] }

    private final class Copy {
        let buffer: UnsafeMutableRawBufferPointer

        init(_ bytes: [UInt8]) {
            buffer = .allocate(byteCount: bytes.count, alignment: 1)
            buffer.copyBytes(from: bytes)
        }

        deinit { buffer.deallocate() }
    }
}
