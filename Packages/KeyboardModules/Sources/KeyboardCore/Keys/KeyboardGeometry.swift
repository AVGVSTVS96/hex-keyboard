/// The keys of a context on a screen: their layout and metrics, the width iOS gives the keyboard there, and the keys'
/// height. The keyboard, the app's preview and Your Taps all lay out from it, so they draw the same keys.
public struct KeyboardGeometry: Hashable, Sendable {
    public let context: LayoutContext
    public let layout: KeyboardLayout
    public var metrics: KeyboardMetrics
    public let width: Double

    /// On a `screen`-sized device, in a keyboard `window` wide where the keyboard knows it, or else as wide as iOS gives
    /// a keyboard there: the whole screen, but on the iPhone Duo its screen's own width.
    public init(_ context: LayoutContext, screen: Size, window: Double? = nil, style: KeyboardStyle) {
        let duo = context.device == .phone ? Duo.Screen(width: screen.width, height: screen.height) : nil
        self.context = context
        layout = Layouts.layout(for: context)
        width = window ?? duo?.keyboardWidth ?? screen.width
        metrics = KeyboardMetrics.for(context, screen: screen, window: width, style: style)
    }

    /// The keys' height, under the bar.
    public var height: Double { metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow) }

    public var grid: KeyGrid { KeyGrid(layout, width: width, metrics: metrics.grid, signature: context.signature) }
}

extension LayoutContext {
    /// The screen these keys are laid out on, on a device whose screen is `display`-sized in either orientation: that
    /// screen held this way, or on the iPhone Duo the screen these keys are for, folded or open.
    public func screen(on display: Size) -> Size {
        let short = min(display.width, display.height), long = max(display.width, display.height)
        if device == .phone, Duo.isDuo(short: short) { return Duo.Screen(open: isOpen, landscape: isLandscape).size }
        return isLandscape ? Size(width: long, height: short) : Size(width: short, height: long)
    }
}
