import Flutter
import Foundation
import UIKit
import UserNotifications

/// Direct APNs registration and remote notification taps. Tokens stay in memory;
/// the authenticated Flutter service owns their server binding and navigation.
final class IOSAPNsPushBridge {
    private var channel: FlutterMethodChannel?
    private var cachedToken = ""
    private var pendingTap: [String: Any]?
    private var tapHandlerReady = false
    private var registrationActive = false
    private var registrationGeneration = 0
    // A cold-start tap can arrive before the first login/registration. Explicit
    // logout closes this gate until the next authenticated Flutter session.
    private var acceptsTaps = true
    private lazy var environment = Self.apnsEnvironment()

    func attach(messenger: FlutterBinaryMessenger) {
        guard channel == nil else { return }
        let bridge = FlutterMethodChannel(name: "ios_apns_push", binaryMessenger: messenger)
        channel = bridge
        bridge.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            self.handle(call, result: result)
        }
    }

    func didRegister(deviceToken: Data) {
        guard registrationActive else { return }
        cachedToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard !cachedToken.isEmpty else { return }
        channel?.invokeMethod("onApnsToken", arguments: tokenMetadata())
    }

    func didFailToRegister(error: Error) {
        guard registrationActive else { return }
        cachedToken = ""
        let nativeError = error as NSError
        channel?.invokeMethod("onRegistrationError", arguments: [
            "domain": nativeError.domain,
            "code": nativeError.code,
        ])
    }

    func didReceive(response: UNNotificationResponse) {
        guard acceptsTaps,
              response.notification.request.trigger is UNPushNotificationTrigger,
              response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let payload = Self.channelPayload(response.notification.request.content.userInfo)
        guard !payload.isEmpty else { return }
        if tapHandlerReady, let bridge = channel {
            bridge.invokeMethod("onNotificationTap", arguments: payload)
        } else {
            pendingTap = payload
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "install":
            // Installing the channel never prompts or reopens a logged-out session.
            result(nil)
        case "setNotificationTapHandlerReady":
            let args = call.arguments as? [String: Any] ?? [:]
            tapHandlerReady = args["ready"] as? Bool == true
            result(nil)
        case "activateNotificationTaps":
            // The authenticated Flutter owner restores clicks independently
            // from permission requests or registration for future pushes.
            acceptsTaps = true
            tapHandlerReady = true
            result(nil)
        case "registerForRemoteNotifications":
            register(result: result)
        case "unregisterForRemoteNotifications":
            registrationGeneration += 1
            registrationActive = false
            acceptsTaps = false
            tapHandlerReady = false
            cachedToken = ""
            pendingTap = nil
            UIApplication.shared.unregisterForRemoteNotifications()
            result(nil)
        case "getCachedTokens":
            result(tokenMetadata())
        case "consumePendingNotificationTap":
            let payload = pendingTap
            pendingTap = nil
            result(payload)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func register(result: @escaping FlutterResult) {
        registrationGeneration += 1
        let generation = registrationGeneration
        registrationActive = true
        acceptsTaps = true
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] _, error in
            center.getNotificationSettings { settings in
                DispatchQueue.main.async {
                    let status = Self.authorizationStatus(settings.authorizationStatus)
                    result(["authorizationStatus": status])
                    guard let self = self,
                          self.registrationActive,
                          generation == self.registrationGeneration else { return }
                    if let error = error {
                        self.didFailToRegister(error: error)
                        return
                    }
                    switch settings.authorizationStatus {
                    case .authorized, .provisional, .ephemeral:
                        UIApplication.shared.registerForRemoteNotifications()
                    case .denied, .notDetermined:
                        self.cachedToken = ""
                    @unknown default:
                        self.cachedToken = ""
                    }
                }
            }
        }
    }

    private func tokenMetadata() -> [String: String] {
        return [
            "apnsToken": cachedToken,
            "bundleId": Bundle.main.bundleIdentifier ?? "",
            "apsEnvironment": environment,
        ]
    }

    private static func authorizationStatus(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        case .notDetermined: return "notDetermined"
        @unknown default: return "notDetermined"
        }
    }

    /// Keep APNs data intact for the Dart parser while converting Foundation
    /// containers into values supported by StandardMessageCodec.
    private static func channelPayload(_ input: [AnyHashable: Any]) -> [String: Any] {
        var output: [String: Any] = [:]
        for (key, value) in input {
            if let safe = channelValue(value) {
                output[String(describing: key)] = safe
            }
        }
        return output
    }

    private static func channelValue(_ value: Any) -> Any? {
        if let map = value as? [AnyHashable: Any] { return channelPayload(map) }
        if let list = value as? [Any] { return list.compactMap(channelValue) }
        if value is String || value is NSNumber || value is NSNull { return value }
        return nil
    }

    static func apnsEnvironment() -> String {
        if let provisioned = provisionedAPNsEnvironment() { return provisioned }
        // App Store packages may omit the embedded profile. This explicit build
        // value is also used by Runner.entitlements and must match the signing.
        let declared = Bundle.main.object(forInfoDictionaryKey: "APNsEnvironment") as? String ?? ""
        return declared == "development" || declared == "production" ? declared : ""
    }

    private static func provisionedAPNsEnvironment() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let key = text.range(of: "<key>aps-environment</key>") else { return nil }
        let remainder = text[key.upperBound...]
        guard let start = remainder.range(of: "<string>"),
              let end = remainder.range(of: "</string>", range: start.upperBound..<remainder.endIndex)
        else { return nil }
        let value = remainder[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "development" || value == "production" ? value : nil
    }
}
