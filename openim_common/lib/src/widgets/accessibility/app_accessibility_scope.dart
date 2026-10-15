import 'package:flutter/widgets.dart';

/// Preserves the platform text scaler and exposes iOS Reduce Motion through
/// the same inherited flag already consumed by the app's motion components.
class AppAccessibilityScope extends StatefulWidget {
  const AppAccessibilityScope({super.key, required this.child});
  final Widget child;

  @override
  State<AppAccessibilityScope> createState() => _AppAccessibilityScopeState();
}

class _AppAccessibilityScopeState extends State<AppAccessibilityScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
        data: media.copyWith(
            disableAnimations: media.disableAnimations ||
                WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
                    .reduceMotion),
        child: widget.child);
  }
}
