import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_user_detail_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'sangong_test_support.dart';

Map<String, dynamic> profileWithLimit(int limit) => {
      'exists': true,
      'user': {
        'userId': 19,
        'imUserId': 'im_target',
        'maxNegative': limit,
        'balance': 1000,
      }
    };

Map<String, dynamic> reportWithLimit(int limit) => sangongUserReport(
    imUserId: 'im_target',
    user: Map<String, dynamic>.from(profileWithLimit(limit)['user']));

dynamic profileBackground(SangongCall call) {
  if (call.path.endsWith('/snapshot'))
    return {
      'session': {'id': 2},
      'round': null
    };
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
  testWidgets('older report cannot replace a newer selected batch',
      (tester) async {
    final oldRead = Completer<dynamic>();
    var profileReads = 0;
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/user-report')) {
          return ++profileReads == 1 ? oldRead.future : reportWithLimit(100);
        }
        return profileBackground(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(tester, runtime, target);
    await tester.tap(find.text('开机批次'));
    await flushSangong(tester);
    expect(find.text('可负额度 100'), findsOneWidget);
    oldRead.complete(reportWithLimit(10));
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
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/user-report')) return oldRead.future;
        if (call.path.endsWith('/user')) return profileWithLimit(500);
        if (call.path.endsWith('/commands/wallet.limit'))
          return sangongReceipt(
              call, Map<String, dynamic>.from(profileWithLimit(500)['user']));
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
    expect(api.count('/commands/wallet.limit'), 1);
    expect(find.text('可负额度 500'), findsOneWidget);
    oldRead.complete(reportWithLimit(10));
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
      ..respond = (call) => call.path.endsWith('/user-report')
          ? {
              ...reportWithLimit(100),
              'exists': true,
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
      ..respond = (call) => call.path.endsWith('/user-report')
          ? {
              ...reportWithLimit(100),
              'exists': true,
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
        ..respond = (call) => call.path.endsWith('/user-report')
            ? reportWithLimit(100)
            : call.path.endsWith('/commands/wallet.limit')
                ? sangongReceipt(call,
                    Map<String, dynamic>.from(profileWithLimit(500)['user']))
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
      expect(api.count('/commands/wallet.limit'), 0);
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
