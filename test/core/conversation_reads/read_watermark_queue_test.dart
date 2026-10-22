import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/conversation_reads/conversation_batch_read_api.dart';
import 'package:openim/core/conversation_reads/read_watermark_queue.dart';

void main() {
  late ReadWatermarkQueue queue;
  late Map<String, int> stored, confirmed;
  late List<List<BatchReadTarget>> calls;
  late List<Completer<Set<String>>> replies;
  late bool active;
  late int changes;
  ReadWatermarkQueue create() => ReadWatermarkQueue(
        targets: stored,
        confirmed: confirmed,
        save: (targets, ack) async {
          stored = Map.of(targets);
          confirmed = Map.of(ack);
        },
        apply: (targets) {
          expectSync(stored[targets.first.conversationID],
              greaterThanOrEqualTo(targets.first.hasReadSeq));
          calls.add(targets);
          final reply = Completer<Set<String>>();
          replies.add(reply);
          return reply.future;
        },
        isCurrent: () => active,
        changed: () => changes++,
        acknowledged: (_) {},
        onError: (_) {},
      );
  setUp(() {
    stored = {};
    confirmed = {};
    calls = [];
    replies = [];
    active = true;
    changes = 0;
    queue = create();
  });
  tearDown(() => queue.close());

  testWidgets('rejected first batch does not starve later conversation reads',
      (tester) async {
    queue.close();
    stored = {for (var i = 0; i < 101; i++) 'sg_$i': 7};
    queue = create();
    queue.kick();
    await tester.pump();
    expect(calls.single, hasLength(100));
    replies.first.complete({});
    await tester.pump();
    expect(calls, hasLength(2));
    expect(calls.last.single.conversationID, 'sg_100');
    replies.last.complete({'sg_100'});
    await tester.pump();
    expect(confirmed['sg_100'], 7);
    expect(confirmed.containsKey('sg_0'), isFalse);
    await tester.pump(const Duration(seconds: 4));
    expect(calls.last, hasLength(100));
    expect(calls.last.any((t) => t.conversationID == 'sg_100'), isFalse);
    replies.last.complete(calls.last.map((t) => t.conversationID).toSet());
    await tester.pump();
    expect(confirmed, hasLength(101));
    queue.close();
  });

  testWidgets('old completion cannot discard a newer entry; no regression',
      (tester) async {
    queue.close();
    queue = create();
    await queue.enqueue(const BatchReadTarget('sg_a', 100));
    await queue.enqueue(const BatchReadTarget('sg_a', 105));
    await queue.enqueue(const BatchReadTarget('sg_a', 90));
    expect(calls, hasLength(1));
    replies[0].complete({'sg_a'});
    await tester.pump();
    expect(calls.last.single.hasReadSeq, 105);
    expect(confirmed['sg_a'], 100);
    replies[1].complete({'sg_a'});
    await tester.pump();
    expect(confirmed['sg_a'], 105);
    expect(changes, 2);
  });

  testWidgets('timeout survives restart and retries only frozen boundary',
      (tester) async {
    queue.close();
    queue = create();
    await queue.enqueue(const BatchReadTarget('sg_a', 100));
    replies.single.completeError(TimeoutException('lost response'));
    await tester.pump();
    queue.close();
    queue = create();
    queue.kick();
    await tester.pump();
    expect(calls.last.single.hasReadSeq, 100);
    replies.last.complete({'sg_a'});
    await tester.pump();
    queue.close();
    queue = create();
    queue.kick();
    await tester.pump();
    expect(calls, hasLength(2));
    expect(queue.through('sg_a'), 100);
  });

  testWidgets('background pauses retry; resume retains original seq',
      (tester) async {
    queue.close();
    queue = create();
    await queue.enqueue(const BatchReadTarget('sg_a', 7));
    replies.single.complete({});
    await tester.pump();
    queue.setForeground(false);
    await tester.pump(const Duration(minutes: 2));
    expect(calls, hasLength(1));
    queue.setForeground(true);
    await tester.pump();
    expect(calls.last.single.hasReadSeq, 7);
    replies.last.complete({'sg_a'});
    await tester.pump();
  });

  testWidgets('account switch ignores late completion and cancels retries',
      (tester) async {
    queue.close();
    queue = create();
    await queue.enqueue(const BatchReadTarget('sg_a', 7));
    active = false;
    replies.single.complete({'sg_a'});
    await tester.pump();
    queue.kick();
    await tester.pump(const Duration(minutes: 2));
    expect(confirmed, isEmpty);
    expect(calls, hasLength(1));
  });

  testWidgets('partial acknowledgements retry only failed conversations',
      (tester) async {
    queue.close();
    queue = create();
    queue.setForeground(false);
    await queue.enqueue(const BatchReadTarget('sg_a', 10));
    await queue.enqueue(const BatchReadTarget('sg_b', 20));
    queue.setForeground(true);
    await tester.pump();
    replies.single.complete({'sg_a'});
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(calls.last.map((t) => t.conversationID), ['sg_b']);
    replies.last.complete({'sg_b'});
    await tester.pump();
  });

  test('failed storage never projects or sends an undurable read', () async {
    queue.close();
    queue = ReadWatermarkQueue(
        targets: {},
        confirmed: {},
        save: (_, __) async => throw StateError('disk'),
        apply: (_) async {
          fail('must persist first');
        },
        isCurrent: () => true,
        changed: () => changes++,
        acknowledged: (_) {},
        onError: (_) {});
    await expectLater(
        queue.enqueue(const BatchReadTarget('sg_a', 7)), throwsStateError);
    expect(queue.through('sg_a'), 0);
    expect(changes, 0);
  });
}
