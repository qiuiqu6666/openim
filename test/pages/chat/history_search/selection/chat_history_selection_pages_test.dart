import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_date_page.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_page.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';

typedef _Load = Future<ChatHistorySenderPageData> Function(String, int);

class _Source implements ChatHistorySenderSource {
  _Source(this.loader);
  final _Load loader;
  @override
  String currentUserID = 'me';
  @override
  Future<ChatHistorySenderPageData> load(
      {required String conversationID,
      required String query,
      required int offset,
      required int count}) {
    expect(conversationID, 'current-chat');
    expect(count, 50);
    return loader(query, offset);
  }
}

class _DateSource implements ChatHistorySearchSource {
  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    expect(conversationID, 'current-chat');
    expect(count, 1);
    final today = DateTime.now();
    final message = Message.fromJson({
      'clientMsgID': 'first-day-record',
      'contentType': MessageType.text,
      'sendTime':
          DateTime(today.year, today.month, 1, 12).millisecondsSinceEpoch,
      'textElem': {'content': '本月第一天的聊天记录'},
    });
    return pageIndex == 1 && query.accepts(message) ? [message] : [];
  }
}

ChatHistoryDatePage _datePage() => ChatHistoryDatePage(
      conversationID: 'current-chat',
      source: _DateSource(),
      isCurrent: () => true,
    );

ChatHistorySender _person(String id, String name) =>
    ChatHistorySender(userID: id, displayName: name);
ChatHistorySenderPageData _page(List<ChatHistorySender> items,
        {int? nextOffset, bool hasMore = false}) =>
    ChatHistorySenderPageData(
        items: items, nextOffset: nextOffset ?? items.length, hasMore: hasMore);

void main() {
  setUp(() {
    Get.testMode = true;
    Get.locale = const Locale('zh', 'CN');
  });
  tearDown(Get.reset);

  Future<void> open<T>(WidgetTester tester, Widget page,
      {Brightness brightness = Brightness.light,
      ValueChanged<T?>? selected}) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        navigatorKey: nav,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(brightness: brightness),
        home: const Scaffold(),
      ),
    ));
    nav.currentState!
        .push<T>(MaterialPageRoute(builder: (_) => page))
        .then((value) => selected?.call(value));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'date requires explicit selection and returns a single day ($brightness)',
        (tester) async {
      DateTime? date;
      await open<DateTime>(tester, _datePage(),
          brightness: brightness, selected: (value) => date = value);
      await tester.pumpAndSettle();
      expect(date, isNull);
      final confirm = find.byKey(const ValueKey('chat-history-date-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      final calendar =
          tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
      expect(calendar.firstDate, DateTime(2000));
      expect(calendar.lastDate, DateUtils.dateOnly(DateTime.now()));
      final firstDay = DateTime(DateTime.now().year, DateTime.now().month, 1);
      await tester.tap(find.byKey(ValueKey<DateTime>(firstDay)).last);
      await tester.pumpAndSettle();
      expect(date, isNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(date, firstDay);
    });

    testWidgets(
        'sender selection returns actual member and supports retry ($brightness)',
        (tester) async {
      var attempts = 0;
      ChatHistorySender? sender;
      final source = _Source((_, __) async {
        if (++attempts == 1) throw StateError('offline');
        return _page([_person('member', '小林')]);
      });
      await open<ChatHistorySender>(tester,
          ChatHistorySenderPage(conversationID: 'current-chat', source: source),
          brightness: brightness, selected: (value) => sender = value);
      await tester.tap(find.byKey(const ValueKey('chat-history-sender-retry')));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      await tester
          .tap(find.byKey(const ValueKey('chat-history-sender-member')));
      await tester.pumpAndSettle();
      expect(sender?.userID, 'member');
      expect(sender?.displayName, '小林');
    });
  }

  testWidgets(
      'new search isolates stale results and dispose ignores pending result',
      (tester) async {
    final initial = Completer<ChatHistorySenderPageData>();
    final searched = Completer<ChatHistorySenderPageData>();
    final afterDispose = Completer<ChatHistorySenderPageData>();
    final queries = <String>[];
    final source = _Source((query, offset) {
      queries.add(query);
      expect(offset, 0);
      return query.isEmpty
          ? initial.future
          : query == '新'
              ? searched.future
              : afterDispose.future;
    });
    await open(tester,
        ChatHistorySenderPage(conversationID: 'current-chat', source: source));
    await tester.enterText(find.byType(TextField), '新');
    await tester.pump(const Duration(milliseconds: 310));
    initial.complete(_page([_person('old', '旧成员')]));
    await tester.pump();
    expect(find.text('旧成员'), findsNothing);
    searched.complete(_page([_person('new', '新成员')]));
    await tester.pumpAndSettle();
    expect(find.text('新成员'), findsOneWidget);
    expect(queries, ['', '新']);
    await tester.enterText(find.byType(TextField), '离开');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    afterDispose.complete(_page([_person('late', '迟到成员')]));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pagination consumes source cursor and deduplicates sender rows',
      (tester) async {
    final offsets = <int>[];
    final source = _Source((query, offset) async {
      offsets.add(offset);
      return offset == 0
          ? _page([_person('a', '第一位')], nextOffset: 50, hasMore: true)
          : _page([_person('a', '重复'), _person('b', '第二位')], nextOffset: 52);
    });
    await open(tester,
        ChatHistorySenderPage(conversationID: 'current-chat', source: source));
    await tester.tap(find.byKey(const ValueKey('chat-history-sender-more')));
    await tester.pumpAndSettle();
    expect(offsets, [0, 50]);
    expect(find.text('第一位'), findsOneWidget);
    expect(find.text('第二位'), findsOneWidget);
    expect(find.text('重复'), findsNothing);
    expect(
        find.byKey(const ValueKey('chat-history-sender-more')), findsNothing);
  });

  testWidgets('account change discards old rows and prevents selecting them',
      (tester) async {
    final pending = Completer<ChatHistorySenderPageData>();
    final source = _Source((_, __) => pending.future);
    await open(tester,
        ChatHistorySenderPage(conversationID: 'current-chat', source: source));
    source.currentUserID = 'another-account';
    pending.complete(_page([_person('old', '旧账户成员')]));
    await tester.pumpAndSettle();
    expect(find.text('旧账户成员'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });

  testWidgets('cancelled calendar never confirms the highlighted initial month',
      (tester) async {
    DateTime? selected;
    await open<DateTime>(tester, _datePage(),
        selected: (value) => selected = value);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });
}
