import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/pages/chat/history/date_jump/chat_date_window_controller.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';

Message _message(String id, int time) => Message(
      clientMsgID: id,
      sendTime: time,
      seq: time,
      contentType: MessageType.text,
      status: MessageStatus.succeeded,
    );

AdvancedMessage _page(List<Message> messages, {bool end = false}) =>
    AdvancedMessage(messageList: messages, isEnd: end);

class _Positions extends ChatListPositionController {
  final targets = <String>[];
  Future<bool> Function(String) respond = (_) async => true;

  @override
  Future<bool> jumpToMessage(String messageID, {double alignment = 0.5}) {
    targets.add(messageID);
    return respond(messageID);
  }

  @override
  void cancel() {}
}

class _Harness {
  _Harness({
    required Future<AdvancedMessage> Function(Message?) older,
    required Future<AdvancedMessage> Function(Message?) newer,
  }) {
    timeline = ChatTimelineController(
      accountID: 'me',
      currentAccountID: () => 'me',
      conversation: () => ConversationInfo(conversationID: 'chat'),
      fetch: ({required count, startMsg}) {
        olderCursors.add(startMsg?.clientMsgID);
        return older(startMsg);
      },
      fetchNewer: ({required count, startMsg}) {
        newerCursors.add(startMsg?.clientMsgID);
        return newer(startMsg);
      },
      isClosed: () => closed,
      onFirstPage: () {},
      captureOffset: () => 0,
      restoreOffset: (_) {},
      onFirstLoaded: () {},
    )..initialize(prefetch: false);
    timeline.messageList.add(_message('latest-seed', 100));
    window = ChatDateWindowController(
      timeline: timeline,
      positions: positions,
      isClosed: () => closed,
      cancelLatestScroll: () {},
      updateScrollOffset: offsets.add,
      distanceFromLatest: () => 5,
      requestLatestScroll: latestScrolls.add,
    );
    addTearDown(close);
  }

  bool closed = false;
  final positions = _Positions();
  final olderCursors = <String?>[];
  final newerCursors = <String?>[];
  final latestScrolls = <bool>[];
  final offsets = <double>[];
  late final ChatTimelineController timeline;
  late final ChatDateWindowController window;

  List<String?> get ids =>
      timeline.messageList.map((m) => m.clientMsgID).toList();

  void close() {
    closed = true;
    window.invalidate();
    timeline.close();
  }
}

Future<bool> _paint(WidgetTester tester, Future<bool> request) async {
  bool? result;
  request.then((value) => result = value);
  for (var frame = 0; frame < 8 && result == null; frame++) {
    await tester.pump();
  }
  expect(result, isNotNull, reason: 'A coordinator request must settle');
  return result!;
}

