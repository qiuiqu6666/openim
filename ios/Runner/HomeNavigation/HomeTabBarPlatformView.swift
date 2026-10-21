import Flutter
import UIKit

/// UIKit renders the system material, indicators, interactions and accessibility.
/// Empty native pages never replace Flutter's persistent navigation stacks.
final class HomeTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarControllerDelegate {
    private let host: HomeTabBarHostView
    private let channel: FlutterMethodChannel
    private let assetKey: (String) -> String
    private var previousItems: NSArray?
    private var previousIconSize: CGFloat?

    init(frame: CGRect, identifier: Int64, args: Any?,
         messenger: FlutterBinaryMessenger, parent: UIViewController?,
         assetKey: @escaping (String) -> String) {
        host = HomeTabBarHostView(frame: frame, owner: parent)
        channel = FlutterMethodChannel(name: "openim/home-navigation/\(identifier)",
                                       binaryMessenger: messenger)
        self.assetKey = assetKey
        super.init()
        host.tabs.delegate = self
        if let configuration = args as? [String: Any] {
            _ = update(configuration)
        }
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            guard call.method == "update", let configuration = call.arguments as? [String: Any] else {
                result(FlutterMethodNotImplemented)
                return
            }
            result(self.update(configuration))
        }
    }

    deinit { channel.setMethodCallHandler(nil) }

    func view() -> UIView { host }

    private func color(_ argb: NSNumber) -> UIColor {
        let value = argb.uint32Value
        return UIColor(
            red: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255,
            alpha: CGFloat((value >> 24) & 255) / 255)
    }

    private func image(_ asset: String, size: CGFloat) -> UIImage? {
        guard let path = Bundle.main.path(forResource: assetKey(asset), ofType: nil),
              let original = UIImage(contentsOfFile: path) else { return nil }
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            original.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }.withRenderingMode(.alwaysTemplate)
    }

    private func update(_ configuration: [String: Any]) -> FlutterError? {
        guard let items = configuration["items"] as? [[String: String]], items.count == 5,
              let selected = configuration["selectedIndex"] as? Int,
              items.indices.contains(selected) else {
            return FlutterError(code: "invalid-tabs", message: "Expected five home tabs", details: nil)
        }
        let dark = configuration["dark"] as? Bool == true
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        host.tabs.overrideUserInterfaceStyle = dark ? .dark : .light
        let rtl = configuration["rtl"] as? Bool == true
        host.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        host.tabs.view.semanticContentAttribute = host.semanticContentAttribute
        host.tabs.tabBar.semanticContentAttribute = host.semanticContentAttribute
        if let argb = configuration["accent"] as? NSNumber {
            host.tabs.tabBar.tintColor = color(argb)
        }
        if let argb = configuration["inactive"] as? NSNumber {
            host.tabs.tabBar.unselectedItemTintColor = color(argb)
        }
        // Rebuild artwork only for a changed label/asset/size, not every badge tick.
        let artwork = items.map { item in
            ["title": item["title"] ?? "", "icon": item["icon"] ?? "",
             "selectedIcon": item["selectedIcon"] ?? ""]
        } as NSArray
        let iconSize = (configuration["iconSize"] as? NSNumber)?.doubleValue ?? 24
        if previousItems != artwork || previousIconSize != iconSize {
            var controllers: [UIViewController] = []
            for (index, item) in items.enumerated() {
                guard let normal = image(item["icon"] ?? "", size: iconSize),
                      let selectedImage = image(item["selectedIcon"] ?? "", size: iconSize) else {
                    return FlutterError(code: "missing-tab-icon", message: "Home tab asset missing", details: index)
                }
                let page = UIViewController()
                page.view.backgroundColor = .clear
                page.tabBarItem = UITabBarItem(title: item["title"], image: normal,
                                               selectedImage: selectedImage)
                controllers.append(page)
            }
            host.tabs.setViewControllers(controllers, animated: false)
            previousItems = artwork
            previousIconSize = iconSize
        }
        for (index, item) in items.enumerated() {
            let badge = item["badge"] ?? ""
            host.tabs.viewControllers?[index].tabBarItem.badgeValue = badge.isEmpty ? nil : badge
        }
        host.tabs.selectedIndex = selected
        return nil
    }

    func tabBarController(_ tabBarController: UITabBarController,
                          shouldSelect viewController: UIViewController) -> Bool {
        if let index = tabBarController.viewControllers?.firstIndex(of: viewController) {
            channel.invokeMethod("select", arguments: index)
        }
        // Wallet entry, reselection and selected state remain owned by Flutter.
        return false
    }
}
