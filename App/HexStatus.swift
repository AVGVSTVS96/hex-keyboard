import SwiftUI
import UIKit

/// What iOS keeps for Hex in Settings › Apps › iikb, read again whenever Hex comes forward, as it does when you come back
/// from Settings.
@Observable final class HexStatus {
    static let shared = HexStatus()

    private(set) var isAdded = false
    private(set) var fullAccess = false
    private(set) var pasteAllowed = false

    var isSetUp: Bool { isAdded && fullAccess && pasteAllowed }

    private init() {
        refresh()
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { HexStatus.shared.refresh() }
        }
    }

    func refresh() {
        isAdded = (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] ?? []).contains("com.shahidy.hexkeyboard.keyboard")
        fullAccess = Self.allowed("kTCCServiceKeyboardNetwork")
        pasteAllowed = Self.allowed("kTCCServicePasteboard")
    }

    /// Asks TCC, where iOS keeps privacy switches, through its private `TCCAccessPreflight`. iOS files the keyboard's Full
    /// Access under the app, and Paste from Other Apps is only granted at Allow, never at Ask.
    private static func allowed(_ service: String) -> Bool {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
        guard let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY), let preflight = dlsym(tcc, "TCCAccessPreflight") else { return false }
        return unsafeBitCast(preflight, to: Preflight.self)(service as CFString, nil) == 0
    }

    var summary: String {
        guard isAdded else { return "Not added yet" }
        return fullAccess ? "On, with Full Access" : "On, without Full Access"
    }

    var color: Color { isAdded ? (fullAccess ? .green : .yellow) : .orange }

    static func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}
