import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/editing/batch_read/conversation_batch_read_api.dart';
import 'package:openim/pages/conversation/editing/batch_read/conversation_batch_read_runner.dart';

void main() {
  test('3000 server conversations use 30 batch writes and one snapshot',
      () async {
    var prepares = 0, writes = 0, confirmed = 0;
    final progress = <(int, int)>[];
    final failed = await runServerConversationReadBatch(
      scope: 'group',
      prepare: (scope, ids) async {
        prepares++;
        expect(scope, 'group');
        expect(ids, isNull);
        return List.generate(3000, (i) => BatchReadTarget('sg_$i', 10));
      },
      apply: (targets) async {
        writes++;
        expect(targets.length, 100);
        return targets.map((t) => t.conversationID).toSet();
      },
      isCurrent: () => true,
      progress: (done, total) => progress.add((done, total)),
      confirmed: (targets) => confirmed += targets.length,
    );
    expect((prepares, writes, confirmed, failed), (1, 30, 3000, 0));
    expect(progress.last, (3000, 3000));
  });

  test('selected IDs are deduplicated and all snapshots precede writes',
      () async {
    var prepares = 0;
    final ids = List.generate(1500, (i) => 'si_$i');
    await runServerConversationReadBatch(
      conversationIDs: [...ids, ...ids],
      prepare: (scope, ids) async {
        prepares++;
        expect(ids!.length, prepares == 1 ? 1000 : 500);
        return ids.map((id) => BatchReadTarget(id, 5)).toList();
      },
      apply: (targets) async {
        expect(prepares, 2);
        return targets.map((t) => t.conversationID).toSet();
      },
      isCurrent: () => true,
      progress: (_, __) {},
      confirmed: (_) {},
    );
  });

  test('only failed fixed targets retry and permanent failures are counted',
      () async {
    var writes = 0;
    final confirmed = <String>[];
    final failures = await runServerConversationReadBatch(
      scope: 'single',
      prepare: (_, __) async => [
        const BatchReadTarget('si_a', 5),
        const BatchReadTarget('si_b', 6),
      ],
      apply: (targets) async {
        writes++;
        if (writes == 1) return {'si_a'};
        expect(targets.single.conversationID, 'si_b');
        expect(targets.single.hasReadSeq, 6);
        return {};
      },
      isCurrent: () => true,
      progress: (_, __) {},
      confirmed: (rows) => confirmed.addAll(rows.map((r) => r.conversationID)),
    );
    expect((writes, failures), (2, 1));
    expect(confirmed, ['si_a']);
  });

  test('account switch suppresses acknowledgement and remaining batches',
      () async {
    var active = true, writes = 0, confirmations = 0;
    await runServerConversationReadBatch(
      scope: 'all',
      prepare: (_, __) async =>
          List.generate(200, (i) => BatchReadTarget('sg_$i', 5)),
      apply: (rows) async {
        writes++;
        active = false;
        return rows.map((r) => r.conversationID).toSet();
      },
      isCurrent: () => active,
      progress: (_, __) {},
      confirmed: (_) => confirmations++,
    );
    expect((writes, confirmations), (1, 0));
  });

  test('ambiguous timeout is not retried with a new snapshot', () async {
    var writes = 0;
    await expectLater(
        runServerConversationReadBatch(
          scope: 'single',
          prepare: (_, __) async => [const BatchReadTarget('si_a', 5)],
          apply: (_) async {
            writes++;
            throw TimeoutException('unknown outcome');
          },
          isCurrent: () => true,
          progress: (_, __) {},
          confirmed: (_) => fail('must not clear unacknowledged state'),
        ),
        throwsA(isA<TimeoutException>()));
    expect(writes, 1);
  });
}
