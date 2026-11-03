import KeyboardUI
import SwiftUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

/// Which tab shows, and which page inside the Keyboard and More tabs, so a tile on one tab can open a page on another.
@Observable final class Router {
    static let shared = Router()

    enum Destination: String { case home, keyboard, voice, taps, more }

    var keyboardPage = KeyboardPage.Tab.theme
    var voicePage = VoicePage.Tab.transcripts
    var morePath: [MorePage.Page] = []
    @ObservationIgnored weak var tabs: UITabBarController?

    func show(_ destination: Destination, page: KeyboardPage.Tab? = nil, voice: VoicePage.Tab? = nil) {
        if let page { keyboardPage = page }
        if let voice { voicePage = voice }
        tabs?.selectedTab = tabs?.tab(forIdentifier: destination.rawValue)
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        LaunchOptions.resetSettingsIfAsked()
        LaunchOptions.applyOneHanded()
        LaunchOptions.applyLook()
        VoiceProbe.runIfAsked()
        let tabs = UITabBarController(tabs: [
            UITab(title: "Hex", image: UIImage(systemName: "house"), identifier: Router.Destination.home.rawValue) { _ in HomeViewController() },
            UITab(title: "Keyboard", image: UIImage(systemName: "keyboard"), identifier: Router.Destination.keyboard.rawValue) { _ in
                Self.hosting(NavigationStack { KeyboardPage() })
            },
            UITab(title: "Voice", image: UIImage(systemName: "waveform"), identifier: Router.Destination.voice.rawValue) { _ in
                Self.hosting(VoicePage())
            },
            UITab(title: "Your Taps", image: UIImage(systemName: "hand.tap"), identifier: Router.Destination.taps.rawValue) { _ in TapsViewController() },
            UITab(title: "More", image: UIImage(systemName: "square.grid.2x2"), identifier: Router.Destination.more.rawValue) { _ in
                Self.hosting(MorePage())
            },
        ])
        Router.shared.tabs = tabs
        LaunchOptions.route()
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
        open(options.urlContexts)
    }

    private static func hosting(_ view: some View) -> UIViewController {
        let controller = UIHostingController(rootView: view.readsWindow())
        controller.view.backgroundColor = HexStyle.page
        return controller
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !VoiceProbe.asked else { return }
        VoiceModel.shared.prepare()
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        open(contexts)
    }

    private func open(_ contexts: Set<UIOpenURLContext>) {
        if let source = contexts.lazy.compactMap({ Source(link: $0.url) }).first { return offer(source) }
        if contexts.contains(where: { $0.url == HexLink.settings }) { return UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
        guard let request = contexts.lazy.compactMap({ Dictation.Request($0.url) }).first, let root = window?.rootViewController else { return }
        Task { await listen(thenOpen: request.host) }
        guard !(root.presentedViewController is DictationViewController) else { return }
        root.dismiss(animated: false)
        let dictation = DictationViewController()
        dictation.modalPresentationStyle = .fullScreen
        root.present(dictation, animated: false)
    }

    /// Starts listening while Hex is in front, the only place iOS lets a recording begin, then reopens the app you were typing in.
    private func listen(thenOpen host: String?) async {
        let asked = Date.now
        await Listener.shared.start()
        guard Listener.shared.state == .listening else {
            return HostApp.log.notice("not listening after \(Date.now.timeIntervalSince(asked), format: .fixed(precision: 2))s")
        }
        let opened = if let host { await HostApp.open(host) } else { false }
        HostApp.log.notice("back to \(host ?? "none", privacy: .public) \(opened ? "opened" : "failed", privacy: .public) after \(Date.now.timeIntervalSince(asked), format: .fixed(precision: 2))s")
    }

    /// A source's link asks before Hex starts telling it what you type.
    private func offer(_ source: Source) {
        let alert = UIAlertController(
            title: "Add “\(source.name)”?",
            message: "With Allow Full Access on, Hex will send \(source.url.host() ?? "it") the text of the field you’re typing in, except passwords and codes, and show the hints it answers with above the keys.",
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
