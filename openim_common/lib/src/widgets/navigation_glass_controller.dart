import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

import '../utils/sp_util.dart';

enum NavigationGlassMode { automatic, liquid, translucent }

/// Navigation-only rendering preference; never applied to message/list content.
class NavigationGlassController extends ChangeNotifier {
  static final instance = NavigationGlassController();
  static const storageKey = 'navigationGlassMode';

  NavigationGlassMode _mode = NavigationGlassMode.automatic;
  NavigationGlassMode get mode => _mode;
  bool _rendererAvailable = true;

  void load() {
    final saved = SpUtil().getString(storageKey);
    _mode = NavigationGlassMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => NavigationGlassMode.automatic,
    );
    notifyListeners();
  }

  Future<void> setMode(NavigationGlassMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await SpUtil().putString(storageKey, mode.name);
  }

  Future<void> initializeRenderer() async {
    // Avoid shader compilation at startup when Android uses the safe default.
    // Explicitly enabling glass later loads the package shaders lazily.
    if (_mode == NavigationGlassMode.translucent ||
        (_mode == NavigationGlassMode.automatic &&
            defaultTargetPlatform == TargetPlatform.android)) {
      return;
    }
    try {
      await glass.LiquidGlassWidgets.initialize();
    } catch (error) {
      // Shader warm-up must never prevent users from opening their chats.
      _rendererAvailable = false;
      notifyListeners();
      debugPrint(
          'Navigation glass unavailable; using translucent bars: $error');
    }
  }

  bool usesTranslucent(BuildContext context) =>
      !_rendererAvailable ||
      MediaQuery.highContrastOf(context) ||
      MediaQuery.disableAnimationsOf(context) ||
      _mode == NavigationGlassMode.translucent ||
      (_mode == NavigationGlassMode.automatic &&
          Theme.of(context).platform == TargetPlatform.android);
}
