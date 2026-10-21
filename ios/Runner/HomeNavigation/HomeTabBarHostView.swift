import UIKit

/// Keep UIKit containment aligned with the platform view's actual lifetime.
/// All geometry is supplied by Flutter; the system lays out its own tab bar.
final class HomeTabBarHostView: UIView {
    let tabs = UITabBarController()
    weak var owner: UIViewController?

    init(frame: CGRect, owner: UIViewController?) {
        self.owner = owner
        super.init(frame: frame)
        backgroundColor = .clear
        tabs.view.backgroundColor = .clear
        if #available(iOS 18.0, *) {
            tabs.mode = .tabBar
            // Home keeps five bottom destinations on iPad as well as iPhone.
            tabs.traitOverrides.horizontalSizeClass = .compact
        }
        if #available(iOS 26.0, *) {
            // Flutter scroll views do not participate in UIKit scroll tracking.
            tabs.tabBarMinimizeBehavior = .never
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            detach()
        } else if tabs.parent == nil, let owner {
            owner.addChild(tabs)
            addSubview(tabs.view)
            tabs.view.frame = bounds
            tabs.didMove(toParent: owner)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tabs.view.frame = bounds
    }

    func detach() {
        guard tabs.parent != nil else { return }
        tabs.willMove(toParent: nil)
        tabs.view.removeFromSuperview()
        tabs.removeFromParent()
    }
}
