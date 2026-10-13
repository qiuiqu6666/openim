import Flutter
import Foundation

public final class GameShieldBridgePlugin: NSObject, FlutterPlugin {
    private let worker = DispatchQueue(label: "openim.gameshield.client", qos: .userInitiated)
    private var detached = false // Main-thread only.
    #if canImport(GameShieldSDK)
    private var client: GameShieldIOSClient? // Worker-queue only.
    #endif

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = GameShieldBridgePlugin()
        let channel = FlutterMethodChannel(name: "openim/gameshield", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard ["start", "status", "stop"].contains(call.method) else {
            result(FlutterMethodNotImplemented); return
        }
        let token = (call.arguments as? [String: Any])?["licenseToken"] as? String
        if call.method == "start" && !(token?.hasPrefix("GS2.") ?? false) {
            result(FlutterError(code: "TOKEN_INVALID", message: "GameShield credentials are not configured.", details: nil))
            return
        }
        #if canImport(GameShieldSDK)
        worker.async {
            do {
                if call.method == "stop" {
                    self.client?.stop()
                    self.client = nil
                    self.reply(result, nil)
                    return
                }
                if call.method == "start", self.client == nil {
                    let client = try GameShieldIOSClient(token: token!, worker: self.worker)
                    self.client = client
                    try client.start()
                }
                guard let client = self.client else {
                    self.reply(result, FlutterError(code: "SDK_NOT_STARTED", message: "GameShield is not running.", details: nil))
                    return
                }
                self.reply(result, try client.snapshot())
            } catch {
                if call.method == "start" {
                    self.client?.stop()
                    self.client = nil
                }
                // Native errors may contain credentials; use a fixed message.
                self.reply(result, FlutterError(code: "NATIVE_FAILED", message: "GameShield operation failed.", details: nil))
            }
        }
        #else
        if call.method == "stop" { result(nil); return }
        result(FlutterError(code: "SDK_UNAVAILABLE", message: "A compatible GameShield SDK has not been installed.", details: nil))
        #endif
    }

    private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.detached else { return }
            result(value)
        }
    }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        detached = true
        #if canImport(GameShieldSDK)
        worker.async {
            self.client?.stop()
            self.client = nil
        }
        #endif
    }
    deinit {
        #if canImport(GameShieldSDK)
        let closingClient = client
        worker.async { closingClient?.stop() }
        #endif
    }
}
