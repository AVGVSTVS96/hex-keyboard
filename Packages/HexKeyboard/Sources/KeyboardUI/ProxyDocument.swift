import UIKit
import KeyboardCore

/// The host's field, through the keyboard's `textDocumentProxy`, as the `TextDocument` that `TypingEngine` edits.
public final class ProxyDocument: TextDocument {
    private let proxy: () -> UITextDocumentProxy

    public init(_ proxy: @escaping () -> UITextDocumentProxy) {
        self.proxy = proxy
    }

    public var textBeforeInput: String? { proxy().documentContextBeforeInput }

    public var textAfterInput: String? { proxy().documentContextAfterInput }

    public var selectedText: String? { proxy().selectedText }

    public func insert(_ text: String) { proxy().insertText(text) }

    public func deleteBackward(_ count: Int) {
        for _ in 0..<count { proxy().deleteBackward() }
    }

    public func moveCursor(by offset: Int) { proxy().adjustTextPosition(byCharacterOffset: offset) }
}

extension InputTraits {
    /// What the host's field asks for: its keyboard, return key, capitals, and whether it takes corrections.
    public init(_ proxy: UITextDocumentProxy) {
        let kind = InputKind(proxy.keyboardType ?? .default)
        let returnKind = ReturnKind(proxy.returnKeyType ?? .default)
        let content: UITextContentType? = proxy.textContentType ?? nil
        self.init(
            kind: kind,
            content: content.map(InputContent.init) ?? .other,
            returnKind: kind == .webSearch && returnKind == .default ? .go : returnKind,
            autocapitalization: Autocapitalization(proxy.autocapitalizationType ?? .sentences),
            smartPunctuation: proxy.smartQuotesType != .no,
            returnRequiresText: proxy.enablesReturnKeyAutomatically ?? false,
            autocorrection: proxy.autocorrectionType != .no && !(content.map(Self.literalContent.contains) ?? false)
        )
    }

    private static let literalContent: Set<UITextContentType> = [
        .URL, .emailAddress, .username, .password, .newPassword, .oneTimeCode, .telephoneNumber, .postalCode, .creditCardNumber,
    ]
}

extension InputContent {
    init(_ type: UITextContentType) {
        self = switch type {
        case .emailAddress: .emailAddress
        case .URL: .url
        case .username: .username
        case .telephoneNumber: .telephoneNumber
        case .oneTimeCode: .oneTimeCode
        case .postalCode: .postalCode
        case .creditCardNumber: .creditCardNumber
        default: .other
        }
    }
}

extension InputKind {
    init(_ type: UIKeyboardType) {
        self = switch type {
        case .emailAddress: .email
        case .URL: .url
        case .numberPad, .asciiCapableNumberPad, .phonePad, .namePhonePad, .numbersAndPunctuation: .number
        case .decimalPad: .decimal
        case .twitter: .twitter
        case .webSearch: .webSearch
        default: .text
        }
    }
}

extension ReturnKind {
    init(_ type: UIReturnKeyType) {
        self = switch type {
        case .go: .go
        case .google: .google
        case .join: .join
        case .next: .next
        case .route: .route
        case .search: .search
        case .send: .send
        case .yahoo: .yahoo
        case .done: .done
        case .emergencyCall: .emergencyCall
        case .continue: .continue
        default: .default
        }
    }
}

extension Autocapitalization {
    init(_ type: UITextAutocapitalizationType) {
        self = switch type {
        case .none: .none
        case .words: .words
        case .allCharacters: .allCharacters
        default: .sentences
        }
    }
}
