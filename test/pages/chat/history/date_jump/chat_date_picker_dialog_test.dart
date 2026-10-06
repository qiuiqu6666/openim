import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history/date_jump/widgets/chat_date_picker_dialog.dart';
import 'package:openim/pages/chat/history/date_jump/widgets/chat_date_image_calendar.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim_common/openim_common.dart' show TranslationService;

class _PickerResult {
  DateTime? date;
  int completions = 0;
}

class _DateSource implements ChatHistorySearchSource {
  final records = {
    DateTime(2026, 10, 5),
    DateTime(2026, 10, 8),
    DateTime(2026, 10, 9),
    DateTime(2026, 10, 15),
    DateTime(1997, 4, 7),
  };
  final probes = <DateTime, int>{};
  final imageReads = <DateTime>[];
  Future<List<Message>> Function(DateTime)? recheck;

  List<Message> messagesFor(DateTime day) => records.contains(day)
      ? [
          Message.fromJson({
            'clientMsgID': 'record-$day',
            'contentType': MessageType.text,
            'sendTime': DateTime(day.year, day.month, day.day, 12)
                .millisecondsSinceEpoch,
            'textElem': {'content': '当天的聊天记录'},
          })
        ]
      : [];

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    expect(conversationID, 'current-chat');
    expect(query.keyword, isEmpty);
    expect(query.startDate, query.endDate);
    if (query.messageTypes.length == 1 &&
        query.messageTypes.single == MessageType.picture) {
      expect(count, 20);
      imageReads.add(query.startDate!);
      return [];
    }
    expect(count, 1);
    if (pageIndex != 1) return [];
    final day = query.startDate!;
    final probesForDay =
        probes.update(day, (count) => count + 1, ifAbsent: () => 1);
    if (probesForDay > 1 && recheck != null) return recheck!(day);
    return messagesFor(day).where(query.accepts).take(1).toList();
  }
}

Finder _key(String name) => find.byKey(ValueKey('chat-date-picker-$name'));

