import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';
import 'package:openim/pages/group_features/sangong/services/realtime/sangong_realtime_scope.dart';
import 'package:openim/routes/swipe_back/app_page_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../sangong_test_support.dart';

class _Fixture {
  final api = SangongTestApi();
  final events = StreamController<Map<String, dynamic>>.broadcast();
  final navigator = GlobalKey<NavigatorState>();
  SangongRuntime? runtime;

  int get reads => api.count('/snapshot');

  Future<void> mount(WidgetTester tester) async {
    api.respond = (call) {
      if (call.path.endsWith('/config')) {
        return {
          'ok': true,
          'data': {...sangongConfig(), 'active': true}
        };
      }
      return sangongFixtureResponse(call);
    };
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: SangongFeatureHost(
            featureContext: sangongTestContext(api,
                canOpenAgent: false, events: events.stream),
            builder: (context, banner, overlay) {
              runtime = SangongScope.read(context);
              return const Text('chat host');
            },
          ),
        ),
      ),
    ));
    await flushSangong(tester);
    expect(runtime!.canManage, isTrue);
    expect(runtime!.realtime.ownerCount, 1);
    expect(reads, 1);
    addTearDown(() async {
      await unmountSangong(tester);
      await events.close();
      api.privilege.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  }

  Future<void> cover(WidgetTester tester, {Widget? child}) async {
    unawaited(navigator.currentState!.push(AppMaterialPageRoute<void>(
        builder: (_) => Scaffold(body: child ?? const Text('covered page')))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await flushSangong(tester);
    expect(find.text('chat host'), findsNothing);
  }

  Future<void> uncover(WidgetTester tester) async {
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await flushSangong(tester);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenIM.iMManager.userID = 'owner';
  });

  testWidgets('opaque page pauses real host for a minute, return reads once',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.cover(tester);
    expect(fixture.runtime!.realtime.ownerCount, 0);
    final before = fixture.reads;
    fixture.events.add({'key': 'imReconnected', 'groupID': 'group-sangong'});
    fixture.events.add({'key': 'groupGameChanged', 'groupID': 'group-sangong'});
    await tester.pump(const Duration(seconds: 60));
    await flushSangong(tester);
    expect(fixture.reads, before);

    await fixture.uncover(tester);
    expect(fixture.runtime!.realtime.ownerCount, 1);
    expect(fixture.reads, before + 1);
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.reads, before + 1);
    await tester.pump(const Duration(seconds: 3));
    await flushSangong(tester);
    expect(fixture.reads, before + 2);
  });

  testWidgets('transparent business dialog retains calibration and reconnect',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    unawaited(showDialog<void>(
        context: fixture.navigator.currentContext!,
        builder: (_) => const AlertDialog(content: Text('business dialog'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(fixture.runtime!.realtime.ownerCount, 1);
    final before = fixture.reads;
    fixture.events.add({'key': 'imReconnected', 'groupID': 'group-sangong'});
    await flushSangong(tester);
    expect(fixture.reads, before + 1);
    await tester.pump(const Duration(seconds: 3));
    await flushSangong(tester);
    expect(fixture.reads, before + 2);
    await fixture.uncover(tester);
    expect(fixture.runtime!.realtime.ownerCount, 1);
  });

  testWidgets('visible business owner shares the host runtime and timer',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.cover(tester,
        child: SangongRealtimeScope(
            runtime: fixture.runtime!, child: const Text('business surface')));
    expect(fixture.runtime!.realtime.ownerCount, 1);
    final before = fixture.reads;
    await tester.pump(const Duration(seconds: 3));
    await flushSangong(tester);
    expect(fixture.reads, before + 1);

    await fixture.cover(tester);
    expect(fixture.runtime!.realtime.ownerCount, 0);
    final stopped = fixture.reads;
    await tester.pump(const Duration(seconds: 60));
    expect(fixture.reads, stopped);
    await fixture.uncover(tester);
    expect(fixture.runtime!.realtime.ownerCount, 1);
    expect(fixture.reads, stopped + 1);
    await fixture.uncover(tester);
    expect(fixture.runtime!.realtime.ownerCount, 1);
    final returned = fixture.reads;
    await tester.pump(const Duration(seconds: 3));
    await flushSangong(tester);
    expect(fixture.reads, returned + 1);
  });

  testWidgets('app resume cannot reactivate an opaque-covered owner',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.cover(tester);
    final before = fixture.reads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 60));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 60));
    expect(fixture.reads, before);
    await fixture.uncover(tester);
    expect(fixture.reads, before + 1);
  });

  testWidgets('revoked permission stays stopped after returning to host',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.cover(tester);
    fixture.api.privilege.setAllowed(false);
    await flushSangong(tester);
    final before = fixture.reads;
    await fixture.uncover(tester);
    await tester.pump(const Duration(seconds: 60));
    expect(fixture.runtime!.realtime.ownerCount, 0);
    expect(fixture.reads, before);
  });

  testWidgets('disposing a covered host cancels every realtime owner',
      (tester) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.cover(tester);
    await unmountSangong(tester);
    expect(fixture.runtime!.realtime.ownerCount, 0);
    final stopped = fixture.reads;
    fixture.events.add({'key': 'imReconnected', 'groupID': 'group-sangong'});
    await tester.pump(const Duration(seconds: 60));
    expect(fixture.reads, stopped);
    expect(fixture.events.hasListener, isFalse);
  });
}
