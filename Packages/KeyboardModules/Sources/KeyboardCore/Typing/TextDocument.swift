public protocol TextDocument: AnyObject {
    var textBeforeInput: String? { get }
    var textAfterInput: String? { get }
    /// The text selected between the two, which the next insert or delete replaces.
    var selectedText: String? { get }
    func insert(_ text: String)
    func deleteBackward(_ count: Int)
    func moveCursor(by offset: Int)
}

extension TextDocument {
    public var selectedText: String? { nil }
}
