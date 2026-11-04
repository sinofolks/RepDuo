import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let navigationController = RDNavigationController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigationController
        window.tintColor = RDColor.accent
        window.makeKeyAndVisible()
        self.window = window

        let coordinator = AppCoordinator(
            navigationController: navigationController,
            container: DependencyContainer()
        )
        self.coordinator = coordinator
        coordinator.start()
    }
}
