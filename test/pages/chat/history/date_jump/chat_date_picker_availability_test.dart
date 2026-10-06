import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history/date_jump/widgets/chat_date_image_calendar.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;

import 'support/chat_date_picker_availability_fixture.dart';

void _pickerTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _tapDisabled(WidgetTester tester, DateTime day) async {
  await tester.tapAt(tester.getCenter(dateJumpDay(day)));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    _pickerTest('${brightness.name}: empty days are grey and cannot jump',
        (tester) async {
      final fixture = DateJumpFixture(DateJumpSource(days: {dateJumpPresent}));
      await fixture.open(tester, brightness: brightness);
      expect(dateJumpEnabled(tester, dateJumpPresent), isTrue);
      expect(dateJumpEnabled(tester, dateJumpEmpty), isFalse);
      final enabled = tester.widget<Text>(find.descendant(
          of: dateJumpDay(dateJumpPresent), matching: find.byType(Text)));
      final disabled = tester.widget<Text>(find.descendant(
          of: dateJumpDay(dateJumpEmpty), matching: find.byType(Text)));
      expect(disabled.style!.color, isNot(enabled.style!.color));
      expect(find.text('确定'), findsNothing);
      expect(fixture.completions, 0);
      await _tapDisabled(tester, dateJumpEmpty);
      expect(fixture.completions, 0);
      expect(dateJumpKey('dialog'), findsOneWidget);
      await tester.tap(dateJumpDay(dateJumpPresent));
      await dateJumpFrames(tester);
      await tester.pumpAndSettle();
      expect(fixture.returned, dateJumpPresent);
      expect(fixture.completions, 1);
      expect(dateJumpKey('dialog'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    _pickerTest('${brightness.name}: brand theme and compact cancel row',
        (tester) async {
      final fixture = DateJumpFixture(DateJumpSource(days: {dateJumpPresent}));
      await fixture.open(tester, brightness: brightness);
      final calendarContext =
          tester.element(find.byType(ChatDateImageCalendar));
      expect(Theme.of(calendarContext).colorScheme.primary, AppTokens.accent);
      final dialog = tester.widget<Dialog>(dateJumpKey('dialog'));
      expect(dialog.backgroundColor,
          Theme.of(calendarContext).colorScheme.surface);
      expect(find.text('chatJumpToDate'.tr), findsOneWidget);
      expect(find.text('chatJumpToDateHint'.tr), findsNothing);
      final cancel = tester.getRect(dateJumpKey('cancel'));
      final dialogBounds = tester.getRect(find
          .descendant(
              of: dateJumpKey('dialog'), matching: find.byType(Material))
          .first);
      expect(cancel.width, greaterThan(dialogBounds.width * .8));
      expect(dialogBounds.height, lessThan(600),
          reason: 'The normal picker should be a compact dialog');
      expect(dateJumpKey('cancel').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final changedAccount in [false, true]) {
    _pickerTest(
        changedAccount
            ? 'an account change during loading leaves dates grey'
            : 'unconfirmed dates stay disabled until loading completes',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final fixture = DateJumpFixture(DateJumpSource(respond: (day) async {
        await gate.future;
        return day == dateJumpPresent ? [dateJumpMessage(day)] : [];
      }));
      await fixture.open(tester, settle: false);
      expect(dateJumpEnabled(tester, dateJumpPresent), isFalse);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await _tapDisabled(tester, dateJumpPresent);
      expect(fixture.completions, 0);
      fixture.current = !changedAccount;
      gate.complete();
      await dateJumpFrames(tester);
      await tester.pumpAndSettle();
      expect(dateJumpEnabled(tester, dateJumpPresent), !changedAccount);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(fixture.completions, 0,
          reason: 'Availability completion must not automatically jump');
      expect(tester.takeException(), isNull);
    });
  }

  _pickerTest('a conversation with no records has no selectable dates',
      (tester) async {
    final fixture = DateJumpFixture(DateJumpSource());
    await fixture.open(tester);
    expect(dateJumpEnabled(tester, dateJumpPresent), isFalse);
    await _tapDisabled(tester, dateJumpPresent);
    await dateJumpMonth(tester, previous: true);
    await tester.pumpAndSettle();
    expect(dateJumpEnabled(tester, dateJumpPast), isFalse);
    await _tapDisabled(tester, dateJumpPast);
    expect(fixture.completions, 0);
    expect(tester.takeException(), isNull);
  });

  for (final initial in [dateJumpEmpty, DateTime(1997, 4, 7), DateTime(2030)]) {
    _pickerTest(
        'an unavailable initial date $initial never bypasses availability',
        (tester) async {
      final fixture = DateJumpFixture(DateJumpSource(), initialDate: initial);
      await fixture.open(tester);
      final picker = tester
          .widget<ChatDateImageCalendar>(find.byType(ChatDateImageCalendar));
      expect(picker.initialDate, isNull);
      expect(fixture.completions, 0);
      expect(tester.takeException(), isNull,
          reason: 'Unknown initial dates must not assert the day predicate');
    });
  }

  _pickerTest(
      'returning to a month reflects removed and newly received records',
      (tester) async {
    final source = DateJumpSource(days: {dateJumpPresent});
    final fixture = DateJumpFixture(source);
    await fixture.open(tester);
    await dateJumpMonth(tester, previous: true);
    await tester.pumpAndSettle();
    source.days
      ..remove(dateJumpPresent)
      ..add(dateJumpEmpty);
    await dateJumpMonth(tester, previous: false);
    await tester.pumpAndSettle();
    expect(dateJumpEnabled(tester, dateJumpPresent), isFalse);
    expect(dateJumpEnabled(tester, dateJumpEmpty), isTrue);
    await _tapDisabled(tester, dateJumpPresent);
    expect(fixture.completions, 0);
    await tester.tap(dateJumpDay(dateJumpEmpty));
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(fixture.returned, dateJumpEmpty);
    expect(tester.takeException(), isNull);
  });

  _pickerTest('a late earlier month response cannot change the visible month',
      (tester) async {
    final gate = Completer<List<Message>>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete([]);
    });
    final fixture = DateJumpFixture(DateJumpSource(respond: (day) async {
      if (day == dateJumpFirst) return gate.future;
      return day == dateJumpPast ? [dateJumpMessage(day)] : [];
    }));
    await fixture.open(tester, settle: false);
    await dateJumpMonth(tester, previous: true);
    expect(dateJumpEnabled(tester, dateJumpPast), isTrue);
    gate.complete([dateJumpMessage(dateJumpFirst)]);
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(dateJumpDay(dateJumpPast), findsOneWidget);
    expect(dateJumpEnabled(tester, dateJumpPast), isTrue);
    expect(fixture.completions, 0);
    expect(tester.takeException(), isNull);
  });

  for (final failure in [false, true]) {
    _pickerTest(
        failure
            ? 'a failed day recheck keeps the dialog open for retry'
            : 'a deleted day recheck keeps the dialog open and disables that day',
        (tester) async {
      var verify = false;
      final fixture = DateJumpFixture(DateJumpSource(respond: (day) async {
        if (day != dateJumpPresent) return [];
        if (!verify) return [dateJumpMessage(day)];
        if (failure) throw StateError('temporary unavailable');
        return [];
      }));
      await fixture.open(tester);
      verify = true;
      await tester.tap(dateJumpDay(dateJumpPresent));
      await dateJumpFrames(tester);
      await tester.pumpAndSettle();
      expect(dateJumpKey('dialog'), findsOneWidget);
      expect(fixture.completions, 0);
      expect(dateJumpEnabled(tester, dateJumpPresent), isFalse);
      if (failure) {
        final retry = dateJumpKey('retry');
        expect(retry, findsOneWidget);
        verify = false;
        await tester.tap(retry);
        await dateJumpFrames(tester);
        await tester.pumpAndSettle();
        expect(dateJumpEnabled(tester, dateJumpPresent), isTrue);
        expect(retry, findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  _pickerTest('foreground resume recalibrates the visible month',
      (tester) async {
    final source = DateJumpSource(days: {dateJumpPresent});
    final fixture = DateJumpFixture(source);
    await fixture.open(tester);
    source.days
      ..remove(dateJumpPresent)
      ..add(dateJumpEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(dateJumpEnabled(tester, dateJumpPresent), isFalse);
    expect(dateJumpEnabled(tester, dateJumpEmpty), isTrue);
    expect(fixture.completions, 0);
    expect(tester.takeException(), isNull);
  });

  _pickerTest('an account change during day verification cannot return a date',
      (tester) async {
    final gate = Completer<List<Message>>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete([]);
    });
    var reads = 0;
    final fixture = DateJumpFixture(DateJumpSource(respond: (day) async {
      if (day != dateJumpPresent) return [];
      return ++reads == 2 ? gate.future : [dateJumpMessage(day)];
    }));
    await fixture.open(tester);
    await tester.tap(dateJumpDay(dateJumpPresent));
    await dateJumpFrames(tester);
    fixture.current = false;
    gate.complete([dateJumpMessage(dateJumpPresent)]);
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(fixture.completions, 0);
    expect(dateJumpEnabled(tester, dateJumpPresent), isFalse);
    expect(dateJumpKey('dialog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _pickerTest('cancelling pending verification ignores its eventual response',
      (tester) async {
    final gate = Completer<List<Message>>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete([]);
    });
    var reads = 0;
    final fixture = DateJumpFixture(DateJumpSource(respond: (day) async {
      if (day != dateJumpPresent) return [];
      return ++reads == 2 ? gate.future : [dateJumpMessage(day)];
    }));
    await fixture.open(tester);
    await tester.tap(dateJumpDay(dateJumpPresent));
    await dateJumpFrames(tester);
    await tester.tap(dateJumpKey('cancel'));
    await dateJumpFrames(tester);
    gate.complete([dateJumpMessage(dateJumpPresent)]);
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(fixture.returned, isNull);
    expect(fixture.completions, 1);
    expect(find.text('打开日期跳转'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _pickerTest('disposing a loading dialog stops subsequent day reads',
      (tester) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final fixture = DateJumpFixture(DateJumpSource(respond: (day) async {
      await gate.future;
      return [dateJumpMessage(day)];
    }));
    await fixture.open(tester, settle: false);
    await tester.tap(dateJumpKey('cancel'));
    await dateJumpFrames(tester);
    final reads = fixture.source.calls.length;
    gate.complete();
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(fixture.source.calls, hasLength(reads));
    expect(fixture.completions, 1);
    expect(tester.takeException(), isNull);
  });

  _pickerTest('a pending day recheck cannot dismiss a covering route',
      (tester) async {
    final gate = Completer<List<Message>>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete([]);
    });
    var reads = 0;
    final fixture = DateJumpFixture(DateJumpSource(respond: (day) async {
      if (day != dateJumpPresent) return [];
      return ++reads == 2 ? gate.future : [dateJumpMessage(day)];
    }));
    await fixture.open(tester);
    await tester.tap(dateJumpDay(dateJumpPresent));
    await dateJumpFrames(tester);
    unawaited(fixture.navigator.currentState!.push<void>(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('覆盖日期弹窗的页面')),
    )));
    await tester.pumpAndSettle();
    gate.complete([dateJumpMessage(dateJumpPresent)]);
    await dateJumpFrames(tester);
    expect(find.text('覆盖日期弹窗的页面'), findsOneWidget);
    expect(fixture.completions, 0);
    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(dateJumpKey('dialog'), findsOneWidget);
    await tester.tap(dateJumpDay(dateJumpPresent));
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(fixture.returned, dateJumpPresent);
    expect(tester.takeException(), isNull);
  });

  _pickerTest(
      'a day recheck from before resume cannot jump during recalibration',
      (tester) async {
    final confirming = Completer<List<Message>>();
    final restoring = Completer<List<Message>>();
    addTearDown(() {
      if (!confirming.isCompleted) confirming.complete([]);
      if (!restoring.isCompleted) restoring.complete([]);
    });
    var reads = 0;
    final fixture = DateJumpFixture(DateJumpSource(respond: (day) async {
      if (day != dateJumpPresent) return [];
      if (++reads == 2) return confirming.future;
      if (reads == 3) return restoring.future;
      return [dateJumpMessage(day)];
    }));
    await fixture.open(tester);
    await tester.tap(dateJumpDay(dateJumpPresent));
    await dateJumpFrames(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await dateJumpFrames(tester);
    expect(reads, 3);
    confirming.complete([dateJumpMessage(dateJumpPresent)]);
    await dateJumpFrames(tester);
    expect(fixture.completions, 0);
    expect(dateJumpDay(dateJumpPresent), findsOneWidget);
    expect(dateJumpEnabled(tester, dateJumpPresent), isFalse);
    restoring.complete([dateJumpMessage(dateJumpPresent)]);
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(dateJumpEnabled(tester, dateJumpPresent), isTrue);
    await tester.tap(dateJumpDay(dateJumpPresent));
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(fixture.returned, dateJumpPresent);
    expect(tester.takeException(), isNull);
  });

  _pickerTest('the last day of a six-week month remains reachable',
      (tester) async {
    final august = DateTime(2026, 8, 31);
    final fixture =
        DateJumpFixture(DateJumpSource(days: {august}), initialDate: august);
    await fixture.open(tester);
    expect(dateJumpEnabled(tester, august), isTrue);
    await tester.ensureVisible(dateJumpDay(august));
    await tester.pumpAndSettle();
    expect(dateJumpDay(august).hitTestable(), findsOneWidget);
    await tester.tap(dateJumpDay(august));
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(fixture.returned, august);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      _pickerTest('${brightness.name}: $size at 200% text keeps cancel visible',
          (tester) async {
        final fixture =
            DateJumpFixture(DateJumpSource(days: {dateJumpPresent}));
        await fixture.open(tester,
            brightness: brightness, size: size, textScale: 2);
        final cancelBefore = tester.getRect(dateJumpKey('cancel'));
        expect(cancelBefore.left, greaterThanOrEqualTo(0));
        expect(cancelBefore.right, lessThanOrEqualTo(size.width));
        expect(cancelBefore.top, greaterThanOrEqualTo(24));
        expect(cancelBefore.bottom, lessThanOrEqualTo(size.height - 24));
        expect(dateJumpKey('cancel').hitTestable(), findsOneWidget);
        await tester.ensureVisible(dateJumpDay(dateJumpPresent));
        await tester.pumpAndSettle();
        expect(dateJumpDay(dateJumpPresent).hitTestable(), findsOneWidget);
        expect(tester.getRect(dateJumpKey('cancel')), cancelBefore,
            reason: 'Calendar scrolling must not move the cancel action');
        await tester.tap(dateJumpKey('cancel'));
        await tester.pumpAndSettle();
        expect(fixture.returned, isNull);
        expect(fixture.completions, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
