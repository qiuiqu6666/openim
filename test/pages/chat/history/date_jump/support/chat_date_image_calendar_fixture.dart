import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/date_jump/widgets/chat_date_image_calendar.dart';
import 'package:openim/pages/chat/history_search/selection/date_availability/chat_date_day_image.dart';

final imageCalendarToday = DateTime(2026, 10, 15);
final imageCalendarDay = DateTime(2026, 10, 8);
final imageCalendarEmpty = DateTime(2026, 10, 9);
final imageCalendarPhotoPath = File('assets/ai/11.webp').absolute.path;

Future<void> settleCalendarImages(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class ImageCalendarFixture {
  ImageCalendarFixture({DateTime? first, DateTime? last, this.initial})
      : first = first ?? DateTime(2000),
        last = last ?? imageCalendarToday;
  final DateTime first, last;
  DateTime? initial;
  final days = <DateTime>{};
  final images = <DateTime, ChatDateDayImage>{};
  final imageReads = <DateTime>[];
  final months = <DateTime>[];
  final changes = ValueNotifier<int>(0);
  DateTime? chosen;
  int selections = 0;
  bool current = true;

  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Size size = const Size(390, 844),
    double textScale = 1,
    Locale locale = const Locale('zh', 'CN'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      changes.dispose();
      tester.view.reset();
    });
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
        Locale('en', 'GB'),
        Locale('ar'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width - 32,
            child: SingleChildScrollView(
              child: ValueListenableBuilder<int>(
                valueListenable: changes,
                builder: (_, __, ___) => ChatDateImageCalendar(
                  initialDate: initial,
                  firstDate: first,
                  lastDate: last,
                  currentDate: imageCalendarToday,
                  selectableDayPredicate: (day) =>
                      current && days.contains(day),
                  onDateChanged: (day) {
                    chosen = day;
                    selections++;
                  },
                  onDisplayedMonthChanged: months.add,
                  imageForDate: (day) {
                    imageReads.add(day);
                    return images[day];
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await settleCalendarImages(tester);
    await tester.pumpAndSettle();
  }
}
