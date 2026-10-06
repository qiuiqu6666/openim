import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_date_page.dart';
import 'package:openim_common/openim_common.dart';

const _conversation = 'date-picker-current-conversation';
final _today = DateUtils.dateOnly(DateTime.now());
final _thisMonthFirst = DateTime(_today.year, _today.month);
final _previousMonth = DateTime(_today.year, _today.month - 1);
final _availablePastDay =
    DateTime(_previousMonth.year, _previousMonth.month, 10);
final _emptyPastDay = DateTime(_previousMonth.year, _previousMonth.month, 11);
const _confirmKey = ValueKey('chat-history-date-confirm');

typedef _Respond = Future<List<Message>> Function(DateTime day);

Message _message(DateTime day) => Message.fromJson({
      'clientMsgID': 'message-${day.toIso8601String()}',
      'contentType': MessageType.text,
      'sendID': 'member',
      'sendTime':
          DateTime(day.year, day.month, day.day, 12).millisecondsSinceEpoch,
      'textElem': {'content': '该日聊天记录'},
    });

class _DateSource implements ChatHistorySearchSource {
  _DateSource({Set<DateTime>? days, this.respond}) : days = days ?? {};
  final Set<DateTime> days;
  final _Respond? respond;
  final calls = <DateTime>[];

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    expect(conversationID, _conversation);
    expect(query.keyword, isEmpty,
        reason: 'Calendar availability must browse the current conversation');
    final day = query.localStart!;
    calls.add(day);
    if (respond != null) return respond!(day);
    return days.contains(day) ? [_message(day)] : [];
  }
}

class _PickerFixture {
  _PickerFixture(this.source, {this.initialDate});
  final _DateSource source;
  final DateTime? initialDate;
  final navigator = GlobalKey<NavigatorState>();
  bool current = true;
  DateTime? returned;
}

// The calendar's month container shares the first day's key; its day cell is
// the last (deepest) match, which also gives that cell's own semantics node.
Finder _day(DateTime day) => find.byKey(ValueKey<DateTime>(day)).last;

bool _enabled(WidgetTester tester, DateTime day) =>
    tester.getSemantics(_day(day)).flagsCollection.isEnabled == Tristate.isTrue;

bool _canConfirm(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(_confirmKey)).onPressed != null;

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _mount(
  WidgetTester tester,
  _PickerFixture fixture, {
  Brightness brightness = Brightness.light,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = brightness == Brightness.dark;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    fontSizeResolver: (fontSize, _) => fontSize.toDouble(),
    builder: (_, __) => GetMaterialApp(
      navigatorKey: fixture.navigator,
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: brightness),
      home: const Scaffold(body: Text('搜索聊天记录入口')),
    ),
  ));
  unawaited(fixture.navigator.currentState!
      .push<DateTime>(MaterialPageRoute<DateTime>(
        builder: (_) => ChatHistoryDatePage(
          conversationID: _conversation,
          source: fixture.source,
          initialDate: fixture.initialDate,
          isCurrent: () => fixture.current,
        ),
      ))
      .then((value) => fixture.returned = value));
  await _frames(tester);
  if (settle) await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _month(WidgetTester tester, {required bool previous}) async {
  final calendar = find.byKey(const ValueKey('chat-history-date-calendar'));
  final localizations = MaterialLocalizations.of(tester.element(calendar));
  await tester.tap(find.byTooltip(previous
      ? localizations.previousMonthTooltip
      : localizations.nextMonthTooltip));
  await _frames(tester);
}

Future<void> _tapEmptyDay(WidgetTester tester, DateTime day) async {
  // Disabled dates deliberately have no tappable InkResponse. Tapping their
  // visible position verifies actual calendar behavior without callback bypass.
  await tester.tapAt(tester.getCenter(_day(day)));
  await tester.pump();
}

