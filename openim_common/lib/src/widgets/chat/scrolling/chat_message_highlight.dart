import 'package:flutter/material.dart';

/// Scope the feedback to the bubble, leaving avatars and the timeline alone.
class ChatMessageHighlight extends InheritedWidget {
  const ChatMessageHighlight({
    super.key,
    required this.active,
    required this.color,
    required this.fadeDuration,
    required super.child,
  });

  final bool active;
  final Color color;
  final Duration fadeDuration;

  static Widget wrap(BuildContext context, Widget child, double radius) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ChatMessageHighlight>();
    if (scope == null) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: scope.active ? 1 : 0),
      duration: scope.active || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : scope.fadeDuration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, opacity, child) => Stack(
        children: [
          child!,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scope.color.withValues(alpha: scope.color.a * opacity),
                  borderRadius: BorderRadius.circular(radius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool updateShouldNotify(ChatMessageHighlight oldWidget) =>
      active != oldWidget.active ||
      color != oldWidget.color ||
      fadeDuration != oldWidget.fadeDuration;
}
