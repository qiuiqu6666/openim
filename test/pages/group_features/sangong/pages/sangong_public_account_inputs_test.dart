import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:openim/pages/contacts/search/contact_search_source.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_all_users_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_members_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_my_config_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:openim_common/openim_common.dart';

import '../sangong_test_support.dart';

Future<void> _pumpInputsPage(
        WidgetTester tester, SangongRuntime runtime, Widget page,
        {bool dark = false}) =>
    pumpSangongPage(tester, runtime,
        Builder(builder: (context) => EasyLoading.init()(context, page)),
        dark: dark);

class _AccountSearch extends ContactSearchSource {
  final requests = <String>[];
  FutureOr<List<UserFullInfo>?> Function(String keyword)? respond;

  @override
  Future<List<UserFullInfo>?> users(String keyword, int page,
      {int? way}) async {
    requests.add(keyword);
    final handler = respond;
    return handler == null
        ? [UserFullInfo(userID: 'im_real_target', account: 'abcdefgh12')]
        : await handler(keyword);
  }
}

Future<void> _addHelper(WidgetTester tester, String account) async {
  await tester.tap(find.text('添加帮工'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(find.byType(CupertinoTextField), account);
  await tester.tap(find.text('添加'));
  await flushSangong(tester);
}

void main() {
  tearDown(() => EasyLoading.dismiss(animation: false));
  for (final account in ['@abcdefgh12', 'abcdefgh12']) {
    testWidgets('add helper resolves $account before the member API write',
        (tester) async {
      final api = SangongTestApi();
      final runtime = sangongTestRuntime(sangongTestContext(api));
      final source = _AccountSearch();
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await _pumpInputsPage(
          tester, runtime, SangongMembersPage(accountSearchSource: source));
      await _addHelper(tester, account);
      final write = api.calls.singleWhere((call) => call.method == 'POST');
      expect(source.requests, ['@abcdefgh12']);
      expect(write.path, endsWith('/access'));
      expect(write.body, {'imUserId': 'im_real_target', 'role': 'admin'});
      expect(tester.takeException(), isNull);
    });

    testWidgets('bot config resolves $account before saving the internal ID',
        (tester) async {
      final api = SangongTestApi();
      final runtime = sangongTestRuntime(sangongTestContext(api));
      final source = _AccountSearch();
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await _pumpInputsPage(
          tester, runtime, SangongMyConfigPage(accountSearchSource: source));
      await tester.enterText(find.byType(TextField).last, account);
      await tester.tap(find.text('保存'));
      await flushSangong(tester);
      final write = api.calls.singleWhere((call) => call.method == 'PUT');
      expect(source.requests, ['@abcdefgh12']);
      expect(write.body?['imBotUserId'], 'im_real_target');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('saved internal bot ID does not require public-account search',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    final source = _AccountSearch();
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpInputsPage(
        tester, runtime, SangongMyConfigPage(accountSearchSource: source));
    await tester.tap(find.text('保存'));
    await flushSangong(tester);
    expect(source.requests, isEmpty);
    expect(
        api.calls
            .singleWhere((call) => call.method == 'PUT')
            .body?['imBotUserId'],
        'bot-sangong');
  });

  for (final page in ['helper', 'bot']) {
    testWidgets('$page account mismatch cannot reach the mutation API',
        (tester) async {
      final source = _AccountSearch()
        ..respond = (_) => [
              UserFullInfo(userID: 'im_wrong', account: 'otheracct1'),
              UserFullInfo(userID: '', account: 'abcdefgh12'),
            ];
      final api = SangongTestApi();
      final runtime = sangongTestRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await _pumpInputsPage(
          tester,
          runtime,
          page == 'helper'
              ? SangongMembersPage(accountSearchSource: source)
              : SangongMyConfigPage(accountSearchSource: source));
      if (page == 'helper') {
        await _addHelper(tester, '@abcdefgh12');
      } else {
        await tester.enterText(find.byType(TextField).last, '@abcdefgh12');
        await tester.tap(find.text('保存'));
        await flushSangong(tester);
      }
      expect(source.requests, ['@abcdefgh12']);
      expect(api.calls.where((call) => call.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$page lookup cannot mutate after the session changes',
        (tester) async {
      var current = true;
      final reply = Completer<List<UserFullInfo>?>();
      final source = _AccountSearch()..respond = (_) => reply.future;
      final api = SangongTestApi();
      final runtime =
          sangongTestRuntime(sangongTestContext(api, current: () => current));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await _pumpInputsPage(
          tester,
          runtime,
          page == 'helper'
              ? SangongMembersPage(accountSearchSource: source)
              : SangongMyConfigPage(accountSearchSource: source));
      if (page == 'helper') {
        await _addHelper(tester, '@abcdefgh12');
      } else {
        await tester.enterText(find.byType(TextField).last, '@abcdefgh12');
        await tester.tap(find.text('保存'));
        await flushSangong(tester);
      }
      expect(source.requests, ['@abcdefgh12']);
      current = false;
      reply.complete([
        UserFullInfo(userID: 'im_previous_account', account: 'abcdefgh12'),
      ]);
      await flushSangong(tester);
      expect(api.calls.where((call) => call.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('account search finds a tenant user beyond loaded report pages',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/users')) {
          return {
            'users': [
              {'userId': 1, 'imUserId': 'im_loaded', 'nickname': '已加载用户', 'balance': 0},
            ],
            'nextBeforeId': 1,
            'pageSize': 50,
            'total': 250,
            'totalPages': 5,
          };
        }
        if (call.path.endsWith('/user')) {
          return {
            'exists': true,
'user': {
              'userId': 208,
              'imUserId': 'im_real_target',
              'nickname': '公开账号目标',
              'balance': 987,
              'rebatePer10000': 20,
            },
          };
        }
        return sangongFixtureResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    final source = _AccountSearch();
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpInputsPage(
        tester, runtime, SangongAllUsersPage(accountSearchSource: source),
        dark: true);
    await tester.enterText(find.byType(TextField), 'abcdefgh12');
    await tester.pump(const Duration(milliseconds: 320));
    await flushSangong(tester);
    expect(source.requests, ['@abcdefgh12']);
    final lookup = api.calls.singleWhere((call) => call.path.endsWith('/user'));
    expect(lookup.query, {'imUserId': 'im_real_target'});
    expect(lookup.headers?['X-Tenant-Id'], expectedSangongRequestTenant());
    expect(api.count('/users'), 1);
    expect(find.text('公开账号目标'), findsOneWidget);
    expect(find.text('积分 987'), findsOneWidget);
    expect(find.text('已加载用户'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account search rejects a different tenant user response',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/users')
          ? {'users': [], 'total': 0, 'nextBeforeId': 0}
          : {
              'exists': true,
'user': {
                'userId': 99,
                'imUserId': 'im_wrong',
                'nickname': '错误用户',
                'balance': 888,
              },
            };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpInputsPage(tester, runtime,
        SangongAllUsersPage(accountSearchSource: _AccountSearch()));
    await tester.enterText(find.byType(TextField), '@abcdefgh12');
    await tester.pump(const Duration(milliseconds: 320));
    await flushSangong(tester);
    expect(find.text('错误用户'), findsNothing);
    expect(find.text('返回数据格式无效，请重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('superseded account lookup cannot display a late private result',
      (tester) async {
    final reply = Completer<dynamic>();
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/users')
          ? {'users': [], 'total': 0, 'nextBeforeId': 0}
          : reply.future;
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpInputsPage(tester, runtime,
        SangongAllUsersPage(accountSearchSource: _AccountSearch()));
    await tester.enterText(find.byType(TextField), '@abcdefgh12');
    await tester.pump(const Duration(milliseconds: 320));
    await flushSangong(tester);
    expect(api.count('/user'), 1);
    await tester.enterText(find.byType(TextField), '');
    reply.complete({
      'exists': true,
'user': {
        'userId': 208,
        'imUserId': 'im_real_target',
        'nickname': '已失效的私有结果',
        'balance': 987,
      },
    });
    await flushSangong(tester);
    expect(find.text('已失效的私有结果'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoking permission clears already displayed account results',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/users')
          ? {'users': [], 'total': 0, 'nextBeforeId': 0}
          : {
              'exists': true,
'user': {
                'userId': 208,
                'imUserId': 'im_real_target',
                'nickname': '受保护的账户结果',
                'balance': 987,
              },
            };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpInputsPage(tester, runtime,
        SangongAllUsersPage(accountSearchSource: _AccountSearch()));
    await tester.enterText(find.byType(TextField), '@abcdefgh12');
    await tester.pump(const Duration(milliseconds: 320));
    await flushSangong(tester);
    expect(find.text('受保护的账户结果'), findsOneWidget);
    runtime.updateContext(sangongTestContext(api,
        canManage: false, canConfigure: false, capabilityVersion: 2));
    await flushSangong(tester);
    expect(find.text('受保护的账户结果'), findsNothing);
    expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'revoking during account resolution prevents private detail query',
      (tester) async {
    final reply = Completer<List<UserFullInfo>?>();
    final source = _AccountSearch()..respond = (_) => reply.future;
    final api = SangongTestApi()
      ..respond = (_) => {'users': [], 'total': 0, 'nextBeforeId': 0};
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pumpInputsPage(
        tester, runtime, SangongAllUsersPage(accountSearchSource: source));
    await tester.enterText(find.byType(TextField), '@abcdefgh12');
    await tester.pump(const Duration(milliseconds: 320));
    await flushSangong(tester);
    expect(source.requests, ['@abcdefgh12']);
    runtime.updateContext(sangongTestContext(api,
        canManage: false, canConfigure: false, capabilityVersion: 2));
    reply.complete([
      UserFullInfo(userID: 'im_real_target', account: 'abcdefgh12'),
    ]);
    await flushSangong(tester);
    expect(api.count('/user'), 0);
    expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
