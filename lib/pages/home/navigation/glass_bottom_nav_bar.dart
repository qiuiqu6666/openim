import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

import 'home_navigation_tokens.dart';

/// Liquid glass around the existing persistent tabs and unread icons.
class GlassBottomNavBar extends StatefulWidget {
  const GlassBottomNavBar({
    super.key,
    required this.config,
    this.onItemSelected,
  });

  final NavBarConfig config;

  /// Optional entry checks run before the persistent tab is changed.
  final ValueChanged<int>? onItemSelected;

  @override
  State<GlassBottomNavBar> createState() => _GlassBottomNavBarState();
}

class _GlassBottomNavBarState extends State<GlassBottomNavBar> {
  @override
  void initState() {
    super.initState();
    unawaited(NavigationGlassController.instance
        .initializeRenderer(preferLiquid: true));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = AppTokens.surface(dark: dark);
    final inactive = AppTokens.textSecondary(dark: dark);
    final config = widget.config;
    const corners =
        BorderRadius.all(Radius.circular(HomeNavigationTokens.radius));

    return AppSystemBars(
        background: background,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: HomeNavigationTokens.inset),
            child: DecoratedBox(
              decoration: BoxDecoration(
                  borderRadius: corners,
                  boxShadow: [HomeNavigationTokens.shadow(context)]),
              child: LiquidGlassSurface(
                surface: NavigationGlassSurface.bottom,
                borderRadius: corners,
                opacity: HomeNavigationTokens.opacity(context),
                preferLiquid: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      borderRadius: corners,
                      border: Border.all(
                          color: HomeNavigationTokens.edge(context))),
                  child: SizedBox(
                    height: HomeNavigationTokens.height,
                    child: LayoutBuilder(builder: (context, constraints) {
                      final slotWidth =
                          constraints.maxWidth / config.items.length;
                      return Stack(children: [
                        AnimatedPositionedDirectional(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : NavigationGlassTokens.duration,
                          curve: Curves.easeInOutCubic,
                          start: slotWidth * config.selectedIndex +
                              HomeNavigationTokens.selectionInset,
                          top: HomeNavigationTokens.selectionInset,
                          bottom: HomeNavigationTokens.selectionInset,
                          width: slotWidth -
                              HomeNavigationTokens.selectionInset * 2,
                          child: IgnorePointer(
                              child: DecoratedBox(
                            key: const ValueKey('home-nav-selection'),
                            decoration: BoxDecoration(
                                color: HomeNavigationTokens.selection(context),
                                borderRadius: corners,
                                border: Border.all(
                                    color: HomeNavigationTokens.edge(context))),
                          )),
                        ),
                        Positioned.fill(
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
                                for (var index = 0;
                                    index < config.items.length;
                                    index++)
                                  BottomNavigationBarItem(
                                    // The fixed icon lane contains compact unread
                                    // pills; keep their digits inside the pill.
                                    icon: MediaQuery.withClampedTextScaling(
                                      maxScaleFactor: 1,
                                      child: config.selectedIndex == index
                                          ? config.items[index].icon
                                          : config.items[index].inactiveIcon,
                                    ),
                                    label: config.items[index].title ?? '',
                                  ),
                              ],
                              currentIndex: config.selectedIndex,
                              type: BottomNavigationBarType.fixed,
                              selectedFontSize: HomeNavigationTokens.labelSize,
                              unselectedFontSize:
                                  HomeNavigationTokens.labelSize,
                              selectedItemColor: AppTokens.accent,
                              unselectedItemColor: inactive,
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              onTap: widget.onItemSelected ??
                                  config.onItemSelected,
                            ),
                          ),
                        )),
                      ]);
                    }),
                  ),
                ),
              ),
            ),
          ),
        ));
  }
}
