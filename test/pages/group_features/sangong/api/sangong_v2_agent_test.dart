import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/sangong/api/sangong_v2_api.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import '../sangong_test_support.dart';

void main() {
  testWidgets('agent context is bound to the current group and login',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (_) => {
            'ok': true,
            'data': {
              'showAgentEntry': true,
              'tenantId': 'game-tenant',
              'agentImGroupId': '@agent#room',
              'agentImUserId': 'owner',
              'imGroupGameId': 'game-room',
              'agent': {'userId': 7, 'balance': 42},
            }
          };
    final runtime = SangongRuntime(sangongTestContext(api,
        groupID: '@agent#room', tenantID: '', canManage: false));
    addTearDown(runtime.dispose);
    final context = await completeSangongRequest(
        tester, runtime.agent.fetchEntryContext('@agent#room'));
    expect(context.tenantId, 'game-tenant');
    expect(context.balance, 42);
    expect(api.calls.single.path,
        '/sangong/api/v2/agent-groups/%40agent%23room/context');
    expect(api.calls.single.headers, isEmpty);
    expect(api.calls.single.useBearerAuth, isTrue);
    await rejectSangongRequest(
        tester,
        runtime.agent.fetchEntryContext('different-group'),
        isA<ArgumentError>());
    expect(api.calls, hasLength(1));
  });

  testWidgets('team pagination never silently truncates or combines versions',
      (tester) async {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    api.respond = (call) => {
          'version': 4,
          'nextBeforeId': call.query?['beforeId'] == null ? 9 : 0,
          'members': [
            {'imUserId': call.query?['beforeId'] == null ? 'first' : 'second'}
          ],
        };
    final team = await completeSangongRequest(
        tester, runtime.agent.fetchSangongTeamMembers());
    expect(team.members.map((m) => m.imUserId), ['first', 'second']);
    expect(api.calls.last.query?['beforeId'], 9);
    api.respond = (call) => {
          'version': call.query?['beforeId'] == null ? 4 : 5,
          'nextBeforeId': call.query?['beforeId'] == null ? 9 : 0,
          'members': <dynamic>[],
        };
    await rejectSangongRequest(
        tester, runtime.agent.fetchSangongTeamMembers(), isA<StateError>());
  });

  testWidgets('command success requires the matching idempotency receipt',
      (tester) async {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    final v2 = SangongV2Api(runtime.http, agent: true);
    api.respond = (call) => {
          'errCode': 0,
          'data': {
            'ok': true,
            'requestId': call.body!['requestId'],
            'data': {'amount': 7, 'balance': 49},
          }
        };
    final result = await completeSangongRequest(
        tester, v2.command('rebate.claim', {}, requestId: 'claim-1'));
    expect(result['balance'], 49);
    expect(api.calls.single.body, {
      'requestId': 'claim-1',
      'input': {},
      'expectedTenantId': runtime.http.tenantId
    });
    api.respond = (_) => {
          'ok': true,
          'requestId': 'other',
          'data': {'amount': 7}
        };
    await rejectSangongRequest(
        tester,
        v2.command('rebate.claim', {}, requestId: 'claim-1'),
        isA<GroupFeatureException>()
            .having((e) => e.unknownResult, 'unknown', true));
  });

  testWidgets('ordinary or history-revoked accounts cannot use agent endpoints',
      (tester) async {
    final api = SangongTestApi();
    final runtime =
        SangongRuntime(sangongTestContext(api, canViewHistory: false));
    addTearDown(runtime.dispose);
    await rejectSangongRequest(
        tester,
        runtime.agent.fetchSangongMemberDaily(imUserId: 'owner'),
        isA<Exception>());
    runtime.updateContext(sangongTestContext(api,
        capabilityVersion: 2,
        canConfigure: false,
        canManage: false,
        canOpenAgent: false));
    await rejectSangongRequest(
        tester, runtime.agent.fetchSangongTeamMembers(), isA<Exception>());
    expect(api.calls, isEmpty);
  });
}
