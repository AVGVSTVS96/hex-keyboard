public enum Autocapitalization: Sendable {
    case none, words, sentences, allCharacters
}

public enum InputKind: Sendable {
    case text, email, url, number, decimal, twitter, webSearch
}

/// What the field says it holds (`textContentType`), beside the keyboard it asks for.
public enum InputContent: Sendable {
    case other, emailAddress, url, username, telephoneNumber, oneTimeCode, postalCode, creditCardNumber
}

public enum ReturnKind: Hashable, Sendable {
    case `default`, go, google, join, next, route, search, send, yahoo, done, emergencyCall, `continue`

    public var symbol: String? {
        switch self {
        case .default: "return.left"
        case .go: "arrow.right"
        case .google, .yahoo, .search: "magnifyingglass"
        case .send: "arrow.up"
        case .done: "checkmark"
        case .next: "chevron.right"
        case .join, .route, .emergencyCall, .continue: nil
        }
    }

    public var title: String {
        switch self {
        case .join: "join"
        case .route: "route"
        case .emergencyCall: "Emergency Call"
        case .continue: "continue"
        default: "return"
        }
    }

    public var isProminent: Bool {
        switch self {
        case .default, .next, .continue: false
        default: true
        }
    }
}

public struct InputTraits: Hashable, Sendable {
    public var kind: InputKind
    public var content: InputContent
    public var returnKind: ReturnKind
    public var autocapitalization: Autocapitalization
    public var smartPunctuation: Bool
    public var returnRequiresText: Bool
    public var autocorrection: Bool

    public init(
        kind: InputKind = .text,
        content: InputContent = .other,
        returnKind: ReturnKind = .default,
        autocapitalization: Autocapitalization = .sentences,
        smartPunctuation: Bool = true,
        returnRequiresText: Bool = false,
        autocorrection: Bool = true
    ) {
        self.kind = kind
        self.content = content
        self.returnKind = returnKind
        self.autocapitalization = autocapitalization
        self.smartPunctuation = smartPunctuation
        self.returnRequiresText = returnRequiresText
        self.autocorrection = autocorrection
    }

    public var allowsCorrection: Bool {
        switch kind {
        case .email, .url, .number, .decimal: false
        default: autocorrection
        }
    }
}