void _testPicker(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      semantics.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
  });
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  for (final brightness in Brightness.values) {
    _testPicker(
        '$brightness: only a day with chat records is enabled and can be returned',
        (tester) async {
      final fixture = _PickerFixture(_DateSource(days: {_availablePastDay}));
      await _mount(tester, fixture, brightness: brightness);
      await _month(tester, previous: true);
      await tester.pumpAndSettle();
      expect(_enabled(tester, _availablePastDay), isTrue);
      expect(_enabled(tester, _emptyPastDay), isFalse);
      final enabledText = tester.widget<Text>(find.descendant(
          of: _day(_availablePastDay), matching: find.byType(Text)));
      final disabledText = tester.widget<Text>(find.descendant(
          of: _day(_emptyPastDay), matching: find.byType(Text)));
      expect(disabledText.style!.color, isNot(enabledText.style!.color),
          reason: 'Empty days must have visibly disabled calendar text');
      expect(_canConfirm(tester), isFalse);
      await _tapEmptyDay(tester, _emptyPastDay);
      expect(_canConfirm(tester), isFalse);
      expect(fixture.returned, isNull);

      await tester.tap(_day(_availablePastDay));
      await tester.pump();
      expect(_canConfirm(tester), isTrue);
      await tester.tap(find.byKey(_confirmKey));
      await _frames(tester);
      await tester.pumpAndSettle();
      expect(fixture.returned, _availablePastDay);
      expect(find.text('搜索聊天记录入口'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final changedAccount in [false, true]) {
    _testPicker(
        changedAccount
            ? 'an account change while loading leaves dates grey and removes progress'
            : 'unknown dates stay disabled until the initial month finishes',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final fixture = _PickerFixture(_DateSource(respond: (day) async {
        await gate.future;
        return day == _thisMonthFirst ? [_message(day)] : [];
      }));
      await _mount(tester, fixture, settle: false);
      expect(_enabled(tester, _thisMonthFirst), isFalse);
      expect(_canConfirm(tester), isFalse);
      await _tapEmptyDay(tester, _thisMonthFirst);
      expect(_canConfirm(tester), isFalse);
      fixture.current = !changedAccount;
      gate.complete();
      await _frames(tester);
      await tester.pumpAndSettle();
      expect(_enabled(tester, _thisMonthFirst), !changedAccount);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(_canConfirm(tester), isFalse,
          reason: 'Finishing availability must not automatically choose a day');
      expect(tester.takeException(), isNull);
    });
  }

  _testPicker('an empty conversation has no selectable date or calendar assert',
      (tester) async {
    final fixture = _PickerFixture(_DateSource());
    await _mount(tester, fixture);
    expect(_enabled(tester, _thisMonthFirst), isFalse);
    await _tapEmptyDay(tester, _thisMonthFirst);
    expect(_canConfirm(tester), isFalse);
    await _month(tester, previous: true);
    await tester.pumpAndSettle();
    expect(_enabled(tester, _emptyPastDay), isFalse);
    expect(_canConfirm(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final initial in [
    _emptyPastDay,
    DateTime(1999, 12, 31),
    DateTime(_today.year + 1, 1, 1),
  ]) {
    _testPicker('unavailable initial date $initial cannot enable confirmation',
        (tester) async {
      final fixture = _PickerFixture(_DateSource(), initialDate: initial);
      await _mount(tester, fixture);
      expect(_canConfirm(tester), isFalse);
      expect(fixture.returned, isNull);
      expect(tester.takeException(), isNull,
          reason: 'Initial selection must satisfy the day predicate');
    });
  }

  _testPicker('an existing initial date is selected only after verification',
      (tester) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final fixture = _PickerFixture(
      _DateSource(respond: (day) async {
        await gate.future;
        return day == _availablePastDay ? [_message(day)] : [];
      }),
      initialDate: DateTime(_availablePastDay.year, _availablePastDay.month,
          _availablePastDay.day, 18, 42),
    );
    await _mount(tester, fixture, settle: false);
    final calendar = tester.widget<CalendarDatePicker>(
        find.byKey(const ValueKey('chat-history-date-calendar')));
    expect(calendar.initialDate, isNull);
    expect(_canConfirm(tester), isFalse);
    gate.complete();
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(_canConfirm(tester), isTrue);
    expect(_enabled(tester, _availablePastDay), isTrue);
    expect(
        tester.getSemantics(_day(_availablePastDay)).flagsCollection.isSelected,
        Tristate.isTrue);
    expect(tester.takeException(), isNull);
  });

  _testPicker('a late previous month load cannot enable dates in the new month',
      (tester) async {
    final oldDay = Completer<List<Message>>();
    addTearDown(() {
      if (!oldDay.isCompleted) oldDay.complete([]);
    });
    final fixture = _PickerFixture(_DateSource(respond: (day) async {
      if (day == _thisMonthFirst) return oldDay.future;
      return day == _availablePastDay ? [_message(day)] : [];
    }));
    await _mount(tester, fixture, settle: false);
    await _month(tester, previous: true);
    await _frames(tester);
    expect(_enabled(tester, _availablePastDay), isTrue);
    expect(_enabled(tester, _emptyPastDay), isFalse);
    oldDay.complete([_message(_thisMonthFirst)]);
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(_enabled(tester, _availablePastDay), isTrue);
    expect(_enabled(tester, _emptyPastDay), isFalse);
    expect(_canConfirm(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  _testPicker(
      'returning to a month reflects deleted and newly received records',
      (tester) async {
    final fixture = _PickerFixture(_DateSource(days: {_availablePastDay}));
    await _mount(tester, fixture);
    await _month(tester, previous: true);
    await tester.pumpAndSettle();
    final previousReads = fixture.source.calls
        .where((day) =>
            day.year == _previousMonth.year &&
            day.month == _previousMonth.month)
        .length;
    await _month(tester, previous: false);
    await tester.pumpAndSettle();
    fixture.source.days
      ..remove(_availablePastDay)
      ..add(_emptyPastDay);
    await _month(tester, previous: true);
    await tester.pumpAndSettle();
    expect(_enabled(tester, _availablePastDay), isFalse);
    expect(_enabled(tester, _emptyPastDay), isTrue);
    expect(
        fixture.source.calls
            .where((day) =>
                day.year == _previousMonth.year &&
                day.month == _previousMonth.month)
            .length,
        greaterThan(previousReads));
    await _tapEmptyDay(tester, _availablePastDay);
    expect(_canConfirm(tester), isFalse);
    await tester.tap(_day(_emptyPastDay));
    await tester.pump();
    expect(_canConfirm(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  _testPicker('a failed month keeps unknown days disabled and supports retry',
      (tester) async {
    var fail = true;
    final fixture = _PickerFixture(_DateSource(respond: (day) async {
      if (fail) throw StateError('temporary unavailable');
      return day == _thisMonthFirst ? [_message(day)] : [];
    }));
    await _mount(tester, fixture);
    final retry = find.byKey(const ValueKey('chat-history-date-retry'));
    expect(retry, findsOneWidget);
    expect(_enabled(tester, _thisMonthFirst), isFalse);
    expect(_canConfirm(tester), isFalse);
    fail = false;
    await tester.tap(retry);
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(_enabled(tester, _thisMonthFirst), isTrue);
    expect(retry, findsNothing);
    expect(_canConfirm(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  _testPicker(
      'a previous selection cannot confirm while the next month is loading',
      (tester) async {
    final gate = Completer<List<Message>>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete([]);
    });
    var delayCurrentMonth = false;
    final fixture = _PickerFixture(_DateSource(respond: (day) async {
      if (delayCurrentMonth && day == _thisMonthFirst) return gate.future;
      return day == _availablePastDay ? [_message(day)] : [];
    }));
    await _mount(tester, fixture);
    await _month(tester, previous: true);
    await tester.pumpAndSettle();
    await tester.tap(_day(_availablePastDay));
    await tester.pump();
    expect(_canConfirm(tester), isTrue);
    delayCurrentMonth = true;
    await _month(tester, previous: false);
    expect(_canConfirm(tester), isFalse,
        reason: 'Changing months must not submit during availability loading');
    expect(fixture.returned, isNull);
    gate.complete([]);
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(fixture.returned, isNull);
    expect(tester.takeException(), isNull);
  });

  _testPicker(
      'deleting the selected day before confirmation keeps the page open',
      (tester) async {
    final fixture = _PickerFixture(_DateSource(days: {_thisMonthFirst}));
    await _mount(tester, fixture);
    await tester.tap(_day(_thisMonthFirst));
    await tester.pump();
    expect(_canConfirm(tester), isTrue);
    fixture.source.days.clear();
    await tester.tap(find.byKey(_confirmKey));
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ChatHistoryDatePage), findsOneWidget);
    expect(fixture.returned, isNull);
    expect(_canConfirm(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  _testPicker(
      'foreground resume recalibrates dates and clears a deleted selection',
      (tester) async {
    final fixture = _PickerFixture(_DateSource(days: {_thisMonthFirst}));
    await _mount(tester, fixture);
    await tester.tap(_day(_thisMonthFirst));
    await tester.pump();
    expect(_canConfirm(tester), isTrue);
    final probesBefore =
        fixture.source.calls.where((d) => d == _thisMonthFirst).length;
    fixture.source.days.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(_canConfirm(tester), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(_enabled(tester, _thisMonthFirst), isFalse);
    expect(_canConfirm(tester), isFalse);
    expect(fixture.source.calls.where((d) => d == _thisMonthFirst).length,
        probesBefore + 1,
        reason: 'Resume should recalibrate the visible month once');
    expect(fixture.returned, isNull);
    expect(tester.takeException(), isNull);
  });

  _testPicker('an account change prevents returning a previously selected day',
      (tester) async {
    final fixture = _PickerFixture(_DateSource(days: {_thisMonthFirst}));
    await _mount(tester, fixture);
    await tester.tap(_day(_thisMonthFirst));
    await tester.pump();
    expect(_canConfirm(tester), isTrue);
    final requests = fixture.source.calls.length;
    fixture.current = false;
    await tester.tap(find.byKey(_confirmKey));
    await _frames(tester);
    expect(fixture.returned, isNull);
    expect(fixture.source.calls, hasLength(requests));
    expect(find.byType(ChatHistoryDatePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final resumeFinishedFirst in [false, true]) {
    _testPicker(
        'a stale confirmation preserves the selected day when resume ${resumeFinishedFirst ? 'has completed' : 'is loading'}',
        (tester) async {
      final confirming = Completer<List<Message>>();
      final restoring = Completer<List<Message>>();
      addTearDown(() {
        if (!confirming.isCompleted) confirming.complete([]);
        if (!restoring.isCompleted) restoring.complete([]);
      });
      var pastDayReads = 0;
      final fixture = _PickerFixture(_DateSource(respond: (day) async {
        if (day != _availablePastDay) return [];
        if (++pastDayReads == 2) return confirming.future;
        if (pastDayReads == 3) return restoring.future;
        return [_message(day)];
      }));
      await _mount(tester, fixture);
      await _month(tester, previous: true);
      await tester.pumpAndSettle();
      await tester.tap(_day(_availablePastDay));
      await tester.pump();
      await tester.tap(find.byKey(_confirmKey));
      await _frames(tester);
      expect(_canConfirm(tester), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _frames(tester);
      expect(pastDayReads, 3);
      if (resumeFinishedFirst) {
        restoring.complete([_message(_availablePastDay)]);
        await _frames(tester);
      }
      confirming.complete([_message(_availablePastDay)]);
      await _frames(tester);
      expect(fixture.returned, isNull,
          reason: 'A confirmation from before resume must not return a day');
      expect(_day(_availablePastDay), findsOneWidget,
          reason: 'A stale confirmation must not reset the displayed month');
      if (!resumeFinishedFirst) {
        expect(_canConfirm(tester), isFalse);
        restoring.complete([_message(_availablePastDay)]);
        await _frames(tester);
      }
      await tester.pumpAndSettle();
      expect(_enabled(tester, _availablePastDay), isTrue);
      expect(_canConfirm(tester), isTrue);
      expect(
          tester
              .getSemantics(_day(_availablePastDay))
              .flagsCollection
              .isSelected,
          Tristate.isTrue);
      await tester.tap(find.byKey(_confirmKey));
      await _frames(tester);
      await tester.pumpAndSettle();
      expect(fixture.returned, _availablePastDay);
      expect(tester.takeException(), isNull);
    });
  }

  _testPicker(
      'disposing a loading picker ignores responses and stops more reads',
      (tester) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final fixture = _PickerFixture(_DateSource(respond: (day) async {
      await gate.future;
      return [_message(day)];
    }));
    await _mount(tester, fixture, settle: false);
    fixture.navigator.currentState!.pop();
    await _frames(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final requests = fixture.source.calls.length;
    gate.complete();
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(fixture.source.calls, hasLength(requests));
    expect(fixture.returned, isNull);
    expect(find.text('搜索聊天记录入口'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
