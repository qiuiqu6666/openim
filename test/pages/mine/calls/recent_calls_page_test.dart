import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/secondary/recent_calls_page.dart';
import 'package:openim/pages/mine/secondary/calls/recent_call_tile.dart';
import 'package:openim_common/openim_common.dart';

import 'recent_call_test_support.dart';

Widget _host(Widget page, {bool dark = false, double scale = 1}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    );

List<CallRecords> _records() => [
      callFixture(room: 'connected', nickname: '阿明', duration: 73),
      callFixture(
          room: 'missed',
          nickname: '小林',
          type: 'video',
          incoming: true,
          success: false,
          state: 'timeout',
          duration: 0),
      callFixture(
          room: 'declined',
          nickname: '小秋',
          incoming: true,
          success: false,
          state: 'reject',
          duration: 0),
    ];

Finder _key(String name) => find.byKey(ValueKey(name));

void main() {
  testWidgets('canonical server status labels keep incoming and outgoing roles', (tester) async {
    final labels = <String>[];
    await tester.pumpWidget(_host(Builder(builder: (context) {
      labels.addAll([
        recentCallResult(context, callFixture(incoming: true, success: false, state: 'rejected')),
        recentCallResult(context, callFixture(incoming: false, success: false, state: 'rejected')),
        recentCallResult(context, callFixture(incoming: true, success: false, state: 'cancelled')),
        recentCallResult(context, callFixture(incoming: false, success: false, state: 'cancelled')),
      ]);
      return const SizedBox();
    })));
    expect(labels.take(4), ['已拒接', '对方已拒接', '对方已取消', '已取消']);
  });

  testWidgets(
      'All and Missed render real records and update after another call',
      (tester) async {
    final box = RecentCallMemoryBox()..backingMap['account-a'] = _records();
    final cache = CacheController(
        accountIDProvider: () => 'account-a', boxOpener: () async => box);
    await tester.pumpWidget(_host(RecentCallsPage(cacheController: cache)));
    await tester.pumpAndSettle();
    expect(find.text('阿明'), findsOneWidget);
    expect(find.text('拨出 · 已接通 · 01:13'), findsOneWidget);
    expect(find.text('小林'), findsOneWidget);
    expect(find.text('呼入 · 未接'), findsOneWidget);
    expect(find.text('小秋'), findsOneWidget);
    await tester.tap(_key('recent-calls-tab-missed'));
    await tester.pumpAndSettle();
    expect(find.text('小林'), findsOneWidget);
    expect(find.text('阿明'), findsNothing);
    expect(find.text('小秋'), findsNothing);
    await cache.recordCall(
        callFixture(
            room: 'new-missed',
            nickname: '刚刚未接来电',
            incoming: true,
            success: false,
            state: 'beCanceled'),
        accountID: 'account-a');
    await tester.pumpAndSettle();
    expect(find.text('刚刚未接来电'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('redial asks media type and calls existing callback once',
      (tester) async {
    final box = RecentCallMemoryBox()
      ..backingMap['account-a'] = [callFixture(peer: 'real-peer')];
    final cache = CacheController(
        accountIDProvider: () => 'account-a', boxOpener: () async => box);
    final started = <(String, bool)>[];
    await tester.pumpWidget(_host(RecentCallsPage(
      cacheController: cache,
      onStartCall: (peer, video) => started.add((peer, video)),
    )));
    await tester.pumpAndSettle();
    await tester.tap(_key('recent-call-room:room-1'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('视频通话'));
    await tester.pumpAndSettle();
    expect(started, [('real-peer', true)]);
    await tester.tap(_key('recent-call-room:room-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(started, hasLength(1));
  });

  testWidgets('account change while choosing redial discards stale callback',
      (tester) async {
    var account = 'account-a';
    final box = RecentCallMemoryBox()
      ..backingMap['account-a'] = [callFixture()]
      ..backingMap['account-b'] = [callFixture(room: 'b', nickname: '乙')];
    final cache = CacheController(
        accountIDProvider: () => account, boxOpener: () async => box);
    var started = 0;
    await tester.pumpWidget(_host(RecentCallsPage(
      cacheController: cache,
      onStartCall: (_, __) => started++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(_key('recent-call-room:room-1'));
    await tester.pumpAndSettle();
    account = 'account-b';
    await cache.initCallRecords();
    await tester.tap(find.text('语音通话'));
    await tester.pumpAndSettle();
    expect(started, 0);
    expect(find.text('阿明'), findsNothing);
    expect(
        find.descendant(
            of: _key('recent-call-room:b'),
            matching: find.byWidgetPredicate((widget) =>
                widget is Text && widget.data == '乙' && widget.maxLines == 1)),
        findsOneWidget);
  });

  testWidgets('editing deletes only confirmed record and can cancel',
      (tester) async {
    final box = RecentCallMemoryBox()..backingMap['account-a'] = _records();
    final cache = CacheController(
        accountIDProvider: () => 'account-a', boxOpener: () async => box);
    await tester.pumpWidget(_host(RecentCallsPage(cacheController: cache)));
    await tester.pumpAndSettle();
    await tester.tap(_key('recent-calls-edit'));
    await tester.pumpAndSettle();
    await tester.tap(_key('recent-call-delete-room:missed'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '取消'));
    await tester.pumpAndSettle();
    expect(cache.callRecordList, hasLength(3));
    await tester.tap(_key('recent-call-delete-room:missed'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '隐藏'));
    await tester.pumpAndSettle();
    expect(cache.callRecordList.map((item) => item.roomID),
        ['connected', 'declined']);
    expect(find.text('小林'), findsNothing);
    expect(find.text('阿明'), findsOneWidget);
  });

  testWidgets('bulk delete captures only selected filter before confirmation',
      (tester) async {
    final box = RecentCallMemoryBox()..backingMap['account-a'] = _records();
    final cache = CacheController(
        accountIDProvider: () => 'account-a', boxOpener: () async => box);
    await tester.pumpWidget(_host(RecentCallsPage(cacheController: cache)));
    await tester.pumpAndSettle();
    await tester.tap(_key('recent-calls-tab-missed'));
    await tester.pumpAndSettle();
    await tester.tap(_key('recent-calls-edit'));
    await tester.pumpAndSettle();
    await tester.tap(_key('recent-calls-delete-visible'));
    await tester.pumpAndSettle();
    await cache.recordCall(
        callFixture(
            room: 'new',
            nickname: '新来电',
            incoming: true,
            success: false,
            state: 'timeout'),
        accountID: 'account-a');
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '隐藏'));
    await tester.pumpAndSettle();
    expect(cache.callRecordList.map((item) => item.roomID),
        containsAll(['connected', 'declined', 'new']));
    expect(
        cache.callRecordList.any((item) => item.roomID == 'missed'), isFalse);
    expect(find.text('新来电'), findsOneWidget);
  });

  testWidgets('time uses local timezone, including old Unix seconds',
      (tester) async {
    final epoch = DateTime.utc(2026, 10, 5, 4, 7).millisecondsSinceEpoch;
    final local = DateTime.fromMillisecondsSinceEpoch(epoch);
    final expected = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    String? current;
    String? legacy;
    await tester.pumpWidget(_host(Builder(builder: (context) {
      current = recentCallTime(context, callFixture(date: epoch), now: local);
      legacy =
          recentCallTime(context, callFixture(date: epoch ~/ 1000), now: local);
      return const SizedBox();
    })));
    expect(current, expected);
    expect(legacy, expected);
  });

  for (final dark in [false, true]) {
    testWidgets('real rows fit narrow 320px / 2x text / safe area / dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      final box = RecentCallMemoryBox()..backingMap['account-a'] = _records();
      final cache = CacheController(
          accountIDProvider: () => 'account-a', boxOpener: () async => box);
      await tester.pumpWidget(
          _host(RecentCallsPage(cacheController: cache), dark: dark, scale: 2));
      await tester.pumpAndSettle();
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, AppTokens.background(dark: dark));
      expect(tester.takeException(), isNull);
      await tester.tap(_key('recent-calls-edit'));
      await tester.pumpAndSettle();
      final delete = _key('recent-call-delete-room:connected');
      expect(tester.getSize(delete), const Size(48, 48));
      expect(delete.hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(
          _key('recent-call-delete-room:declined'), 150,
          scrollable: find.descendant(
              of: _key('recent-calls-list'),
              matching: find.byType(Scrollable)));
      await tester.pumpAndSettle();
      expect(_key('recent-call-delete-room:declined').hitTestable(),
          findsOneWidget);
      final bottom =
          tester.getRect(_key('recent-call-delete-room:declined')).bottom;
      expect(bottom, lessThanOrEqualTo(616));
      expect(tester.takeException(), isNull);
    });
  }
}
