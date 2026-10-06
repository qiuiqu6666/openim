import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Paint page backgrounds behind system bars, keeping icon contrast local to
/// the visible route. SafeArea belongs inside the painted page, not outside it.
class AppSystemBars extends StatelessWidget {
  const AppSystemBars(
      {super.key,
      required this.child,
      required this.background,
      this.navigationBackground});

  final Widget child;
  final Color background;
  final Color? navigationBackground;

  static Future<void> initialize() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  static SystemUiOverlayStyle styleFor(Color background,
      {Color? navigationBackground}) {
    final dark =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
    final navDark = ThemeData.estimateBrightnessForColor(
            navigationBackground ?? background) ==
        Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarIconBrightness:
          navDark ? Brightness.light : Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: styleFor(background, navigationBackground: navigationBackground),
        child: child,
      );
}
