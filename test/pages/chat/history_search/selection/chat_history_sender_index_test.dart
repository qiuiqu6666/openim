import 'dart:async';

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_date_page.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_page.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';
import 'package:openim_common/openim_common.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

typedef _Loader = Future<ChatHistorySenderPageData> Function(String, int);

class _Source implements ChatHistorySenderSource {
  _Source(this.loader);
  final _Loader loader;
  @override
  String get currentUserID => 'me';
  @override
  Future<ChatHistorySenderPageData> load({
    required String conversationID,
    required String query,
    required int offset,
    required int count,
  }) {
    expect(conversationID, 'current-chat');
    expect(count, 50);
    return loader(query, offset);
  }
}

ChatHistorySender _sender(String id, String name) =>
    ChatHistorySender(userID: id, displayName: name);
ChatHistorySenderPageData _page(List<ChatHistorySender> items,
        {int? nextOffset, bool hasMore = false}) =>
    ChatHistorySenderPageData(
      items: items,
      nextOffset: nextOffset ?? items.length,
      hasMore: hasMore,
    );

Finder _row(String id) => find.byKey(ValueKey('chat-history-sender-$id'));
ScrollablePositionedList _directory(WidgetTester tester) => tester
    .widget<ScrollablePositionedList>(find.byType(ScrollablePositionedList));
Finder _scrollable() => find
    .descendant(
        of: find.byType(ScrollablePositionedList),
        matching: find.byType(Scrollable))
    .first;

