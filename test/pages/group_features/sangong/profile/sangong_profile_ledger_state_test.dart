import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_user_detail_page.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_ledger.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_ledger_floating_entry.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_ledger_frame.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_surface.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;
import 'package:shared_preferences/shared_preferences.dart';

import '../sangong_test_support.dart';

const _target = 'im_target';
const _ordinaryProfile = '普通用户资料';

Map<String, dynamic> _account() => {
      'exists': true,
      'user': {
        'userId': 19,
        'imUserId': _target,
        'nickname': '目标用户',
        'balance': 420,
      },
    };

GroupInfo _group() => GroupInfo.fromJson({
      'groupID': 'g',
      'groupName': '游戏群',
      'ex': jsonEncode({
        'groupFeatures': {
          'schemaVersion': 1,
          'revision': 1,
          'games': {
            'sangong': {'enabled': true, 'manageEntry': true}
          }
        }
      }),
    });

SangongTestApi _api(FutureOr<dynamic> Function(SangongCall) readUser) =>
    SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/feature-capabilities')) {
          return {
            'groupID': 'g',
            'capabilityVersion': 1,
            'sangong': {'canManage': true, 'tenantID': 'tenant-authorized'},
          };
        }
        if (call.path.endsWith('/user')) return readUser(call);
        if (call.path.endsWith('/user-report')) {
          return sangongUserReport(
              imUserId: _target, user: {'nickname': '目标用户', 'balance': 420});
        }
        return sangongFixtureResponse(call);
      };

GroupFeatureStore _store(SangongTestApi api) => GroupFeatureStore(
      api: api,
      accountPrivilege: api.privilege,
      sessionCurrent: () => true,
      fetchGroups: (_) async => [],
    );

Future<void> _mount(WidgetTester tester, GroupFeatureStore store,
    {bool dark = false, Size size = const Size(320, 700)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        body: SangongProfileSurface(
          userID: _target,
          store: store,
          loadGroups: () async => [_group()],
          child: const Center(child: Text(_ordinaryProfile)),
        ),
      ),
    ),
  ));
  await flushSangong(tester);
  await flushSangong(tester);
}

Finder _inFrame(Finder matching) => find.descendant(
    of: find.byType(SangongProfileLedgerFrame), matching: matching);

Future<void> _openLedger(WidgetTester tester) async {
  final entry = find.descendant(
      of: find.byType(SangongProfileLedgerFloatingEntry),
      matching: find.byType(InkWell));
  expect(entry, findsOneWidget);
  expect(tester.widget<InkWell>(entry).onTap, isNotNull);
  await tester.tap(entry);
  await flushSangong(tester);
  await tester.pump(const Duration(milliseconds: 350));
  await flushSangong(tester);
  expect(find.byType(BottomSheet), findsOneWidget);
  expect(find.byType(SangongProfileLedger), findsOneWidget);
}

void _expectOpaqueFrame(WidgetTester tester, {required bool dark}) {
  final frame = find.byType(SangongProfileLedgerFrame);
  expect(frame, findsOneWidget);
  final surface = tester.widget<Material>(
      find.descendant(of: frame, matching: find.byType(Material)).first);
  expect(surface.color, AppTokens.surface(dark: dark));
  expect(surface.color!.a, 1);
  expect(Theme.of(tester.element(frame)).brightness,
      dark ? Brightness.dark : Brightness.light);
  expect(_inFrame(find.text('游戏流水')), findsOneWidget);
  expect(tester.getSize(frame).width, tester.view.physicalSize.width);
  expect(tester.getSize(frame).height,
      greaterThan(tester.view.physicalSize.height * .75));
  expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
      AppTokens.surface(dark: dark));
}

Future<void> _finish(WidgetTester tester, GroupFeatureStore store) async {
  await unmountSangong(tester);
  store.dispose();
  debugPrint = tester.binding.debugPrintOverride;
}

List<Map<String, dynamic>> _ledgerEvents(List<String> logs, String stage) {
  final prefix = RegExp(r'^\[三公API\]\[[^\]]*\]\[资料流水_' +
      RegExp.escape(stage) +
      r'\]\[(\d+)/(\d+)\] ([\s\S]*)$');
  final events = <Map<String, dynamic>>[];
  var parts = StringBuffer();
  for (final line in logs) {
    final match = prefix.firstMatch(line);
    if (match == null) continue;
    if (match.group(1) == '1') parts = StringBuffer();
    parts.write(match.group(3));
    if (match.group(1) == match.group(2)) {
      events
          .add(Map<String, dynamic>.from(jsonDecode(parts.toString()) as Map));
    }
  }
  return events;
}

