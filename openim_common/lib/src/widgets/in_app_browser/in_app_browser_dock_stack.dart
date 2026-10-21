import 'package:flutter/material.dart';

import '../../res/app_tokens.dart';

/// The rear cards are only a visual cue; the front dock owns all interaction.
class InAppBrowserDockStack extends StatelessWidget {
  const InAppBrowserDockStack(
      {super.key,
      required this.count,
      required this.progress,
      required this.child});
  final int count;
  final double progress;
  final Widget child;

  static double depth(int count) => count > 1 ? AppTokens.s3 : 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(fit: StackFit.expand, children: [
      if (count > 1)
        Positioned(
          top: 0,
          bottom: 0,
          left: AppTokens.s5,
          right: AppTokens.s5,
          child: IgnorePointer(
              child: ExcludeSemantics(
                  child: DecoratedBox(
            key: const ValueKey('browser-rear-card'),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(AppTokens.rLg),
            ),
          ))),
        ),
      Padding(
          padding: EdgeInsets.only(top: depth(count) * progress), child: child),
    ]);
  }
}
