import 'package:flutter/widgets.dart';

/// Gesture boundaries end inside the unobscured reading area, not behind chrome.
/// Keep the bounds stable when controls are toggled during a reading gesture.
class MediaReadingViewport extends StatelessWidget {
  const MediaReadingViewport({super.key, required this.child});

  static const toolbarExtent = 72.0;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return MediaReadingInsets(
      insets: EdgeInsets.only(
        top: safe.top + toolbarExtent,
        bottom: safe.bottom + toolbarExtent,
        left: safe.left,
        right: safe.right,
      ),
      child: child,
    );
  }
}

class MediaReadingInsets extends InheritedWidget {
  const MediaReadingInsets(
      {super.key, required this.insets, required super.child});
  final EdgeInsets insets;
  static EdgeInsets of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MediaReadingInsets>()
          ?.insets ??
      EdgeInsets.zero;
  @override
  bool updateShouldNotify(MediaReadingInsets oldWidget) =>
      insets != oldWidget.insets;
}
