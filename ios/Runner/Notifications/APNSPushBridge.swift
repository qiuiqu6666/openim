import Flutter
import UIKit
import UserNotifications

/// Native Apple push registration. No third-party push SDK is involved.
final class APNSPushBridge {
    private let channel: FlutterMethodChannel
    private var active = false
    private var deviceToken: String?
    private var generation = 0

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "openim_apns", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            switch call.method {
            case "register": self.register(result)
            case "unregister":
                self.active = false
                self.generation += 1
                self.deviceToken = nil
                UIApplication.shared.unregisterForRemoteNotifications()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }

    private var environment: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String
        return value == "development" || value == "production" ? value : nil
    }

    private func register(_ result: @escaping FlutterResult) {
        guard environment != nil else {
            result(FlutterError(code: "APNS_CONFIG", message: "Invalid APNS_ENVIRONMENT build setting", details: nil))
            return
        }
        active = true
        let expected = generation
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] allowed, error in
            DispatchQueue.main.async {
                guard let self = self, self.active, self.generation == expected else {
                    result(nil)
                    return
                }
                if error != nil {
                    result(FlutterError(code: "APNS_PERMISSION", message: "Notification authorization failed", details: nil))
                    return
                }
                guard allowed else { result(nil); return }
                UIApplication.shared.registerForRemoteNotifications()
                result(self.registration())
            }
        }
    }

    func didRegister(_ token: Data) {
        guard active else { return }
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        if let value = registration() { channel.invokeMethod("tokenChanged", arguments: value) }
    }

    func didFail() {
        guard active else { return }
        channel.invokeMethod("registrationFailed", arguments: nil)
    }

    private func registration() -> [String: String]? {
        guard let token = deviceToken, let environment = environment else { return nil }
        return ["token": token, "environment": environment]
    }
}
