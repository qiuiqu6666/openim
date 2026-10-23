import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

import 'glass_bottom_nav_bar.dart';
import 'native/ios_home_tab_bar.dart';

/// Chooses a renderer without changing the persistent tab/page owner.
class HomeBottomNavBar extends StatefulWidget {
  const HomeBottomNavBar({
    super.key,
    required this.config,
    required this.unreadCounts,
    required this.onItemSelected,
  });

  final NavBarConfig config;
  final List<int> unreadCounts;
  final ValueChanged<int> onItemSelected;

  @override
  State<HomeBottomNavBar> createState() => _HomeBottomNavBarState();
}

class _HomeBottomNavBarState extends State<HomeBottomNavBar>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('openim/home-navigation');
  bool _nativeAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _checkNativeSupport();
    }
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkNativeSupport() async {
    try {
      final supported = await _channel.invokeMethod<bool>('isSupported');
      if (mounted && supported == true) {
        setState(() => _nativeAvailable = true);
      }
    } on MissingPluginException {
      // Older host binaries and tests retain the Flutter renderer.
    } on PlatformException catch (error) {
      debugPrint('Native home navigation unavailable: ${error.code}');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: NavigationGlassController.instance,
        builder: (context, _) {
          // Read the actual view: a nested Scaffold may remove MediaQuery's
          // keyboard inset while the root customer-service dialog owns focus.
          // Remove platform views too, so UIKit cannot lift its bar over input.
          if (View.of(context).viewInsets.bottom > 0) {
            return const SizedBox.shrink();
          }
          if (_nativeAvailable &&
              NavigationGlassController.instance.mode !=
                  NavigationGlassMode.translucent) {
            return IOSHomeTabBar(
              config: widget.config,
              unreadCounts: widget.unreadCounts,
              onItemSelected: widget.onItemSelected,
              onUnavailable: () {
                if (mounted) setState(() => _nativeAvailable = false);
              },
            );
          }
          return GlassBottomNavBar(
            config: widget.config,
            onItemSelected: widget.onItemSelected,
          );
        },
      );
}