Future<_PickerResult> _openPicker(
  WidgetTester tester, {
  DateTime? initialDate,
  DateTime? today,
  ChatHistorySearchSource? source,
  bool Function()? isCurrent,
  bool Function(DateTime day)? knownDayHasMessages,
  bool Function(Message message)? isRemoved,
  Brightness brightness = Brightness.light,
  Size size = const Size(375, 812),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.reset);
  final result = _PickerResult();
  Get.testMode = true;
  await tester.pumpWidget(GetMaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    translations: TranslationService(),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(brightness: brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            result.date = await showChatDatePicker(
              context: context,
              conversationID: 'current-chat',
              source: source ?? _DateSource(),
              isCurrent: isCurrent ?? () => true,
              knownDayHasMessages: knownDayHasMessages,
              isRemoved: isRemoved,
              initialDate: initialDate ?? DateTime(2026, 10, 5, 7, 16),
              now: today ?? DateTime(2026, 10, 15, 12),
            );
            result.completions++;
          },
          child: const Text('打开'),
        ),
      ),
    ),
  ));
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  tearDown(Get.reset);

  testWidgets('tapping a day immediately returns it without a confirm action',
      (tester) async {
    final result = await _openPicker(tester);
    expect(find.text('chatJumpToDate'.tr), findsOneWidget);
    expect(find.text('chatJumpToDateHint'.tr), findsNothing);
    expect(find.text('确定'), findsNothing);
    expect(
        tester.widget<ButtonStyleButton>(_key('cancel')).onPressed, isNotNull);

    await tester
        .tap(find.byKey(ValueKey<DateTime>(DateTime(2026, 10, 8))).last);
    await tester.pumpAndSettle();

    expect(result.date, DateTime(2026, 10, 8));
    expect(result.completions, 1);
    expect(_key('dialog'), findsNothing);
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final cancel in ['button', 'barrier', 'back']) {
    testWidgets('$cancel cancellation returns null', (tester) async {
      final result = await _openPicker(tester);
      switch (cancel) {
        case 'button':
          expect(find.text('取消'), findsOneWidget);
          await tester.tap(_key('cancel'));
        case 'barrier':
          await tester.tapAt(const Offset(4, 60));
        case 'back':
          Navigator.of(tester.element(_key('dialog'))).pop();
      }
      await tester.pumpAndSettle();
      expect(result.date, isNull);
      expect(result.completions, 1);
      expect(_key('dialog'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancelling pending date verification closes the dialog once',
      (tester) async {
    final reply = Completer<List<Message>>();
    final source = _DateSource()..recheck = (_) => reply.future;
    final result = await _openPicker(tester, source: source);
    final selected = DateTime(2026, 10, 8);
    await tester.tap(find.byKey(ValueKey<DateTime>(selected)).last);
    await tester.pump();
    expect(source.probes[selected], 2,
        reason: 'A real day tap rechecks the message before returning.');
    await tester.tap(_key('cancel'));
    await tester.pumpAndSettle();
    expect(result.date, isNull);
    expect(result.completions, 1);
    expect(find.text('打开'), findsOneWidget);
    reply.complete(source.messagesFor(selected));
    await tester.pumpAndSettle();
    expect(result.date, isNull);
    expect(result.completions, 1);
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('available days reuse loaded records and filter removed records',
      (tester) async {
    final source = _DateSource();
    final loaded = DateTime(2026, 10, 6);
    final removed = DateTime(2026, 10, 8);
    await _openPicker(tester,
        source: source,
        knownDayHasMessages: (day) => day == loaded,
        isRemoved: (message) => message.clientMsgID == 'record-$removed');
    final picker = tester
        .widget<ChatDateImageCalendar>(find.byType(ChatDateImageCalendar));
    expect(picker.selectableDayPredicate(loaded), isTrue);
    expect(source.probes[loaded], isNull,
        reason: 'Actual loaded messages need no duplicate SDK search.');
    expect(picker.selectableDayPredicate(removed), isFalse);
    expect(picker.selectableDayPredicate(DateTime(2026, 10, 7)), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a deleted day stays open after its tap is rechecked',
      (tester) async {
    final source = _DateSource();
    final selected = DateTime(2026, 10, 8);
    final result = await _openPicker(tester, source: source);
    source.records.remove(selected);
    await tester.tap(find.byKey(ValueKey<DateTime>(selected)).last);
    await tester.pumpAndSettle();
    expect(source.probes[selected], 2);
    expect(result.completions, 0);
    expect(_key('dialog'), findsOneWidget);
    final picker = tester
        .widget<ChatDateImageCalendar>(find.byType(ChatDateImageCalendar));
    expect(picker.selectableDayPredicate(selected), isFalse);
    await tester.tap(_key('cancel'));
    await tester.pumpAndSettle();
    expect(result.date, isNull);
    expect(result.completions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing month loads and rechecks that months real records',
      (tester) async {
    final source = _DateSource();
    final selected = DateTime(2026, 9, 9);
    source.records.add(selected);
    final result = await _openPicker(tester, source: source);
    final previous = MaterialLocalizations.of(tester.element(_key('dialog')))
        .previousMonthTooltip;
    await tester.tap(find.byTooltip(previous));
    await tester.pumpAndSettle();
    expect(source.probes[selected], 1);
    await tester.tap(find.byKey(ValueKey<DateTime>(selected)).last);
    await tester.pumpAndSettle();
    expect(source.probes[selected], 2);
    expect(result.date, selected);
    expect(result.completions, 1);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('initial day and range follow the time tip / $brightness',
        (tester) async {
      await _openPicker(tester, brightness: brightness);
      final picker = tester
          .widget<ChatDateImageCalendar>(find.byType(ChatDateImageCalendar));
      expect(picker.initialDate, DateTime(2026, 10, 5));
      expect(picker.firstDate, DateTime(2000));
      expect(picker.lastDate, DateTime(2026, 10, 15));
      expect(picker.currentDate, DateTime(2026, 10, 15));
      final context = tester.element(_key('dialog'));
      final theme = Theme.of(context);
      expect(theme.brightness, brightness);
      expect(tester.widget<Dialog>(_key('dialog')).backgroundColor,
          theme.colorScheme.surface);
      expect(tester.takeException(), isNull);
    });

    testWidgets('future tip dates clamp to today / $brightness',
        (tester) async {
      await _openPicker(tester,
          initialDate: DateTime(2030, 1, 1), brightness: brightness);
      final picker = tester
          .widget<ChatDateImageCalendar>(find.byType(ChatDateImageCalendar));
      expect(picker.initialDate, DateTime(2026, 10, 15));
      expect(picker.lastDate, DateTime(2026, 10, 15));
      expect(tester.takeException(), isNull);
    });

    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      testWidgets(
          'small screen and large text remain usable / $size / $brightness',
          (tester) async {
        final result = await _openPicker(tester,
            brightness: brightness, size: size, textScale: 2);
        final cancel = tester.getRect(_key('cancel'));
        expect(cancel.left, greaterThanOrEqualTo(0));
        expect(cancel.right, lessThanOrEqualTo(size.width));
        expect(cancel.top, greaterThanOrEqualTo(24));
        expect(cancel.bottom, lessThanOrEqualTo(size.height - 24));
        expect(_key('cancel').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);

        final day = find.byKey(ValueKey<DateTime>(DateTime(2026, 10, 8))).last;
        await Scrollable.ensureVisible(tester.element(day), alignment: .5);
        await tester.pumpAndSettle();
        expect(day.hitTestable(), findsOneWidget);
        await tester.tap(day);
        await tester.pumpAndSettle();
        expect(result.date, DateTime(2026, 10, 8));
        expect(result.completions, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a tip predating 2000 remains selectable', (tester) async {
    await _openPicker(tester, initialDate: DateTime(1997, 4, 7, 7, 16));
    final picker = tester
        .widget<ChatDateImageCalendar>(find.byType(ChatDateImageCalendar));
    expect(picker.initialDate, DateTime(1997, 4, 7));
    expect(picker.firstDate, DateTime(1997, 4, 7));
    expect(picker.lastDate, DateTime(2026, 10, 15));
    expect(tester.takeException(), isNull);
  });
}
