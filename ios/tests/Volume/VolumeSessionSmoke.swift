import AVFoundation
import Flutter
import UIKit

@main
final class VolumeSmokeApp: UIResponder, UIApplicationDelegate {}

final class VolumeSmokeScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        DispatchQueue.main.async { self.runChecks() }
    }

    private func runChecks() {
        let session = AVAudioSession.sharedInstance()
        let category = session.category
        let mode = session.mode
        var failures: [String] = []
        func check(_ condition: Bool, _ name: String) {
            if !condition { failures.append(name) }
        }
        func checkSession(_ step: String) {
            check(session.category == category, "category_changed_\(step)")
            check(session.mode == mode, "mode_changed_\(step)")
        }
        let plugin = VolumeControllerPlugin()
        plugin.applicationWillEnterForeground(UIApplication.shared)
        checkSession("foreground")
        let controller = VolumeController(audioSession: session)
        let volume = controller.getVolume()
        check((0...1).contains(volume), "volume_out_of_range")
        checkSession("get_volume")
        _ = controller.isMuted()
        checkSession("is_muted")
        let listener = VolumeListener(audioSession: session)
        var events = 0
        var mainThreadEvents = true
        let error = listener.onListen(withArguments: [EventArgument.fetchInitialVolume: true]) { value in
            events += 1
            mainThreadEvents = mainThreadEvents && Thread.isMainThread
        }
        check(error == nil && listener.isObservingVolume, "observer_not_registered")
        check(events == 1, "initial_event_missing")
        checkSession("listen")
        plugin.applicationWillEnterForeground(UIApplication.shared)
        checkSession("resume_with_observer")
        listener.sendVolumeChangeEvent()
        check(events == 2 && mainThreadEvents, "event_delivery")
        // Exercise the actual KVO callback on a background thread, then verify
        // that production dispatches its Flutter event on the main queue.
        DispatchQueue.global().async {
            listener.observeValue(forKeyPath: "outputVolume", of: session, change: [:], context: nil)
            DispatchQueue.main.async {
                check(events == 3 && mainThreadEvents, "background_kvo_delivery")
                // Queue another event, then cancel before it is delivered.
                listener.observeValue(forKeyPath: "outputVolume", of: session, change: [:], context: nil)
                _ = listener.onCancel(withArguments: nil)
                check(!listener.isObservingVolume, "observer_not_removed")
                checkSession("cancel")
                _ = listener.onCancel(withArguments: nil)
                listener.sendVolumeChangeEvent()
                DispatchQueue.main.async {
                    check(events == 3, "cancelled_observer_delivered_event")
                    let report: [String: Any] = ["passed": failures.isEmpty, "failures": failures,
                        "initialCategory": category.rawValue, "finalCategory": session.category.rawValue,
                        "events": events, "mainThreadEvents": mainThreadEvents, "volume": volume]
                    let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("volume-smoke.json")
                    try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: file)
                    print("Volume session smoke: \(failures.isEmpty ? "passed" : "FAILED")")
                }
            }
        }

    }
}
