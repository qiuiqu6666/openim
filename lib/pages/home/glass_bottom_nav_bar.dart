import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:openim_common/openim_common.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

/// Adapts the existing persistent tabs to the package's liquid glass tab bar.
class GlassBottomNavBar extends StatelessWidget {
  const GlassBottomNavBar({super.key, required this.config});

  final NavBarConfig config;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: NavigationGlassController.instance,
        builder: (context, _) => _buildBar(context),
      );

  Widget _buildBar(BuildContext context) {
    final theme = Theme.of(context);
    if (NavigationGlassController.instance.usesTranslucent(context)) {
      return _buildTranslucentBar(context);
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return CupertinoTheme(
      data: CupertinoTheme.of(context).copyWith(brightness: theme.brightness),
      child: SafeArea(
        top: false,
        child: glass.GlassBottomBar(
          tabs: [
            for (final item in config.items)
              glass.GlassBottomBarTab(
                icon: item.inactiveIcon,
                activeIcon: item.icon,
                label: item.title ?? '',
              ),
          ],
          selectedIndex: config.selectedIndex,
          onTabSelected: config.onItemSelected,
          horizontalPadding: NavigationGlassTokens.inset,
          verticalPadding: NavigationGlassTokens.gap,
          barHeight: NavigationGlassTokens.barHeight +
              (MediaQuery.textScalerOf(context)
                          .scale(NavigationGlassTokens.labelSize) -
                      NavigationGlassTokens.labelSize)
                  .clamp(0, 48),
          barBorderRadius: NavigationGlassTokens.radius,
          textStyle: theme.textTheme.labelSmall?.copyWith(
              fontSize: NavigationGlassTokens.labelSize, height: 1.2),
          selectedIconColor: theme.colorScheme.primary,
          unselectedIconColor: theme.colorScheme.onSurfaceVariant,
          glassSettings: NavigationGlassTokens.settings(context),
          quality: NavigationGlassTokens.quality,
          glowDuration:
              reduceMotion ? Duration.zero : NavigationGlassTokens.duration,
          maskingQuality: reduceMotion
              ? glass.MaskingQuality.off
              : glass.MaskingQuality.high,
        ),
      ),
    );
  }

  Widget _buildTranslucentBar(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NavigationGlassTokens.inset,
          vertical: NavigationGlassTokens.gap,
        ),
        child: LiquidGlassSurface(
          borderRadius: BorderRadius.circular(NavigationGlassTokens.radius),
          child: SizedBox(
            height: NavigationGlassTokens.barHeight,
            child: Material(
              type: MaterialType.transparency,
              child: Row(children: [
                for (var index = 0; index < config.items.length; index++)
                  Expanded(
                      child: Semantics(
                    button: true,
                    selected: config.selectedIndex == index,
                    label: config.items[index].title,
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(NavigationGlassTokens.radius),
                      onTap: () => config.onItemSelected(index),
                      child: Container(
                        margin:
                            const EdgeInsets.all(NavigationGlassTokens.gap / 2),
                        decoration: BoxDecoration(
                          color: config.selectedIndex == index
                              ? theme.colorScheme.primary.withValues(alpha: .13)
                              : null,
                          borderRadius: BorderRadius.circular(
                              NavigationGlassTokens.radius),
                        ),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                  height: AppIconTokens.large,
                                  child: config.selectedIndex == index
                                      ? config.items[index].icon
                                      : config.items[index].inactiveIcon),
                              Flexible(
                                  child: ExcludeSemantics(
                                      child: Text(
                                config.items[index].title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: NavigationGlassTokens.labelSize,
                                  color: config.selectedIndex == index
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ))),
                            ]),
                      ),
                    ),
                  )),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
