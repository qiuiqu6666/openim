import 'package:flutter/material.dart';

/// A neutral composer surface derived from the active light or dark theme.
Color chatComposerSurface(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return Color.alphaBlend(
    colors.onSurface.withValues(alpha: .06),
    colors.surface,
  );
}
