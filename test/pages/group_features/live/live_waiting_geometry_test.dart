import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/live/widgets/live_watch_surface.dart';
import 'package:openim_common/openim_common.dart';

import 'live_test_support.dart';

const _waiting = '直播准备中，请稍候…';

Future<void> _loadingFrames(WidgetTester tester) async {
  // Dio dispatches through the real event queue even though the transport is a
  // fake. Pumping frames alone does not deterministically flush that queue.
  for (var frame = 0; frame < 4; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _mountWaiting(
  WidgetTester tester,
  LiveTransport transport, {
  required bool dark,
  required double textScale,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = dark;
  addTearDown(() => Styles.isDark = false);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Column(
          children: [
            GroupLiveWatchSurface(
              featureContext: liveContext(transport.api()),
              session: liveSession(),
              onClose: () {},
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ),
  ));
  await _loadingFrames(tester);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

void _expectSameRect(Rect actual, Rect expected, String reason) {
  expect(actual.left, closeTo(expected.left, .01), reason: reason);
  expect(actual.top, closeTo(expected.top, .01), reason: reason);
  expect(actual.width, closeTo(expected.width, .01), reason: reason);
  expect(actual.height, closeTo(expected.height, .01), reason: reason);
}

void main() {
  for (final dark in [false, true]) {
    for (final textScale in [1.0, 2.0]) {
      final theme = '${dark ? 'dark' : 'light'}, text scale $textScale';
      testWidgets(
        'waiting text and surface stay fixed when initial detail completes ($theme)',
        (tester) async {
          final detail = Completer<Map<String, dynamic>>();
          final transport = LiveTransport((_) => detail.future);
          await _mountWaiting(tester, transport,
              dark: dark, textScale: textScale);
          expect(transport.requests.length, 1);
          expect(transport.requests.single.path, endsWith('/live/live-1'));
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text(_waiting), findsOneWidget);
          final surface = find.byType(GroupLiveWatchSurface);
          final loadingSurface = tester.getRect(surface);
          final loadingText = tester.getRect(find.text(_waiting));
          final loadingTextCenter = tester.getCenter(find.text(_waiting));

          detail.complete(liveDTO());
          await _loadingFrames(tester);
          await tester.pumpAndSettle();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('刷新状态'), findsOneWidget);
          expect(transport.requests.length, 1);
          _expectSameRect(tester.getRect(surface), loadingSurface,
              'Completing public detail must not resize the 16:9 watch surface');
          _expectSameRect(tester.getRect(find.text(_waiting)), loadingText,
              'The same waiting message must not move when loading completes');
          expect(tester.getCenter(find.text(_waiting)), loadingTextCenter);
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets(
        'manual waiting refresh keeps text and surface fixed throughout ($theme)',
        (tester) async {
          final refresh = Completer<Map<String, dynamic>>();
          var reads = 0;
          final transport = LiveTransport((_) {
            reads++;
            return reads == 1 ? liveDTO() : refresh.future;
          });
          await _mountWaiting(tester, transport,
              dark: dark, textScale: textScale);
          await tester.pumpAndSettle();
          final surface = find.byType(GroupLiveWatchSurface);
          final readySurface = tester.getRect(surface);
          final readyText = tester.getRect(find.text(_waiting));
          final readyTextCenter = tester.getCenter(find.text(_waiting));

          await tester.tap(find.text('刷新状态'));
          await _loadingFrames(tester);
          expect(reads, 2);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          final refreshingSurface = tester.getRect(surface);
          final refreshingText = tester.getRect(find.text(_waiting));
          final refreshingTextCenter = tester.getCenter(find.text(_waiting));
          refresh.complete(liveDTO());
          await _loadingFrames(tester);
          await tester.pumpAndSettle();

          _expectSameRect(refreshingSurface, readySurface,
              'Starting a refresh must not resize the watch surface');
          _expectSameRect(tester.getRect(surface), readySurface,
              'Completing a refresh must not resize the watch surface');
          _expectSameRect(refreshingText, readyText,
              'The waiting message must not move while manually refreshing');
          expect(refreshingTextCenter, readyTextCenter);
          _expectSameRect(tester.getRect(find.text(_waiting)), readyText,
              'The waiting message must retain its position after a refresh');
          expect(tester.getCenter(find.text(_waiting)), readyTextCenter);
          expect(reads, 2);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
