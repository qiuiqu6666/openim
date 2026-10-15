import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_openim_sdk/src/window/message_window_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'message_window_ingress_test.dart' show window;

void main() {
  test(
      'navigation and page share pending native IO but receive isolated copies',
      () async {
    final cache = MessageWindowCache();
    final pending = Completer<AdvancedMessage>();
    var reads = 0;
    Future<AdvancedMessage> load() {
      reads++;
      return pending.future;
    }

    final navigation = cache.read('s', 'chat', 40, load);
    final page = cache.read('s', 'chat', 40, load);
    expect(reads, 1);
    expect(cache.peek('s', 'chat', 40), isNull);
    pending.complete(AdvancedMessage(
        window: window(40),
        messageList: [Message(clientMsgID: 'm40', seq: 40)]));
    final first = await navigation;
    final second = await page;
    first.messageList!.clear();
    expect(second.messageList!.length, 1);
    expect(cache.peek('s', 'chat', 40)!.messageList!.length, 1);
    expect(cache.peek('other session', 'chat', 40), isNull);
  });
  test('late invalidated preparation cannot replace a newer cached proof',
      () async {
    final cache = MessageWindowCache();
    final old = Completer<AdvancedMessage>();
    final warm = cache.read('s', 'chat', 40, () => old.future);
    cache.invalidate('chat');
    await cache.read(
        's',
        'chat',
        40,
        () async => AdvancedMessage(
            window: window(41),
            messageList: [Message(clientMsgID: 'm41', seq: 41)]));
    old.complete(AdvancedMessage(window: window(40), messageList: []));
    await warm;
    expect(cache.peek('s', 'chat', 40)!.window!.targetWatermark, 41);
  });
  test('failed pending reads are removed and allow retry', () async {
    final cache = MessageWindowCache();
    final pending = Completer<AdvancedMessage>();
    final first = cache.read('s', 'chat', 40, () => pending.future);
    final second =
        cache.read('s', 'chat', 40, () => throw StateError('duplicate'));
    final assertions = Future.wait([
      expectLater(first, throwsStateError),
      expectLater(second, throwsStateError)
    ]);
    pending.completeError(StateError('native failure'));
    await assertions;
    await cache.read(
        's', 'chat', 40, () async => AdvancedMessage(window: window(40)));
    expect(cache.peek('s', 'chat', 40), isNotNull);
  });
  test('memory copies are bounded, isolated and expire', () async {
    var now = DateTime(2026);
    var reads = 0;
    final cache = MessageWindowCache(limit: 2, now: () => now);
    Future<AdvancedMessage> load(String id) async {
      reads++;
      return AdvancedMessage(window: window(40, id: id), messageList: [
        Message(clientMsgID: id, seq: 40, sendID: id, recvID: 'self')
      ]);
    }

    final a = await cache.read('session', 'A', 40, () => load('A'));
    a.messageList!.clear();
    expect(
        (await cache.read('session', 'A', 40, () => load('A')))
            .messageList!
            .length,
        1);
    expect(reads, 1);
    await cache.read('other session', 'A', 40, () => load('A'));
    expect(reads, 2);
    now = now.add(const Duration(seconds: 3));
    await cache.read('session', 'A', 40, () => load('A'));
    expect(reads, 3);
    await cache.read('session', 'B', 40, () => load('B'));
    await cache.read('session', 'C', 40, () => load('C'));
    await cache.read('session', 'A', 40, () => load('A'));
    expect(reads, 6);
  });
  test('event invalidates its conversation and fences pending snapshots',
      () async {
    final cache = MessageWindowCache();
    var reads = 0;
    Future<AdvancedMessage> load(String id) async {
      reads++;
      return AdvancedMessage(window: window(40, id: id), messageList: [
        Message(clientMsgID: id, seq: 40, sendID: id, recvID: 'self')
      ]);
    }

    await cache.read('s', 'A', 40, () => load('A'));
    await cache.read('s', 'B', 40, () => load('B'));
    cache.received(Message(sendID: 'A', recvID: 'self'), 'self');
    await cache.read('s', 'B', 40, () => load('B'));
    expect(reads, 2);
    await cache.read('s', 'A', 40, () => load('A'));
    expect(reads, 3);
    final pending = Completer<AdvancedMessage>();
    final result = cache.read('s', 'C', 40, () => pending.future);
    cache.invalidate();
    pending.complete(await load('C'));
    await result;
    await cache.read('s', 'C', 40, () => load('C'));
    expect(reads, 5);
  });
}
