import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import '../sangong_test_support.dart';

void main() {
  final reads = <String, Future<dynamic> Function(SangongRuntime)>{
    'team members': (runtime) => runtime.agent.fetchSangongTeamMembers(),
    'team dashboard': (runtime) => runtime.agent.fetchSangongTeamDashboard(),
    'member dashboard': (runtime) =>
        runtime.agent.fetchSangongMemberDashboard(imUserId: 'winter'),
    'member daily': (runtime) =>
        runtime.agent.fetchSangongMemberDaily(imUserId: 'winter'),
  };

  for (final read in reads.entries) {
    testWidgets('${read.key} rejects an empty success payload', (tester) async {
      final api = SangongTestApi()..respond = (_) => <String, dynamic>{};
      final runtime = SangongRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      await rejectSangongRequest(
          tester, read.value(runtime), isA<FormatException>());
      expect(api.calls, hasLength(1));
    });
  }

  testWidgets('valid empty lists and omitted optional metrics remain valid',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => {
            'code': 0,
            'data': call.path.endsWith('/team')
                ? {'version': 1, 'nextBeforeId': 0, 'members': []}
                : call.path.endsWith('/team-summary')
                    ? {
                        'summary': <String, dynamic>{},
                        'version': 1,
                        'nextBeforeId': 0,
                        'members': []
                      }
                    : call.path.endsWith('/member')
                        ? {
                            'member': {'imUserId': 'winter'}
                          }
                        : {'days': []},
          };
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    for (final read in reads.values) {
      await completeSangongRequest(tester, read(runtime));
    }
    expect(api.calls, hasLength(4));
  });

  testWidgets('members reject invalid list rows and malformed numeric fields',
      (tester) async {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    for (final row in [
      null,
      <String, dynamic>{},
      {'imUserId': 'winter', 'balance': 'broken'},
      {'imUserId': 'winter', 'balance': double.infinity},
    ]) {
      api.respond = (_) => {
            'version': 1,
            'nextBeforeId': 0,
            'members': [row]
          };
      await rejectSangongRequest(tester,
          runtime.agent.fetchSangongTeamMembers(), isA<FormatException>());
    }
    api.respond = (_) => {
          'version': 1,
          'nextBeforeId': 0,
          'members': [
            {'imUserId': 'winter', 'balance': '0', 'pendingRebate': 0}
          ]
        };
    final members = await completeSangongRequest(
        tester, runtime.agent.fetchSangongTeamMembers());
    expect(members.members.single.balance, 0);
  });

  testWidgets('dashboard rejects missing containers and invalid summary values',
      (tester) async {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    for (final response in [
      {'version': 1, 'nextBeforeId': 0, 'members': []},
      {'summary': <String, dynamic>{}},
      {
        'summary': {'totalBalance': 'NaN'},
        'version': 1,
        'nextBeforeId': 0,
        'members': []
      },
      {
        'summary': {'totalBalance': false},
        'version': 1,
        'nextBeforeId': 0,
        'members': []
      },
      {
        'summary': <String, dynamic>{},
        'version': 1,
        'nextBeforeId': 0,
        'members': [],
        'batch': []
      },
    ]) {
      api.respond = (_) => response;
      await rejectSangongRequest(tester,
          runtime.agent.fetchSangongTeamDashboard(), isA<FormatException>());
    }
  });

  testWidgets('member dashboard rejects a different identity', (tester) async {
    final api = SangongTestApi()
      ..respond = (_) => {
            'member': {'imUserId': 'other'}
          };
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    await rejectSangongRequest(
        tester,
        runtime.agent.fetchSangongMemberDashboard(imUserId: 'winter'),
        isA<FormatException>());
  });

  testWidgets('daily records reject malformed rows and preserve explicit zeros',
      (tester) async {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    for (final response in [
      {'days': 'broken'},
      {
        'days': [null]
      },
      {
        'days': [<String, dynamic>{}]
      },
      {
        'days': [
          {'businessDate': '2026-10-06', 'balance': 'oops'}
        ]
      },
    ]) {
      api.respond = (_) => response;
      await rejectSangongRequest(
          tester,
          runtime.agent.fetchSangongMemberDaily(imUserId: 'winter'),
          isA<FormatException>());
    }
    api.respond = (_) => {
          'days': [
            {'businessDate': '2026-10-06', 'balance': 0}
          ]
        };
    final result = await completeSangongRequest(
        tester, runtime.agent.fetchSangongMemberDaily(imUserId: 'winter'));
    expect((result['days'] as List).single['balance'], 0);
  });

  testWidgets(
      'rebate claim keeps the amount contract and rejects unknown results',
      (tester) async {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    for (final response in [
      <String, dynamic>{},
      {'amount': 'broken'},
      {'amount': double.infinity},
      {'amount': -1},
      <dynamic>[],
    ]) {
      api.respond = (_) => response;
      await rejectSangongRequest(
          tester,
          runtime.agent.claimSangongRebate(),
          isA<GroupFeatureException>()
              .having((error) => error.unknownResult, 'unknownResult', isTrue));
    }
    api.respond = (call) => {
          'ok': true,
          'requestId': call.body!['requestId'],
          'data': {'amount': '0'}
        };
    final result = await completeSangongRequest(
        tester, runtime.agent.claimSangongRebate());
    expect(result['amount'], '0');
    expect(api.count('/commands/rebate.claim'), 6);
  });

  testWidgets('nonfinite transfer quantities never reach the transport',
      (tester) async {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    for (final amount in [double.nan, double.infinity]) {
      await rejectSangongRequest(
          tester,
          runtime.agent.transferToChild(toImUserId: 'winter', amount: amount),
          isA<ArgumentError>());
    }
    expect(api.calls, isEmpty);
  });
}
