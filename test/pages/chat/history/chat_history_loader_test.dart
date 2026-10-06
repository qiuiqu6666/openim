import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_history_loader.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';

Message msg(String id, int time, {int? status}) => Message(
    clientMsgID: id,
    sendTime: time,
    seq: time,
    contentType: MessageType.text,
    status: status ?? MessageStatus.succeeded);

class Harness {
  Harness(ChatHistoryReader fetch) {
    loader = ChatHistoryLoader(
      fetch: fetch,
      messages: () => values,
      replace: (next, first, refresh) {
        values = next;
        applications++;
      },
      removedIDs: removed,
      onStateChanged: () {
        states++;
      },
    );
  }
  List<Message> values = [];
  final removed = <String>{};
  int applications = 0, states = 0;
  late ChatHistoryLoader loader;
}

void main() {
  test(
      'first-page requests share one SDK call and render messages arriving during it',
      () async {
    final pending = Completer<AdvancedMessage>();
    var calls = 0;
    final h = Harness(({required count, startMsg}) {
      calls++;
      return pending.future;
    });
    h.values = [msg('seed', 1)];
    final first = h.loader.loadOlder();
    final repeated = h.loader.loadOlder();
    expect(identical(first, repeated), true);
    expect(calls, 1);
    expect(h.loader.loading, true);
    h.values.add(msg('live', 3));
    pending.complete(
        AdvancedMessage(messageList: [msg('history', 2)], isEnd: false));
    await first;
    expect(h.values.map((m) => m.clientMsgID), ['history', 'live']);
    expect(h.loader.loading, false);
    expect(h.loader.loaded, true);
  });

  test('overlapping pages are deduplicated and end prevents subsequent queries',
      () async {
    final cursors = <String?>[];
    final h = Harness(({required count, startMsg}) async {
      cursors.add(startMsg?.clientMsgID);
      return cursors.length == 1
          ? AdvancedMessage(
              messageList: [msg('b', 2), msg('c', 3)], isEnd: false)
          : AdvancedMessage(
              messageList: [msg('a', 1), msg('b', 2)], isEnd: true);
    });
    await h.loader.loadOlder();
    await h.loader.loadOlder();
    await h.loader.loadOlder();
    expect(cursors, [null, 'b']);
    expect(h.values.map((m) => m.clientMsgID), ['a', 'b', 'c']);
    expect(h.loader.hasMore, false);
  });

  test('failed first load preserves seed, completes state, and can retry',
      () async {
    var calls = 0;
    final h = Harness(({required count, startMsg}) async {
      if (++calls == 1) throw StateError('offline');
      return AdvancedMessage(messageList: [msg('fresh', 2)], isEnd: true);
    });
    h.values = [msg('seed', 1)];
    await h.loader.loadOlder();
    expect(h.loader.error, isA<StateError>());
    expect(h.loader.loading, false);
    expect(h.loader.loaded, false);
    expect(h.values.single.clientMsgID, 'seed');
    await h.loader.loadOlder();
    expect(h.loader.error, isNull);
    expect(h.values.single.clientMsgID, 'fresh');
  });

  test(
      'deleted messages and private-message deletion during query are not restored',
      () async {
    final pending = Completer<AdvancedMessage>();
    final h = Harness(({required count, startMsg}) => pending.future);
    final load = h.loader.loadOlder();
    h.removed.add('gone');
    pending.complete(AdvancedMessage(
        messageList: [msg('gone', 1), msg('kept', 2)], isEnd: true));
    await load;
    expect(h.values.single.clientMsgID, 'kept');
  });

  test('closing during a request suppresses late list and UI writes', () async {
    final pending = Completer<AdvancedMessage>();
    final h = Harness(({required count, startMsg}) => pending.future);
    final load = h.loader.loadOlder();
    final statesBeforeClose = h.states;
    h.loader.close();
    pending
        .complete(AdvancedMessage(messageList: [msg('late', 1)], isEnd: true));
    await load;
    expect(h.applications, 0);
    expect(h.states, statesBeforeClose);
    expect(await h.loader.refresh(), false);
  });

  test('clear discards both an outstanding page and its queued sync refresh',
      () async {
    final pending = Completer<AdvancedMessage>();
    var calls = 0;
    final h = Harness(({required count, startMsg}) {
      calls++;
      return pending.future;
    });
    final load = h.loader.loadOlder();
    final refresh = h.loader.refresh();
    h.loader.clear();
    h.values.clear();
    pending
        .complete(AdvancedMessage(messageList: [msg('old', 1)], isEnd: false));
    await load;
    await refresh;
    expect(calls, 1);
    expect(h.values, isEmpty);
    expect(h.loader.hasMore, false);
    expect(h.loader.loading, false);
    expect(h.loader.error, isNull);
  });

  test(
      'sync refresh waits for first load, coalesces, and keeps the older-page cursor',
      () async {
    final pending = Completer<AdvancedMessage>();
    final cursors = <String?>[];
    final h = Harness(({required count, startMsg}) async {
      cursors.add(startMsg?.clientMsgID);
      if (cursors.length == 1) return pending.future;
      if (cursors.length == 2)
        return AdvancedMessage(
            messageList: [msg('b', 2), msg('c', 3)], isEnd: false);
      return AdvancedMessage(messageList: [msg('old', 0)], isEnd: true);
    });
    final first = h.loader.loadOlder();
    final refresh = h.loader.refresh();
    final again = h.loader.refresh();
    expect(identical(refresh, again), true);
    expect(cursors.length, 1);
    pending.complete(
        AdvancedMessage(messageList: [msg('a', 1), msg('b', 2)], isEnd: false));
    await first;
    await refresh;
    expect(h.values.map((m) => m.clientMsgID), ['a', 'b', 'c']);
    await h.loader.loadOlder();
    expect(cursors, [null, null, 'a']);
  });

  test('sync completing after an empty first page re-enables older pagination',
      () async {
    final cursors = <String?>[];
    final h = Harness(({required count, startMsg}) async {
      cursors.add(startMsg?.clientMsgID);
      if (cursors.length == 1)
        return AdvancedMessage(messageList: [], isEnd: true);
      if (cursors.length == 2)
        return AdvancedMessage(messageList: [msg('b', 2)], isEnd: false);
      return AdvancedMessage(messageList: [msg('a', 1)], isEnd: true);
    });
    await h.loader.loadOlder();
    await h.loader.refresh();
    expect(h.loader.hasMore, true);
    await h.loader.loadOlder();
    expect(cursors, [null, null, 'b']);
    expect(h.values.map((m) => m.clientMsgID), ['a', 'b']);
  });

  test('fresh latest page removes absent items while retaining older history',
      () async {
    var calls = 0;
    final h = Harness(({required count, startMsg}) async {
      calls++;
      return calls == 1
          ? AdvancedMessage(
              messageList: [msg('older', 1), msg('gone', 2), msg('last', 3)],
              isEnd: false)
          : AdvancedMessage(
              messageList: [msg('middle', 2), msg('last', 3)], isEnd: false);
    });
    await h.loader.loadOlder();
    await h.loader.refresh();
    expect(h.values.map((m) => m.clientMsgID), ['older', 'middle', 'last']);
  });

  test(
      'a sync burst beyond the visible window resets the paging boundary to fill the gap',
      () async {
    final cursors = <String?>[];
    final h = Harness(({required count, startMsg}) async {
      cursors.add(startMsg?.clientMsgID);
      if (cursors.length == 1) {
        return AdvancedMessage(messageList: [msg('old', 1)], isEnd: true);
      }
      if (cursors.length == 2) {
        return AdvancedMessage(
            messageList: [msg('newer', 100), msg('latest', 101)], isEnd: false);
      }
      return AdvancedMessage(
          messageList: [msg('old', 1), msg('gap', 50)], isEnd: true);
    });
    await h.loader.loadOlder();
    await h.loader.refresh();
    expect(h.loader.hasMore, true);
    expect(h.values.map((m) => m.clientMsgID), ['newer', 'latest']);
    await h.loader.loadOlder();
    expect(cursors, [null, null, 'newer']);
    expect(
        h.values.map((m) => m.clientMsgID), ['old', 'gap', 'newer', 'latest']);
  });

  test('a partial live burst cannot hide a gap from the confirmed SDK window',
      () async {
    final cursors = <String?>[];
    final h = Harness(({required count, startMsg}) async {
      cursors.add(startMsg?.clientMsgID);
      if (cursors.length == 1) {
        return AdvancedMessage(messageList: [msg('old', 1)], isEnd: false);
      }
      if (cursors.length == 2) {
        return AdvancedMessage(
            messageList: [msg('newer', 100), msg('latest', 101)], isEnd: false);
      }
      return AdvancedMessage(messageList: [msg('gap', 50)], isEnd: true);
    });
    await h.loader.loadOlder();
    h.values.add(msg('latest', 101));
    await h.loader.refresh();
    await h.loader.loadOlder();
    expect(cursors, [null, null, 'newer']);
    expect(h.values.map((m) => m.clientMsgID), ['gap', 'newer', 'latest']);
  });

  test('receipts delivered during history query are kept', () async {
    final pending = Completer<AdvancedMessage>();
    final h = Harness(({required count, startMsg}) => pending.future);
    final local = msg('same', 1);
    h.values = [local];
    final load = h.loader.loadOlder();
    local.isRead = true;
    local.hasReadTime = 123;
    pending.complete(AdvancedMessage(
        messageList: [msg('same', 1)..isRead = false], isEnd: true));
    await load;
    expect(h.values.single.isRead, true);
    expect(h.values.single.hasReadTime, 123);
  });

  test('pending local sends remain visible when absent from SDK history',
      () async {
    final h = Harness(({required count, startMsg}) async =>
        AdvancedMessage(messageList: [], isEnd: true));
    h.values = [
      msg('sending', 1, status: MessageStatus.sending),
      msg('failed', 2, status: MessageStatus.failed)
    ];
    await h.loader.loadOlder();
    expect(h.values.map((m) => m.clientMsgID), ['sending', 'failed']);
  });

  test(
      'SDK success replaces cached failed status without detaching a send callback target',
      () async {
    final local = msg('same', 1, status: MessageStatus.failed);
    final h = Harness(({required count, startMsg}) async =>
        AdvancedMessage(messageList: [msg('same', 1)], isEnd: true));
    h.values = [local];
    await h.loader.loadOlder();
    expect(h.values.single.status, MessageStatus.succeeded);
    expect(identical(h.values.single, local), true);
  });

  test(
      'local voice metadata changed during a query survives its stale snapshot',
      () async {
    final pending = Completer<AdvancedMessage>();
    final local = msg('same', 1)..localEx = '{"voiceHeard":false}';
    final h = Harness(({required count, startMsg}) => pending.future);
    h.values = [local];
    final load = h.loader.loadOlder();
    local.localEx = '{"voiceHeard":true,"text":"hello"}';
    pending.complete(AdvancedMessage(
        messageList: [msg('same', 1)..localEx = '{"voiceHeard":false}'],
        isEnd: true));
    await load;
    expect(h.values.single.localEx, local.localEx);
  });

  test('deleting a pagination anchor uses the oldest surviving message next',
      () async {
    final cursors = <String?>[];
    final h = Harness(({required count, startMsg}) async {
      cursors.add(startMsg?.clientMsgID);
      return cursors.length == 1
          ? AdvancedMessage(
              messageList: [msg('a', 1), msg('b', 2)], isEnd: false)
          : AdvancedMessage(messageList: [msg('older', 0)], isEnd: true);
    });
    await h.loader.loadOlder();
    h.removed.add('a');
    h.values.removeAt(0);
    await h.loader.loadOlder();
    expect(cursors, [null, 'b']);
    expect(h.values.map((m) => m.clientMsgID), ['older', 'b']);
  });

  test('retry repeats a failed refresh even when more older history exists',
      () async {
    final cursors = <String?>[];
    final h = Harness(({required count, startMsg}) async {
      cursors.add(startMsg?.clientMsgID);
      if (cursors.length == 2) throw StateError('offline');
      return AdvancedMessage(messageList: [msg('latest', 2)], isEnd: false);
    });
    await h.loader.loadOlder();
    await h.loader.refresh();
    expect(h.loader.error, isNotNull);
    await h.loader.retry();
    expect(cursors, [null, null, null]);
    expect(h.loader.error, isNull);
  });

  test(
      'snapshots isolate accounts, exclude private messages, and invalidate revoked/deleted messages',
      () {
    ChatHistoryCache.clear();
    final private = msg('private', 2)
      ..attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
    ChatHistoryCache.write('alice', 'chat', [msg('normal', 1), private]);
    expect(ChatHistoryCache.read('alice', 'chat').map((m) => m.clientMsgID),
        ['normal']);
    expect(ChatHistoryCache.read('bob', 'chat'), isEmpty);
    ChatHistoryCache.removeMessage('alice', 'normal');
    expect(ChatHistoryCache.read('alice', 'chat'), isEmpty);
    ChatHistoryCache.clear();
  });

  test('snapshot privacy, tombstones and logout remain valid after late writes',
      () {
    ChatHistoryCache.clear();
    final normal = msg('normal', 1);
    ChatHistoryCache.write('self', 'chat', [normal]);
    normal.attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
    expect(ChatHistoryCache.read('self', 'chat'), isEmpty);
    ChatHistoryCache.removeMessage('self', 'gone');
    expect(ChatHistoryCache.isRemoved('self', 'gone'), true);
    ChatHistoryCache.write('self', 'chat', [msg('gone', 2)]);
    expect(ChatHistoryCache.read('self', 'chat'), isEmpty);
    final epoch = ChatHistoryCache.epoch;
    ChatHistoryCache.clear();
    ChatHistoryCache.write('self', 'chat', [msg('late', 3)], epoch: epoch);
    expect(ChatHistoryCache.read('self', 'chat'), isEmpty);
    ChatHistoryCache.clear();
  });

  test('snapshots bound messages and evict least recently used conversations',
      () {
    ChatHistoryCache.clear();
    ChatHistoryCache.write(
        'user', 'chat-0', List.generate(100, (i) => msg('$i', i)));
    expect(ChatHistoryCache.read('user', 'chat-0').length, 40);
    expect(ChatHistoryCache.read('user', 'chat-0').first.clientMsgID, '60');
    for (var i = 1; i <= 12; i++) {
      ChatHistoryCache.write('user', 'chat-$i', [msg('$i', i)]);
    }
    expect(ChatHistoryCache.read('user', 'chat-0'), isEmpty);
    ChatHistoryCache.clear();
  });

  test(
      'time separators reset after deleting their old anchor and tolerate missing timestamps',
      () {
    final values = [msg('a', 0), msg('b', 6 * 60000), msg('c', 10 * 60000)];
    IMUtils.calChatTimeInterval(values);
    expect(values[1].exMap['showTime'], true);
    expect(values[2].exMap['showTime'], isNull);
    values.removeAt(0);
    values.insert(0, msg('replacement', 5 * 60000));
    values.add(Message(clientMsgID: 'no-time'));
    IMUtils.calChatTimeInterval(values);
    expect(values[1].exMap['showTime'], isNull);
  });
}
