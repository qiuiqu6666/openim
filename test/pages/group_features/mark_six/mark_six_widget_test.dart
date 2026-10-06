import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/group_features/mark_six/pages/mark_six_page.dart';
import 'package:openim/pages/group_features/mark_six/mark_six_module.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_feature_host.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_latest_card.dart';
import 'package:openim/pages/group_features/mark_six/agent/pages/agent_current_page.dart';
import 'package:openim/pages/group_features/mark_six/agent/pages/agent_history_page.dart';
import 'mark_six_fixtures.dart';

Future<void> _mount(WidgetTester tester, Widget page,
    {bool dark = false}) async {
  Styles.isDark = dark;
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              colorSchemeSeed: const Color(0xFF0089FF)),
          home: page)));
  await tester.pump();
}

Widget _host(MarkSixFakeApi api,
        {bool enabled = true, bool agent = false, int revision = 1}) =>
    Scaffold(
        body: MarkSixFeatureHost(
            featureContext: markSixContext(api,
                enabled: enabled, agent: agent, revision: revision),
            builder: (context, entry, overlay) => Stack(children: [
                  const Positioned.fill(child: Text('实际聊天内容')),
                  overlay
                ])));

void main() {
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      for (final width in [320.0, 390.0]) {
        testWidgets('actual lottery tabs fit $platform dark=$dark width=$width',
            (tester) async {
          tester.view.physicalSize = Size(width, 812);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final api = MarkSixFakeApi();
          await _mount(tester, MarkSixPage(featureContext: markSixContext(api)),
              dark: dark);
          await tester.pumpAndSettle();
          expect(find.text('开奖历史'), findsOneWidget);
          expect(find.byType(MarkSixNumberBall), findsWidgets);
          expect(api.calls, hasLength(2));
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('智能预测'));
          await tester.pumpAndSettle();
          expect(find.text('逐期预测'), findsOneWidget);
          expect(api.calls.where((c) => c.path.endsWith('/predictions')),
              hasLength(1));
          await tester.tap(find.text('已开统计'));
          await tester.pumpAndSettle();
          expect(api.calls, hasLength(3));
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('本群宣言'));
          await tester.pumpAndSettle();
          expect(find.textContaining('本群信息以实际开奖结果为准'), findsOneWidget);
          expect(api.calls.last.path, '/chat/platform');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }, variant: TargetPlatformVariant({platform}));
      }
    }
  }
  testWidgets(
      'lottery failure has real retry and refreshes successful snapshot',
      (tester) async {
    var fail = true;
    final api = MarkSixFakeApi(respond: (_, path, query, __) {
      if (fail) throw StateError('接口暂未部署');
      return markSixFixtureResponse(path, query);
    });
    await _mount(tester, MarkSixPage(featureContext: markSixContext(api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('接口暂未部署'), findsOneWidget);
    expect(find.byType(MarkSixNumberBall), findsNothing);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkSixNumberBall), findsWidgets);
    expect(api.calls, hasLength(4));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'disabled host is quiet; enabling same binding displays live preview',
      (tester) async {
    final api = MarkSixFakeApi();
    await _mount(tester, _host(api, enabled: false));
    expect(find.byKey(const ValueKey('lottery-edge-handle')), findsNothing);
    expect(api.calls, isEmpty);
    await _mount(tester, _host(api, enabled: true));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('lottery-edge-handle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lottery-preview-card-shell')),
        findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('lottery-preview-card-shell')))
            .height,
        160);
    expect(api.calls, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('lottery-preview-open')));
    await tester.pumpAndSettle();
    expect(find.byType(MarkSixPage), findsOneWidget);
    expect(api.calls, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets(
      'disabling public entry removes exact old preview without stale controller errors',
      (tester) async {
    final api = MarkSixFakeApi();
    await _mount(tester, _host(api));
    await tester.tap(find.byKey(const ValueKey('lottery-edge-handle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lottery-preview-card-shell')),
        findsOneWidget);
    await _mount(tester, _host(api, enabled: false, revision: 2));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('lottery-preview-card-shell')), findsNothing);
    expect(find.byKey(const ValueKey('lottery-edge-handle')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('private history denies permissions and does not query',
      (tester) async {
    final api = MarkSixFakeApi();
    await _mount(tester,
        AgentHistoryPage(featureContext: markSixContext(api, agent: false)));
    await tester.pumpAndSettle();
    expect(find.text('你没有收益历史权限'), findsOneWidget);
    expect(api.calls, isEmpty);
  });
  testWidgets('independent public page closes on newer Mark Six disabled event',
      (tester) async {
    final events = StreamController<Map<String, dynamic>>(sync: true);
    addTearDown(events.close);
    final api = MarkSixFakeApi();
    final c = markSixContext(api, events: events.stream);
    Future<void>? completion;
    await _mount(
        tester,
        Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () =>
                        completion = MarkSixModule.openDrawHistory(context, c),
                    child: const Text('打开开奖')))));
    await tester.tap(find.text('打开开奖'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkSixPage), findsOneWidget);
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 60);
    events.add({
      'key': 'groupFeaturesChanged',
      'groupID': 'group-test',
      'data': {
        'groupFeatures': {
          'schemaVersion': 1,
          'revision': 2,
          'games': {
            'markSix': {
              'enabled': false,
              'drawHistoryEntry': true,
              'machineCode': 'machine-test'
            }
          }
        }
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(MarkSixPage), findsNothing);
    expect(find.text('打开开奖'), findsOneWidget);
    expect(api.calls, hasLength(2));
    expect(tester.takeException(), isNull);
    await completion;
  });
  testWidgets(
      'history date presets use existing Cupertino sheet and load selected dates',
      (tester) async {
    final api = MarkSixFakeApi();
    await _mount(tester, AgentHistoryPage(featureContext: markSixContext(api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.date_range_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('当前选择'), findsOneWidget);
    await tester.tap(find.text('一周'));
    await tester.pumpAndSettle();
    expect(api.calls, hasLength(2));
    expect(api.calls.last.query['startDate'],
        isNot(api.calls.first.query['startDate']));
  });
  testWidgets(
      'team and personal history buttons query their actual distinct routes',
      (tester) async {
    final api = MarkSixFakeApi();
    await _mount(tester, AgentHistoryPage(featureContext: markSixContext(api)));
    await tester.pumpAndSettle();
    expect(api.calls.single.path, '/me/agent/rebate/history');
    expect(find.text('合计'), findsOneWidget);
    await tester.tap(find.text('个人历史'));
    await tester.pumpAndSettle();
    expect(api.calls.last.path, '/me/agent/rebate/personal-history');
    expect(find.text('已反水'), findsWidgets);
    expect(find.text('记录数'), findsWidgets);
    expect(find.text('平台输赢'), findsNothing);
    expect(find.text('下载'), findsNothing);
  });
  testWidgets(
      'rebate cancellation never submits and failed acknowledgement is visible',
      (tester) async {
    final api = MarkSixFakeApi(
        respond: (method, path, query, _) => method == 'POST'
            ? {'status': 'FAILED'}
            : markSixFixtureResponse(path, query));
    await _mount(tester, AgentCurrentPage(featureContext: markSixContext(api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('申请反水'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    await tester.tap(find.text('申请反水'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认申请'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.method == 'POST'), hasLength(1));
    expect(find.textContaining('反水结算失败'), findsOneWidget);
    expect(find.text('反水结算成功'), findsNothing);
  });
  testWidgets(
      'rebate page disables application while restoring and recovers pending work after route reopen',
      (tester) async {
    var serverStatus = 'NONE';
    var firstStatusRead = true;
    final restored = Completer<Map<String, dynamic>>();
    final submitted = Completer<Map<String, dynamic>>();
    final api = MarkSixFakeApi(respond: (method, path, query, _) {
      if (method == 'POST') {
        serverStatus = 'PROCESSING';
        return submitted.future;
      }
      if (path.endsWith('/apply/status')) {
        if (firstStatusRead) {
          firstStatusRead = false;
          return restored.future;
        }
        return {'status': serverStatus};
      }
      return markSixFixtureResponse(path, query);
    });
    final featureContext = markSixContext(api);
    await _mount(
        tester,
        Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => MarkSixModule.openCurrentRebate(
                        context, featureContext),
                    child: const Text('打开汇总')))));
    await tester.tap(find.text('打开汇总'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AgentCurrentPage), findsOneWidget);
    expect(find.text('恢复申请状态中…'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(api.calls.where((call) => call.path.endsWith('/apply/status')),
        hasLength(1));
    expect(api.calls.any((call) => call.path == '/me/rebate/apply/status'),
        isFalse);
    restored.complete({'status': 'NONE'});
    await tester.pumpAndSettle();
    await tester.tap(find.text('申请反水'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认申请'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.calls.where((call) => call.method == 'POST'), hasLength(1));
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(AgentCurrentPage), findsNothing);
    submitted.complete({'status': 'PROCESSING'});
    await tester.pump();
    await tester.tap(find.text('打开汇总'));
    await tester.pumpAndSettle();
    expect(find.text('查询处理状态'), findsOneWidget);
    expect(find.text('申请反水'), findsNothing);
    expect(api.calls.where((call) => call.method == 'POST'), hasLength(1));
    serverStatus = 'SUCCESS';
    await tester.tap(find.text('查询处理状态'));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(api.calls.where((call) => call.method == 'POST'), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
