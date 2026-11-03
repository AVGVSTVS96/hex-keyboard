import KeyboardUI
import SwiftUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if !VoiceProbe.asked { VoiceModel.shared.prepare() }
        return true
    }
}

/// Which tab shows, and which settings page, so a tile, a link or the keyboard's menu can open one.
@Observable final class Router {
    static let shared = Router()

    enum Destination: String { case home, transcripts, clipboard, taps, settings }

    /// The settings page open on its own, or, wide, the one beside the list.
    var settingsPath: [SettingsPage.Page] = []
    @ObservationIgnored weak var tabs: UITabBarController?

    func show(_ destination: Destination, settings page: SettingsPage.Page? = nil) {
        if destination == .settings { settingsPath = page.map { [$0] } ?? [] }
        tabs?.selectedTab = tabs?.tab(forIdentifier: destination.rawValue)
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        LaunchOptions.resetSettingsIfAsked()
        LaunchOptions.applySettings()
        LaunchOptions.applyLook()
        HexStyle.applyTitles()
        VoiceProbe.runIfAsked()
        let tabs = UITabBarController(tabs: [
            UITab(title: "iikb", image: UIImage(systemName: "house"), identifier: Router.Destination.home.rawValue) { _ in HomeViewController() },
            UITab(title: "Transcripts", image: UIImage(systemName: "waveform"), identifier: Router.Destination.transcripts.rawValue) { _ in
                Self.hosting(TranscriptsPage())
            },
            UITab(title: "Clipboard", image: UIImage(systemName: "list.clipboard"), identifier: Router.Destination.clipboard.rawValue) { _ in
                Self.hosting(ClipboardPage())
            },
            UITab(title: "Your Taps", image: UIImage(systemName: "hand.tap"), identifier: Router.Destination.taps.rawValue) { _ in Self.navigation(TapsViewController()) },
            UITab(title: "Settings", image: UIImage(systemName: "gearshape"), identifier: Router.Destination.settings.rawValue) { _ in
                Self.hosting(SettingsPage())
            },
        ])
        Router.shared.tabs = tabs
        LaunchOptions.route()
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
        Task { await Transcripts.shared.recover() }
        open(options.urlContexts)
    }

    private static func navigation(_ root: UIViewController) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: root)
        navigation.view.backgroundColor = HexStyle.page
        return navigation
    }

    private static func hosting(_ view: some View) -> UIViewController {
        let controller = UIHostingController(rootView: view.readsWindow())
        controller.view.backgroundColor = HexStyle.page
        return controller
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        open(contexts)
    }

    private func open(_ contexts: Set<UIOpenURLContext>) {
        if let source = contexts.lazy.compactMap({ Source(link: $0.url) }).first { return offer(source) }
        if contexts.contains(where: { $0.url == HexLink.settings }) { return UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
        if contexts.contains(where: { $0.url == HexLink.keyboard }) { return Router.shared.show(.settings) }
        guard let request = contexts.lazy.compactMap({ Dictation.Request($0.url) }).first, let root = window?.rootViewController else { return }
        let fromHex = request.host == Bundle.main.bundleIdentifier
        Task { await listen(thenOpen: fromHex ? nil : request.host) }
        guard !fromHex, !(root.presentedViewController is DictationViewController) else { return }
        root.dismiss(animated: false)
        let dictation = DictationViewController()
        dictation.modalPresentationStyle = .fullScreen
        root.present(dictation, animated: false)
    }

    /// Starts listening while Hex is in front, the only place iOS lets a recording begin, then reopens the app you were
    /// typing in. Dictating in Hex's own field it stays put: iOS quits an app that opens itself, and the quit throws
    /// away a Parakeet still getting ready.
    private func listen(thenOpen host: String?) async {
        let asked = Date.now
        await Listener.shared.start()
        guard Listener.shared.isListening else {
            return HostApp.log.notice("not listening after \(Date.now.timeIntervalSince(asked), format: .fixed(precision: 2))s")
        }
        let opened = if let host { await HostApp.open(host) } else { false }
        HostApp.log.notice("back to \(host ?? "none", privacy: .public) \(opened ? "opened" : "failed", privacy: .public) after \(Date.now.timeIntervalSince(asked), format: .fixed(precision: 2))s")
    }

    /// A source's link asks before Hex starts telling it what you type.
    private func offer(_ source: Source) {
        let alert = UIAlertController(
            title: "Add “\(source.name)”?",
            message: "With Allow Full Access on, iikb will send \(source.url.host() ?? "it") the text of the field you’re typing in, except passwords and codes, and show the hints it answers with above the keys.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
            SourceStore.add(source)
            SettingsModel.shared.reload()
        })
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(alert, animated: true)
    }
}
