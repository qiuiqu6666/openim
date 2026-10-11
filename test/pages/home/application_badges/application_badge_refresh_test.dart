import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/home/application_badges/application_badge_refresh.dart';

void main() {
  testWidgets('bursts share a read and queue one later calibration',
      (tester) async {
    final replies = <Completer<void>>[];
    final errors = <Object>[];
    final refresh = ApplicationBadgeRefresh(
      load: () {
        final reply = Completer<void>();
        replies.add(reply);
        return reply.future;
      },
      isCurrent: () => true,
      onError: errors.add,
    );
    for (var i = 0; i < 10; i++) {
      refresh.request();
    }
    await tester.pump(const Duration(milliseconds: 80));
    expect(replies, hasLength(1));
    for (var i = 0; i < 10; i++) {
      refresh.request();
    }
    await tester.pump(const Duration(milliseconds: 80));
    expect(replies, hasLength(1));
    replies.first.complete();
    await tester.pump();
    expect(replies, hasLength(2));
    replies.last.complete();
    await tester.pump();
    expect(errors, isEmpty);
    refresh.close();
  });

  testWidgets('continuous requests do not postpone the first read forever',
      (tester) async {
    var reads = 0;
    final refresh = ApplicationBadgeRefresh(
      load: () async => reads++,
      isCurrent: () => true,
      onError: (_) {},
    );
    refresh.request();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      refresh.request();
    }
    expect(reads, 1);
    refresh.close();
  });

  testWidgets('close cancels a timer and queued follow-up', (tester) async {
    final reply = Completer<void>();
    var reads = 0;
    final refresh = ApplicationBadgeRefresh(
      load: () {
        reads++;
        return reply.future;
      },
      isCurrent: () => true,
      onError: (_) => fail('closed errors must not reach the page'),
    );
    refresh.request();
    await tester.pump(const Duration(milliseconds: 80));
    refresh.request();
    await tester.pump(const Duration(milliseconds: 80));
    refresh.close();
    refresh.request();
    reply.completeError(StateError('late failure'));
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 1);
  });

  testWidgets('failure recovers and expired sessions cannot start requests',
      (tester) async {
    var reads = 0, current = true;
    final errors = <Object>[];
    final refresh = ApplicationBadgeRefresh(
      load: () async {
        if (++reads == 1) throw StateError('offline');
      },
      isCurrent: () => current,
      onError: errors.add,
    );
    refresh.request();
    await tester.pump(const Duration(milliseconds: 80));
    expect(errors, hasLength(1));
    refresh.request();
    await tester.pump(const Duration(milliseconds: 80));
    expect(reads, 2);
    refresh.request();
    current = false;
    await tester.pump(const Duration(milliseconds: 80));
    refresh.request();
    await tester.pump(const Duration(milliseconds: 80));
    expect(reads, 2);
    refresh.close();
  });
}
