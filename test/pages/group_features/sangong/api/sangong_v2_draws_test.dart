import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/api/admin/sangong_round_api.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_draw_input_format.dart';

import '../sangong_test_support.dart';

void main() {
  test('all keypad numbers preserve hundredths and decimal input remains valid',
      () {
    final runtime = SangongRuntime(sangongTestContext(SangongTestApi()));
    addTearDown(runtime.dispose);
    final api = SangongRoundApi(runtime.http);
    for (var value = 0; value < 100; value++) {
      final result = api.draws([
        SangongDrawInput(door: 1, amount: value.toString().padLeft(2, '0'))
      ]);
      expect(result.single['amountHundredths'], value == 0 ? 100 : value);
    }
    for (final entry
        in {'0.01': 1, '0.9': 90, '0.99': 99, '1.00': 100}.entries) {
      expect(api.draws([SangongDrawInput(door: 1, amount: entry.key)]).single,
          {'door': 1, 'amountHundredths': entry.value});
    }
    for (final invalid in ['', '0.00', '100', '-1', '1.01', '0.001', 'abc']) {
      expect(() => api.draws([SangongDrawInput(door: 1, amount: invalid)]),
          throwsArgumentError,
          reason: invalid);
    }
  });

  for (final resettle in [false, true]) {
    testWidgets('keypad numbers reach Go unchanged; resettle=$resettle',
        (tester) async {
      final api = SangongTestApi();
      final runtime = SangongRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      final inputs = ['90', '00', '7', '3', '88', '12']
          .indexed
          .map((entry) => SangongDrawInput(
              door: entry.$1 + 1,
              amount: SangongDrawInputFormat.normalizeForSubmit(entry.$2)))
          .toList();
      api.respond = (call) => sangongReceipt(call, {
            'round': {'id': 2, 'status': 'settled'},
            'state': {
              ...sangongState(12),
              'round': {'id': 2, 'status': 'betting'},
              'draw': {'roundId': 2, 'complete': true, 'missingDoors': []},
            },
          });
      if (resettle) {
        final result = await completeSangongRequest(tester,
            runtime.admin.resettleLastSettled(roundId: 2, draws: inputs));
        expect(result.ok, isTrue);
      } else {
        final result = await completeSangongRequest(
            tester, runtime.admin.submitDraws(inputs, roundId: 2));
        expect(result.draw.complete, isTrue);
      }
      expect(api.calls, hasLength(1));
      final call = api.calls.single;
      expect(call.path,
          endsWith('/commands/round.${resettle ? 'resettle' : 'draws'}'));
      expect(call.body?['input'], {
        'roundId': 2,
        'draws': [
          for (final entry in [90, 100, 7, 3, 88, 12].indexed)
            {'door': entry.$1 + 1, 'amountHundredths': entry.$2},
        ],
      });
    });
  }
}
