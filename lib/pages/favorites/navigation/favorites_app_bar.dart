import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Shared favorites navigation styling; routes and edit state stay with callers.
GlassAppBar favoritesAppBar(
  BuildContext context, {
  required String title,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  final navigator = Navigator.of(context);
  final titleStyle = theme.textTheme.titleMedium?.copyWith(
    fontSize: AppTokens.listTitleFontSize,
    fontWeight: FontWeight.w600,
    color: scheme.onSurface,
  );
  final actionStyle = theme.textTheme.labelLarge?.copyWith(
    fontSize: AppTokens.secondaryFontSize,
    fontWeight: FontWeight.w600,
  );
  final textScaler = MediaQuery.textScalerOf(context);
  final textHeight = math.max(
    textScaler.scale(AppTokens.listTitleFontSize) * (titleStyle?.height ?? 1),
    actionLabel == null
        ? 0.0
        : textScaler.scale(AppTokens.secondaryFontSize) *
            (actionStyle?.height ?? 1),
  );
  return GlassAppBar(
    toolbarHeight: math.max(kToolbarHeight, textHeight + AppTokens.s3),
    centerTitle: true,
    backgroundColor: AppTokens.surface(dark: dark),
    foregroundColor: scheme.onSurface,
    automaticallyImplyLeading: false,
    leading: navigator.canPop()
        ? IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            color: scheme.primary,
            iconSize: AppTokens.chevronSize,
            constraints: const BoxConstraints(
              minWidth: AppIconTokens.androidTouchTarget,
              minHeight: AppIconTokens.androidTouchTarget,
            ),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => navigator.maybePop(),
          )
        : null,
    title: Text(
      title,
      key: const ValueKey('favorites-navigation-title'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: titleStyle,
    ),
    actions: [
      if (actionLabel != null)
        Padding(
          padding: const EdgeInsetsDirectional.only(end: AppTokens.s4),
          child: TextButton(
            key: const ValueKey('favorites-edit'),
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: const Size(
                AppIconTokens.androidTouchTarget,
                AppIconTokens.androidTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
              backgroundColor: AppTokens.surfaceAlt(dark: dark),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.rMd),
              ),
              textStyle: actionStyle,
            ).copyWith(
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.disabled)
                      ? theme.disabledColor
                      : scheme.primary),
            ),
            child: Text(actionLabel, maxLines: 1),
          ),
        ),
    ],
  );
}
