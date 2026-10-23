import Flutter
import UIKit

/// Engine-scoped registration; there is no app/session state in the bridge.
final class HomeTabBarFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private let assetKey: (String) -> String
    private let registrar: FlutterPluginRegistrar
    private let capability: FlutterMethodChannel

    init(registrar: FlutterPluginRegistrar) {
        messenger = registrar.messenger()
        assetKey = { registrar.lookupKey(forAsset: $0) }
        self.registrar = registrar
        capability = FlutterMethodChannel(
            name: "openim/home-navigation", binaryMessenger: registrar.messenger())
        super.init()
        capability.setMethodCallHandler { call, result in
            guard call.method == "isSupported" else {
                result(FlutterMethodNotImplemented)
                return
            }
            if #available(iOS 26.0, *) {
                result(Bundle.main.object(forInfoDictionaryKey:
                    "UIDesignRequiresCompatibility") as? Bool != true)
            } else {
                result(false)
            }
        }
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        HomeTabBarPlatformView(frame: frame, identifier: viewId, args: args,
                               messenger: messenger, parent: registrar.viewController, assetKey: assetKey)
    }
}
