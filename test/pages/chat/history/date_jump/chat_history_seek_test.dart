import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_history_loader.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/services/chat_history_cache.dart';

Message _msg(String id, int time, {int? status}) => Message(
      clientMsgID: id,
      sendTime: time,
      seq: time,
      contentType: MessageType.text,
      status: status ?? MessageStatus.succeeded,
    );

AdvancedMessage _page(List<Message> messages, {bool end = false}) =>
    AdvancedMessage(messageList: messages, isEnd: end);

class _History {
  _History(
      {required ChatHistoryReader older, required ChatHistoryReader newer}) {
    loader = ChatHistoryLoader(
      fetch: older,
      fetchNewer: newer,
      pageSize: 8,
      messages: () => values,
      replace: (next, first, refresh) {
        values = next;
        replacements++;
      },
      removedIDs: removed,
      onStateChanged: () => states++,
    );
  }

  List<Message> values = [];
  final removed = <String>{};
  int replacements = 0;
  int states = 0;
  late final ChatHistoryLoader loader;

  List<String?> get ids => values.map((m) => m.clientMsgID).toList();
}

ChatTimelineController _timeline({
  required ChatHistoryReader older,
  required ChatHistoryReader newer,
}) =>
    ChatTimelineController(
      accountID: 'me',
      currentAccountID: () => 'me',
      conversation: () => ConversationInfo(conversationID: 'chat'),
      fetch: older,
      fetchNewer: newer,
      isClosed: () => false,
      onFirstPage: () {},
      captureOffset: () => 0,
      restoreOffset: (_) {},
      onFirstLoaded: () {},
    )..initialize(prefetch: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);

  test('seek reads a bounded range in both directions and preserves sends',
      () async {
    final calls = <(String, int, String?)>[];
    final h = _History(
      older: ({required count, startMsg}) async {
        calls.add(('older', count, startMsg?.clientMsgID));
        return _page([_msg('before', 49), _msg('target', 50)]);
      },
      newer: ({required count, startMsg}) async {
        calls.add(('newer', count, startMsg?.clientMsgID));
        return _page([_msg('after', 51), _msg('target', 50)]);
      },
    );
    final sending = _msg('sending', 100, status: MessageStatus.sending);
    final failed = _msg('failed', 101, status: MessageStatus.failed);
    h.values = [_msg('latest', 99), sending, failed];

    expect(await h.loader.jumpTo(_msg('target', 50)), isTrue);
    expect(calls, [('older', 4, 'target'), ('newer', 4, 'target')]);
    expect(h.ids, ['before', 'target', 'after', 'sending', 'failed']);
    expect(h.values[3], same(sending));
    expect(h.values[4], same(failed));
    expect(h.loader.viewingHistory, isTrue);
    expect(h.loader.hasMore, isTrue);
    expect(h.loader.hasNewer, isTrue);
  });

  test('seek supersedes an initial page without letting it release ownership',
      () async {
    final initial = Completer<AdvancedMessage>();
    final seekOlder = Completer<AdvancedMessage>();
    final seekNewer = Completer<AdvancedMessage>();
    final h = _History(
      older: ({required count, startMsg}) =>
          startMsg == null ? initial.future : seekOlder.future,
      newer: ({required count, startMsg}) => seekNewer.future,
    );
    h.values = [_msg('seed', 100)];
    final initialLoad = h.loader.loadOlder();
    final refresh = h.loader.refresh();
    final seek = h.loader.jumpTo(_msg('target', 50));
    expect(h.loader.viewingHistory, isTrue);
    initial.complete(_page([_msg('stale-latest', 101)]));
    expect(await initialLoad, isFalse);
    expect(await refresh, isFalse);
    expect(h.loader.loading, isTrue);
    expect(h.ids, ['seed']);
    seekOlder.complete(_page([_msg('before', 49)]));
    seekNewer.complete(_page([_msg('after', 51)]));
    expect(await seek, isTrue);
    expect(h.ids, ['before', 'target', 'after']);
    expect(h.loader.loading, isFalse);
  });

  test('a later seek rejects an earlier seek and its stale state completion',
      () async {
    final firstOlder = Completer<AdvancedMessage>();
    final firstNewer = Completer<AdvancedMessage>();
    final secondOlder = Completer<AdvancedMessage>();
    final secondNewer = Completer<AdvancedMessage>();
    final h = _History(
      older: ({required count, startMsg}) => startMsg?.clientMsgID == 'one'
          ? firstOlder.future
          : secondOlder.future,
      newer: ({required count, startMsg}) => startMsg?.clientMsgID == 'one'
          ? firstNewer.future
          : secondNewer.future,
    );
    final first = h.loader.jumpTo(_msg('one', 10));
    final second = h.loader.jumpTo(_msg('two', 20));
    firstOlder.completeError(StateError('late failure'));
    firstNewer.complete(_page([_msg('stale', 11)]));
    expect(await first, isFalse);
    expect(h.loader.error, isNull);
    expect(h.loader.loading, isTrue);
    expect(h.loader.viewingHistory, isTrue);
    secondOlder.complete(_page([_msg('before-two', 19)]));
    secondNewer.complete(_page([_msg('after-two', 21)]));
    expect(await second, isTrue);
    expect(h.ids, ['before-two', 'two', 'after-two']);
  });

  test('older and newer pagination follow historical boundaries, not sends',
      () async {
    final cursors = <(String, String?)>[];
    final h = _History(
      older: ({required count, startMsg}) async {
        cursors.add(('older', startMsg?.clientMsgID));
        return startMsg?.clientMsgID == 'target'
            ? _page([_msg('before', 49)])
            : _page([_msg('oldest', 48)], end: true);
      },
      newer: ({required count, startMsg}) async {
        cursors.add(('newer', startMsg?.clientMsgID));
        return startMsg?.clientMsgID == 'target'
            ? _page([_msg('after', 51)])
            : _page([_msg('latest', 52)], end: true);
      },
    );
    h.values = [_msg('failed', 100, status: MessageStatus.failed)];
    await h.loader.jumpTo(_msg('target', 50));
    expect(await h.loader.loadOlder(), isFalse);
    expect(await h.loader.loadNewer(), isFalse);
    expect(cursors, [
      ('older', 'target'),
      ('newer', 'target'),
      ('older', 'before'),
      ('newer', 'after'),
    ]);
    expect(h.ids, ['oldest', 'before', 'target', 'after', 'latest', 'failed']);
    expect(h.loader.viewingHistory, isFalse);
    expect(h.loader.hasNewer, isFalse);
  });

  test('failed replacement seek restores the installed latest window state',
      () async {
    final firstOlder = Completer<AdvancedMessage>();
    final firstNewer = Completer<AdvancedMessage>();
    final h = _History(
      older: ({required count, startMsg}) async {
        if (startMsg?.clientMsgID == 'one') return firstOlder.future;
        throw StateError('replacement offline');
      },
      newer: ({required count, startMsg}) => startMsg?.clientMsgID == 'one'
          ? firstNewer.future
          : Future.value(_page([])),
    );
    h.values = [_msg('latest', 100)];
    final first = h.loader.jumpTo(_msg('one', 10));
    expect(await h.loader.jumpTo(_msg('two', 20)), isFalse);
    expect(h.loader.viewingHistory, isFalse);
    expect(h.ids, ['latest']);
    firstOlder.complete(_page([_msg('stale', 9)]));
    firstNewer.complete(_page([_msg('stale-newer', 11)]));
    expect(await first, isFalse);
    expect(h.loader.viewingHistory, isFalse);
    expect(h.loader.error, isA<StateError>());
  });

  test('empty filtered newer page cannot reconnect a historical window',
      () async {
    var newerCalls = 0;
    final h = _History(
      older: ({required count, startMsg}) async => _page([_msg('before', 49)]),
      newer: ({required count, startMsg}) async => ++newerCalls == 1
          ? _page([_msg('after', 51)])
          : _page([_msg('deleted', 52)]),
    );
    await h.loader.jumpTo(_msg('target', 50));
    h.removed.add('deleted');
    expect(await h.loader.loadNewer(), isTrue);
    expect(h.loader.viewingHistory, isTrue);
    expect(h.loader.hasNewer, isTrue);
    expect(h.ids, ['before', 'target', 'after']);
  });

  test('cancelled seek preserves the installed window and normal refresh',
      () async {
    final seekOlder = Completer<AdvancedMessage>();
    final seekNewer = Completer<AdvancedMessage>();
    final cursors = <String?>[];
    final h = _History(
      older: ({required count, startMsg}) async {
        cursors.add(startMsg?.clientMsgID);
        return startMsg?.clientMsgID == 'target'
            ? seekOlder.future
            : _page([_msg('latest', 100)]);
      },
      newer: ({required count, startMsg}) => seekNewer.future,
    );
    await h.loader.loadOlder();
    final seeking = h.loader.jumpTo(_msg('target', 50));
    h.loader.cancelWindowChange();
    expect(h.loader.loading, isFalse);
    expect(h.loader.viewingHistory, isFalse);
    expect(h.ids, ['latest']);
    seekOlder.complete(_page([_msg('before', 49)]));
    seekNewer.complete(_page([_msg('after', 51)]));
    expect(await seeking, isFalse);
    expect(h.ids, ['latest']);
    expect(await h.loader.refresh(), isTrue);
    expect(cursors, [null, 'target', null]);
    expect(h.loader.error, isNull);
  });

  test('cancel window change leaves an ordinary older-page request active',
      () async {
    final older = Completer<AdvancedMessage>();
    final h = _History(
      older: ({required count, startMsg}) => older.future,
      newer: ({required count, startMsg}) async => _page([]),
    );
    final loading = h.loader.loadOlder();
    h.loader.cancelWindowChange();
    expect(h.loader.loading, isTrue);
    older.complete(_page([_msg('latest', 100)]));
    expect(await loading, isTrue);
    expect(h.ids, ['latest']);
  });

  test('cancel latest return restores installed historical state and cursors',
      () async {
    final latest = Completer<AdvancedMessage>();
    final cursors = <String?>[];
    final h = _History(
      older: ({required count, startMsg}) async {
        cursors.add(startMsg?.clientMsgID);
        if (startMsg == null) return latest.future;
        return _page([_msg('before', 49)]);
      },
      newer: ({required count, startMsg}) async => _page([_msg('after', 51)]),
    );
    await h.loader.jumpTo(_msg('target', 50));
    final returning = h.loader.returnToLatest();
    h.loader.cancelWindowChange();
    expect(h.loader.viewingHistory, isTrue);
    expect(h.loader.loading, isFalse);
    latest.complete(_page([_msg('latest', 100)]));
    expect(await returning, isFalse);
    expect(h.ids, ['before', 'target', 'after']);
    await h.loader.loadOlder();
    expect(cursors, ['target', null, 'before']);
  });

  test('refresh keeps a historical window intact without querying latest',
      () async {
    var olderCalls = 0;
    final h = _History(
      older: ({required count, startMsg}) async {
        olderCalls++;
        return _page([_msg('before', 49)]);
      },
      newer: ({required count, startMsg}) async => _page([_msg('after', 51)]),
    );
    await h.loader.jumpTo(_msg('target', 50));
    h.values[1].isRead = true;
    h.removed.add('before');
    h.values.removeAt(0);
    await h.loader.refresh();
    expect(olderCalls, 1);
    expect(h.replacements, 1);
    expect(h.ids, ['target', 'after']);
    expect(h.values.first.isRead, isTrue);
    expect(h.loader.viewingHistory, isTrue);
  });

  test('return to latest replaces the old range and keeps pending identities',
      () async {
    final h = _History(
      older: ({required count, startMsg}) async => startMsg == null
          ? _page([_msg('latest', 100)], end: true)
          : _page([_msg('before', 49)]),
      newer: ({required count, startMsg}) async => _page([_msg('after', 51)]),
    );
    final failed = _msg('failed', 101, status: MessageStatus.failed);
    h.values = [failed];
    await h.loader.jumpTo(_msg('target', 50));
    expect(await h.loader.returnToLatest(), isTrue);
    expect(h.ids, ['latest', 'failed']);
    expect(h.values.last, same(failed));
    expect(h.loader.viewingHistory, isFalse);
    expect(h.loader.hasNewer, isFalse);
    expect(h.loader.hasMore, isFalse);
  });

  test('completed sends and concurrent receipts survive a seek snapshot',
      () async {
    final older = Completer<AdvancedMessage>();
    final newer = Completer<AdvancedMessage>();
    final h = _History(
      older: ({required count, startMsg}) => older.future,
      newer: ({required count, startMsg}) => newer.future,
    );
    final sending = _msg('sending', 100, status: MessageStatus.sending);
    final local = _msg('near-target', 49)..localEx = 'old-voice';
    h.values = [local, sending];
    final seek = h.loader.jumpTo(_msg('target', 50));
    sending.status = MessageStatus.succeeded;
    local.isRead = true;
    local.hasReadTime = 200;
    local.localEx = 'voice-heard';
    older.complete(_page([_msg('near-target', 49)..localEx = 'old-voice']));
    newer.complete(_page([_msg('after', 51)]));
    await seek;
    expect(h.values.last, same(sending));
    expect(h.values.first.isRead, isTrue);
    expect(h.values.first.hasReadTime, 200);
    expect(h.values.first.localEx, 'voice-heard');
  });

  test('failed seek leaves the window in place and retry seeks the same target',
      () async {
    final cursors = <String?>[];
    var fail = true;
    final h = _History(
      older: ({required count, startMsg}) async {
        cursors.add(startMsg?.clientMsgID);
        if (fail) throw StateError('offline');
        return _page([_msg('before', 49)]);
      },
      newer: ({required count, startMsg}) async => _page([_msg('after', 51)]),
    );
    h.values = [_msg('latest', 100)];
    expect(await h.loader.jumpTo(_msg('target', 50)), isFalse);
    expect(h.ids, ['latest']);
    expect(h.loader.viewingHistory, isFalse);
    expect(h.loader.error, isA<StateError>());
    fail = false;
    expect(await h.loader.retry(), isTrue);
    expect(cursors, ['target', 'target']);
    expect(h.ids, ['before', 'target', 'after']);
  });

  test('failed newer request retries newer without touching the latest page',
      () async {
    final cursors = <String?>[];
    var newerCalls = 0;
    var olderCalls = 0;
    final h = _History(
      older: ({required count, startMsg}) async {
        olderCalls++;
        return _page([_msg('before', 49)]);
      },
      newer: ({required count, startMsg}) async {
        cursors.add(startMsg?.clientMsgID);
        if (++newerCalls == 2) throw StateError('offline');
        return _page([_msg('after', 51)]);
      },
    );
    await h.loader.jumpTo(_msg('target', 50));
    await h.loader.loadNewer();
    expect(h.loader.error, isNotNull);
    await h.loader.retry();
    expect(cursors, ['target', 'after', 'after']);
    expect(olderCalls, 1);
    expect(h.loader.error, isNull);
    expect(h.loader.viewingHistory, isTrue);
  });

  test('failed return to latest preserves the historical window and retries',
      () async {
    var latestCalls = 0;
    final h = _History(
      older: ({required count, startMsg}) async {
        if (startMsg != null) return _page([_msg('before', 49)]);
        if (++latestCalls == 1) throw StateError('offline');
        return _page([_msg('latest', 100)]);
      },
      newer: ({required count, startMsg}) async => _page([_msg('after', 51)]),
    );
    await h.loader.jumpTo(_msg('target', 50));
    expect(await h.loader.returnToLatest(), isFalse);
    expect(h.ids, ['before', 'target', 'after']);
    expect(h.loader.viewingHistory, isTrue);
    expect(await h.loader.retry(), isTrue);
    expect(latestCalls, 2);
    expect(h.ids, ['latest']);
    expect(h.loader.viewingHistory, isFalse);
  });

  test('a target removed while loading cannot reappear or replace the window',
      () async {
    final older = Completer<AdvancedMessage>();
    final newer = Completer<AdvancedMessage>();
    final h = _History(
      older: ({required count, startMsg}) => older.future,
      newer: ({required count, startMsg}) => newer.future,
    );
    h.values = [_msg('latest', 100)];
    final seek = h.loader.jumpTo(_msg('target', 50));
    h.removed.add('target');
    older.complete(_page([_msg('target', 50)]));
    newer.complete(_page([_msg('after', 51)]));
    expect(await seek, isFalse);
    expect(h.ids, ['latest']);
    expect(h.replacements, 0);
    expect(h.loader.viewingHistory, isFalse);
  });

  for (final close in [false, true]) {
    test(
        '${close ? 'close' : 'clear'} rejects late seek pages and state writes',
        () async {
      final older = Completer<AdvancedMessage>();
      final newer = Completer<AdvancedMessage>();
      final h = _History(
        older: ({required count, startMsg}) => older.future,
        newer: ({required count, startMsg}) => newer.future,
      );
      final seek = h.loader.jumpTo(_msg('target', 50));
      if (close) {
        h.loader.close();
      } else {
        h.loader.clear();
      }
      final states = h.states;
      older.complete(_page([_msg('before', 49)]));
      newer.complete(_page([_msg('after', 51)]));
      expect(await seek, isFalse);
      expect(h.values, isEmpty);
      expect(h.replacements, 0);
      expect(h.states, states);
      expect(h.loader.loading, isFalse);
      if (!close) {
        expect(h.loader.viewingHistory, isFalse);
        expect(h.loader.hasNewer, isFalse);
        expect(await h.loader.retry(), isFalse);
      }
    });
  }

  test('deleted newer boundary falls back to a surviving confirmed message',
      () async {
    final cursors = <String?>[];
    final h = _History(
      older: ({required count, startMsg}) async => _page([_msg('before', 49)]),
      newer: ({required count, startMsg}) async {
        cursors.add(startMsg?.clientMsgID);
        return cursors.length == 1
            ? _page([_msg('after', 51)])
            : _page([_msg('latest', 52)], end: true);
      },
    );
    h.values = [_msg('sending', 100, status: MessageStatus.sending)];
    await h.loader.jumpTo(_msg('target', 50));
    h.removed.add('after');
    h.values.removeWhere((m) => m.clientMsgID == 'after');
    await h.loader.loadNewer();
    expect(cursors, ['target', 'target']);
    expect(h.ids, ['before', 'target', 'latest', 'sending']);
  });

  test('acknowledged retained sends cannot become a disjoint newer cursor',
      () async {
    final cursors = <String?>[];
    final h = _History(
      older: ({required count, startMsg}) async => _page([_msg('before', 49)]),
      newer: ({required count, startMsg}) async {
        cursors.add(startMsg?.clientMsgID);
        return cursors.length == 1
            ? _page([_msg('after', 51)])
            : _page([_msg('latest', 52)], end: true);
      },
    );
    final sending = _msg('sending', 100, status: MessageStatus.sending);
    h.values = [sending];
    await h.loader.jumpTo(_msg('target', 50));
    sending.status = MessageStatus.succeeded;
    h.removed.add('after');
    h.values.removeWhere((m) => m.clientMsgID == 'after');
    await h.loader.loadNewer();
    expect(cursors, ['target', 'target']);
    expect(h.ids, ['before', 'target', 'latest', 'sending']);
  });

  test('deleting the entire history range cannot use a retained latest send',
      () async {
    final olderCursors = <String?>[];
    final newerCursors = <String?>[];
    final h = _History(
      older: ({required count, startMsg}) async {
        olderCursors.add(startMsg?.clientMsgID);
        return _page([_msg('before', 49)]);
      },
      newer: ({required count, startMsg}) async {
        newerCursors.add(startMsg?.clientMsgID);
        return _page([_msg('after', 51)]);
      },
    );
    final sending = _msg('sending', 100, status: MessageStatus.sending);
    h.values = [sending];
    await h.loader.jumpTo(_msg('target', 50));
    sending.status = MessageStatus.succeeded;
    h.removed.addAll(['before', 'target', 'after']);
    h.values.removeWhere((m) => h.removed.contains(m.clientMsgID));
    expect(await h.loader.loadOlder(), isFalse);
    expect(await h.loader.loadNewer(), isFalse);
    expect(olderCursors, ['target']);
    expect(newerCursors, ['target']);
    expect(h.loader.viewingHistory, isTrue);
    expect(h.values.single, same(sending));
  });

  test('historical windows do not replace the latest cached seed on close',
      () async {
    ChatHistoryCache.write('me', 'chat', [_msg('latest-seed', 100)]);
    final timeline = _timeline(
      older: ({required count, startMsg}) async => _page([_msg('before', 49)]),
      newer: ({required count, startMsg}) async => _page([_msg('after', 51)]),
    );
    await timeline.jumpTo(_msg('target', 50));
    expect(timeline.viewingHistory.value, isTrue);
    expect(timeline.newerHasMore.value, isTrue);
    timeline.close();
    expect(ChatHistoryCache.read('me', 'chat').map((m) => m.clientMsgID),
        ['latest-seed']);
  });

  test('pending seek also prevents a historical seed cache write', () async {
    ChatHistoryCache.write('me', 'chat', [_msg('latest-seed', 100)]);
    final older = Completer<AdvancedMessage>();
    final newer = Completer<AdvancedMessage>();
    final timeline = _timeline(
      older: ({required count, startMsg}) => older.future,
      newer: ({required count, startMsg}) => newer.future,
    );
    final seeking = timeline.jumpTo(_msg('target', 50));
    expect(timeline.viewingHistory.value, isTrue);
    timeline.close();
    older.complete(_page([_msg('before', 49)]));
    newer.complete(_page([_msg('after', 51)]));
    expect(await seeking, isFalse);
    expect(ChatHistoryCache.read('me', 'chat').map((m) => m.clientMsgID),
        ['latest-seed']);
  });

  test('private mode still clears latest cache while viewing history',
      () async {
    ChatHistoryCache.write('me', 'chat', [_msg('latest-seed', 100)]);
    final info = ConversationInfo(conversationID: 'chat');
    final timeline = ChatTimelineController(
      accountID: 'me',
      currentAccountID: () => 'me',
      conversation: () => info,
      fetch: ({required count, startMsg}) async => _page([_msg('before', 49)]),
      fetchNewer: ({required count, startMsg}) async =>
          _page([_msg('after', 51)]),
      isClosed: () => false,
      onFirstPage: () {},
      captureOffset: () => 0,
      restoreOffset: (_) {},
      onFirstLoaded: () {},
    )..initialize(prefetch: false);
    await timeline.jumpTo(_msg('target', 50));
    info.isPrivateChat = true;
    timeline.close();
    expect(ChatHistoryCache.read('me', 'chat'), isEmpty);
  });

  test('reaching latest flushes buffered arrivals and deduplicates overlaps',
      () async {
    final timeline = _timeline(
      older: ({required count, startMsg}) async => _page([_msg('before', 49)]),
      newer: ({required count, startMsg}) async =>
          startMsg?.clientMsgID == 'target'
              ? _page([_msg('after', 51)])
              : _page([_msg('latest', 100)], end: true),
    );
    addTearDown(timeline.close);
    timeline.scrollingCacheMessageList.addAll([
      _msg('after', 51),
      _msg('latest', 100),
      _msg('live', 101),
    ]);
    await timeline.jumpTo(_msg('target', 50));
    expect(timeline.scrollingCacheMessageList.map((m) => m.clientMsgID),
        ['latest', 'live']);
    await timeline.loadNewer();
    expect(timeline.viewingHistory.value, isFalse);
    expect(timeline.scrollingCacheMessageList, isEmpty);
    expect(timeline.messageList.map((m) => m.clientMsgID),
        ['before', 'target', 'after', 'latest', 'live']);
    timeline.close();
    expect(ChatHistoryCache.read('me', 'chat').last.clientMsgID, 'live');
  });
}
