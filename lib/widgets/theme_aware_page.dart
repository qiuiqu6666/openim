import 'package:flutter/material.dart';

/// Rebuilds a page when the app theme changes, including pages inside a tab's
/// nested Navigator. The child keeps its state when its widget type is stable.
class ThemeAwarePage extends StatelessWidget {
  const ThemeAwarePage({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return builder(context);
  }
}
