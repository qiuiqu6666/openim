import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

/// OpenIM tab host rendered with the same bottom-navigation visual contract
/// used by 99chat. The app keeps OpenIM's existing tab set; only presentation
/// is aligned here.
class GlassBottomNavBar extends StatelessWidget {
  const GlassBottomNavBar({super.key, required this.config});

  final NavBarConfig config;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = AppTokens.surface(dark: dark);
    final inactive = AppTokens.textSecondary(dark: dark);

    return ColoredBox(
      color: background,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: kBottomNavigationBarHeight,
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: Theme(
              data: Theme.of(context).copyWith(
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                hoverColor: Colors.transparent,
              ),
              child: BottomNavigationBar(
                items: [
                  for (var index = 0; index < config.items.length; index++)
                    BottomNavigationBarItem(
                      icon: config.selectedIndex == index
                          ? config.items[index].icon
                          : config.items[index].inactiveIcon,
                      label: config.items[index].title ?? '',
                    ),
                ],
                currentIndex: config.selectedIndex,
                type: BottomNavigationBarType.fixed,
                selectedFontSize: 11,
                unselectedFontSize: 11,
                selectedItemColor: AppTokens.accent,
                unselectedItemColor: inactive,
                backgroundColor: background,
                elevation: 0,
                onTap: config.onItemSelected,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
