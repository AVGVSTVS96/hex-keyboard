public struct Size: Hashable, Sendable {
    public var width, height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct KeyboardMetrics: Hashable, Sendable {
    public var columns: Double
    public var sideInset: Double
    public var keyGap: Double
    public var rowGap: Double
    public var keyHeight: Double
    public var numberRowHeight: Double
    public var topInset: Double
    public var bottomInset: Double
    public var cornerRadius: Double
    public var letterSize: Double
    public var labelSize: Double
    public var secondarySize: Double
    public var symbolSize: Double
    public var letterOffset: Double = 0
    public var edgeInset = Size(width: 4, height: 3)
    public var textBaselineInset: Double = 8
    public var letterBaselineInset: Double = 9
    public var secondaryCapTop: Double = 10.5
    public var pairSize: Double = 20
    public var pairCapTop: Double = 12.5
    public var pairBaselineRatio: Double = 0.216
    public var margin = Margin.none
    public var toolbar = Toolbar.phone

    public var grid: GridMetrics {
        GridMetrics(columns: columns, sideInset: sideInset, keyGap: keyGap, rowGap: rowGap, keyHeight: keyHeight, numberRowHeight: numberRowHeight, topInset: topInset, margin: margin)
    }

    public func height(rows: Int, hasNumberRow: Bool) -> Double {
        let keys = Double(rows) * keyHeight - (hasNumberRow ? keyHeight - numberRowHeight : 0)
        return topInset + keys + Double(rows - 1) * rowGap + bottomInset
    }
}

extension KeyboardMetrics {
    public static func `for`(_ device: DeviceClass, width: Double, height: Double, style: KeyboardStyle = .ios26, oneHanded: OneHanded = .off) -> KeyboardMetrics {
        let landscape = width > height
        switch device {
        case .phone where landscape: return min(width, height) > 440 ? foldedOutLandscape(width: width, open: min(width, height) >= 600) : phoneLandscape(width: width)
        case .phone where width > 466: return phone(width: 466, style: style).centered(in: width)
        case .phone: return phone(width: width, style: style).oneHanded(oneHanded, width: width)
        case .compactPad: return compactPad
        case .pad: return pad(shortSide: min(width, height))
        case .largePad: return largePad
        }
    }

    /// Keys at most `block` wide, centered, as the iPhone Duo's open screen draws the folded keys (docs/design.md).
    func centered(in width: Double) -> KeyboardMetrics {
        var metrics = self
        let side = (width - Self.blockWidth(of: self, in: width)) / 2
        metrics.margin = Margin(leading: side, trailing: side)
        return metrics
    }

    private static func blockWidth(of metrics: KeyboardMetrics, in width: Double) -> Double {
        metrics.toolbar.pills == nil ? min(width, 560) : min(width, 466)
    }

    public static func phone(width: Double, style: KeyboardStyle = .ios26) -> KeyboardMetrics {
        let large = width >= 415
        // iOS 27 draws its rows 7pt lower on 6.1" phones, but a third-party keyboard's area ends where iOS 26's did: it
        // can follow by 3pt. On the large phones (Air, Pro Max) iOS 27's rows sit 2pt higher instead.
        let lowered = style == .ios27 ? (large ? -2.0 : 3) : 0
        return KeyboardMetrics(
            columns: 10, sideInset: 6.5, keyGap: 6, rowGap: 11,
            keyHeight: large ? 45 : 43, numberRowHeight: 0,
            topInset: 11, bottomInset: (large ? 5 : 3) - lowered, cornerRadius: 9,
            letterSize: 23, labelSize: 18, secondarySize: 12, symbolSize: 19,
            letterOffset: -1.67
        )
    }

    /// iOS can give a third-party keyboard a window narrower than the screen and centered on it (452pt of the iPhone
    /// Duo's 466pt), while its own keys still sit where they would across the whole screen: the keys move out by the
    /// difference, up to the window's edges.
    public func fitted(screen: Double, window: Double) -> KeyboardMetrics {
        let inset = (screen - window) / 2
        guard inset > 0, window > 0 else { return self }
        var metrics = self
        metrics.sideInset = max(0, sideInset - inset)
        metrics.margin = Margin(leading: max(0, margin.leading - inset), trailing: max(0, margin.trailing - inset))
        return metrics
    }

    /// Measured on iOS 27: one-handed keys span 320pt on every iPhone (322pt toward the right hand), 4pt in from their edges.
    func oneHanded(_ hand: OneHanded, width: Double) -> KeyboardMetrics {
        var metrics = self
        switch hand {
        case .off: return self
        case .left: metrics.margin = Margin(trailing: width - 320)
        case .right: metrics.margin = Margin(leading: width - 322)
        }
        metrics.sideInset = 4
        return metrics
    }

    static func phoneLandscape(width: Double) -> KeyboardMetrics {
        KeyboardMetrics(
            columns: 10, sideInset: 3.75, keyGap: 6, rowGap: 8,
            keyHeight: 27.33, numberRowHeight: 0,
            topInset: 8, bottomInset: 4, cornerRadius: 9,
            letterSize: 20, labelSize: 15.5, secondarySize: 11, symbolSize: 19,
            letterOffset: -1, toolbar: .compact(top: 4, bar: 34, mic: 34)
        )
    }

    /// The iPhone Duo on its side, folded or open: shorter keys, at most 560pt of them, centered.
    static func foldedOutLandscape(width: Double, open: Bool) -> KeyboardMetrics {
        var metrics = phoneLandscape(width: width)
        metrics.sideInset = 6.5
        metrics.keyHeight = open ? 36 : 30
        metrics.rowGap = open ? 9 : 7
        metrics.topInset = open ? 10 : 8
        metrics.bottomInset = open ? 16 : 6
        metrics.toolbar = open ? .compact(top: 6, bar: 36, mic: 34) : .compact(top: 4, bar: 34, mic: 32)
        return metrics.centered(in: width)
    }

    static let compactPad = KeyboardMetrics(
        columns: 11.2, sideInset: 6, keyGap: 12, rowGap: 9,
        keyHeight: 55.5, numberRowHeight: 0,
        topInset: 8, bottomInset: 8, cornerRadius: 9.5,
        letterSize: 22, labelSize: 15, secondarySize: 12.5, symbolSize: 23,
        toolbar: .compact(top: 0, bar: 36, mic: 34)
    )

    static func pad(shortSide: Double) -> KeyboardMetrics {
        let large = shortSide >= 830
        return KeyboardMetrics(
            columns: 12.5, sideInset: 9, keyGap: 10, rowGap: large ? 9 : 8.75,
            keyHeight: large ? 55.5 : 55, numberRowHeight: 0,
            topInset: 8, bottomInset: 8, cornerRadius: 9.5,
            letterSize: 22, labelSize: 15, secondarySize: 12.5, symbolSize: 23,
            toolbar: .compact(top: 0, bar: 36, mic: 34)
        )
    }

    static let largePad = KeyboardMetrics(
        columns: 14.54, sideInset: 3.5, keyGap: 7, rowGap: 7,
        keyHeight: 61, numberRowHeight: 45.5,
        topInset: 6, bottomInset: 4, cornerRadius: 11.5,
        letterSize: 22, labelSize: 17, secondarySize: 16, symbolSize: 21,
        edgeInset: Size(width: 11.5, height: 8), textBaselineInset: 13.5,
        pairSize: 16, pairCapTop: 10, pairBaselineRatio: 0.175,
        toolbar: .compact(top: 0, bar: 36, mic: 34)
    )
}
