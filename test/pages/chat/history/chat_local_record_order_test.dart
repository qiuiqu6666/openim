import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_history_loader.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  Message server(String id, int seq, int time) => Message(
      clientMsgID: id,
      seq: seq,
      sendTime: time,
      status: MessageStatus.succeeded,
      contentType: MessageType.text);
  Message call(String type, int time) => Message.fromJson({
        'clientMsgID': 'call-$type',
        'seq': 0,
        'sendTime': time,
        'status': MessageStatus.succeeded,
        'contentType': MessageType.custom,
        'customElem': {
          'data': jsonEncode({
            'customType': 901,
            'data': {'type': type, 'state': 'cancel', 'duration': 0},
          })
        },
      });

  test('persisted older call does not become the last message', () {
    final card = server('card', 2, 1613);
    final oldCall = call('audio', 1553);
    final result = ChatHistoryLoader.merge([
      card,
      oldCall,
      server('first', 1, 1231),
      oldCall,
    ]);
    expect(result.map((m) => m.clientMsgID), ['first', 'call-audio', 'card']);
    expect(ChatHistoryLoader.compareMessageOrder(oldCall, card), lessThan(0));
    expect(ChatHistoryLoader.merge(result).map((m) => m.clientMsgID),
        result.map((m) => m.clientMsgID));
  });

  test('newest audio and video call retain their conversation summaries', () {
    for (final type in ['audio', 'video']) {
      final result = ChatHistoryLoader.merge([
        call(type, 1700),
        server('card', 1, 1613),
      ]);
      final label = type == 'audio' ? StrRes.callVoice : StrRes.callVideo;
      expect(IMUtils.parseMsg(result.last, isConversation: true),
          '[$label] ${StrRes.cancelled}');
    }
  });

  test('local records preserve server sequence order and pending tail', () {
    final pending = server('pending', 0, 50)..status = MessageStatus.sending;
    final result = ChatHistoryLoader.merge([
      server('second', 2, 100),
      pending,
      call('audio', 200),
      server('first', 1, 300),
    ]);
    expect(result.where((m) => (m.seq ?? 0) > 0).map((m) => m.clientMsgID),
        ['first', 'second']);
    expect(result.last, same(pending));
    expect(ChatHistoryLoader.merge(result).map((m) => m.clientMsgID),
        result.map((m) => m.clientMsgID));
  });
}
