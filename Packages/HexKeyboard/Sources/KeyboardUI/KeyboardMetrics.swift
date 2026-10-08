import UIKit
import KeyboardCore

public struct KeyboardMetrics: Equatable, Sendable {
    public var columns: CGFloat
    public var sideInset: CGFloat
    public var keyGap: CGFloat
    public var rowGap: CGFloat
    public var keyHeight: CGFloat
    public var numberRowHeight: CGFloat
    public var topInset: CGFloat
    public var bottomInset: CGFloat
    public var cornerRadius: CGFloat
    public var letterSize: CGFloat
    public var labelSize: CGFloat
    public var secondarySize: CGFloat
    public var symbolSize: CGFloat
    public var letterOffset: CGFloat = 0
    public var edgeInset = CGSize(width: 7, height: 5.5)
    public var textBaselineInset: CGFloat = 8
    public var letterBaselineInset: CGFloat = 9
    public var secondaryCapTop: CGFloat = 10.5
    public var pairSize: CGFloat = 20

    public func height(rows: Int, hasNumberRow: Bool) -> CGFloat {
        let keys = CGFloat(rows) * keyHeight - (hasNumberRow ? keyHeight - numberRowHeight : 0)
        return topInset + keys + CGFloat(rows - 1) * rowGap + bottomInset
    }
}

extension KeyboardMetrics {
    public static func `for`(_ device: DeviceClass, size: CGSize) -> KeyboardMetrics {
        let landscape = size.width > size.height
        switch device {
        case .phone: return landscape ? phoneLandscape(width: size.width) : phone(width: size.width)
        case .compactPad: return compactPad
        case .pad: return pad(shortSide: min(size.width, size.height))
        case .largePad: return largePad
        }
    }

    static func phone(width: CGFloat) -> KeyboardMetrics {
        let large = width >= 415
        return KeyboardMetrics(
            columns: 10, sideInset: 6.5, keyGap: 6, rowGap: 11,
            keyHeight: large ? 45 : 43, numberRowHeight: 0,
            topInset: 8, bottomInset: 3, cornerRadius: 8,
            letterSize: 23, labelSize: 18, secondarySize: 12, symbolSize: 19,
            letterOffset: -1.67
        )
    }

    static func phoneLandscape(width: CGFloat) -> KeyboardMetrics {
        KeyboardMetrics(
            columns: 10, sideInset: 3.75, keyGap: 6, rowGap: 8,
            keyHeight: 27.33, numberRowHeight: 0,
            topInset: 22.67, bottomInset: 4, cornerRadius: 8,
            letterSize: 20, labelSize: 15.5, secondarySize: 11, symbolSize: 19,
            letterOffset: -1
        )
    }

    static let compactPad = KeyboardMetrics(
        columns: 11.2, sideInset: 6, keyGap: 12, rowGap: 9,
        keyHeight: 55.5, numberRowHeight: 0,
        topInset: 8, bottomInset: 8, cornerRadius: 9.5,
        letterSize: 23, labelSize: 17, secondarySize: 12.5, symbolSize: 23
    )

    static func pad(shortSide: CGFloat) -> KeyboardMetrics {
        let large = shortSide >= 830
        return KeyboardMetrics(
            columns: 12.5, sideInset: 9, keyGap: 10, rowGap: large ? 9 : 8.75,
            keyHeight: large ? 55.5 : 55, numberRowHeight: 0,
            topInset: 8, bottomInset: 8, cornerRadius: 9.5,
            letterSize: 23, labelSize: 17, secondarySize: 12.5, symbolSize: 23
        )
    }

    static let largePad = KeyboardMetrics(
        columns: 14.54, sideInset: 3.5, keyGap: 7, rowGap: 7,
        keyHeight: 61, numberRowHeight: 45.5,
        topInset: 6, bottomInset: 4, cornerRadius: 11.5,
        letterSize: 23, labelSize: 17, secondarySize: 16, symbolSize: 21,
        edgeInset: CGSize(width: 14, height: 10), textBaselineInset: 13.5, pairSize: 16
    )
}