Future<void> _open<T>(
  WidgetTester tester,
  Widget page, {
  Brightness brightness = Brightness.light,
  Size size = const Size(375, 812),
  double scale = 1,
  ValueChanged<T?>? selected,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final originalDark = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() => Styles.isDark = originalDark);
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      navigatorKey: nav,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const Scaffold(body: Text('parent')),
    ),
  ));
  nav.currentState!
      .push<T>(MaterialPageRoute(builder: (_) => page))
      .then((value) => selected?.call(value));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.locale = const Locale('zh', 'CN');
  });
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets(
        'sender list keeps SDK order without alphabet sections ($brightness)',
        (tester) async {
      final source = _Source((_, __) async => _page([
            _sender('other', '🍀'),
            _sender('qian', '钱七'),
            _sender('ding', '丁一'),
            _sender('david', 'David'),
          ]));
      await _open(tester,
          ChatHistorySenderPage(conversationID: 'current-chat', source: source),
          brightness: brightness);
      expect(_directory(tester).itemCount, 4);
      expect(find.byType(AzListView), findsNothing);
      expect(find.byType(IndexBar), findsNothing);
      expect(tester.getTopLeft(_row('other')).dy,
          lessThan(tester.getTopLeft(_row('qian')).dy));
      expect(tester.getTopLeft(_row('qian')).dy,
          lessThan(tester.getTopLeft(_row('ding')).dy));
      expect(tester.getTopLeft(_row('ding')).dy,
          lessThan(tester.getTopLeft(_row('david')).dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sender title and back match existing navigation ($brightness)',
        (tester) async {
      final source = _Source((_, __) async => _page([]));
      await _open(tester,
          ChatHistorySenderPage(conversationID: 'current-chat', source: source),
          brightness: brightness);
      final title = tester.widget<Text>(find.text('选择发送人'));
      expect(title.style?.fontSize, Styles.ts_0C1C33_17sp_semibold.fontSize);
      expect(title.style?.fontWeight, FontWeight.w600);
      expect(title.style?.color, Styles.ts_0C1C33_17sp_semibold.color);
      final back =
          tester.widget<Icon>(find.byIcon(Icons.arrow_back_ios_new_rounded));
      expect(back.color, Styles.c_0089FF);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('parent'), findsOneWidget);
      expect(find.byType(ChatHistorySenderPage), findsNothing);
    });
  }

  testWidgets('long sender lists remain reachable by scrolling without letters',
      (tester) async {
    final source = _Source((_, __) async => _page([
          for (var i = 0; i < 20; i++)
            _sender('d$i', '丁${i.toString().padLeft(2, '0')}'),
          for (var i = 0; i < 20; i++)
            _sender('q$i', '钱${i.toString().padLeft(2, '0')}'),
          _sender('other', '🍀'),
        ]));
    await _open(tester,
        ChatHistorySenderPage(conversationID: 'current-chat', source: source));
    expect(_row('d0').hitTestable(), findsOneWidget);
    expect(_row('other').hitTestable(), findsNothing);
    await tester.scrollUntilVisible(_row('other'), 400,
        scrollable: _scrollable());
    await tester.pumpAndSettle();
    expect(_row('other').hitTestable(), findsOneWidget);
    expect(_row('d0').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search resets the sender list and removes stale rows',
      (tester) async {
    final searched = Completer<ChatHistorySenderPageData>();
    final source = _Source((query, offset) async {
      expect(offset, 0);
      if (query == '钱') return searched.future;
      if (query == 'none') return _page([]);
      return _page(
          [_sender('d', '丁一'), _sender('q', '钱七'), _sender('other', '🍀')]);
    });
    await _open(tester,
        ChatHistorySenderPage(conversationID: 'current-chat', source: source));
    expect(_directory(tester).itemCount, 3);
    await tester.enterText(find.byType(TextField), '钱');
    await tester.pump(const Duration(milliseconds: 310));
    expect(_row('d'), findsNothing);
    searched.complete(_page([_sender('q2', '钱小明')]));
    await tester.pumpAndSettle();
    expect(_directory(tester).itemCount, 1);
    expect(_row('d'), findsNothing);
    expect(_row('other'), findsNothing);
    expect(_row('q2'), findsOneWidget);
    expect(_row('q'), findsNothing);
    await tester.enterText(find.byType(TextField), 'none');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();
    expect(find.byType(IndexBar), findsNothing);
    expect(find.byType(ScrollablePositionedList), findsNothing);
  });

  testWidgets(
      'background pages append without reordering or recreating the viewport',
      (tester) async {
    final offsets = <int>[];
    final middle = Completer<ChatHistorySenderPageData>();
    final last = Completer<ChatHistorySenderPageData>();
    final source = _Source((query, offset) async {
      offsets.add(offset);
      if (offset == 0) {
        return _page([_sender('d', '丁一')], nextOffset: 50, hasMore: true);
      }
      return offset == 50 ? middle.future : last.future;
    });
    ChatHistorySender? selected;
    await _open<ChatHistorySender>(tester,
        ChatHistorySenderPage(conversationID: 'current-chat', source: source),
        selected: (value) => selected = value);
    expect(_directory(tester).itemCount, 1);
    final initialState = tester.state(find.byType(ScrollablePositionedList));
    final initialTop = tester.getTopLeft(_row('d')).dy;
    await tester.pump(const Duration(milliseconds: 400));
    middle.complete(_page([_sender('a', 'Alice'), _sender('q', '钱七')],
        nextOffset: 100, hasMore: true));
    await tester.pumpAndSettle();
    expect(offsets, [0, 50]);
    expect(_directory(tester).itemCount, 3);
    expect(tester.getTopLeft(_row('d')).dy,
        lessThan(tester.getTopLeft(_row('a')).dy));
    expect(tester.getTopLeft(_row('d')).dy, initialTop);
    await tester.pump(const Duration(milliseconds: 400));
    last.complete(_page([_sender('d-before', 'David'), _sender('other', '🍀')],
        nextOffset: 102));
    // Deliver the async source result before rendering its first changed frame.
    await tester.idle();
    await tester.pump();
    expect(offsets, [0, 50, 100]);
    expect(_directory(tester).itemCount, 5);
    expect(tester.state(find.byType(ScrollablePositionedList)),
        same(initialState));
    expect(tester.getTopLeft(_row('d')).dy, closeTo(initialTop, 1));
    await tester.pumpAndSettle();
    await tester.tap(_row('q'));
    await tester.pumpAndSettle();
    expect(selected?.userID, 'q');
    expect(selected?.displayName, '钱七');
  });

  testWidgets(
      'small screen and large text keep the full-width member list usable',
      (tester) async {
    final source = _Source((_, __) async => _page([
          for (var code = 65; code <= 90; code++)
            _sender('$code',
                '${String.fromCharCode(code)} long sender display name with extra words'),
          _sender('other', '🍀'),
        ]));
    await _open(tester,
        ChatHistorySenderPage(conversationID: 'current-chat', source: source),
        size: const Size(320, 568), scale: 2);
    expect(_directory(tester).itemCount, 27);
    expect(tester.takeException(), isNull);
    expect(find.byType(IndexBar), findsNothing);
    final list = tester.getRect(find.byType(ScrollablePositionedList));
    expect(list.left, greaterThanOrEqualTo(0));
    expect(list.right, lessThanOrEqualTo(320));
    expect(list.bottom, lessThanOrEqualTo(568));
    await tester.scrollUntilVisible(_row('90'), 250, scrollable: _scrollable());
    await tester.pumpAndSettle();
    expect(_row('90').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date selector uses matching title and back navigation',
      (tester) async {
    await _open(
        tester,
        ChatHistoryDatePage(
            conversationID: 'current-chat', isCurrent: () => false));
    final title = tester.widget<Text>(find.text('选择日期'));
    expect(title.style?.fontSize, Styles.ts_0C1C33_17sp_semibold.fontSize);
    expect(title.style?.fontWeight, FontWeight.w600);
    final back =
        tester.widget<Icon>(find.byIcon(Icons.arrow_back_ios_new_rounded));
    expect(back.color, Styles.c_0089FF);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('parent'), findsOneWidget);
  });
}
