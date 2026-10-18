import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/compensation/models/compensation_detail.dart';
import 'package:openim/pages/fund/compensation/state/compensation_controller.dart';
import 'support.dart';

void main() {
  test(
      'pool label stays distinct from personal amount and hides unclaimed amount',
      () {
    final d = CompensationDetail.fromJson({...response(), 'amount': '88.66'});
    expect(d.poolLabel, '300万99币');
    expect(d.amount, isNull);
    expect(
        () => CompensationDetail.fromJson(
            {...response(state: 'claimed'), 'arrivalStatus': 'pending'}),
        throwsFormatException);
  });
  test('only server eligible state can claim and duplicate taps submit once',
      () async {
    final source = FakeSource();
    final c = CompensationController(source: source, id: 'activity-one');
    addTearDown(c.dispose);
    await c.claim();
    expect(source.claims, 0);
    await c.refresh();
    final pending = Completer<CompensationDetail>();
    source.claimAction = () => pending.future;
    final first = c.claim();
    await c.claim();
    expect(source.claims, 1);
    expect(c.state, CompensationState.unclaimed);
    pending.complete(CompensationDetail.fromJson(response(state: 'claimed')));
    await first;
    expect(c.detail!.amount, '88.66');
    expect(source.notified, 1);
    expect(c.canClaim, false);
  });
  test('deadline clamps at zero and preserves claimed receipt after expiry',
      () async {
    var elapsed = Duration.zero;
    final source = FakeSource();
    final c = CompensationController(
        source: source, id: 'activity-one', elapsed: () => elapsed);
    addTearDown(c.dispose);
    await c.refresh();
    elapsed = const Duration(days: 4);
    c.tick();
    expect(c.remaining, Duration.zero);
    expect(c.state, CompensationState.ended);
    await c.claim();
    expect(source.claims, 0);
    source.current =
        CompensationDetail.fromJson(response(state: 'claimed', ended: true));
    await c.refresh();
    expect(c.state, CompensationState.claimed);
    expect(c.detail!.receiptID, 'fo-receipt');
  });
  test('lost write response recovers by querying, never fabricates success',
      () async {
    final source = FakeSource();
    final c = CompensationController(source: source, id: 'activity-one');
    addTearDown(c.dispose);
    await c.refresh();
    source.claimAction = () async {
      source.failRead = true;
      throw Exception('timeout');
    };
    await c.claim();
    expect(c.uncertain, true);
    expect(c.canClaim, false);
    expect(c.detail!.amount, isNull);
    await c.claim();
    expect(source.claims, 1);
    source.failRead = false;
    source.current = CompensationDetail.fromJson(response(state: 'claimed'));
    await c.refresh();
    expect(c.uncertain, false);
    expect(c.state, CompensationState.claimed);
    expect(source.notified, 1);
  });
  test('ineligible cannot initiate claim', () async {
    final source = FakeSource()
      ..current = CompensationDetail.fromJson(response(state: 'ineligible'));
    final c = CompensationController(source: source, id: 'activity-one');
    addTearDown(c.dispose);
    await c.refresh();
    await c.claim();
    expect(source.claims, 0);
  });
  test('account switch and disposed recovery cannot publish stale results',
      () async {
    final source = FakeSource();
    final c = CompensationController(source: source, id: 'activity-one');
    await c.refresh();
    final pending = Completer<CompensationDetail>();
    source.readAction = () => pending.future;
    final work = c.refresh();
    source.valid = false;
    pending.complete(CompensationDetail.fromJson(response(state: 'claimed')));
    await work;
    expect(c.detail, isNull);
    expect(source.notified, 0);
    c.dispose();
  });
  test('background invalidates claim permission until server recalibration',
      () async {
    final source = FakeSource();
    final c = CompensationController(source: source, id: 'activity-one');
    addTearDown(c.dispose);
    await c.refresh();
    c.suspend();
    expect(c.canClaim, false);
    await c.refresh();
    expect(c.canClaim, true);
  });
}