void _expectLedgerScope(Map<String, dynamic> event, {String? lookupID}) {
  expect(event['targetIMUserID'], _target);
  expect(event['groupID'], 'g');
  expect(event['currentUserID'], 'owner');
  expect(event['resource'], 'user');
  expect(event['lookupID'],
      isA<String>().having((id) => id.isNotEmpty, 'set', true));
  if (lookupID != null) expect(event['lookupID'], lookupID);
  expect(event['elapsedMs'], isA<int>());
}

void main() {
  late List<String> logs;
  late DebugPrintCallback previousPrint;
  setUp(() {
    OpenIM.iMManager.userID = 'owner';
    SharedPreferences.setMockInitialValues({});
    logs = [];
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });
  tearDown(() => debugPrint = previousPrint);

  for (final dark in [false, true]) {
    testWidgets('authorized loading sheet is opaque and can close dark=$dark',
        (tester) async {
      final pending = Completer<dynamic>();
      final api = _api((_) => pending.future);
      final store = _store(api);
      await _mount(tester, store, dark: dark);
      expect(api.count('/user'), 0,
          reason: 'The floating entry must be opened before reading the user.');
      await _openLedger(tester);
      expect(api.count('/user'), 1);
      final started = _ledgerEvents(logs, '开始').single;
      _expectLedgerScope(started);
      expect(_ledgerEvents(logs, '结果'), isEmpty);
      expect(_ledgerEvents(logs, '失败'), isEmpty);
      _expectOpaqueFrame(tester, dark: dark);
      expect(_inFrame(find.text('正在加载游戏流水…')), findsOneWidget);
      expect(_inFrame(find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(_inFrame(find.text('重试')), findsNothing);
      expect(find.byType(SangongUserDetailPage), findsNothing);

      await tester.tap(_inFrame(find.byTooltip('关闭')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text(_ordinaryProfile), findsOneWidget);
      pending.complete(_account());
      await flushSangong(tester);
      final completed = _ledgerEvents(logs, '结果').single;
      _expectLedgerScope(completed, lookupID: started['lookupID'] as String);
      expect(completed['result'], 'account_confirmed');
      expect(completed['current'], isFalse,
          reason: 'A closed ledger must identify its late result as inactive.');
      expect(find.byType(SangongUserDetailPage), findsNothing);
      expect(api.count('/user-report'), 0);
      expect(tester.takeException(), isNull);
      await _finish(tester, store);
    });

    testWidgets(
        'network failure retries inside the same ledger sheet dark=$dark',
        (tester) async {
      final first = Completer<dynamic>();
      final retry = Completer<dynamic>();
      var userRequests = 0;
      final api = _api((_) {
        userRequests++;
        return userRequests == 1
            ? first.future
            : userRequests == 2
                ? retry.future
                : _account();
      });
      final store = _store(api);
      await _mount(tester, store, dark: dark);
      await _openLedger(tester);
      final sheet = tester.element(find.byType(BottomSheet));
      final firstStarted = _ledgerEvents(logs, '开始').single;
      _expectLedgerScope(firstStarted);
      first.completeError(DioException(
          requestOptions: RequestOptions(path: '/sangong/api/v2/groups/g/user'),
          type: DioExceptionType.connectionError));
      await flushSangong(tester);
      final failed = _ledgerEvents(logs, '失败').single;
      _expectLedgerScope(failed, lookupID: firstStarted['lookupID'] as String);
      expect(failed['errorType'], 'DioException');
      expect(failed['networkType'], 'connectionError');
      expect(_ledgerEvents(logs, '结果'), isEmpty);
      _expectOpaqueFrame(tester, dark: dark);
      expect(_inFrame(find.text('游戏流水加载失败')), findsOneWidget);
      expect(_inFrame(find.text('网络连接失败，请重试')), findsOneWidget);
      expect(find.text('暂未找到该用户的游戏账户'), findsNothing);
      expect(find.text('未能读取该用户的游戏流水'), findsNothing);
      expect(_inFrame(find.byTooltip('关闭')), findsOneWidget);
      expect(find.byType(SangongUserDetailPage), findsNothing);

      await tester.tap(_inFrame(find.text('重试')));
      await flushSangong(tester);
      expect(userRequests, 2);
      final starts = _ledgerEvents(logs, '开始');
      expect(starts, hasLength(2));
      _expectLedgerScope(starts.last);
      expect(starts.last['lookupID'], isNot(firstStarted['lookupID']));
      expect(tester.element(find.byType(BottomSheet)), same(sheet));
      _expectOpaqueFrame(tester, dark: dark);
      expect(_inFrame(find.text('正在加载游戏流水…')), findsOneWidget);
      expect(_inFrame(find.text('游戏流水加载失败')), findsNothing);
      retry.complete(_account());
      await flushSangong(tester);
      await flushSangong(tester);
      final completed = _ledgerEvents(logs, '结果').single;
      _expectLedgerScope(completed,
          lookupID: starts.last['lookupID'] as String);
      expect(completed['result'], 'account_confirmed');
      expect(completed['returnedIMUserID'], _target);
      expect(completed['current'], isTrue);
      expect(_ledgerEvents(logs, '失败'), hasLength(1));
      expect(tester.element(find.byType(BottomSheet)), same(sheet));
      expect(find.byType(SangongUserDetailPage), findsOneWidget);
      expect(find.text('用户详情'), findsOneWidget);
      expect(find.byType(SangongProfileLedgerFrame), findsNothing);
      expect(api.count('/user-report'), 1);
      expect(
          api.calls
              .where((call) =>
                  call.path.endsWith('/user') ||
                  call.path.endsWith('/user-report'))
              .every((call) => call.query?['imUserId'] == _target),
          isTrue);
      expect(tester.takeException(), isNull);
      await _finish(tester, store);
    });

    testWidgets(
        'missing game account has its own opaque empty state dark=$dark',
        (tester) async {
      final api = _api((_) => {'exists': false});
      final store = _store(api);
      await _mount(tester, store, dark: dark);
      await _openLedger(tester);
      final started = _ledgerEvents(logs, '开始').single;
      final completed = _ledgerEvents(logs, '结果').single;
      _expectLedgerScope(started);
      _expectLedgerScope(completed, lookupID: started['lookupID'] as String);
      expect(completed['result'], 'account_not_found');
      expect(completed['returnedIMUserID'], isNull);
      expect(completed['current'], isTrue);
      expect(_ledgerEvents(logs, '失败'), isEmpty);
      _expectOpaqueFrame(tester, dark: dark);
      expect(_inFrame(find.text('暂未找到该用户的游戏账户')), findsOneWidget);
      expect(_inFrame(find.text('重试')), findsOneWidget);
      expect(find.text('游戏流水加载失败'), findsNothing);
      expect(find.text('网络连接失败，请重试'), findsNothing);
      expect(find.byType(SangongUserDetailPage), findsNothing);
      expect(api.count('/user-report'), 0);
      await tester.tap(_inFrame(find.byTooltip('关闭')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text(_ordinaryProfile), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _finish(tester, store);
    });
  }

  for (final wrongID in ['another-private-account', null]) {
    testWidgets('invalid returned IM identity reveals no private data $wrongID',
        (tester) async {
      final api = _api((_) => {
            'exists': true,
            'user': {
              'userId': 991,
              if (wrongID != null) 'imUserId': wrongID,
              'nickname': '不能显示的私密昵称',
              'balance': 987654321,
            },
          });
      final store = _store(api);
      await _mount(tester, store);
      await _openLedger(tester);
      final started = _ledgerEvents(logs, '开始').single;
      final failed = _ledgerEvents(logs, '失败').single;
      _expectLedgerScope(started);
      _expectLedgerScope(failed, lookupID: started['lookupID'] as String);
      expect(failed['errorType'], 'FormatException');
      expect(failed['validationError'], '用户资料与当前账号不匹配');
      expect(_ledgerEvents(logs, '结果'), isEmpty);
      _expectOpaqueFrame(tester, dark: false);
      expect(_inFrame(find.text('游戏流水加载失败')), findsOneWidget);
      expect(_inFrame(find.text('返回数据格式无效，请重试')), findsOneWidget);
      expect(find.text('不能显示的私密昵称'), findsNothing);
      expect(find.textContaining('987654321'), findsNothing);
      expect(find.byType(SangongUserDetailPage), findsNothing);
      expect(api.count('/user-report'), 0);
      expect(api.count('/sessions'), 0);
      final lookup =
          api.calls.singleWhere((call) => call.path.endsWith('/user'));
      expect(lookup.query?['imUserId'], _target);
      expect(tester.takeException(), isNull);
      await _finish(tester, store);
    });
  }

  testWidgets('wide embedded ledger keeps status but cannot close its profile',
      (tester) async {
    final pending = Completer<dynamic>();
    final api = _api((_) => pending.future);
    final store = _store(api);
    await _mount(tester, store, dark: true, size: const Size(1200, 900));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SangongProfileLedgerFloatingEntry), findsNothing);
    expect(
        tester
            .widget<SangongProfileLedger>(find.byType(SangongProfileLedger))
            .embedded,
        isTrue);
    expect(_inFrame(find.text('游戏流水')), findsOneWidget);
    expect(_inFrame(find.text('正在加载游戏流水…')), findsOneWidget);
    expect(_inFrame(find.byTooltip('关闭')), findsNothing);
    pending.complete({'exists': false});
    await flushSangong(tester);
    expect(_inFrame(find.text('暂未找到该用户的游戏账户')), findsOneWidget);
    expect(_inFrame(find.byTooltip('关闭')), findsNothing);
    expect(find.text(_ordinaryProfile), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _finish(tester, store);
  });
}
