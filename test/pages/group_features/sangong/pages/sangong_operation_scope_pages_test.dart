import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/search/contact_search_source.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_all_users_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_members_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_my_config_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:openim_common/openim_common.dart';

import '../sangong_test_support.dart';

class _Search extends ContactSearchSource {
  final reply = Completer<List<UserFullInfo>?>();
  int requests = 0;

  @override
  Future<List<UserFullInfo>?> users(String keyword, int page, {int? way}) {
    requests++;
    return reply.future;
  }
}

Future<void> _pump(WidgetTester tester, SangongRuntime runtime, Widget page) =>
    pumpSangongPage(tester, runtime,
        Builder(builder: (context) => EasyLoading.init()(context, page)));

void _switchTenant(SangongRuntime runtime, SangongTestApi api) {
  final context =
      sangongTestContext(api, tenantID: 'tenant-B', capabilityVersion: 2);
  runtime.updateContext(context);
  final confirmed = sangongTestRuntime(context);
  runtime.groupTenant.applySaved(confirmed.groupTenant.state!);
  confirmed.dispose();
  expect(runtime.canManage, isTrue);
}

void main() {
  tearDown(() => EasyLoading.dismiss(animation: false));

  for (final page in ['helper', 'bot']) {
    testWidgets(
        '$page old form cannot write after equally privileged tenant switch',
        (tester) async {
      final source = _Search();
      final api = SangongTestApi();
      final runtime = sangongTestRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await _pump(
          tester,
          runtime,
          page == 'helper'
              ? SangongMembersPage(accountSearchSource: source)
              : SangongMyConfigPage(accountSearchSource: source));
      if (page == 'helper') {
        await tester.tap(find.text('添加帮工'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(CupertinoTextField), '@abcdefgh12');
        await tester.tap(find.text('添加'));
      } else {
        await tester.enterText(find.byType(TextField).last, '@abcdefgh12');
        await tester.tap(find.text('保存'));
      }
      await flushSangong(tester);
      expect(source.requests, 1);
      _switchTenant(runtime, api);
      source.reply.complete([
        UserFullInfo(userID: 'im_tenant_A', account: 'abcdefgh12'),
      ]);
      await flushSangong(tester);
      expect(api.calls.where((call) => call.method != 'GET'), isEmpty);
      expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final stage in ['account', 'detail']) {
    testWidgets('equally privileged tenant switch discards late $stage search',
        (tester) async {
      final source = _Search();
      final detailReply = Completer<dynamic>();
      final api = SangongTestApi()
        ..respond = (call) => call.path.endsWith('/reports/users')
            ? {'users': [], 'page': 1, 'totalPages': 0}
            : detailReply.future;
      final runtime = sangongTestRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await _pump(
          tester, runtime, SangongAllUsersPage(accountSearchSource: source));
      await tester.enterText(find.byType(TextField), '@abcdefgh12');
      await tester.pump(const Duration(milliseconds: 320));
      if (stage == 'detail') {
        source.reply.complete([
          UserFullInfo(userID: 'im_real_target', account: 'abcdefgh12'),
        ]);
      }
      await flushSangong(tester);
      expect(source.requests, 1);
      _switchTenant(runtime, api);
      if (stage == 'account') {
        source.reply.complete([
          UserFullInfo(userID: 'im_real_target', account: 'abcdefgh12'),
        ]);
      } else {
        detailReply.complete({
          'user': {
            'userId': 208,
            'imUserId': 'im_real_target',
            'nickname': 'A 厅私有账户',
            'balance': 987,
          },
        });
      }
      await flushSangong(tester);
      expect(api.count('/reports/user-detail'), stage == 'account' ? 0 : 1);
      expect(find.text('A 厅私有账户'), findsNothing);
      expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('member removal confirmation from tenant A cannot delete in B',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/my-config/members')
          ? {
              'members': [
                {'imUserId': 'helper-A', 'role': 'admin'},
              ],
            }
          : sangongFixtureResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pump(tester, runtime, const SangongMembersPage());
    await tester.tap(find.text('helper-A'));
    await tester.pump(const Duration(milliseconds: 300));
    _switchTenant(runtime, api);
    await tester.tap(find.text('移除'));
    await flushSangong(tester);
    expect(api.calls.where((call) => call.method == 'DELETE'), isEmpty);
    expect(find.text('helper-A'), findsNothing);
    expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first configuration accepts its own confirmed tenant binding',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.method == 'PUT'
          ? sangongConfig()
          : call.path.endsWith('/my-config')
              ? {'configured': false}
              : sangongFixtureResponse(call);
    final runtime = SangongRuntime(sangongTestContext(api,
        enabled: false, canManage: false, tenantID: ''));
    var saved = false;
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await _pump(
        tester,
        runtime,
        SangongMyConfigPage(
            initialGameGroupId: 'group-sangong',
            onSaved: (config) => saved = config.configured));
    await tester.enterText(find.byType(TextField).at(2), 'group-statistics');
    await tester.enterText(find.byType(TextField).last, 'im_existing_bot');
    await tester.tap(find.text('保存'));
    await flushSangong(tester);
    expect(api.calls.where((call) => call.method == 'PUT'), hasLength(1));
    expect(saved, isTrue);
    expect(runtime.http.tenantId, 'tenant-authorized');
    expect(tester.takeException(), isNull);
  });
}
