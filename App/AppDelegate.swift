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
        window.rootViewController = UINavigationController(rootViewController: home)
        if LaunchOptions.settings { home.showSettings() }
        if LaunchOptions.taps { home.showTaps() }
        window.makeKeyAndVisible()
        self.window = window
        open(options.urlContexts)
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        open(contexts)
    }

    private func open(_ contexts: Set<UIOpenURLContext>) {
        guard contexts.contains(where: { $0.url == Dictation.url }), let root = window?.rootViewController else { return }
        Task { await Listener.shared.start() }
        guard !(root.presentedViewController is DictationViewController) else { return }
        root.dismiss(animated: false)
        let dictation = DictationViewController()
        dictation.modalPresentationStyle = .fullScreen
        root.present(dictation, animated: false)
    }
}
