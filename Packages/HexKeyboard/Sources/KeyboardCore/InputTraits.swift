public enum Autocapitalization: Sendable {
    case none, words, sentences, allCharacters
}

public enum InputKind: Sendable {
    case text, email, url, number, decimal, twitter, webSearch
}

public enum ReturnKind: Hashable, Sendable {
    case `default`, go, google, join, next, route, search, send, yahoo, done, emergencyCall, `continue`

    public var title: String? {
        switch self {
        case .default: nil
        case .go: "go"
        case .google, .yahoo, .search: "search"
        case .join: "join"
        case .next: "next"
        case .route: "route"
        case .send: "send"
        case .done: "done"
        case .emergencyCall: "Emergency Call"
        case .continue: "continue"
        }
    }

    public var isProminent: Bool {
        switch self {
        case .default, .next, .continue: false
        default: true
        }
    }
}

public struct InputTraits: Sendable {
    public var kind: InputKind
    public var returnKind: ReturnKind
    public var autocapitalization: Autocapitalization
    public var smartPunctuation: Bool
    public var returnRequiresText: Bool

    public init(
        kind: InputKind = .text,
        returnKind: ReturnKind = .default,
        autocapitalization: Autocapitalization = .sentences,
        smartPunctuation: Bool = true,
        returnRequiresText: Bool = false
    ) {
        self.kind = kind
        self.returnKind = returnKind
        self.autocapitalization = autocapitalization
        self.smartPunctuation = smartPunctuation
        self.returnRequiresText = returnRequiresText
    }

}
