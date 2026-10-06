import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/date_jump/widgets/chat_date_image_calendar.dart';
import 'package:openim/pages/chat/history_search/selection/date_availability/chat_date_day_image.dart';
import 'package:openim/pages/chat/media/widgets/chat_video_thumbnail.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;

import '../../../../support/media/deferred_thumbnail_http.dart';
import 'support/chat_date_image_calendar_fixture.dart';

Finder _day(DateTime day) => find.byKey(ValueKey<DateTime>(day));
Finder _number(DateTime day) =>
    find.descendant(of: _day(day), matching: find.byType(Text));

void _calendarTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      DeferredThumbnailHttpClient.restore();
      semantics.dispose();
    }
  });
}

void main() {
  for (final brightness in Brightness.values) {
    _calendarTest(
        '${brightness.name}: a decoded photo uses white date text and a circular crop',
        (tester) async {
      final fixture = ImageCalendarFixture()..days.add(imageCalendarDay);
      fixture.images[imageCalendarDay] = ChatDateDayImage(
          messageID: 'photo', localPath: imageCalendarPhotoPath);
      await fixture.open(tester, brightness: brightness);
      expect(
          find.descendant(
              of: _day(imageCalendarDay), matching: find.byType(Image)),
          findsOneWidget);
      expect(
          find.descendant(
              of: _day(imageCalendarDay), matching: find.byType(ClipOval)),
          findsOneWidget);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
      expect(tester.widget<Text>(_number(imageCalendarDay)).style!.color,
          AppTokens.onAccent);
      final semantics = tester.getSemantics(_day(imageCalendarDay));
      expect(semantics.flagsCollection.isEnabled, Tristate.isTrue);
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.label, contains('2026'));
      expect(tester.getRect(_day(imageCalendarDay)).height,
          greaterThanOrEqualTo(48));
      await tester.tap(_day(imageCalendarDay));
      await tester.pump();
      expect(fixture.chosen, imageCalendarDay);
      expect(fixture.selections, 1,
          reason: 'The thumbnail is decoration, not a separate preview action');
      expect(
          tester
              .getSemantics(_day(imageCalendarDay))
              .flagsCollection
              .isSelected,
          Tristate.isTrue);
      expect(tester.takeException(), isNull);
    });

    _calendarTest(
        '${brightness.name}: a missing image returns readable plain dates',
        (tester) async {
      final fixture = ImageCalendarFixture()..days.add(imageCalendarDay);
      fixture.images[imageCalendarDay] = const ChatDateDayImage(
          messageID: 'missing', localPath: '/missing/calendar-photo.png');
      await fixture.open(tester, brightness: brightness);
      expect(
          tester.widget<Text>(_number(imageCalendarDay)).style!.color,
          Theme.of(tester.element(_day(imageCalendarDay)))
              .colorScheme
              .onSurface);
      expect(find.byType(Image), findsNothing);
      await tester.tap(_day(imageCalendarDay));
      await tester.pump();
      expect(fixture.chosen, imageCalendarDay);
      expect(tester.takeException(), isNull);
    });

    _calendarTest(
        '${brightness.name}: unknown or empty days never request an image or select',
        (tester) async {
      final fixture = ImageCalendarFixture();
      fixture.images[imageCalendarEmpty] = ChatDateDayImage(
          messageID: 'must-not-render', localPath: imageCalendarPhotoPath);
      await fixture.open(tester, brightness: brightness);
      expect(find.byType(ChatVideoThumbnail), findsNothing);
      expect(fixture.imageReads, isEmpty);
      expect(
          tester
              .getSemantics(_day(imageCalendarEmpty))
              .flagsCollection
              .isEnabled,
          Tristate.isFalse);
      await tester.tapAt(tester.getCenter(_day(imageCalendarEmpty)));
      await tester.pump();
      expect(fixture.selections, 0);
      fixture.days.add(imageCalendarEmpty);
      fixture.changes.value++;
      await settleCalendarImages(tester);
      expect(
          tester
              .getSemantics(_day(imageCalendarEmpty))
              .flagsCollection
              .isEnabled,
          Tristate.isTrue);
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  _calendarTest(
      'updating a photo to a failed file cannot retain white text or old pixels',
      (tester) async {
    final fixture = ImageCalendarFixture()..days.add(imageCalendarDay);
    fixture.images[imageCalendarDay] =
        ChatDateDayImage(messageID: 'first', localPath: imageCalendarPhotoPath);
    await fixture.open(tester);
    expect(tester.widget<Text>(_number(imageCalendarDay)).style!.color,
        AppTokens.onAccent);
    fixture.images[imageCalendarDay] = const ChatDateDayImage(
        messageID: 'replacement', localPath: '/missing/replacement.png');
    fixture.changes.value++;
    await settleCalendarImages(tester);
    expect(find.byType(Image), findsNothing);
    expect(tester.widget<Text>(_number(imageCalendarDay)).style!.color,
        isNot(AppTokens.onAccent));
    expect(tester.takeException(), isNull);
  });

  _calendarTest('a failed remote thumbnail returns the ordinary date',
      (tester) async {
    await HttpOverrides.runZoned(() async {
      final fixture = ImageCalendarFixture()..days.add(imageCalendarDay);
      fixture.images[imageCalendarDay] = const ChatDateDayImage(
          messageID: 'remote-failure',
          localPath: '/missing/photo.png',
          url: 'https://example.invalid/calendar-photo.png');
      await fixture.open(tester);
      expect(tester.widget<Text>(_number(imageCalendarDay)).style!.color,
          isNot(AppTokens.onAccent));
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => throw StateError('thumbnail unavailable'));
  });

  for (final accountChanged in [false, true]) {
    _calendarTest(
        accountChanged
            ? 'a late decoded frame after an account change cannot retain photo or selected white text'
            : 'a late decoded frame after image removal returns a plain date',
        (tester) async {
      final client = DeferredThumbnailHttpClient()..install();
      final fixture = ImageCalendarFixture(
          initial: accountChanged ? imageCalendarDay : null)
        ..days.add(imageCalendarDay);
      fixture.images[imageCalendarDay] = ChatDateDayImage(
          messageID: 'late-frame',
          url: 'https://thumbnail.test/calendar-late-$accountChanged.webp');
      await fixture.open(tester);
      expect(client.requests, 1);
      final calendar = tester
          .widget<ChatDateImageCalendar>(find.byType(ChatDateImageCalendar));
      if (accountChanged) {
        fixture.current = false;
      } else {
        fixture.images.remove(imageCalendarDay);
      }
      // No parent notification or pumpWidget: only the image receives its frame.
      client.bytes.complete(await tester
          .runAsync(() => File(imageCalendarPhotoPath).readAsBytes()));
      await settleCalendarImages(tester);
      expect(
          tester.widget<ChatDateImageCalendar>(
              find.byType(ChatDateImageCalendar)),
          same(calendar));
      expect(find.byType(RawImage), findsNothing);
      expect(tester.widget<Text>(_number(imageCalendarDay)).style!.color,
          isNot(AppTokens.onAccent));
      expect(
          tester
              .widgetList<ColoredBox>(find.descendant(
                  of: _day(imageCalendarDay),
                  matching: find.byType(ColoredBox)))
              .any((box) => box.color == AppTokens.accent),
          isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (locale, column) in [
    (const Locale('en', 'US'), 4),
    (const Locale('en', 'GB'), 3),
  ]) {
    _calendarTest(
        '$locale: weekdays follow the locale and boundaries remain disabled',
        (tester) async {
      final fixture = ImageCalendarFixture(first: DateTime(2026, 10, 2));
      fixture.days.addAll([DateTime(2026, 10, 1), DateTime(2026, 10, 2)]);
      await fixture.open(tester, locale: locale);
      final bounds = tester.getRect(find.byType(ChatDateImageCalendar));
      final first = tester.getRect(_day(DateTime(2026, 10, 1)));
      expect(first.left, closeTo(bounds.left + bounds.width / 7 * column, .1));
      expect(
          tester
              .getSemantics(_day(DateTime(2026, 10, 1)))
              .flagsCollection
              .isEnabled,
          Tristate.isFalse);
      final text =
          MaterialLocalizations.of(tester.element(_day(imageCalendarDay)));
      expect(tester.getSemantics(_day(DateTime(2026, 10, 2))).label,
          contains(text.formatFullDate(DateTime(2026, 10, 2))));
      expect(
          tester
              .widgetList<IconButton>(find.byType(IconButton))
              .firstWhere(
                  (button) => button.tooltip == text.previousMonthTooltip)
              .onPressed,
          isNull);
      expect(
          tester
              .widgetList<IconButton>(find.byType(IconButton))
              .firstWhere((button) => button.tooltip == text.nextMonthTooltip)
              .onPressed,
          isNull);
      expect(tester.takeException(), isNull);
    });
  }

  _calendarTest(
      'year selection changes the visible month without automatically choosing a day',
      (tester) async {
    final fixture = ImageCalendarFixture(
        first: DateTime(2025, 6, 30),
        last: DateTime(2026, 2, 5),
        initial: DateTime(2025, 10, 8));
    fixture.days.add(DateTime(2025, 10, 8));
    await fixture.open(tester);
    final height = tester.getSize(find.byType(ChatDateImageCalendar)).height;
    await tester
        .tap(find.byKey(const ValueKey('chat-date-image-calendar-month')));
    await tester.pumpAndSettle();
    expect(find.byType(YearPicker), findsOneWidget);
    expect(tester.getSize(find.byType(ChatDateImageCalendar)).height, height);
    final year =
        MaterialLocalizations.of(tester.element(find.byType(YearPicker)))
            .formatYear(DateTime(2026));
    await tester.tap(find.text(year));
    await tester.pumpAndSettle();
    expect(find.byType(YearPicker), findsNothing);
    expect(_day(DateTime(2026, 2, 5)), findsOneWidget);
    expect(fixture.months, [DateTime(2026, 2)]);
    expect(fixture.selections, 0);
    expect(tester.takeException(), isNull);
  });

  _calendarTest('six-week months keep the last date and stable calendar height',
      (tester) async {
    final august = DateTime(2026, 8, 31);
    final fixture = ImageCalendarFixture(initial: august)..days.add(august);
    await fixture.open(tester);
    final before = tester.getSize(find.byType(ChatDateImageCalendar)).height;
    await tester.tap(_day(august));
    await tester.pump();
    expect(fixture.chosen, august);
    final next =
        MaterialLocalizations.of(tester.element(_day(august))).nextMonthTooltip;
    await tester.tap(find.byTooltip(next));
    await tester.pump();
    expect(_day(DateTime(2026, 9, 30)), findsOneWidget);
    expect(tester.getSize(find.byType(ChatDateImageCalendar)).height, before);
    expect(tester.takeException(), isNull);
  });

  for (final rtl in [false, true]) {
    _calendarTest(
        '${rtl ? 'RTL' : 'LTR'}: horizontal swipes change months within the range',
        (tester) async {
      final fixture = ImageCalendarFixture(first: DateTime(2026, 9))
        ..days.add(imageCalendarDay);
      await fixture.open(tester,
          locale: rtl ? const Locale('ar') : const Locale('en', 'US'));
      final grid = find.byKey(const ValueKey('chat-date-image-calendar-days'));
      final toPrevious = Offset(rtl ? -180 : 180, 0);
      await tester.drag(grid, toPrevious);
      await tester.pumpAndSettle();
      expect(_day(DateTime(2026, 9, 30)), findsOneWidget);
      expect(fixture.months, [DateTime(2026, 9)]);
      await tester.drag(grid, toPrevious);
      await tester.pumpAndSettle();
      expect(fixture.months, hasLength(1));
      await tester.drag(grid, -toPrevious);
      await tester.pumpAndSettle();
      expect(_day(imageCalendarDay), findsOneWidget);
      expect(fixture.months, [DateTime(2026, 9), DateTime(2026, 10)]);
      await tester.drag(grid, -toPrevious);
      await tester.pumpAndSettle();
      expect(fixture.months, hasLength(2));
      expect(fixture.selections, 0);
      expect(tester.takeException(), isNull);
    });
  }

  _calendarTest(
      'vertical drags still scroll the calendar and short drags do not change month',
      (tester) async {
    final fixture = ImageCalendarFixture();
    await fixture.open(tester, size: const Size(568, 320), textScale: 2);
    final grid = find.byKey(const ValueKey('chat-date-image-calendar-days'));
    final before = tester.getRect(_day(imageCalendarDay));
    await tester.drag(grid, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getRect(_day(imageCalendarDay)).top, lessThan(before.top));
    expect(fixture.months, isEmpty);
    await tester.drag(grid, const Offset(35, 0));
    await tester.pumpAndSettle();
    expect(fixture.months, isEmpty);
    expect(fixture.selections, 0);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    _calendarTest(
        '$size: large-text days remain reachable and have complete date labels',
        (tester) async {
      final fixture = ImageCalendarFixture()..days.add(DateTime(2026, 10, 12));
      await fixture.open(tester, size: size, textScale: 2);
      final day = _day(DateTime(2026, 10, 12));
      await tester.ensureVisible(day);
      await tester.pumpAndSettle();
      final number = tester.widget<Text>(_number(DateTime(2026, 10, 12)));
      expect(number.data, '12');
      expect(number.softWrap, isFalse);
      expect(day.hitTestable(), findsOneWidget);
      expect(tester.getRect(day).height, greaterThanOrEqualTo(48));
      await tester.tap(day);
      await tester.pump();
      expect(fixture.chosen, DateTime(2026, 10, 12));
      expect(tester.takeException(), isNull);
    });
  }

  _calendarTest(
      'controls have names and usable touch targets on a standard phone',
      (tester) async {
    final fixture = ImageCalendarFixture()..days.add(imageCalendarDay);
    await fixture.open(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester.takeException(), isNull);
  });
}
