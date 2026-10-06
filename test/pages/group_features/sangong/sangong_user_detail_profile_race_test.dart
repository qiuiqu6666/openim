import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_user_detail_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'sangong_test_support.dart';

Map<String, dynamic> profileWithLimit(int limit) => {
      'user': {
        'userId': 19,
        'imUserId': 'im_target',
        'maxNegative': limit,
        'balance': 1000,
      }
    };

dynamic profileBackground(SangongCall call) {
  if (call.path.endsWith('/sessions')) return {'sessions': []};
  if (call.path.endsWith('/user-hierarchy')) return {'members': []};
  if (call.path.endsWith('/user-flow')) {
    return {
      'flow': {'entries': []}
    };
  }
  return sangongFixtureResponse(call);
}

const target = SangongUserDetailPage(
    user: SangongAdminUserReport(
        userId: 19, imUserId: 'im_target', balance: 1000, maxNegative: 10));

void _switchToConfirmedTenant(SangongRuntime runtime, SangongTestApi api) {
  final context = sangongTestContext(api, tenantID: 'tenant-b');
  runtime.updateContext(context);
  final confirmed = sangongTestRuntime(context);
  runtime.groupTenant.applySaved(confirmed.groupTenant.state!);
  confirmed.dispose();
}

void main() {
  testWidgets('older profile response cannot replace a newer refresh',
      (tester) async {
    final oldRead = Completer<dynamic>();
    var profileReads = 0;
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/user-detail')) {
          return ++profileReads == 1 ? oldRead.future : profileWithLimit(100);
        }
        return profileBackground(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(tester, runtime, target);
    await tester.tap(find.descendant(
        of: find.byType(AppBar), matching: find.byIcon(Icons.refresh)));
    await flushSangong(tester);
    expect(find.text('可负额度 100'), findsOneWidget);
    oldRead.complete(profileWithLimit(10));
    await flushSangong(tester);
    expect(find.text('可负额度 100'), findsOneWidget);
    expect(find.text('可负额度 10'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('late pre-save profile cannot overwrite confirmed new limit',
      (tester) async {
    final oldRead = Completer<dynamic>();
    var profileReads = 0;
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/user-detail')) {
          return ++profileReads == 1 ? oldRead.future : profileWithLimit(500);
        }
        if (call.path.endsWith('/max-negative')) return profileWithLimit(500);
        return profileBackground(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(tester, runtime, target);
    await tester.tap(find.text('设置额度'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(CupertinoTextField), '500');
    await tester.tap(find.text('下一步'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('确认保存'));
    await tester.pump(const Duration(milliseconds: 350));
    await flushSangong(tester);
    expect(api.count('/max-negative'), 1);
    expect(find.text('可负额度 500'), findsOneWidget);
    oldRead.complete(profileWithLimit(10));
    await flushSangong(tester);
    expect(find.text('可负额度 500'), findsOneWidget);
    expect(find.text('可负额度 10'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('direct detail route hides cached private data on revocation',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/user-detail')
          ? {
              'user': {
                ...profileWithLimit(100)['user'],
                'nickname': '私人资料缓存',
              }
            }
          : profileBackground(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(tester, runtime, target);
    expect(find.text('私人资料缓存'), findsOneWidget);
    expect(find.text('可负额度 100'), findsOneWidget);
    final reads = api.calls.length;
    runtime.updateContext(
        sangongTestContext(api, canManage: false, capabilityVersion: 2));
    await tester.pump();
    expect(find.text('私人资料缓存'), findsNothing);
    expect(find.text('可负额度 100'), findsNothing);
    expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
    expect(api.calls.length, reads);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets(
      'same-permission tenant switch hides detail from the entry tenant',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/user-detail')
          ? {
              'user': {
                ...profileWithLimit(100)['user'],
                'nickname': '厅 A 私人资料',
              }
            }
          : profileBackground(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(tester, runtime, target);
    expect(find.text('厅 A 私人资料'), findsOneWidget);
    final reads = api.calls.length;
    _switchToConfirmedTenant(runtime, api);
    expect(runtime.canManage, isTrue,
        reason:
            'Tenant B grants the same permission, but this route belongs to A.');
    await tester.pump();
    expect(find.text('厅 A 私人资料'), findsNothing);
    expect(find.text('可负额度 100'), findsNothing);
    expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
    expect(api.calls.length, reads);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  for (final confirming in [false, true]) {
    testWidgets(
        'open max-negative dialog cannot write after tenant switch '
        '(confirming=$confirming)', (tester) async {
      final api = SangongTestApi()
        ..respond = (call) => call.path.endsWith('/user-detail')
            ? profileWithLimit(100)
            : call.path.endsWith('/max-negative')
                ? profileWithLimit(500)
                : profileBackground(call);
      final runtime = sangongTestRuntime(sangongTestContext(api));
      await pumpSangongPage(tester, runtime, target);
      await tester.tap(find.text('设置额度'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(find.byType(CupertinoTextField), '500');
      if (confirming) {
        await tester.tap(find.text('下一步'));
        await tester.pump(const Duration(milliseconds: 350));
      }
      _switchToConfirmedTenant(runtime, api);
      expect(runtime.canManage, isTrue);
      await tester.pump();
      expect(find.byType(CupertinoTextField), findsNothing);
      expect(find.text('确认保存'), findsNothing);
      expect(find.text('下一步'), findsNothing);
      expect(find.text('游戏信息已变化'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pump(const Duration(milliseconds: 350));
      await flushSangong(tester);
      expect(api.count('/max-negative'), 0);
      expect(
          api.calls.every((call) =>
              call.headers?['X-Tenant-Id'] == expectedSangongRequestTenant()),
          isTrue);
      expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountSangong(tester);
      runtime.dispose();
    });
  }
}
