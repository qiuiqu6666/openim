import 'package:flutter/material.dart';

/// Small adapter for the reference page's inline translations.
class AiAssistantI18n {
  const AiAssistantI18n(this.locale);

  final Locale locale;

  static AiAssistantI18n of(BuildContext context) =>
      AiAssistantI18n(Localizations.localeOf(context));

  String t({
    required String zhHans,
    String? zhHant,
    required String en,
    String? ja,
    String? ko,
  }) {
    final code = locale.languageCode.toLowerCase();
    if (code == 'ja') return ja ?? en;
    if (code == 'ko') return ko ?? en;
    if (code == 'zh') {
      final script = locale.scriptCode?.toLowerCase();
      final region = locale.countryCode?.toUpperCase();
      final traditional = script == 'hant' ||
          region == 'TW' ||
          region == 'HK' ||
          region == 'MO';
      return traditional ? zhHant ?? zhHans : zhHans;
    }
    return en;
  }

  String format({
    required String zhHans,
    String? zhHant,
    required String en,
    String? ja,
    String? ko,
    required Map<String, Object?> vars,
  }) {
    var result = t(zhHans: zhHans, zhHant: zhHant, en: en, ja: ja, ko: ko);
    for (final entry in vars.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return result;
  }
}
