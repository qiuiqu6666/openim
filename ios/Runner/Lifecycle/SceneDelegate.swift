import Flutter
import UIKit

/// Flutter forwards foreground/background events to its engine and plugins.
/// Only the application's custom invitation URLs need additional routing.
final class SceneDelegate: FlutterSceneDelegate {
    override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                        options connectionOptions: UIScene.ConnectionOptions) {
        let app = UIApplication.shared.delegate as? AppDelegate
        for context in connectionOptions.urlContexts {
            app?.handleFriendInvite(context.url)
        }
        super.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        let app = UIApplication.shared.delegate as? AppDelegate
        let remaining = Set(URLContexts.filter { app?.handleFriendInvite($0.url) != true })
        if !remaining.isEmpty {
            super.scene(scene, openURLContexts: remaining)
        }
    }
}
