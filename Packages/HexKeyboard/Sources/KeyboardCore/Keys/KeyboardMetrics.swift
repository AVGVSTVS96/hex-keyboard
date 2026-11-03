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

    /// The keys in `room`, where iOS gives the keyboard more height than it asks for (the open Duo in portrait,
    /// slightly folded, gives Apple's keyboard and Hex the same taller height): each row takes its share of the extra,
    /// as Apple's do, and the gaps and insets stay as they are.
    public func filling(_ room: Double, rows: Int, hasNumberRow: Bool) -> KeyboardMetrics {
        let extra = room - height(rows: rows, hasNumberRow: hasNumberRow)
        guard extra > 0, rows > 0 else { return self }
        var metrics = self
        metrics.keyHeight += extra / Double(rows)
        metrics.numberRowHeight += extra / Double(rows)
        return metrics
    }
}

extension KeyboardMetrics {
    public static func `for`(_ device: DeviceClass, width: Double, height: Double, style: KeyboardStyle = .ios26, oneHanded: OneHanded = .off, split: Bool = false) -> KeyboardMetrics {
        let landscape = width > height
        var metrics = switch (device, Duo.Screen(width: width, height: height)) {
        case (.phone, let duo?): Self.duo(duo, style: style, oneHanded: oneHanded, split: split)
        case (.phone, nil) where landscape: phoneLandscape(width: width)
        case (.phone, nil): phone(width: width, style: style).oneHanded(oneHanded, width: width)
        case (.compactPad, _): compactPad
        case (.pad, _): pad(shortSide: min(width, height))
        case (.largePad, _): largePad
        }
        if device == .phone { metrics.numberRowHeight = (metrics.keyHeight * 0.8).rounded() }
        return metrics
    }

    /// The keys of `context` on a `screen`-sized device, in a keyboard `window` wide: what the keyboard draws, and the
    /// app's preview and Your Taps with it.
    public static func `for`(_ context: LayoutContext, screen: Size, window: Double, style: KeyboardStyle) -> KeyboardMetrics {
        let metrics = Self.for(context.device, width: screen.width, height: screen.height, style: style, oneHanded: context.oneHanded, split: context.isSplit)
        guard context.device == .phone, !context.isLandscape else { return metrics }
        return metrics.fitted(screen: screen.width, window: window)
    }

    public static func phone(width: Double, style: KeyboardStyle = .ios26) -> KeyboardMetrics {
        let large = width >= 415
        // iOS 27 draws its rows 7pt lower on 6.1" phones, but a third-party keyboard's area ends where iOS 26's did: it
        // can follow by 3pt. On the large phones (Air, Pro Max) iOS 27's rows sit 2pt higher instead.
        let lowered = style == .ios27 ? (large ? -2.0 : 3) : 0
        return KeyboardMetrics(
            columns: 10, sideInset: 6.5, keyGap: 6, rowGap: 11,
            keyHeight: large ? 45 : 43, numberRowHeight: 0,
            topInset: Toolbar.gap, bottomInset: (large ? 5 : 3) - lowered, cornerRadius: 9,
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
            topInset: Toolbar.gap, bottomInset: 4, cornerRadius: 9,
            letterSize: 20, labelSize: 15.5, secondarySize: 11, symbolSize: 19,
            letterOffset: -1, toolbar: .compact(mic: 34)
        )
    }

    /// The iPhone Duo's four screens: Apple's keys and letters measured on each in the iOS 27.1 simulator
    /// (docs/design.md), across the keyboard's whole width. Open, Apple's keys leave wide margins and gaps (18 in, 9
    /// apart, rows 14 apart in portrait; 9 in, 10 apart, rows 13 apart in landscape), and Bassim wants the keys "taller
    /// and wider as much as possible using as much available space as possible", so there they take the margins and
    /// gaps of the folded Duo in landscape, in Apple's keyboard height.
    static func duo(_ screen: Duo.Screen, style: KeyboardStyle, oneHanded: OneHanded, split: Bool) -> KeyboardMetrics {
        let width = screen.size.width
        var metrics = phone(width: width, style: style)
        switch screen {
        case .foldedPortrait:
            metrics.letterSize = 25.5
            metrics.labelSize = 20
            metrics.symbolSize = 21
            return metrics.oneHanded(oneHanded, width: width)
        case .openPortrait:
            metrics.sideInset = 4.5
            metrics.keyGap = 6
            metrics.keyHeight = 49.42
            metrics.rowGap = 9
            metrics.bottomInset = 3
            metrics.letterSize = 28
            metrics.labelSize = 22
            metrics.symbolSize = 23
        case .foldedLandscape:
            metrics.sideInset = 4.5
            metrics.keyGap = 7
            metrics.keyHeight = 33.33
            metrics.rowGap = 9
            metrics.bottomInset = 4
            metrics.letterSize = 23.5
            metrics.labelSize = 18.5
            metrics.symbolSize = 19.5
            metrics.toolbar = .compact(mic: 32)
        case .openLandscape:
            metrics.sideInset = 4.5
            metrics.keyGap = 6
            metrics.keyHeight = 41.67
            metrics.rowGap = 9
            metrics.bottomInset = 4
            metrics.letterSize = 28.5
            metrics.labelSize = 22
            metrics.symbolSize = 23
            metrics.toolbar = .compact(mic: 38, backdropAbove: Toolbar.openWideBackdropAbove)
            if split { metrics.columns = Self.splitColumns }
        }
        return metrics
    }

    /// The split keyboard's width in keys: each half five keys from the keyboard's edge, and two keys' room between
    /// the hands. Apple's keys are a fifth narrower, with about four keys' room between the halves, which Bassim found
    /// used "barely any" of the screen.
    static let splitColumns = 12.0

    static let compactPad = KeyboardMetrics(
        columns: 11.2, sideInset: 6, keyGap: 12, rowGap: 9,
        keyHeight: 55.5, numberRowHeight: 0,
        topInset: 8, bottomInset: 8, cornerRadius: 9.5,
        letterSize: 22, labelSize: 15, secondarySize: 12.5, symbolSize: 23,
        toolbar: .pad
    )

    static func pad(shortSide: Double) -> KeyboardMetrics {
        let large = shortSide >= 830
        return KeyboardMetrics(
            columns: 12.5, sideInset: 9, keyGap: 10, rowGap: large ? 9 : 8.75,
            keyHeight: large ? 55.5 : 55, numberRowHeight: 0,
            topInset: 8, bottomInset: 8, cornerRadius: 9.5,
            letterSize: 22, labelSize: 15, secondarySize: 12.5, symbolSize: 23,
            toolbar: .pad
        )
    }

    static let largePad = KeyboardMetrics(
        columns: 14.54, sideInset: 3.5, keyGap: 7, rowGap: 7,
        keyHeight: 61, numberRowHeight: 45.5,
        topInset: 6, bottomInset: 4, cornerRadius: 11.5,
        letterSize: 22, labelSize: 17, secondarySize: 16, symbolSize: 21,
        edgeInset: Size(width: 11.5, height: 8), textBaselineInset: 13.5,
        pairSize: 16, pairCapTop: 10, pairBaselineRatio: 0.175,
        toolbar: .pad
    )
}
