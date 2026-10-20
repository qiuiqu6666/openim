import 'package:flutter/material.dart';

/// Keep ordinary lists within their bounds on every platform.
/// Refresh controls can still consume overscroll notifications.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
