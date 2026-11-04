import Testing
@testable import KeyboardCore

struct RoundnessTests {
    private let key = Size(width: 36, height: 44)

    private func metrics(_ roundness: KeyRoundness) -> KeyboardMetrics {
        var metrics = KeyboardMetrics.phone(width: 402)
        metrics.roundness = roundness
        return metrics
    }

    @Test func fiveStopsWithStandardInTheMiddleKeepingTheThemesCorners() {
        #expect(KeyRoundness.allCases.count == 5 && KeyRoundness.allCases[KeyRoundness.allCases.count / 2] == .standard)
        #expect(metrics(.standard).rounded(13.75, key: key) == 13.75)
    }

    @Test func eachStopScalesTheCornersFromSquareToDouble() {
        #expect(metrics(.sharper).rounded(9, key: key) == 0)
        #expect(metrics(.sharp).rounded(9, key: key) == 4.5)
        #expect(metrics(.round).rounded(9, key: key) == 13.5)
        #expect(metrics(.rounder).rounded(9, key: key) == 18)
    }

    @Test func cornersNeverPassAPillOfTheSmallestKey() {
        #expect(metrics(.rounder).rounded(13.75, key: key) == 18)
        #expect(metrics(.rounder).rounded(13.75, key: Size(width: 20, height: 44)) == 10)
    }

    @Test func theContextCarriesTheSettingIntoTheKeyboardsMetrics() {
        var settings = KeyboardSettings()
        settings.keyRoundness = .rounder
        let screen = Size(width: 402, height: 874)
        let context = LayoutContext(device: .phone, layer: .letters, screen: screen, settings: settings)
        #expect(KeyboardMetrics.for(context, screen: screen, window: 402, style: .ios27).roundness == .rounder)
    }
}
