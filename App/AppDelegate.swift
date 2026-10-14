import KeyboardUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        LaunchOptions.resetSettingsIfAsked()
        LaunchOptions.applyOneHanded()
        let home = HomeViewController()
        let tabs = UITabBarController(tabs: [
            UITab(title: "Hex", image: UIImage(systemName: "keyboard"), identifier: "home") { _ in Self.navigation(home) },
            UITab(title: "Transcripts", image: UIImage(systemName: "waveform"), identifier: "transcripts") { _ in TranscriptsView.controller() },
            UITab(title: "Your Taps", image: UIImage(systemName: "hand.tap"), identifier: "taps") { _ in Self.navigation(TapsViewController()) },
        ])
        tabs.selectedTab = tabs.tab(forIdentifier: LaunchOptions.tab)
        window.rootViewController = tabs
        if LaunchOptions.settings { home.showSettings() }
        window.makeKeyAndVisible()
        self.window = window
        open(options.urlContexts)
    }

    private static func navigation(_ root: UIViewController) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.prefersLargeTitles = true
        return navigation
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        open(contexts)
    }

    private func open(_ contexts: Set<UIOpenURLContext>) {
        if let source = contexts.lazy.compactMap({ Source(link: $0.url) }).first { return offer(source) }
        guard contexts.contains(where: { $0.url == Dictation.url }), let root = window?.rootViewController else { return }
        Task { await Listener.shared.start() }
        guard !(root.presentedViewController is DictationViewController) else { return }
        root.dismiss(animated: false)
        let dictation = DictationViewController()
        dictation.modalPresentationStyle = .fullScreen
        root.present(dictation, animated: false)
    }

    /// A source's link asks before Hex starts telling it what you type.
    private func offer(_ source: Source) {
        let alert = UIAlertController(
            title: "Add “\(source.name)”?",
            message: "With Allow Full Access on, Hex will send \(source.url.host() ?? "it") the text of the field you’re typing in, except passwords and codes, and show the hints it answers with above the keys.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in SourceStore.add(source) })
        window?.rootViewController?.present(alert, animated: true)
    }
}
