import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppI18n {
  const AppI18n._(this.locale);

  final Locale locale;

  static AppI18n get current =>
      AppI18n._(Get.locale ?? Get.deviceLocale ?? const Locale('zh', 'CN'));

  static AppI18n of(BuildContext context) => AppI18n._(Localizations.localeOf(context));

  String t({
    required String zhHans,
    required String zhHant,
    required String en,
    required String ja,
    required String ko,
  }) {
    final code = locale.languageCode.toLowerCase();
    if (code == 'en') return en;
    if (code == 'ja') return ja;
    if (code == 'ko') return ko;
    if (code == 'zh') {
      final script = locale.scriptCode?.toLowerCase();
      final country = locale.countryCode?.toUpperCase();
      if (script == 'hant' || country == 'TW' || country == 'HK' || country == 'MO') {
        return zhHant;
      }
      return zhHans;
    }
    return en;
  }

  String format({
    required String zhHans,
    required String zhHant,
    required String en,
    required String ja,
    required String ko,
    required Map<String, Object?> vars,
  }) {
    var value = t(zhHans: zhHans, zhHant: zhHant, en: en, ja: ja, ko: ko);
    for (final entry in vars.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return value;
  }
}
