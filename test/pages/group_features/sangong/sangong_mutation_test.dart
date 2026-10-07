import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'sangong_test_support.dart';

void main() {
  final unknown = isA<GroupFeatureException>()
      .having((error) => error.unknownResult, 'unknownResult', isTrue);
  testWidgets('empty balance result never turns into a successful zero balance',
      (tester) async {
    final api = SangongTestApi()..respond = (_) => <String, dynamic>{};
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    await rejectSangongRequest(
        tester, runtime.admin.credit(imUserId: 'winter', amount: 10), unknown);
    await rejectSangongRequest(
        tester, runtime.admin.debit(imUserId: 'winter', amount: 10), unknown);
    expect(api.count('/commands/wallet.adjust'), 2);
    api.respond =
        (call) => sangongReceipt(call, {'imUserId': 'winter', 'balance': 0});
    final result = await completeSangongRequest(
        tester, runtime.admin.credit(imUserId: 'winter', amount: 10));
    expect(result.balance, 0,
        reason: 'An explicit server balance of zero is valid.');
  });
  testWidgets(
      'start and stop require a confirmed session state; unknown writes are not retried',
      (tester) async {
    final api = SangongTestApi()..respond = (_) => <String, dynamic>{};
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    await rejectSangongRequest(tester, runtime.admin.startSession(), unknown);
    await rejectSangongRequest(
        tester, runtime.admin.stopSession(sessionId: 2), unknown);
    expect(api.count('/commands/session.start'), 1);
    expect(api.count('/commands/session.stop'), 1);
    api.respond = (call) => sangongReceipt(call,
        {'status': call.path.endsWith('/session.start') ? 'running' : 'idle'});
    expect(
        (await completeSangongRequest(tester, runtime.admin.startSession()))
            .status,
        'running');
    expect(
        (await completeSangongRequest(
                tester, runtime.admin.stopSession(sessionId: 2)))
            .status,
        'idle');
  });
  testWidgets(
      'empty cutoff result is unknown; explicitly confirmed zero bets may succeed',
      (tester) async {
    final api = SangongTestApi()..respond = (_) => <String, dynamic>{};
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    await rejectSangongRequest(
        tester, runtime.admin.submitBets(roundId: 18), unknown);
    expect(api.count('/commands/round.close'), 1);
    api.respond = (call) => sangongReceipt(call, {
          'refundedAmount': 0,
          'state': {
            ...sangongState(2),
            'round': {'id': 18, 'betWindowCloseAt': '2026-10-04T10:01:00Z'},
            'placed': {'betCount': 0},
            'collectionReady': true,
          },
        });
    final result = await completeSangongRequest(
        tester, runtime.admin.submitBets(roundId: 18));
    expect(result.placedCount, 0);
    expect(result.round!.hasBetWindowClose, isTrue);
  });
  testWidgets(
      'transfer success requires actual reference and resulting balance',
      (tester) async {
    final api = SangongTestApi()..respond = (_) => <String, dynamic>{};
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    await rejectSangongRequest(
        tester,
        runtime.agent.transferToChild(toImUserId: 'winter', amount: 10),
        unknown);
    expect(api.count('/commands/agent.transfer'), 1);
    api.respond = (call) =>
        sangongReceipt(call, {'referenceId': 'transfer-42', 'fromBalance': 0});
    final result = await completeSangongRequest(tester,
        runtime.agent.transferToChild(toImUserId: 'winter', amount: 10));
    expect(result['referenceId'], 'transfer-42');
    expect(result['fromBalance'], 0);
  });
}