void main() {
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);

  testWidgets(
      'a seeded target replaces pending startup history with its SDK window',
      (tester) async {
    final initialLatest = Completer<AdvancedMessage>();
    final targetOlder = Completer<AdvancedMessage>();
    final targetNewer = Completer<AdvancedMessage>();
    final target = _message('cached-target', 50);
    final h = _Harness(
      older: (cursor) =>
          cursor == null ? initialLatest.future : targetOlder.future,
      newer: (_) => targetNewer.future,
    );
    h.timeline.messageList.insert(0, target);
    final initialLoad = h.timeline.loadOlder();
    expect(h.timeline.hasLoadedHistory, isFalse);
    expect(h.timeline.initialHistoryLoading.value, isTrue);
    expect(h.olderCursors, [null]);

    final jump = h.window.jumpToMessage(target);
    expect(h.olderCursors, [null, 'cached-target'],
        reason: 'A cached row has no installed SDK paging boundaries yet');
    expect(h.newerCursors, ['cached-target']);
    expect(h.window.seeking.value, isTrue);

    targetOlder.complete(_page([_message('before', 49)]));
    targetNewer.complete(_page([_message('after', 51)]));
    expect(await _paint(tester, jump), isTrue);
    expect(h.positions.targets, ['cached-target']);
    expect(h.ids, ['before', 'cached-target', 'after']);
    expect(h.timeline.hasLoadedHistory, isTrue);
    expect(h.timeline.viewingHistory.value, isTrue);

    // The first latest request started before the seek. Its late completion
    // must not remove the positioned target or install unrelated latest rows.
    initialLatest.complete(_page([_message('stale-latest', 101)], end: true));
    expect(await initialLoad, isFalse);
    await tester.pump();
    expect(h.ids, ['before', 'cached-target', 'after']);
    expect(h.timeline.messageList[1], same(target));
    expect(h.timeline.historyHasMore.value, isTrue);
    expect(h.timeline.newerHasMore.value, isTrue);
    expect(h.timeline.viewingHistory.value, isTrue);
    expect(h.timeline.historyLoading.value, isFalse);
    expect(h.timeline.historyError.value, isNull);
    expect(h.latestScrolls, isEmpty);
    h.close();
  });

  testWidgets(
      'a loaded target replaces a pending refresh before its late completion',
      (tester) async {
    final pendingRefresh = Completer<AdvancedMessage>();
    final targetOlder = Completer<AdvancedMessage>();
    final targetNewer = Completer<AdvancedMessage>();
    final target = _message('loaded-target', 50);
    var latestCalls = 0;
    final h = _Harness(
      older: (cursor) {
        if (cursor != null) return targetOlder.future;
        if (++latestCalls == 1) {
          return Future.value(_page([target, _message('latest', 100)]));
        }
        return pendingRefresh.future;
      },
      newer: (_) => targetNewer.future,
    );
    expect(await h.timeline.loadOlder(), isTrue);
    expect(h.timeline.hasLoadedHistory, isTrue);
    expect(h.ids, ['loaded-target', 'latest']);
    expect(h.timeline.historyLoading.value, isFalse);

    final refresh = h.timeline.refresh();
    expect(h.timeline.hasLoadedHistory, isTrue);
    expect(h.timeline.historyLoading.value, isTrue);
    expect(h.olderCursors, [null, null]);

    final jump = h.window.jumpToMessage(target);
    expect(h.olderCursors, [null, null, 'loaded-target'],
        reason: 'An in-flight refresh must not replace the positioned window');
    expect(h.newerCursors, ['loaded-target']);
    expect(h.window.seeking.value, isTrue);

    targetOlder.complete(_page([_message('before', 49)]));
    targetNewer.complete(_page([_message('after', 51)]));
    expect(await _paint(tester, jump), isTrue);
    expect(h.positions.targets, ['loaded-target']);
    expect(h.ids, ['before', 'loaded-target', 'after']);
    expect(h.timeline.viewingHistory.value, isTrue);

    // An end-of-history refresh normally replaces the current window. A seek
    // owns a newer generation, so this older response cannot install its rows.
    pendingRefresh
        .complete(_page([_message('stale-refresh-latest', 200)], end: true));
    expect(await refresh, isFalse);
    await tester.pump();
    expect(h.ids, ['before', 'loaded-target', 'after']);
    expect(h.timeline.messageList[1], same(target));
    expect(h.timeline.historyHasMore.value, isTrue);
    expect(h.timeline.newerHasMore.value, isTrue);
    expect(h.timeline.viewingHistory.value, isTrue);
    expect(h.timeline.historyLoading.value, isFalse);
    expect(h.timeline.historyError.value, isNull);
    expect(h.latestScrolls, isEmpty);
    h.close();
  });

  testWidgets('failed date retry reinstalls context and positions the target',
      (tester) async {
    var olderCalls = 0;
    final h = _Harness(
      older: (_) async {
        if (++olderCalls == 1) throw StateError('offline');
        return _page([_message('before', 49)]);
      },
      newer: (_) async => _page([_message('after', 51)]),
    );
    expect(await h.window.jumpToMessage(_message('target', 50)), isFalse);
    expect(h.positions.targets, isEmpty);

    expect(await _paint(tester, h.window.retry()), isTrue);
    expect(h.olderCursors, ['target', 'target']);
    expect(h.newerCursors, ['target', 'target']);
    expect(h.positions.targets, ['target']);
    expect(h.ids, ['before', 'target', 'after']);
    expect(h.window.seeking.value, isFalse);
    h.close();
  });

  testWidgets('failed viewport retry positions its already installed target',
      (tester) async {
    final h = _Harness(
      older: (_) async => _page([_message('before', 49)]),
      newer: (_) async => _page([_message('after', 51)]),
    );
    h.positions.respond = (_) async => h.positions.targets.length > 1;
    expect(await _paint(tester, h.window.jumpToMessage(_message('target', 50))),
        isFalse);

    expect(await _paint(tester, h.window.retry()), isTrue);
    expect(h.positions.targets, ['target', 'target']);
    expect(h.olderCursors, ['target']);
    expect(h.newerCursors, ['target']);
    h.close();
  });

  testWidgets('failed latest retry flushes arrivals and requests latest scroll',
      (tester) async {
    var latestCalls = 0;
    final h = _Harness(
      older: (cursor) async {
        if (cursor != null) return _page([_message('before', 49)]);
        if (++latestCalls == 1) throw StateError('offline');
        return _page([_message('latest', 100)], end: true);
      },
      newer: (_) async => _page([_message('after', 51)]),
    );
    await h.timeline.jumpTo(_message('target', 50));
    h.timeline.scrollingCacheMessageList
        .addAll([_message('latest', 100), _message('live', 101)]);
    expect(await h.window.returnToLatest(smooth: true), isFalse);
    expect(h.timeline.viewingHistory.value, isTrue);
    expect(h.latestScrolls, isEmpty);

    expect(await h.window.retry(), isTrue);
    expect(h.olderCursors, ['target', null, null]);
    expect(h.timeline.scrollingCacheMessageList, isEmpty);
    expect(h.ids, ['latest', 'live']);
    expect(h.latestScrolls, [true]);
    expect(h.window.returning.value, isFalse);
    h.close();
  });

  testWidgets('ordinary newer retry keeps direction and reconnects live buffer',
      (tester) async {
    var newerCalls = 0;
    final h = _Harness(
      older: (_) async => _page([_message('before', 49)]),
      newer: (_) async {
        if (++newerCalls == 1) return _page([_message('after', 51)]);
        if (newerCalls == 2) throw StateError('offline');
        return _page([_message('latest', 100)], end: true);
      },
    );
    await h.timeline.jumpTo(_message('target', 50));
    h.timeline.scrollingCacheMessageList.add(_message('live', 101));
    await h.timeline.loadNewer();
    expect(h.timeline.historyError.value, isNotNull);

    expect(await h.window.retry(), isFalse);
    expect(h.olderCursors, ['target']);
    expect(h.newerCursors, ['target', 'after', 'after']);
    expect(h.ids, ['before', 'target', 'after', 'latest', 'live']);
    expect(h.timeline.scrollingCacheMessageList, isEmpty);
    expect(h.latestScrolls, isEmpty);
    expect(h.positions.targets, isEmpty);
    h.close();
  });

  testWidgets('manual cancellation discards a failed date retry action',
      (tester) async {
    final h = _Harness(
      older: (cursor) async {
        if (cursor != null) throw StateError('offline');
        return _page([_message('latest', 100)], end: true);
      },
      newer: (_) async => _page([_message('after', 51)]),
    );
    expect(await h.window.jumpToMessage(_message('target', 50)), isFalse);
    h.window.invalidate();
    expect(h.timeline.historyError.value, isNull);

    expect(await h.window.retry(), isFalse);
    expect(h.olderCursors, ['target', null]);
    expect(h.newerCursors, ['target']);
    expect(h.positions.targets, isEmpty);
    expect(h.ids, ['latest']);
    h.close();
  });

  testWidgets('manual cancellation discards a failed latest retry action',
      (tester) async {
    final h = _Harness(
      older: (cursor) async {
        if (cursor == null) throw StateError('offline');
        return _page([_message('before', 49)]);
      },
      newer: (_) async => _page([_message('after', 51)]),
    );
    await h.timeline.jumpTo(_message('target', 50));
    expect(await h.window.returnToLatest(), isFalse);
    h.window.invalidate();
    expect(h.timeline.historyError.value, isNull);

    expect(await h.window.retry(), isTrue);
    expect(h.olderCursors, ['target', null, 'before']);
    expect(h.latestScrolls, isEmpty);
    expect(h.timeline.viewingHistory.value, isTrue);
    h.close();
  });

  testWidgets('an old position failure cannot overwrite a newer latest action',
      (tester) async {
    var latestCalls = 0;
    final pendingPosition = Completer<bool>();
    final h = _Harness(
      older: (cursor) async {
        if (cursor != null) return _page([_message('before', 49)]);
        if (++latestCalls == 1) throw StateError('latest offline');
        return _page([_message('latest', 100)], end: true);
      },
      newer: (_) async => _page([_message('after', 51)]),
    );
    h.positions.respond = (_) => pendingPosition.future;
    final oldJump = h.window.jumpToMessage(_message('target', 50));
    for (var frame = 0; frame < 8 && h.positions.targets.isEmpty; frame++) {
      await tester.pump();
    }
    expect(h.positions.targets, ['target']);
    expect(await h.window.returnToLatest(), isFalse);
    pendingPosition.complete(false);
    expect(await oldJump, isFalse);

    expect(await h.window.retry(), isTrue);
    expect(h.olderCursors, ['target', null, null]);
    expect(h.positions.targets, ['target']);
    expect(h.latestScrolls, [false]);
    h.close();
  });

  testWidgets('close during position does not retain a failed action',
      (tester) async {
    final pendingPosition = Completer<bool>();
    final h = _Harness(
      older: (_) async => _page([_message('before', 49)]),
      newer: (_) async => _page([_message('after', 51)]),
    );
    h.positions.respond = (_) => pendingPosition.future;
    final jumping = h.window.jumpToMessage(_message('target', 50));
    for (var frame = 0; frame < 8 && h.positions.targets.isEmpty; frame++) {
      await tester.pump();
    }
    h.closed = true;
    h.window.invalidate();
    pendingPosition.complete(false);
    expect(await jumping, isFalse);
    expect(await h.window.retry(), isFalse);
    expect(h.olderCursors, ['target']);
    h.close();
  });
}
