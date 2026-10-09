import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/agents/halls/sangong_agent_hall_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_member_detail_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_team_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import '../../sangong_test_support.dart';

GroupFeatureContext _context(SangongTestApi api) => GroupFeatureContext(
      groupID: 'shared-agent',
      groupName: '代理群',
      currentUserID: 'owner',
      gameType: GroupGameType.sangongAgent,
      api: api,
      accountPrivilege: api.privilege,
      capabilities: const GroupFeatureCapabilities(
          version: 1,
          sangong: GroupGameCapabilities(
              canOpenAgent: true,
              canViewRebateHistory: true,
              raw: {'requiresTenantSelection': true})),
      sessionCurrent: () => true,
      onFeaturesChanged: (_) {},
    );

Map<String, dynamic> _choices([List<String> ids = const ['a', 'b']]) => {
      'agentImUserId': 'owner',
      'agentImGroupId': 'shared-agent',
      'tenants': [
        for (final id in ids)
          {'tenantId': id, 'name': '$id 厅', 'imGroupGameId': '$id-game'}
      ],
    };

dynamic _response(SangongCall call) {
  if (call.path.endsWith('/tenants')) return _choices();
  if (call.path.endsWith('/member')) {
    return {
      'member': {
        'imUserId': 'owner',
        'nickname': '代理',
        'balance': call.query?['tenantId'] == 'a' ? 111 : 222
      }
    };
  }
  if (call.path.endsWith('/member-daily')) return {'days': []};
  return sangongFixtureResponse(call);
}

Future<SangongRuntime> _pump(
  WidgetTester tester,
  SangongTestApi api, {
  bool dark = false,
  TargetPlatform platform = TargetPlatform.android,
  String section = 'team',
  String? initialTenantId,
  ValueChanged<String>? onSelected,
}) async {
  final context = _context(api);
  final runtime = SangongRuntime(context);
  addTearDown(runtime.dispose);
  addTearDown(() => unmountSangong(tester));
  await pumpSangongPage(
      tester,
      runtime,
      SangongAgentHallPage(
          featureContext: context,
          section: section,
          initialTenantId: initialTenantId,
          onSelected: onSelected),
      dark: dark,
      platform: platform);
  return runtime;
}

void main() {
  for (final dark in [false, true]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
          'select and switch halls without mixing requests $dark $platform',
          (tester) async {
        final api = SangongTestApi()..respond = _response;
        final selected = <String>[];
        await _pump(tester, api,
            dark: dark, platform: platform, onSelected: selected.add);
        expect(find.text('选择厅'), findsOneWidget);
        expect(api.calls.every((c) => c.path.endsWith('/tenants')), isTrue);
        await tester.tap(find.text('a 厅'));
        await flushSangong(tester);
        expect(find.text('当前厅：a 厅'), findsOneWidget);
        expect(api.calls.last.query?['tenantId'], 'a');
        await tester.tap(find.text('切换厅'));
        await flushSangong(tester);
        expect(find.byType(SangongAgentTeamPage), findsNothing);
        await tester.tap(find.text('b 厅'));
        await flushSangong(tester);
        expect(find.text('当前厅：b 厅'), findsOneWidget);
        expect(api.calls.last.query?['tenantId'], 'b');
        expect(selected, ['a', 'b']);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'personal detail keeps the selected runtime alive and switches balance',
      (tester) async {
    final api = SangongTestApi()..respond = _response;
    await _pump(tester, api, section: 'personal', initialTenantId: 'a');
    expect(find.byType(SangongAgentMemberDetailPage), findsOneWidget);
    expect(find.text('当前厅：a 厅'), findsOneWidget);
    expect(find.text('111'), findsOneWidget);
    await tester.tap(find.text('切换厅'));
    await flushSangong(tester);
    await tester.tap(find.text('b 厅'));
    await flushSangong(tester);
    expect(find.text('当前厅：b 厅'), findsOneWidget);
    expect(find.text('222'), findsOneWidget);
    expect(find.text('111'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late result from old hall is discarded after switching',
      (tester) async {
    final old = Completer<dynamic>();
    final api = SangongTestApi()
      ..respond = (call) =>
          call.path.endsWith('/team') && call.query?['tenantId'] == 'a'
              ? old.future
              : _response(call);
    await _pump(tester, api, initialTenantId: 'a');
    await tester.tap(find.text('切换厅'));
    await flushSangong(tester);
    await tester.tap(find.text('b 厅'));
    await flushSangong(tester);
    old.complete({
      'members': [
        {'imUserId': 'stale', 'nickname': '旧厅成员'}
      ],
      'version': 1,
      'nextBeforeId': 0
    });
    await flushSangong(tester);
    expect(find.text('当前厅：b 厅'), findsOneWidget);
    expect(find.text('旧厅成员'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unconfirmed write blocks switching and pins both tenant selectors',
      (tester) async {
    final command = Completer<dynamic>();
    final api = SangongTestApi()
      ..respond =
          (call) => call.method == 'POST' ? command.future : _response(call);
    await _pump(tester, api, initialTenantId: 'a');
    final runtime =
        SangongScope.read(tester.element(find.byType(SangongAgentTeamPage)));
    final claim = runtime.agent.claimSangongRebate();
    await flushSangong(tester);
    final write = api.calls.last;
    expect(write.body?['tenantId'], 'a');
    expect(write.body?['expectedTenantId'], 'a');
    await tester.tap(find.text('切换厅'));
    await flushSangong(tester);
    expect(find.text('当前厅：a 厅'), findsOneWidget);
    expect(find.textContaining('当前操作结果尚未确认'), findsOneWidget);
    command.complete(sangongReceipt(write, {'amount': 0}));
    await completeSangongRequest(tester, claim);
    await tester.tap(find.text('切换厅'));
    await flushSangong(tester);
    expect(find.text('选择厅'), findsOneWidget);
  });

  testWidgets(
      'revoked remembered hall is not restored, single hall opens directly',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) =>
          call.path.endsWith('/tenants') ? _choices(['b']) : _response(call);
    await _pump(tester, api, initialTenantId: 'a');
    expect(find.text('当前厅：b 厅'), findsOneWidget);
    expect(
        api.calls
            .where((c) => !c.path.endsWith('/tenants'))
            .every((c) => c.query?['tenantId'] == 'b'),
        isTrue);
  });

  for (final dark in [false, true]) {
    testWidgets('empty and invalid discovery reveal no private data dark=$dark',
        (tester) async {
      final api = SangongTestApi()..respond = (_) => _choices([]);
      await _pump(tester, api, dark: dark);
      expect(find.text('当前代理群暂无可查看的厅'), findsOneWidget);
      api.respond = (_) => {..._choices(), 'agentImUserId': 'someone-else'};
      await tester.tap(find.byTooltip('刷新'));
      await flushSangong(tester);
      expect(find.text('重试'), findsOneWidget);
      expect(api.calls.every((c) => c.path.endsWith('/tenants')), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
