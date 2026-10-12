import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        LaunchOptions.resetSettingsIfAsked()
        let home = HomeViewController()
        window.rootViewController = UINavigationController(rootViewController: home)
        if LaunchOptions.settings { home.showSettings() }
        if LaunchOptions.taps { home.showTaps() }
        window.makeKeyAndVisible()
        self.window = window
    }
}
