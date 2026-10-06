import 'dart:async';

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_date_page.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_directory.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_page.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';
import 'package:openim_common/openim_common.dart';

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
Finder _letter(String letter) =>
    find.descendant(of: find.byType(IndexBar), matching: find.text(letter));
AzListView _directory(WidgetTester tester) =>
    tester.widget<AzListView>(find.byType(AzListView));

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
        'sender index sorts Chinese and Latin names as D/Q/# ($brightness)',
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
      expect(_directory(tester).indexBarData, ['D', 'Q', '#']);
      expect(_directory(tester).data.map((item) => item.getSuspensionTag()),
          ['D', 'D', 'Q', '#']);
      expect(_letter('D'), findsOneWidget);
      expect(_letter('Q'), findsOneWidget);
      expect(_letter('#'), findsOneWidget);
      expect(tester.getTopLeft(_row('david')).dy,
          lessThan(tester.getTopLeft(_row('qian')).dy));
      expect(tester.getTopLeft(_row('ding')).dy,
          lessThan(tester.getTopLeft(_row('qian')).dy));
      expect(tester.getTopLeft(_row('qian')).dy,
          lessThan(tester.getTopLeft(_row('other')).dy));
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

  testWidgets('tapping and dragging letters jumps to real long-list sections',
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
    final rows = _directory(tester).data.cast<ChatHistorySenderRow>();
    final firstD =
        rows.firstWhere((row) => row.getSuspensionTag() == 'D').sender.userID;
    final firstQ =
        rows.firstWhere((row) => row.getSuspensionTag() == 'Q').sender.userID;
    expect(_row(firstD).hitTestable(), findsOneWidget);
    expect(_row(firstQ).hitTestable(), findsNothing);
    await tester.tap(_letter('Q'));
    await tester.pumpAndSettle();
    expect(_row(firstQ).hitTestable(), findsOneWidget);
    expect(_row(firstD).hitTestable(), findsNothing);

    final gesture = await tester.startGesture(tester.getCenter(_letter('Q')));
    await gesture.moveTo(tester.getCenter(_letter('D')));
    // First movement wins the vertical drag arena; continue moving within D
    // to deliver the update, as a finger sliding over the index does.
    await gesture.moveBy(const Offset(0, -1));
    await tester.pumpAndSettle();
    expect(_row(firstD).hitTestable(), findsOneWidget);
    await gesture.moveTo(tester.getCenter(_letter('#')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_row('other').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search resets alphabet and removes stale sections',
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
    expect(_directory(tester).indexBarData, ['D', 'Q', '#']);
    await tester.enterText(find.byType(TextField), '钱');
    await tester.pump(const Duration(milliseconds: 310));
    expect(_letter('D'), findsNothing);
    searched.complete(_page([_sender('q2', '钱小明')]));
    await tester.pumpAndSettle();
    expect(_directory(tester).indexBarData, ['Q']);
    expect(_letter('D'), findsNothing);
    expect(_letter('#'), findsNothing);
    expect(_row('q2'), findsOneWidget);
    expect(_row('q'), findsNothing);
    await tester.enterText(find.byType(TextField), 'none');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();
    expect(find.byType(IndexBar), findsNothing);
    expect(find.byType(AzListView), findsNothing);
  });

  testWidgets(
      'paging updates alphabet while retaining SDK cursor and selected sender',
      (tester) async {
    final offsets = <int>[];
    final source = _Source((query, offset) async {
      offsets.add(offset);
      return offset == 0
          ? _page([_sender('d', '丁一')], nextOffset: 50, hasMore: true)
          : _page([_sender('q', '钱七'), _sender('other', '🍀')], nextOffset: 52);
    });
    ChatHistorySender? selected;
    await _open<ChatHistorySender>(tester,
        ChatHistorySenderPage(conversationID: 'current-chat', source: source),
        selected: (value) => selected = value);
    expect(_directory(tester).indexBarData, ['D']);
    await tester.tap(find.byKey(const ValueKey('chat-history-sender-more')));
    await tester.pumpAndSettle();
    expect(offsets, [0, 50]);
    expect(_directory(tester).indexBarData, ['D', 'Q', '#']);
    await tester.tap(_letter('Q'));
    await tester.pumpAndSettle();
    await tester.tap(_row('q'));
    await tester.pumpAndSettle();
    expect(selected?.userID, 'q');
    expect(selected?.displayName, '钱七');
  });

  testWidgets(
      'small screen and large text keep full alphabet and long names usable',
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
    expect(_directory(tester).indexBarData, hasLength(27));
    expect(tester.takeException(), isNull);
    final bar = tester.getRect(find.byType(IndexBar));
    expect(bar.left, greaterThanOrEqualTo(0));
    expect(bar.right, lessThanOrEqualTo(320));
    expect(bar.bottom, lessThanOrEqualTo(568));
    await tester.tap(_letter('Z'));
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
