import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'sangong_test_support.dart';

void main() {
  final unknown = isA<GroupFeatureException>()
      .having((e) => e.unknownResult, 'unknown result', isTrue);
  testWidgets('empty receipt cannot claim success or repeat a limit write',
      (tester) async {
    final api = SangongTestApi()..respond = (_) => <String, dynamic>{};
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    await rejectSangongRequest(
        tester,
        runtime.admin.setUserMaxNegative(userId: 19, maxNegative: 500),
        unknown);
    expect(api.count('/commands/wallet.limit'), 1);
    expect(api.count('/user'), 0);
  });
  testWidgets('receipt identity and amount must confirm the requested limit',
      (tester) async {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    for (final data in <Map<String, dynamic>>[
      {'userId': 20, 'maxNegative': 500},
      {'userId': 19, 'maxNegative': 100},
      {'userId': 19},
      {},
    ]) {
      api.respond = (call) => sangongReceipt(call, data);
      await rejectSangongRequest(
          tester,
          runtime.admin.setUserMaxNegative(userId: 19, maxNegative: 500),
          unknown);
    }
    api.respond =
        (call) => sangongReceipt(call, {'userId': 19, 'maxNegative': 0});
    final result = await completeSangongRequest(
        tester, runtime.admin.setUserMaxNegative(userId: 19, maxNegative: 0));
    expect(result['user']['maxNegative'], 0);
  });
  testWidgets(
      'unknown receipt retains the key for an explicit retry without readback',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => {
            'ok': true,
            'requestId': 'different',
            'data': {'userId': 19, 'maxNegative': 500}
          };
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    await rejectSangongRequest(
        tester,
        runtime.admin.setUserMaxNegative(userId: 19, maxNegative: 500),
        unknown);
    final id = api.calls.single.body?['requestId'];
    api.respond =
        (call) => sangongReceipt(call, {'userId': 19, 'maxNegative': 500});
    await completeSangongRequest(
        tester, runtime.admin.setUserMaxNegative(userId: 19, maxNegative: 500));
    expect(api.calls.length, 2);
    expect(api.calls.last.body?['requestId'], id);
    expect(api.count('/user'), 0);
  });
  testWidgets('late matching receipt cannot cross an account scope',
      (tester) async {
    final reply = Completer<dynamic>();
    final api = SangongTestApi()..respond = (_) => reply.future;
    var current = true;
    final runtime =
        SangongRuntime(sangongTestContext(api, current: () => current));
    addTearDown(runtime.dispose);
    final task = runtime.admin.setUserMaxNegative(userId: 19, maxNegative: 500);
    final rejected = expectLater(task, throwsA(isA<DioException>()));
    await flushSangong(tester);
    current = false;
    reply.complete(
        sangongReceipt(api.calls.single, {'userId': 19, 'maxNegative': 500}));
    await flushSangong(tester);
    await rejected;
    expect(api.calls.length, 1);
  });
}
