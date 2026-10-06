import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

import 'navigation_glass_controller.dart';
import 'app_system_bars.dart';

enum NavigationGlassSurface { top, bottom }

/// Shared navigation settings for the package's glass renderer.
abstract final class NavigationGlassTokens {
  static double get toolbarHeight => 56.h;

  static const radius = 28.0;
  static const inset = 12.0;
  static const gap = 8.0;
  static const barHeight = 64.0;
  static const labelSize = 12.0;
  static const iconSize = 24.0;
  static const iconLabelGap = 4.0;
  static const tabPadding = EdgeInsets.symmetric(horizontal: 4);
  static const selectionOpacity = 0.0;
  static const selectionBorderOpacity = .25;
  static const duration = Duration(milliseconds: 220);
  static const quality = glass.GlassQuality.standard;
  static const topShape = BorderRadius.zero;
  static const topBlur = 18.0;
  static const bottomBlur = 20.0;
  static const lightOpacity = .76;
  static const darkOpacity = .70;

  static Color frostedTint(BuildContext context,
      {Color? tint, double? opacity}) {
    final base = tint == null || tint.a == 0 ? backgroundColor(context) : tint;
    if (MediaQuery.highContrastOf(context)) return base.withValues(alpha: 1);
    return base.withValues(
      alpha: opacity ??
          (Theme.of(context).brightness == Brightness.dark
              ? darkOpacity
              : lightOpacity),
    );
  }

  static Color backgroundColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).appBarTheme.backgroundColor ??
              Theme.of(context).colorScheme.surface;

  static double height(BuildContext context) =>
      barHeight +
      (MediaQuery.textScalerOf(context).scale(labelSize) - labelSize)
              .clamp(0, double.infinity) *
          1.2;

  static TextStyle labelStyle(BuildContext context) =>
      (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
        fontSize: labelSize,
        height: 1.2,
        color: Theme.of(context).colorScheme.onSurface,
      );

  static Color selectionColor(BuildContext context) =>
      Theme.of(context).colorScheme.primary.withValues(alpha: selectionOpacity);

  static glass.LiquidGlassSettings settings(BuildContext context,
      {Color? tint,
      double? opacity,
      NavigationGlassSurface surface = NavigationGlassSurface.bottom}) {
    final isTop = surface == NavigationGlassSurface.top;
    return glass.LiquidGlassSettings(
      glassColor: frostedTint(context, tint: tint, opacity: opacity),
      blur: isTop ? topBlur : bottomBlur,
      thickness: isTop ? 12 : 24,
      lightIntensity: isTop ? 0 : .4,
      refractiveIndex: isTop ? 0 : 1.2,
      // The standard renderer multiplies the tint by ambient light. Using
      // 0.8 turns an opaque white surface grey even with a white glassColor.
      ambientStrength:
          Theme.of(context).brightness == Brightness.light ? 1 : .8,
      saturation: 1,
      chromaticAberration: 0,
    );
  }
}

/// Adapter for the existing TitleBar and Material AppBar layouts.
/// Bounds blur to navigation chrome and retains the optional liquid renderer.
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = NavigationGlassTokens.topShape,
    this.tint,
    this.opacity,
    this.preferLiquid = false,
    this.surface = NavigationGlassSurface.top,
  }) : assert(opacity == null || (opacity >= 0 && opacity <= 1));

  final Widget child;
  final BorderRadius borderRadius;
  final Color? tint;
  final double? opacity;
  final bool preferLiquid;
  final NavigationGlassSurface surface;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: NavigationGlassController.instance,
        builder: (context, _) => _buildSurface(context),
      );

  Widget _buildSurface(BuildContext context) {
    final theme = Theme.of(context);
    if (MediaQuery.highContrastOf(context) ||
        NavigationGlassController.instance
            .usesTranslucent(context, preferLiquid: preferLiquid)) {
      final content = ColoredBox(
        color: NavigationGlassTokens.frostedTint(context,
            tint: tint, opacity: opacity),
        child: child,
      );
      return ClipRRect(
        borderRadius: borderRadius,
        child: MediaQuery.highContrastOf(context)
            ? content
            : BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: surface == NavigationGlassSurface.top
                      ? NavigationGlassTokens.topBlur
                      : NavigationGlassTokens.bottomBlur,
                  sigmaY: surface == NavigationGlassSurface.top
                      ? NavigationGlassTokens.topBlur
                      : NavigationGlassTokens.bottomBlur,
                  tileMode: TileMode.clamp,
                ),
                child: content,
              ),
      );
    }
    final uniform = borderRadius == BorderRadius.all(borderRadius.topLeft) &&
        borderRadius.topLeft.x == borderRadius.topLeft.y;
    return ClipRRect(
      borderRadius: borderRadius,
      child: CupertinoTheme(
        data: CupertinoTheme.of(context).copyWith(brightness: theme.brightness),
        child: glass.GlassContainer(
          useOwnLayer: true,
          quality: NavigationGlassTokens.quality,
          settings: NavigationGlassTokens.settings(context,
              tint: tint, opacity: opacity, surface: surface),
          shape: glass.LiquidRoundedRectangle(
            // The renderer only accepts one circular radius. For asymmetric
            // corners, render a full surface and clip the complete outline.
            borderRadius: uniform ? borderRadius.topLeft.x : 0,
          ),
          child: child,
        ),
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
    double? toolbarHeight,
    super.titleSpacing,
    Color? backgroundColor,
    this.opaque = false,
    super.foregroundColor,
    super.leadingWidth,
    super.bottom,
    super.iconTheme,
    super.actionsIconTheme,
    super.titleTextStyle,
    super.toolbarTextStyle,
    Widget? flexibleSpace,
    SystemUiOverlayStyle? systemOverlayStyle,
    double? elevation,
    double? scrolledUnderElevation,
    Color? surfaceTintColor,
    Color? shadowColor,
  }) : super(
          toolbarHeight: toolbarHeight ?? NavigationGlassTokens.toolbarHeight,
          backgroundColor: opaque ? backgroundColor : Colors.transparent,
          systemOverlayStyle: systemOverlayStyle ??
              (backgroundColor == null || backgroundColor.a == 0
                  ? null
                  : AppSystemBars.styleFor(backgroundColor)),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          flexibleSpace: opaque
              ? flexibleSpace
              : LiquidGlassSurface(
                  tint: backgroundColor,
                  child: flexibleSpace ?? const SizedBox.expand(),
                ),
        );

  /// Uses the exact Material background instead of glass tint and blur.
  /// Detail/edit pages can match their canvas without changing other bars.
  final bool opaque;
}
