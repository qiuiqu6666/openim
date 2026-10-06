import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history/date_jump/widgets/chat_date_picker_dialog.dart';
import 'package:openim/pages/chat/history/date_jump/widgets/chat_date_image_calendar.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim_common/openim_common.dart';

const dateJumpConversation = 'date-jump-current-conversation';
final dateJumpToday = DateTime(2026, 10, 15);
final dateJumpPresent = DateTime(2026, 10, 8);
final dateJumpEmpty = DateTime(2026, 10, 9);
final dateJumpPast = DateTime(2026, 9, 10);
final dateJumpFirst = DateTime(2026, 10);

Message dateJumpMessage(DateTime day) => Message.fromJson({
      'clientMsgID': 'date-jump-${day.toIso8601String()}',
      'contentType': MessageType.text,
      'sendID': 'member',
      'sendTime':
          DateTime(day.year, day.month, day.day, 12).millisecondsSinceEpoch,
      'textElem': {'content': '该日聊天记录'},
    });

class DateJumpSource implements ChatHistorySearchSource {
  DateJumpSource({Set<DateTime>? days, this.respond}) : days = days ?? {};
  final Set<DateTime> days;
  final Future<List<Message>> Function(DateTime)? respond;
  final calls = <DateTime>[];
  final imageCalls = <DateTime>[];

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    expect(conversationID, dateJumpConversation);
    expect(query.keyword, isEmpty);
    final day = query.localStart!;
    if (query.messageTypes.length == 1 &&
        query.messageTypes.single == MessageType.picture) {
      expect(count, 20);
      imageCalls.add(day);
      return [];
    }
    expect(count, 1);
    if (pageIndex != 1) return [];
    calls.add(day);
    if (respond != null) return respond!(day);
    return days.contains(day) ? [dateJumpMessage(day)] : [];
  }
}

Finder dateJumpKey(String name) =>
    find.byKey(ValueKey('chat-date-picker-$name'));

// The actual cell is deepest if a calendar container also owns this date key.
Finder dateJumpDay(DateTime day) => find.byKey(ValueKey<DateTime>(day)).last;

bool dateJumpEnabled(WidgetTester tester, DateTime day) =>
    tester.getSemantics(dateJumpDay(day)).flagsCollection.isEnabled ==
    Tristate.isTrue;

Future<void> dateJumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> dateJumpMonth(WidgetTester tester,
    {required bool previous}) async {
  final context = tester.element(find.byType(ChatDateImageCalendar));
  final localizations = MaterialLocalizations.of(context);
  final arrow = find.byTooltip(previous
      ? localizations.previousMonthTooltip
      : localizations.nextMonthTooltip);
  await tester.ensureVisible(arrow);
  await tester.tap(arrow);
  await dateJumpFrames(tester);
}

class DateJumpFixture {
  DateJumpFixture(this.source, {DateTime? initialDate})
      : initialDate = initialDate ?? DateTime(2026, 10, 5, 7, 16);
  final DateJumpSource source;
  final DateTime initialDate;
  final navigator = GlobalKey<NavigatorState>();
  final boundary = GlobalKey();
  bool current = true;
  DateTime? returned;
  int completions = 0;

  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Size size = const Size(390, 844),
    double textScale = 1,
    String? fontFamily,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    Styles.isDark = brightness == Brightness.dark;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.reset();
      Styles.isDark = false;
    });
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      fontSizeResolver: (size, _) => size.toDouble(),
      builder: (_, __) => GetMaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          brightness: brightness,
          fontFamily: fontFamily,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.purple, brightness: brightness),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(key: boundary, child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                returned = await showChatDatePicker(
                  context: context,
                  conversationID: dateJumpConversation,
                  initialDate: initialDate,
                  now: dateJumpToday,
                  source: source,
                  isCurrent: () => current,
                );
                completions++;
              },
              child: const Text('打开日期跳转'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开日期跳转'));
    await dateJumpFrames(tester);
    if (settle) await tester.pumpAndSettle();
  }
}
