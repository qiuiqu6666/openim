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
          barHeight: NavigationGlassTokens.height(context),
          barBorderRadius: NavigationGlassTokens.radius,
          tabPadding: NavigationGlassTokens.tabPadding,
          iconSize: NavigationGlassTokens.iconSize,
          iconLabelSpacing: NavigationGlassTokens.iconLabelGap,
          textStyle: NavigationGlassTokens.labelStyle(context),
          // The package applies 0.5 opacity to its resting indicator.
          indicatorColor: theme.colorScheme.primary
              .withValues(alpha: NavigationGlassTokens.selectionOpacity * 2),
          selectedIconColor: theme.colorScheme.primary,
          unselectedIconColor: theme.colorScheme.onSurfaceVariant,
          // Standard-quality rendering generates a rim from refraction and
          // specular light even without a Flutter border. Keep the base plain;
          // the moving indicator retains its separate glass settings below.
          glassSettings: NavigationGlassTokens.settings(context).copyWith(
            refractiveIndex: 0,
            lightIntensity: 0,
          ),
          indicatorSettings:
              NavigationGlassTokens.settings(context, tint: Colors.transparent),
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NavigationGlassTokens.inset,
          vertical: NavigationGlassTokens.gap,
        ),
        child: LiquidGlassSurface(
          surface: NavigationGlassSurface.bottom,
          borderRadius: BorderRadius.circular(NavigationGlassTokens.radius),
          child: SizedBox(
            height: NavigationGlassTokens.height(context),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(NavigationGlassTokens.gap / 2),
                    child: AnimatedAlign(
                      duration: reduceMotion
                          ? Duration.zero
                          : NavigationGlassTokens.duration,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment(
                        config.items.length == 1
                            ? 0
                            : -1 +
                                2 *
                                    config.selectedIndex /
                                    (config.items.length - 1),
                        0,
                      ),
                      child: FractionallySizedBox(
                        widthFactor: 1 / config.items.length,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color:
                                NavigationGlassTokens.selectionColor(context),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: NavigationGlassTokens
                                    .selectionBorderOpacity,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(
                                NavigationGlassTokens.radius * 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Material(
                  type: MaterialType.transparency,
                  child: Padding(
                    padding: NavigationGlassTokens.tabPadding,
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var index = 0;
                              index < config.items.length;
                              index++)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: config.selectedIndex == index,
                                label: config.items[index].title,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                      NavigationGlassTokens.radius),
                                  onTap: () => config.onItemSelected(index),
                                  child: ExcludeSemantics(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      spacing:
                                          NavigationGlassTokens.iconLabelGap,
                                      children: [
                                        IconTheme(
                                          data: IconThemeData(
                                            size:
                                                NavigationGlassTokens.iconSize,
                                            color: config.selectedIndex == index
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme
                                                    .onSurfaceVariant,
                                          ),
                                          child: SizedBox(
                                            height:
                                                NavigationGlassTokens.iconSize,
                                            child: config.selectedIndex == index
                                                ? config.items[index].icon
                                                : config
                                                    .items[index].inactiveIcon,
                                          ),
                                        ),
                                        Text(
                                          config.items[index].title ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style:
                                              NavigationGlassTokens.labelStyle(
                                                  context),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
