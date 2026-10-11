import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/live/models/live_tip_currency.dart';
import 'package:openim/pages/group_features/live/tipping/live_tip_balance.dart';
import 'package:openim/services/fund_models.dart';

const usdt = LiveTipCurrency('USDT', 'USDT', 6);
const yuan = LiveTipCurrency('BI99', '元', 2);

List<FundBalance> balances(String usdt, String yuan) => [
      for (final entry
          in {FundCurrency.usdt: usdt, FundCurrency.bi99: yuan}.entries)
        FundBalance(
            currency: entry.key,
            available: FundAmount.parse(entry.value, entry.key),
            frozen: FundAmount.parse('500', entry.key))
    ];

void main() {
  test(
      'one snapshot preserves currency precision, excludes frozen funds and coalesces reads',
      () async {
    var calls = 0;
    final reply = Completer<List<FundBalance>>();
    final state = LiveTipBalance(
        current: () => true,
        load: () {
          calls++;
          return reply.future;
        });
    addTearDown(state.dispose);
    final first = state.refresh();
    await state.refresh();
    expect(calls, 1);
    expect(state.forCurrency(usdt), isNull);
    reply.complete(balances('1.234567', '98.01'));
    await first;
    expect(state.forCurrency(usdt)!.available.displayDecimal, '1.234567');
    expect(state.forCurrency(yuan)!.available.displayDecimal, '98.01');
    expect(state.forCurrency(const LiveTipCurrency('BI99', '元', 6)), isNull);
    expect(state.forCurrency(const LiveTipCurrency('99', '99', 2)), isNull);
  });

  test('background invalidates old reads; foreground owns a fresh snapshot',
      () async {
    final replies = <Completer<List<FundBalance>>>[];
    final state = LiveTipBalance(
        current: () => true,
        load: () {
          final reply = Completer<List<FundBalance>>();
          replies.add(reply);
          return reply.future;
        });
    addTearDown(state.dispose);
    final first = state.refresh();
    state.setActive(false);
    expect(state.forCurrency(usdt), isNull);
    state.setActive(true);
    final second = state.refresh();
    replies.last.complete(balances('5', '6'));
    await second;
    replies.first.complete(balances('100', '200'));
    await first;
    expect(state.forCurrency(usdt)!.available.decimal, '5');
  });

  for (final close in [false, true]) {
    test('late result after ${close ? 'dispose' : 'account change'} is ignored',
        () async {
      var current = true;
      final reply = Completer<List<FundBalance>>();
      final state =
          LiveTipBalance(current: () => current, load: () => reply.future);
      final read = state.refresh();
      if (close) {
        state.dispose();
      } else {
        current = false;
      }
      reply.complete(balances('100', '200'));
      await read;
      expect(state.forCurrency(usdt), isNull);
      if (!close) state.dispose();
    });
  }

  testWidgets('timeout exposes retry without showing a made-up zero balance',
      (tester) async {
    final reply = Completer<List<FundBalance>>();
    var calls = 0;
    final state = LiveTipBalance(
        current: () => true,
        load: () {
          return ++calls == 1 ? reply.future : Future.value(balances('0', '2'));
        });
    addTearDown(state.dispose);
    final first = state.refresh();
    await tester.pump(const Duration(seconds: 11));
    await first;
    expect(state.failed, isTrue);
    expect(state.loading, isFalse);
    expect(state.forCurrency(usdt), isNull);
    await state.refresh();
    reply.complete(balances('100', '200'));
    await tester.pump();
    expect(state.failed, isFalse);
    expect(state.forCurrency(usdt)!.available.displayDecimal, '0.00');
  });
}
