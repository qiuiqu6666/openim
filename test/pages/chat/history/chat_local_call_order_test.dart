import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/pages/chat/history/chat_history_loader.dart';
import 'package:openim/services/chat_history_cache.dart';

import 'message_window_ingress_test.dart' show window;

Message _row(String id, int time,
        {int seq = 0,
        int status = MessageStatus.succeeded,
        int type = MessageType.custom}) =>
    Message(
        clientMsgID: id,
        sendTime: time,
        createTime: time,
        seq: seq,
        status: status,
        contentType: type);

void main() {
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);

  test('ordered batches keep server sequence order across backwards clocks',
      () {
    final rows = [
      _row('server10', 300, seq: 10),
      _row('server11', 200, seq: 11),
      _row('old-call', 100), // Also repairs a previously misplaced local row.
      _row('recent-call', 350),
      _row('pending', 50, status: MessageStatus.sending),
    ];
    final batch = [_row('image12', 400, seq: 12, type: MessageType.picture)];
    final merged = ChatHistoryLoader.appendOrderedBatch(rows, batch);
    expect(merged.map((m) => m.clientMsgID), [
      'old-call',
      'server10',
      'server11',
      'recent-call',
      'image12',
      'pending',
    ]);
    expect(merged.map((m) => m.clientMsgID),
        ChatHistoryLoader.merge([...rows, ...batch]).map((m) => m.clientMsgID));
    expect(rows[2].sendTime, 100);
    expect(identical(merged.first, rows[2]), isTrue);
  });

  for (final activeWindow in [false, true]) {
    testWidgets(
        'old local calls keep their time position on image receipt '
        '(window=$activeWindow)', (tester) async {
      final initial = [
        _row('voice', 100),
        _row('image10', 200, seq: 10, type: MessageType.picture),
        _row('video', 250),
        _row('image11', 300, seq: 11, type: MessageType.picture),
      ];
      final timeline = ChatTimelineController(
        accountID: 'me',
        currentAccountID: () => 'me',
        conversation: () => ConversationInfo(conversationID: 'chat'),
        fetch: ({required count, startMsg}) async => AdvancedMessage(
            messageList: initial,
            isEnd: true,
            window: activeWindow ? window(11) : null),
        isClosed: () => false,
        onFirstPage: () {},
        captureOffset: () => 0,
        restoreOffset: (_) {},
        onFirstLoaded: () {},
      )..initialize(prefetch: false);
      addTearDown(timeline.close);
      await timeline.loadOlder();
      timeline.messageList.addAll([
        _row('sending', 50, status: MessageStatus.sending),
        _row('failed', 60, status: MessageStatus.failed),
      ]);
      final original = initial.map((m) => m.clientMsgID).toList();
      for (var seq = 12; seq <= 14; seq++) {
        timeline.appendIncoming(
            _row('image$seq', seq * 100, seq: seq, type: MessageType.picture),
            trim: true);
        await tester.pump(const Duration(milliseconds: 20));
        expect(timeline.messageList.map((m) => m.clientMsgID), [
          ...original,
          for (var n = 12; n <= seq; n++) 'image$n',
          'sending',
          'failed',
        ]);
      }
      // A covered replay must not duplicate the image or relocate old calls.
      if (activeWindow) {
        timeline.appendIncoming(
            _row('image14', 1400, seq: 14, type: MessageType.picture),
            trim: true);
        await tester.pump(const Duration(milliseconds: 20));
        expect(timeline.messageList.where((m) => m.clientMsgID == 'image14'),
            hasLength(1));
      }
      timeline.close();
      await tester.pump(const Duration(milliseconds: 100));
    });
  }
}
