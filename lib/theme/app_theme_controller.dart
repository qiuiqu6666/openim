import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

class AppThemeController extends ChangeNotifier with WidgetsBindingObserver {
  AppThemeController._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final instance = AppThemeController._();
  static const _storageKey = 'appThemeMode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  void load() {
    final saved = SpUtil().getString(_storageKey);
    _mode = ThemeMode.values.firstWhere(
      (value) => value.name == saved,
      orElse: () => ThemeMode.system,
    );
    _syncStyles();
  }

  Future<void> setMode(ThemeMode value) async {
    if (_mode == value) return;
    _mode = value;
    _syncStyles();
    notifyListeners();
    await SpUtil().putString(_storageKey, value.name);
  }

  void _syncStyles() {
    Styles.isDark = _mode == ThemeMode.dark ||
        (_mode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    // Visible routes declare system-bar styles. Theme changes must not
    // imperatively overwrite a scanner, photo viewer or nested tab's style.
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == ThemeMode.system) {
      _syncStyles();
      notifyListeners();
    }
  }
}
