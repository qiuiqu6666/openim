import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chat_history_loader_test.dart' show Harness, msg;

void main() {
  test('refresh before initial load still shows loading', () async {
    final pending = Completer<AdvancedMessage>();
    final h = Harness(({required count, startMsg}) => pending.future);
    addTearDown(h.loader.close);
    final refresh = h.loader.refresh();
    expect(h.loader.pagingLoading, isTrue);
    pending.complete(AdvancedMessage(messageList: [], isEnd: true));
    await refresh;
    expect(h.loader.pagingLoading, isFalse);
  });

  test('background failure retains recovery and explicit paging stays visible',
      () async {
    var reads = 0;
    final pending = Completer<AdvancedMessage>();
    final h = Harness(({required count, startMsg}) {
      reads++;
      if (reads == 2) return Future.error(StateError('offline'));
      if (reads == 4) return pending.future;
      return Future.value(
          AdvancedMessage(messageList: [msg('old', 2)], isEnd: false));
    });
    addTearDown(h.loader.close);
    await h.loader.loadOlder();
    await h.loader.refresh();
    expect(h.loader.error, isNotNull);
    expect(h.values.single.clientMsgID, 'old');
    await h.loader.retry();
    expect(h.loader.error, isNull);
    final older = h.loader.loadOlder();
    expect(h.loader.loading, isTrue);
    expect(h.loader.pagingLoading, isTrue);
    pending
        .complete(AdvancedMessage(messageList: [msg('older', 1)], isEnd: true));
    await older;
    expect(h.values.map((m) => m.clientMsgID), ['older', 'old']);
  });

  test('ended history refresh stays busy without showing paging loader',
      () async {
    final pending = Completer<AdvancedMessage>();
    var reads = 0;
    final h = Harness(({required count, startMsg}) => ++reads == 1
        ? Future.value(
            AdvancedMessage(messageList: [msg('old', 1)], isEnd: true))
        : pending.future);
    addTearDown(h.loader.close);
    final initial = h.loader.loadOlder();
    expect(h.loader.pagingLoading, isTrue);
    await initial;
    expect(h.loader.hasMore, isFalse);
    final refresh = h.loader.refresh();
    expect(h.loader.loading, isTrue);
    expect(h.loader.pagingLoading, isFalse);
    pending.complete(AdvancedMessage(
        messageList: [msg('old', 1), msg('new', 2)], isEnd: true));
    await refresh;
    expect(h.values.map((m) => m.clientMsgID), ['old', 'new']);
    expect(h.loader.loading, isFalse);
    expect(h.loader.pagingLoading, isFalse);
    await h.loader.loadOlder();
    expect(reads, 2);
  });
}
