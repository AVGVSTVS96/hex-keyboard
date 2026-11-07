import XCTest
import UIKit

/// The app's pages on an iPad, upright or sideways, in a window of the size asked, for scripts/sim ipadapp: each page
/// in `IIKB_PAGES` (lines of a name and its launch arguments) is launched, the window dragged by its corner to
/// `IIKB_WINDOW` (`600x834`, or none for the whole screen), and the window shot to `IIKB_SHOTS-<page>-<size>.png`.
final class AppShots: XCTestCase {
    func testPages() throws {
        let environment = ProcessInfo.processInfo.environment
        let prefix = try XCTUnwrap(environment["IIKB_SHOTS"])
        let landscape = environment["IIKB_ORIENTATION"] == "landscape"
        let size = environment["IIKB_WINDOW"].flatMap { spec -> CGSize? in
            let parts = spec.split(separator: "x").compactMap { Double($0) }
            return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
        }
        let pages = (environment["IIKB_PAGES"] ?? "").split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        for page in pages where !page.isEmpty {
            let app = XCUIApplication()
            app.launchArguments = Array(page.dropFirst())
            app.launch()
            let window = app.windows.firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 20))
            if let size { resize(window, to: size) }
            Thread.sleep(forTimeInterval: 2.5)
            let frame = window.frame
            print("SHOT \(page[0]) window \(frame.debugDescription)")
            try png(of: frame).write(to: URL(fileURLWithPath: "\(prefix)-\(page[0])-\(Int(frame.width))x\(Int(frame.height)).png"))
            app.terminate()
        }
    }

    /// The screen inside `frame`, turned upright as it shows: a screenshot of a turned iPad keeps the screen's own
    /// orientation in its pixels.
    private func png(of frame: CGRect) -> Data {
        let image = XCUIScreen.main.screenshot().image
        let screen = XCUIApplication(bundleIdentifier: "com.apple.springboard").frame.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.size.width * image.scale / screen.width
        return UIGraphicsImageRenderer(size: frame.size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: CGPoint(x: -frame.minX, y: -frame.minY), size: screen))
        }
    }

    /// Drags the window's bottom right corner, where iPadOS keeps its resize handle, by what the window is short of
    /// `size` or over it, again until it's within a point or two, since iPadOS may move the window as it resizes.
    private func resize(_ window: XCUIElement, to size: CGSize) {
        let screen = XCUIApplication(bundleIdentifier: "com.apple.springboard").coordinate(withNormalizedOffset: .zero)
        for _ in 0 ..< 6 {
            let frame = window.frame
            let change = CGVector(dx: size.width - frame.width, dy: size.height - frame.height)
            guard abs(change.dx) > 2 || abs(change.dy) > 2 else { return }
            let corner = screen.withOffset(CGVector(dx: frame.maxX - 6, dy: frame.maxY - 6))
            corner.press(forDuration: 0.5, thenDragTo: corner.withOffset(change), withVelocity: .slow, thenHoldForDuration: 0.5)
            Thread.sleep(forTimeInterval: 1)
            print("RESIZE to \(size) now \(window.frame.size)")
        }
    }
}
