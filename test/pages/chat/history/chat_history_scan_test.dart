import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_history_loader.dart';

Message row(int seq) => Message(
    clientMsgID: 'row-$seq',
    seq: seq,
    sendTime: seq,
    contentType: MessageType.text,
    status: MessageStatus.succeeded);

HistoryScanCursor cursor(int seq, {bool reverse = false}) => HistoryScanCursor(
    conversationID: 'sg_@lg_test',
    reverse: reverse,
    clientMsgID: 'deleted-$seq',
    sendTime: seq,
    seq: seq);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('scan progress follows native time then sequence order', () {
    final older = HistoryScanCursor(
        conversationID: 'group',
        reverse: false,
        clientMsgID: 'old',
        sendTime: 10,
        seq: 500);
    expect(older.advancesFrom(row(100)), isTrue);
    expect(
        older
            .advancesFrom(Message(clientMsgID: 'same', sendTime: 10, seq: 400)),
        isFalse);
  });
  test(
      'both native channels transmit the scan boundary and decode partial pages',
      () async {
    const channel = MethodChannel('history-scan-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final requests = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      requests.add(call);
      final reverse = call.method.endsWith('Reverse');
      return jsonEncode(AdvancedMessage(
              messageList: [],
              isEnd: false,
              scanLimited: true,
              scanCursor: cursor(reverse ? 90 : 70, reverse: reverse))
          .toJson());
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final manager = MessageManager(channel);
    final older = await manager.getAdvancedHistoryMessageList(
        conversationID: 'sg_@lg_test', startMsg: cursor(80));
    final newer = await manager.getAdvancedHistoryMessageListReverse(
        conversationID: 'sg_@lg_test', startMsg: cursor(80, reverse: true));
    expect((requests[0].arguments as Map)['scanCursor'], cursor(80).toJson());
    expect((requests[1].arguments as Map)['scanCursor'],
        cursor(80, reverse: true).toJson());
    expect(older.scanCursor?.seq, 70);
    expect(newer.scanCursor?.seq, 90);
    expect(older.scanLimited, isTrue);
    expect(newer.isEnd, isFalse);
  });
  for (final empty in [false, true]) {
    test(
        'bounded ${empty ? 'empty' : 'partial'} scan continues without restarting latest',
        () async {
      var rows = <Message>[];
      final starts = <Message?>[];
      var result = AdvancedMessage(
          messageList: empty ? [] : [row(100)],
          isEnd: false,
          scanLimited: true,
          scanCursor: cursor(80));
      final loader = ChatHistoryLoader(
          fetch: ({required count, startMsg}) async {
            starts.add(startMsg);
            return result;
          },
          messages: () => rows,
          replace: (next, _, __) => rows = next,
          removedIDs: {},
          onStateChanged: () {});
      addTearDown(loader.close);
      expect(await loader.loadOlder(), isTrue);
      expect(loader.error, isNull);
      expect(loader.loaded, isTrue);
      expect(loader.scanLimited, isTrue);
      expect(rows.map((m) => m.clientMsgID), empty ? [] : ['row-100']);
      for (var i = 0; i < 10; i++) {
        await loader.refresh();
      }
      expect(starts, [null]);
      result = AdvancedMessage(messageList: [row(20)], isEnd: true);
      expect(await loader.retry(), isFalse);
      expect(starts[1], isA<HistoryScanCursor>());
      expect(starts[1]?.seq, 80);
      expect(loader.scanLimited, isFalse);
      expect(loader.hasMore, isFalse);
      expect(rows.map((m) => m.seq), empty ? [20] : [20, 100]);
    });
  }

  test(
      'failed continuation retains visible rows and retries the same scan cursor',
      () async {
    var rows = <Message>[];
    final starts = <int?>[];
    var calls = 0;
    final loader = ChatHistoryLoader(
        fetch: ({required count, startMsg}) async {
          starts.add(startMsg?.seq);
          if (++calls == 1) {
            return AdvancedMessage(
                messageList: [row(100)],
                isEnd: false,
                scanLimited: true,
                scanCursor: cursor(80));
          }
          if (calls == 2) throw PlatformException(code: 'offline');
          return AdvancedMessage(messageList: [row(20)], isEnd: true);
        },
        messages: () => rows,
        replace: (next, _, __) => rows = next,
        removedIDs: {},
        onStateChanged: () {});
    addTearDown(loader.close);
    await loader.loadOlder();
    await loader.retry();
    expect(loader.error, isA<PlatformException>());
    expect(rows.single.seq, 100);
    await loader.retry();
    expect(starts, [null, 80, 80]);
    expect(loader.error, isNull);
    expect(rows.map((m) => m.seq), [20, 100]);
  });

  test('invalid or stalled continuation is rejected without installing rows',
      () async {
    var rows = [row(100)];
    var result = AdvancedMessage(messageList: [row(90)], isEnd: false);
    final loader = ChatHistoryLoader(
        fetch: ({required count, startMsg}) async => result,
        messages: () => rows,
        replace: (next, _, __) => rows = next,
        removedIDs: {},
        onStateChanged: () {});
    addTearDown(loader.close);
    await loader.loadOlder();
    result = AdvancedMessage(
        messageList: [row(80)],
        isEnd: false,
        scanLimited: true,
        scanCursor: cursor(90));
    await loader.loadOlder();
    expect(loader.error, isA<StateError>());
    expect(rows.single.seq, 90);
    expect(loader.hasMore, isTrue);
  });

  test(
      'newer scan uses its deleted boundary and preserves historical mode until true end',
      () async {
    var rows = <Message>[];
    final starts = <int?>[];
    var newerCalls = 0;
    final loader = ChatHistoryLoader(
        fetch: ({required count, startMsg}) async =>
            AdvancedMessage(messageList: [row(40)], isEnd: true),
        fetchNewer: ({required count, startMsg}) async {
          starts.add(startMsg?.seq);
          if (++newerCalls == 1) {
            return AdvancedMessage(
                messageList: [],
                isEnd: false,
                scanLimited: true,
                scanCursor: cursor(80, reverse: true));
          }
          return AdvancedMessage(messageList: [row(100)], isEnd: true);
        },
        messages: () => rows,
        replace: (next, _, __) => rows = next,
        removedIDs: {},
        onStateChanged: () {});
    addTearDown(loader.close);
    await loader.jumpTo(row(50));
    expect(loader.viewingHistory, isTrue);
    expect(loader.scanLimited, isTrue);
    await loader.retry();
    expect(starts, [50, 80]);
    expect(loader.viewingHistory, isFalse);
    expect(loader.scanLimited, isFalse);
    expect(rows.map((m) => m.seq), [40, 50, 100]);
  });
}
