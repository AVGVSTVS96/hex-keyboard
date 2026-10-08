import UIKit
import KeyboardCore

final class ProxyDocument: TextDocument {
    private let proxy: () -> UITextDocumentProxy

    init(_ proxy: @escaping () -> UITextDocumentProxy) {
        self.proxy = proxy
    }

    var textBeforeInput: String? { proxy().documentContextBeforeInput }

    func insert(_ text: String) { proxy().insertText(text) }

    func deleteBackward(_ count: Int) {
        for _ in 0..<count { proxy().deleteBackward() }
    }

    func moveCursor(by offset: Int) { proxy().adjustTextPosition(byCharacterOffset: offset) }
}

extension InputTraits {
    init(_ proxy: UITextDocumentProxy) {
        self.init(
            kind: InputKind(proxy.keyboardType ?? .default),
            returnKind: ReturnKind(proxy.returnKeyType ?? .default),
            autocapitalization: Autocapitalization(proxy.autocapitalizationType ?? .sentences),
            smartPunctuation: proxy.smartQuotesType != .no,
            returnRequiresText: proxy.enablesReturnKeyAutomatically ?? false
        )
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
