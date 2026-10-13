import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_history_loader.dart';

Message _msg(String id, int time) => Message(
    clientMsgID: id,
    sendTime: time,
    seq: time,
    contentType: MessageType.text,
    status: MessageStatus.succeeded);
AdvancedMessage _failure() => AdvancedMessage(
    errCode: 10006,
    errMsg: 'history unavailable',
    isEnd: true,
    messageList: [_msg('partial', 0)]);

class _History {
  _History() {
    loader = ChatHistoryLoader(
      fetch: ({required count, startMsg}) async {
        olderCursors.add(startMsg?.clientMsgID);
        return older;
      },
      fetchNewer: ({required count, startMsg}) async {
        newerCursors.add(startMsg?.clientMsgID);
        return newer;
      },
      messages: () => messages,
      replace: (next, _, __) {
        messages = next;
        replacements++;
      },
      removedIDs: {},
      onStateChanged: () {},
      onLoaded: () => completions++,
    );
  }
  AdvancedMessage older =
      AdvancedMessage(messageList: [_msg('a', 1), _msg('b', 2)], isEnd: false);
  AdvancedMessage newer =
      AdvancedMessage(messageList: [_msg('d', 4)], isEnd: false);
  List<Message> messages = [_msg('cached', -1)];
  final olderCursors = <String?>[], newerCursors = <String?>[];
  int replacements = 0, completions = 0;
  late final ChatHistoryLoader loader;
}

void _expectFailure(ChatHistoryLoader loader) {
  expect(loader.loading, isFalse);
  expect(
      loader.error,
      isA<PlatformException>()
          .having((e) => e.code, 'code', '10006')
          .having((e) => e.message, 'message', 'history unavailable'));
}

void main() {
  test('partial first-page error preserves seed and remains retryable',
      () async {
    final h = _History();
    addTearDown(h.loader.close);
    h.older = _failure();
    await h.loader.loadOlder();
    _expectFailure(h.loader);
    expect(h.loader.loaded, isFalse);
    expect(h.loader.hasMore, isTrue);
    expect(h.messages.single.clientMsgID, 'cached');
    expect(h.replacements, 0);
    expect(h.completions, 0);
    h.older =
        AdvancedMessage(errCode: 0, messageList: [_msg('ok', 1)], isEnd: true);
    await h.loader.retry();
    expect(h.loader.error, isNull);
    expect(h.loader.loaded, isTrue);
    expect(h.loader.hasMore, isFalse);
    expect(h.messages.single.clientMsgID, 'ok');
    expect(h.olderCursors, [null, null]);
  });

  for (final refresh in [false, true]) {
    test(
        '${refresh ? 'refresh' : 'older page'} error preserves rows and cursor',
        () async {
      final h = _History();
      addTearDown(h.loader.close);
      await h.loader.loadOlder();
      final previous = h.messages;
      h.older = _failure();
      await (refresh ? h.loader.refresh() : h.loader.loadOlder());
      _expectFailure(h.loader);
      expect(identical(h.messages, previous), isTrue);
      expect(h.loader.loaded, isTrue);
      expect(h.loader.hasMore, isTrue);
      expect(h.replacements, 1);
      expect(h.completions, 1);
      h.older = AdvancedMessage(messageList: [_msg('a', 1)], isEnd: false);
      await h.loader.retry();
      expect(h.loader.error, isNull);
      expect(
          h.olderCursors, [null, refresh ? null : 'a', refresh ? null : 'a']);
    });
  }

  for (final direction in ['older', 'newer']) {
    test('date seek rejects an error in its $direction half atomically',
        () async {
      final h = _History();
      addTearDown(h.loader.close);
      await h.loader.loadOlder();
      final previous = h.messages;
      if (direction == 'older') {
        h.older = _failure();
      } else {
        h.newer = _failure();
      }
      expect(await h.loader.jumpTo(_msg('c', 3)), isFalse);
      _expectFailure(h.loader);
      expect(identical(h.messages, previous), isTrue);
      expect(h.loader.viewingHistory, isFalse);
      expect(h.replacements, 1);
      h.older = AdvancedMessage(messageList: [_msg('b', 2)], isEnd: false);
      h.newer = AdvancedMessage(messageList: [_msg('d', 4)], isEnd: false);
      expect(await h.loader.retry(), isTrue);
      expect(h.loader.error, isNull);
      expect(h.messages.map((m) => m.clientMsgID), ['b', 'c', 'd']);
    });
  }

  for (final latest in [false, true]) {
    test(
        '${latest ? 'return to latest' : 'newer page'} error retains historical window',
        () async {
      final h = _History();
      addTearDown(h.loader.close);
      await h.loader.jumpTo(_msg('c', 3));
      final previous = h.messages;
      if (latest) {
        h.older = _failure();
      } else {
        h.newer = _failure();
      }
      final result =
          await (latest ? h.loader.returnToLatest() : h.loader.loadNewer());
      if (latest) expect(result, isFalse);
      _expectFailure(h.loader);
      expect(identical(h.messages, previous), isTrue);
      expect(h.loader.viewingHistory, isTrue);
      expect(h.loader.hasNewer, isTrue);
      h.older =
          h.newer = AdvancedMessage(messageList: [_msg('e', 5)], isEnd: true);
      await h.loader.retry();
      expect(h.loader.error, isNull);
      expect(h.loader.viewingHistory, isFalse);
      expect(h.messages.last.clientMsgID, 'e');
      if (!latest) expect(h.newerCursors, ['c', 'd', 'd']);
    });
  }

  test('late SDK error cannot replace a newer successful window', () async {
    final late = Completer<AdvancedMessage>();
    final h = _History();
    var calls = 0;
    final loader = ChatHistoryLoader(
      fetch: ({required count, startMsg}) =>
          ++calls == 1 ? late.future : Future.value(h.older),
      messages: () => h.messages,
      replace: (next, _, __) => h.messages = next,
      removedIDs: {},
      onStateChanged: () {},
    );
    addTearDown(loader.close);
    final first = loader.loadOlder();
    expect(await loader.returnToLatest(), isTrue);
    late.complete(_failure());
    await first;
    expect(loader.error, isNull);
    expect(loader.loaded, isTrue);
    expect(h.messages.map((m) => m.clientMsgID), ['a', 'b']);
  });
}
