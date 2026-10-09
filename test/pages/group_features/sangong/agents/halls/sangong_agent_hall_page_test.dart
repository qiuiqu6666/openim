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
              tenantID: 'a')),
      sessionCurrent: () => true,
      onFeaturesChanged: (_) {},
    );

Map<String, dynamic> _choices([List<String> ids = const ['a']]) => {
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
}) async {
  final context = _context(api);
  final runtime = SangongRuntime(context);
  addTearDown(runtime.dispose);
  addTearDown(() => unmountSangong(tester));
  await pumpSangongPage(tester, runtime,
      SangongAgentHallPage(featureContext: context, section: section),
      dark: dark, platform: platform);
  return runtime;
}

void main() {
  for (final dark in [false, true]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('fixed hall opens directly without a picker $dark $platform',
          (tester) async {
        final api = SangongTestApi()..respond = _response;
        await _pump(tester, api, dark: dark, platform: platform);
        expect(find.text('所属厅：a 厅'), findsOneWidget);
        expect(find.text('选择厅'), findsNothing);
        expect(find.text('切换厅'), findsNothing);
        expect(api.calls.last.query?['tenantId'], 'a');
        expect(tester.takeException(), isNull);
      });
    }
    for (final ids in [
      <String>[],
      ['a', 'b'],
      ['b']
    ]) {
      testWidgets('invalid fixed hall refuses private requests $ids dark=$dark',
          (tester) async {
        final api = SangongTestApi()
          ..respond = (call) =>
              call.path.endsWith('/tenants') ? _choices(ids) : _response(call);
        await _pump(tester, api, dark: dark);
        expect(find.text('重试'), findsOneWidget);
        expect(find.text('切换厅'), findsNothing);
        expect(api.calls.every((c) => c.path.endsWith('/tenants')), isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('personal view keeps its fixed hall and balance', (tester) async {
    final api = SangongTestApi()..respond = _response;
    await _pump(tester, api, section: 'personal');
    expect(find.byType(SangongAgentMemberDetailPage), findsOneWidget);
    expect(find.text('所属厅：a 厅'), findsOneWidget);
    expect(find.text('111'), findsOneWidget);
    expect(find.text('切换厅'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('write remains pinned to the group hall', (tester) async {
    final command = Completer<dynamic>();
    final api = SangongTestApi()
      ..respond =
          (call) => call.method == 'POST' ? command.future : _response(call);
    await _pump(tester, api);
    final runtime =
        SangongScope.read(tester.element(find.byType(SangongAgentTeamPage)));
    final claim = runtime.agent.claimSangongRebate();
    await flushSangong(tester);
    final write = api.calls.last;
    expect(write.body?['tenantId'], 'a');
    expect(write.body?['expectedTenantId'], 'a');
    expect(find.text('切换厅'), findsNothing);
    command.complete(sangongReceipt(write, {'amount': 0}));
    await completeSangongRequest(tester, claim);
  });
  testWidgets('late discovery after leaving cannot open private data',
      (tester) async {
    final delayed = Completer<dynamic>();
    final api = SangongTestApi()..respond = (_) => delayed.future;
    await _pump(tester, api);
    await unmountSangong(tester);
    delayed.complete(_choices());
    await flushSangong(tester);
    expect(api.calls.length, 1);
    expect(tester.takeException(), isNull);
  });
}
