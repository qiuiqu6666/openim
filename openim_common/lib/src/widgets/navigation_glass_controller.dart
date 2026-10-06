import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

import '../utils/sp_util.dart';

enum NavigationGlassMode { automatic, liquid, translucent }

/// Navigation-only rendering preference; never applied to message/list content.
class NavigationGlassController extends ChangeNotifier {
  NavigationGlassController({Future<void> Function()? initialize})
      : _initialize = initialize ?? _initializeChecked;

  static Future<void> _initializeChecked() async {
    // Version 0.5.0 logs shader failures without rethrowing them. Verify the
    // standard surface and interactive indicator before accepting the mode.
    for (final asset in ['lightweight_glass', 'interactive_indicator']) {
      final program = await ui.FragmentProgram.fromAsset(
          'packages/liquid_glass_widgets/shaders/$asset.frag');
      program.fragmentShader().dispose();
    }
    await glass.LiquidGlassWidgets.initialize();
  }

  final Future<void> Function() _initialize;
  static final instance = NavigationGlassController();
  static const storageKey = 'navigationGlassMode';

  NavigationGlassMode _mode = NavigationGlassMode.automatic;
  NavigationGlassMode get mode => _mode;
  bool _rendererAvailable = false;
  Future<bool>? _initialization;
  int _request = 0;

  void load() {
    final saved = SpUtil().getString(storageKey);
    _mode = NavigationGlassMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => NavigationGlassMode.automatic,
    );
    notifyListeners();
  }

  Future<bool> setMode(NavigationGlassMode mode) async {
    final request = ++_request;
    final ready = !_needsRenderer(mode) || await _ensureRenderer();
    // A newer choice wins even if shader loading finishes afterwards.
    if (request != _request) return true;
    if (!ready) return false;
    if (_mode == mode) return true;
    _mode = mode;
    notifyListeners();
    await SpUtil().putString(storageKey, mode.name);
    return true;
  }

  Future<void> initializeRenderer({bool preferLiquid = false}) async {
    if (_needsRenderer(_mode) ||
        (preferLiquid && _mode == NavigationGlassMode.automatic)) {
      await _ensureRenderer();
    }
  }

  bool _needsRenderer(NavigationGlassMode mode) =>
      mode == NavigationGlassMode.liquid ||
      (mode == NavigationGlassMode.automatic &&
          defaultTargetPlatform != TargetPlatform.android);

  Future<bool> _ensureRenderer() async {
    if (_rendererAvailable) return true;
    if (_initialization != null) return _initialization!;
    final pending = _loadRenderer();
    _initialization = pending;
    try {
      return await pending;
    } finally {
      _initialization = null;
    }
  }

  Future<bool> _loadRenderer() async {
    try {
      await _initialize();
      _rendererAvailable = true;
      notifyListeners();
      return true;
    } catch (error) {
      // Shader warm-up must never prevent users from opening their chats.
      _rendererAvailable = false;
      notifyListeners();
      debugPrint(
          'Navigation glass unavailable; using translucent bars: $error');
      return false;
    }
  }

  bool usesTranslucent(BuildContext context, {bool preferLiquid = false}) =>
      !_rendererAvailable ||
      MediaQuery.highContrastOf(context) ||
      MediaQuery.disableAnimationsOf(context) ||
      _mode == NavigationGlassMode.translucent ||
      (_mode == NavigationGlassMode.automatic &&
          !preferLiquid &&
          Theme.of(context).platform == TargetPlatform.android);
}
