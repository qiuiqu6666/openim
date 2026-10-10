import 'package:flutter/material.dart';
import 'live_style.dart';

/// Paints the current theme inside a transparent modal route so an open sheet
/// changes its background together with its form and picker text.
class LiveSheetSurface extends StatelessWidget {
  const LiveSheetSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
        color: LiveStyle.card(context),
        shape: theme.bottomSheetTheme.shape ??
            (theme.useMaterial3
                ? const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(LiveStyle.sheetRadius)))
                : null),
        clipBehavior: Clip.antiAlias,
        child: child);
  }
}
