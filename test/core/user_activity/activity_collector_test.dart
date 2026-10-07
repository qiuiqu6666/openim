import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/user_activity/activity_collector.dart';

void main() {
  const first =
      (accountID: 'first', token: 'token-1', endpoint: 'https://chat.invalid');
  const second =
      (accountID: 'second', token: 'token-2', endpoint: 'https://chat.invalid');
  var now = DateTime(2026, 10, 7);
  var id = 0;
  ActivityCollector build(ActivityUpload upload) => ActivityCollector(
      upload: upload, newID: () => 'activity-${++id}', now: () => now);
  setUp(() {
    now = DateTime(2026, 10, 7);
    id = 0;
  });
  test('late old account upload cannot consume the new account queue',
      () async {
    final pending = Completer<bool>();
    final batches = <ActivitySession>[];
    final c = build((owner, batch) {
      batches.add(owner);
      return pending.future;
    });
    c.bind(first);
    final sending = c.flush();
    c.bind(second);
    final newCount = c.pendingCount;
    pending.complete(true);
    await sending;
    expect(c.owner, second);
    expect(c.pendingCount, newCount);
    expect(batches, [first]);
  });
  test('backoff retries identical events, with bounded queue and no free text',
      () async {
    final batches = <Map<String, Object>>[];
    var accept = false;
    final c = build((_, batch) async {
      batches.add(batch);
      return accept;
    });
    c.bind(first);
    c.action('submit_withdraw',
        operationID: 'request-123', clientOrderID: 'invalid secret');
    await c.flush();
    await c.flush();
    expect(batches.length, 1);
    now = now.add(const Duration(seconds: 30));
    accept = true;
    await c.flush();
    expect(batches[0]['events'], batches[1]['events']);
    expect(c.pendingCount, 0);
    final rows = batches[0]['events'] as List;
    expect(rows.last.containsKey('clientOrderID'), false);
    c.action('password=secret');
    expect(c.pendingCount, 0);
    for (var i = 0; i < 300; i++) {
      c.action('message_text');
    }
    expect(c.pendingCount, 200);
  });
  test('background stops heartbeat; interaction is throttled', () async {
    final batches = <Map<String, Object>>[];
    final c = build((_, batch) async {
      batches.add(batch);
      return true;
    });
    c.bind(first);
    c.interact();
    c.interact();
    await c.flush();
    expect(
        (batches.single['events'] as List)
            .where((e) => e['kind'] == 'interaction')
            .length,
        1);
    c.setForeground(false);
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(minutes: 5));
    c.tick();
    await Future<void>.delayed(Duration.zero);
    expect(
        batches
            .expand((b) => b['events'] as List)
            .where((e) => e['kind'] == 'heartbeat'),
        isEmpty);
    c.setForeground(true);
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 30));
    c.tick();
    await Future<void>.delayed(Duration.zero);
    expect(
        batches
            .expand((b) => b['events'] as List)
            .where((e) => e['kind'] == 'heartbeat')
            .length,
        1);
  });
  test('logout discards queue and unknown pages use fixed other value',
      () async {
    final batches = <Map<String, Object>>[];
    final c = build((_, batch) async {
      batches.add(batch);
      return true;
    });
    c.bind(first);
    c.visit('https://private.invalid/secret');
    await c.flush();
    expect((batches.single['events'] as List).last['page'], 'other');
    c.action('message_file');
    c.invalidate();
    await c.flush();
    expect(c.pendingCount, 0);
    expect(c.owner, isNull);
  });
}
