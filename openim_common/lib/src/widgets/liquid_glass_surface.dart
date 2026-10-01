import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

import 'navigation_glass_controller.dart';

/// Shared navigation settings for the package's glass renderer.
abstract final class NavigationGlassTokens {
  static const radius = 28.0;
  static const inset = 12.0;
  static const gap = 8.0;
  static const barHeight = 64.0;
  static const labelSize = 12.0;
  static const duration = Duration(milliseconds: 220);
  static const quality = glass.GlassQuality.standard;
  static const topShape = BorderRadius.vertical(bottom: Radius.circular(20));

  static glass.LiquidGlassSettings settings(BuildContext context,
      {Color? tint}) {
    final theme = Theme.of(context);
    return glass.LiquidGlassSettings(
      glassColor: (tint ?? theme.cardColor).withValues(
        alpha: theme.brightness == Brightness.dark ? .32 : .24,
      ),
      blur: 8,
      thickness: 24,
      lightIntensity: .6,
      ambientStrength: .8,
      saturation: 1.1,
      chromaticAberration: .01,
    );
  }
}

/// Adapter for the existing TitleBar and Material AppBar layouts.
/// All blur, refraction and highlights are rendered by liquid_glass_widgets.
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = NavigationGlassTokens.topShape,
    this.tint,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? tint;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: NavigationGlassController.instance,
        builder: (context, _) => _buildSurface(context),
      );

  Widget _buildSurface(BuildContext context) {
    final theme = Theme.of(context);
    if (NavigationGlassController.instance.usesTranslucent(context)) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: ColoredBox(
          color: (tint ?? theme.cardColor).withValues(
            alpha: MediaQuery.highContrastOf(context) ? 1 : .94,
          ),
          child: child,
        ),
      );
    }
    return CupertinoTheme(
      data: CupertinoTheme.of(context).copyWith(brightness: theme.brightness),
      child: glass.GlassContainer(
        useOwnLayer: true,
        quality: NavigationGlassTokens.quality,
        settings: NavigationGlassTokens.settings(context, tint: tint),
        shape: glass.LiquidRoundedRectangle(
          borderRadius: borderRadius.bottomLeft.x,
        ),
        child: child,
      ),
    );
  }
}

/// Keeps Material's automatic back button, semantics and existing actions.
class GlassAppBar extends AppBar {
  GlassAppBar({
    super.key,
    super.title,
    super.leading,
    super.actions,
    super.centerTitle,
    super.automaticallyImplyLeading,
    super.toolbarHeight,
    super.titleSpacing,
  }) : super(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          flexibleSpace: const LiquidGlassSurface(child: SizedBox.expand()),
        );
}
