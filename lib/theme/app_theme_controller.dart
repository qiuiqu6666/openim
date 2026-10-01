import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          Styles.isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: Styles.isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor:
          Styles.isDark ? const Color(0xFF141D27) : Colors.white,
      systemNavigationBarIconBrightness:
          Styles.isDark ? Brightness.light : Brightness.dark,
    ));
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == ThemeMode.system) {
      _syncStyles();
      notifyListeners();
    }
  }
}
