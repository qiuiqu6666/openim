// Exercise the shared formatter with the application's locale delegates.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:openim_common/openim_common.dart';

Future<BuildContext> _context(WidgetTester tester, Locale locale) async {
  Get.locale = locale;
  Get.addTranslations(TranslationService().keys);
  late BuildContext result;
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Builder(builder: (context) {
      result = context;
      return const SizedBox.shrink();
    }),
  ));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  late String? previousIntlLocale;
  setUp(() {
    previousIntlLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'en_US';
    Get.testMode = true;
  });
  tearDown(() {
    Intl.defaultLocale = previousIntlLocale;
    Get.reset();
  });

  for (final locale in [const Locale('zh', 'CN'), const Locale('en', 'US')]) {
    testWidgets('same-day labels retain zero-padded 24-hour time in $locale',
        (tester) async {
      final context = await _context(tester, locale);
      final now = DateTime(2026, 10, 5, 20);
      expect(
          formatChatMessageTime(
              context, DateTime(2026, 10, 5, 0, 5).millisecondsSinceEpoch,
              now: now),
          '00:05');
      expect(
          formatChatMessageTime(
              context, DateTime(2026, 10, 5, 19, 8).millisecondsSinceEpoch,
              now: now),
          '19:08');
    });

    testWidgets(
        'yesterday is a calendar day across month boundaries in $locale',
        (tester) async {
      final context = await _context(tester, locale);
      expect(
          formatChatMessageTime(
              context, DateTime(2026, 5, 31, 0, 1).millisecondsSinceEpoch,
              now: DateTime(2026, 6, 1, 23, 59)),
          '${locale.languageCode == 'zh' ? '昨天' : 'Yesterday'} 00:01');
    });

    testWidgets('rolling six-day boundary and weekday labels in $locale',
        (tester) async {
      final context = await _context(tester, locale);
      final now = DateTime(2026, 10, 5, 18);
      expect(
          formatChatMessageTime(
              context, DateTime(2026, 9, 29).millisecondsSinceEpoch,
              now: now),
          '${locale.languageCode == 'zh' ? '星期二' : 'Tuesday'} 00:00');
      expect(
          formatChatMessageTime(
              context, DateTime(2026, 9, 28, 23, 59).millisecondsSinceEpoch,
              now: now),
          '09-28 23:59');
      expect(
          formatChatMessageTime(
              context, DateTime(2026, 10, 3, 23, 59).millisecondsSinceEpoch,
              now: now),
          '${locale.languageCode == 'zh' ? '星期六' : 'Saturday'} 23:59');
    });
  }

  testWidgets('different-year formatting takes priority over yesterday',
      (tester) async {
    final context = await _context(tester, const Locale('zh', 'CN'));
    expect(
        formatChatMessageTime(
            context, DateTime(2025, 12, 31, 23, 59).millisecondsSinceEpoch,
            now: DateTime(2026, 1, 1, 0, 1)),
        '2025-12-31 23:59');
    expect(
        formatChatMessageTime(
            context, DateTime(2025, 1, 1, 9).millisecondsSinceEpoch,
            now: DateTime(2026, 10, 5)),
        '2025-01-01 09:00');
  });

  testWidgets('older dates within this year omit the year', (tester) async {
    final context = await _context(tester, const Locale('en', 'US'));
    expect(
        formatChatMessageTime(
            context, DateTime(2026, 1, 2, 9, 3).millisecondsSinceEpoch,
            now: DateTime(2026, 10, 5)),
        '01-02 09:03');
  });

  testWidgets('leap-day yesterday and millisecond precision are retained',
      (tester) async {
    final context = await _context(tester, const Locale('en', 'US'));
    expect(
        formatChatMessageTime(context,
            DateTime(2024, 2, 29, 23, 59, 59, 999).millisecondsSinceEpoch,
            now: DateTime(2024, 3, 1)),
        'Yesterday 23:59');
    expect(
        formatChatMessageTime(
            context, DateTime(2024, 3, 1).millisecondsSinceEpoch,
            now: DateTime(2024, 3, 1)),
        '00:00');
  });
}
