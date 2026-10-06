import AVKit
import Flutter
import UIKit

/// Native public AirPlay routing UI; never receives signed playback URLs.
final class LiveAirPlayViewFactory: NSObject, FlutterPlatformViewFactory {
    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        LiveAirPlayPlatformView(frame: frame, arguments: args)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

private final class LiveAirPlayPlatformView: NSObject, FlutterPlatformView {
    private let picker: AVRoutePickerView

    init(frame: CGRect, arguments: Any?) {
        let view = AVRoutePickerView(frame: frame)
        view.backgroundColor = .clear
        view.accessibilityLabel = "投屏"
        view.accessibilityHint = "选择 AirPlay 播放设备"
        let params = arguments as? [String: Any]
        if let tint = params?["tint"] as? NSNumber {
            view.tintColor = Self.color(tint.uint32Value)
        }
        if let activeTint = params?["activeTint"] as? NSNumber {
            view.activeTintColor = Self.color(activeTint.uint32Value)
        }
        if #available(iOS 13.0, *) {
            view.prioritizesVideoDevices = true
        }
        picker = view
        super.init()
    }

    private static func color(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: CGFloat((value >> 24) & 0xff) / 255
        )
    }

    func view() -> UIView { picker }
}
