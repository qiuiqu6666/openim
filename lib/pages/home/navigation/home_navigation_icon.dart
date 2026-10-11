import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'home_navigation_tokens.dart';

/// Keep the icon centered as the unread pill grows away from its upper corner.
class HomeNavigationIcon extends StatelessWidget {
  const HomeNavigationIcon(
      {super.key, required this.icon, required this.count});

  final Widget icon;
  final int count;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: HomeNavigationTokens.iconSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            icon,
            PositionedDirectional(
              top: HomeNavigationTokens.badgeTop,
              start: HomeNavigationTokens.badgeStart,
              child: IgnorePointer(
                child: UnreadCountView.compact(
                  count: count,
                ),
              ),
            ),
          ],
        ),
      );
}
