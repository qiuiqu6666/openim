import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'sangong_test_support.dart';

void main() {
  final unknown = isA<GroupFeatureException>()
      .having((error) => error.unknownResult, 'unknown result', isTrue);

  testWidgets('empty max-negative ack cannot claim success or retry the write',
      (tester) async {
    final api = SangongTestApi()..respond = (_) => <String, dynamic>{};
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    await rejectSangongRequest(
        tester,
        runtime.admin.setUserMaxNegative(userId: 19, maxNegative: 500),
        unknown);
    expect(api.count('/max-negative'), 1);
    expect(api.count('/user-detail'), 0);
  });

  testWidgets('returned identity and amount must confirm the requested setting',
      (tester) async {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    for (final body in [
      {
        'user': {'userId': 20, 'maxNegative': 500}
      },
      {
        'user': {'userId': 19, 'maxNegative': 100}
      },
      {
        'user': {'userId': 19}
      },
      {'ok': true},
    ]) {
      api.respond = (_) => body;
      await rejectSangongRequest(
          tester,
          runtime.admin.setUserMaxNegative(userId: 19, maxNegative: 500),
          unknown);
    }
    api.respond = (_) => {
          'user': {'userId': 19, 'maxNegative': 0}
        };
    final result = await completeSangongRequest(
        tester, runtime.admin.setUserMaxNegative(userId: 19, maxNegative: 0));
    expect(result['user']['maxNegative'], 0,
        reason: 'An explicitly confirmed zero disables the negative limit.');
  });

  testWidgets('legacy ack uses one authoritative read in the same tenant',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.method == 'PUT'
          ? {'ok': true}
          : {
              'user': {
                'userId': 19,
                'imUserId': 'im_target',
                'maxNegative': 500,
              }
            };
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    final result = await completeSangongRequest(
        tester,
        runtime.admin.setUserMaxNegative(
            userId: 19, maxNegative: 500, imUserId: 'im_target'));
    expect(result['user']['maxNegative'], 500);
    expect(api.count('/max-negative'), 1);
    expect(api.count('/user-detail'), 1);
    expect(api.calls.last.query, {'imUserId': 'im_target'});
    expect(
        api.calls.every((call) =>
            call.headers?['X-Tenant-Id'] == expectedSangongRequestTenant()),
        isTrue);
  });

  testWidgets('unconfirmed readback and changed account do not save locally',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.method == 'PUT'
          ? {}
          : {
              'user': {
                'userId': 19,
                'imUserId': 'different_user',
                'maxNegative': 500,
              }
            };
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    await rejectSangongRequest(
        tester,
        runtime.admin.setUserMaxNegative(
            userId: 19, maxNegative: 500, imUserId: 'im_target'),
        unknown);
    expect(api.count('/max-negative'), 1);
    expect(api.count('/user-detail'), 1);

    var current = true;
    final fencedApi = SangongTestApi()
      ..respond = (call) {
        if (call.method == 'PUT') return {'ok': true};
        // An otherwise valid read must not confirm a previous account's write.
        current = false;
        return {
          'user': {'userId': 19, 'maxNegative': 500}
        };
      };
    final fenced =
        SangongRuntime(sangongTestContext(fencedApi, current: () => current));
    addTearDown(fenced.dispose);
    await rejectSangongRequest(
        tester,
        fenced.admin.setUserMaxNegative(
            userId: 19, maxNegative: 500, imUserId: 'im_target'),
        unknown);
    expect(fencedApi.count('/max-negative'), 1);
    expect(fencedApi.count('/user-detail'), 1);
  });
}
