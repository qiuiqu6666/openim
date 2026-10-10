import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/streaming/assistant_stream_chunk.dart';
import 'package:openim/pages/ai_assistant/streaming/assistant_stream_state.dart';
import 'package:openim/pages/ai_assistant/streaming/diagnostics/assistant_stream_log.dart';

Message _packet(String streamID,
        {int index = 0,
        bool end = false,
        int type = MessageType.custom,
        String description = 'assistantStream'}) =>
    Message(
      clientMsgID: 'private-client-message-id',
      sendID: 'assistant',
      recvID: 'private-recipient-account',
      sessionType: ConversationType.single,
      contentType: type,
      customElem: CustomElem(
          description: description,
          extension: 'private-extension',
          data: jsonEncode({
            'streamID': streamID,
            'index': index,
            'end': end,
            'text': 'private-chat-body',
            'token': 'private-token',
            'userID': 'private-payload-account',
            'rawPayload': 'private-raw-payload',
          })),
    );

Map<String, dynamic> _fields(String line) =>
    jsonDecode(line.substring(line.indexOf('{'))) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DebugPrintCallback originalPrint;
  late List<String> lines;

  setUp(() {
    originalPrint = debugPrint;
    lines = [];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
  });
  tearDown(() => debugPrint = originalPrint);

  test('all stream diagnostics expose metadata without private message data',
      () {
    const streamID = 'private-stream-id-for-redaction';
    final message = _packet(streamID);
    final owner = AssistantStreamState();
    addTearDown(owner.dispose);
    const chunk = AssistantStreamChunk(
        streamID: streamID, index: 0, text: 'private-chat-body', end: false);
    final snapshot = owner.accept(chunk)!;

    AssistantStreamLog.received(message,
        source: 'onlineOnly', hasReceiver: true);
    AssistantStreamLog.routed(message,
        active: true, currentChat: true, assistantChat: true, buffering: false);
    AssistantStreamLog.invalid(message);
    AssistantStreamLog.accepted(chunk, snapshot,
        buffering: false, finalized: false);
    AssistantStreamLog.bubble(owner, snapshot);
    AssistantStreamLog.submitted('private-chat-body'.length);
    AssistantStreamLog.finalReply(Message(
      sendID: 'assistant',
      recvID: 'private-recipient-account',
      sessionType: ConversationType.single,
      contentType: MessageType.text,
      textElem: TextElem(content: 'private-final-body'),
      ex: jsonEncode({'streamID': streamID, 'token': 'private-final-token'}),
    ));

    expect(lines, hasLength(7));
    final output = lines.join('\n');
    for (final privateValue in [
      streamID,
      message.customElem!.data!,
      'private-chat-body',
      'private-client-message-id',
      'private-recipient-account',
      'private-payload-account',
      'private-extension',
      'private-token',
      'private-raw-payload',
      'private-final-body',
      'private-final-token',
    ]) {
      expect(output, isNot(contains(privateValue)));
    }
    const allowedFields = {
      'at',
      'source',
      'hasReceiver',
      'type',
      'singleChat',
      'fromAssistant',
      'toCurrentUser',
      'streamEnvelope',
      'matchesDescription',
      'validObject',
      'stream',
      'indexPresent',
      'indexType',
      'index',
      'endPresent',
      'endType',
      'end',
      'textType',
      'textUnits',
      'active',
      'currentChat',
      'assistantChat',
      'buffering',
      'changed',
      'finalized',
      'visibleUnits',
      'ended',
    };
    for (final line in lines) {
      expect(_fields(line).keys, everyElement(isIn(allowedFields)));
    }
    final receive = _fields(lines.first);
    expect(receive['fromAssistant'], isTrue);
    expect(receive['streamEnvelope'], isTrue);
    expect(receive['textUnits'], 'private-chat-body'.length);
    expect(receive['stream'], isA<String>());
    expect(receive['stream'], isNot(streamID));
  });

  test('first out-of-order arrival is logged before later receive sampling',
      () {
    const id = 'sample-first-out-of-order';
    AssistantStreamLog.received(_packet(id, index: 3),
        source: 'onlineOnly', hasReceiver: true);
    expect(lines, hasLength(1));
    expect(_fields(lines.single)['index'], 3);
    expect(_fields(lines.single)['end'], isFalse);

    AssistantStreamLog.received(_packet(id, index: 4),
        source: 'onlineOnly', hasReceiver: true);
    expect(lines, hasLength(1),
        reason: 'Every successive token must not produce another log line.');

    AssistantStreamLog.received(_packet(id, index: 10),
        source: 'onlineOnly', hasReceiver: true);
    AssistantStreamLog.received(_packet(id, index: 11, end: true),
        source: 'onlineOnly', hasReceiver: true);
    expect(lines, hasLength(3));
    expect(lines.map((line) => _fields(line)['index']), [3, 10, 11]);
    expect(_fields(lines.last)['end'], isTrue);
  });

  test('assistant messages identify wrong description and type envelopes', () {
    AssistantStreamLog.received(
        _packet('wrong-description-envelope',
            index: 3, description: 'private-wrong-description'),
        source: 'onlineOnly',
        hasReceiver: true);
    AssistantStreamLog.received(
        _packet('wrong-type-envelope', index: 3, type: MessageType.text),
        source: 'onlineOnly',
        hasReceiver: true);

    expect(lines, hasLength(2));
    final fields = lines.map(_fields).toList();
    expect(fields.map((entry) => entry['fromAssistant']), [true, true]);
    expect(fields.map((entry) => entry['streamEnvelope']), [false, false]);
    expect(fields.map((entry) => entry['matchesDescription']), [false, true]);
    expect(fields.map((entry) => entry['type']),
        [MessageType.custom, MessageType.text]);
    expect(lines.join('\n'), isNot(contains('private-wrong-description')));
  });

  test('receiving diagnostics do not require a logged-in SDK account', () {
    // Leave the SDK singleton untouched: native receive callbacks can precede
    // login, and logging must tolerate an unavailable current account.
    expect(
        () => AssistantStreamLog.received(_packet('before-login-receive'),
            source: 'onlineOnly', hasReceiver: true),
        returnsNormally);
    expect(lines, hasLength(1));
    expect(_fields(lines.single)['hasReceiver'], isTrue);
    expect(_fields(lines.single)['toCurrentUser'], anyOf(isNull, isA<bool>()));
  });

  test('bubble buckets deduplicate rebuilds and the final reply is recorded',
      () {
    final owner = AssistantStreamState();
    addTearDown(owner.dispose);
    const id = 'private-bubble-stream';
    AssistantStreamSnapshot reply(int length, {bool ended = false}) =>
        AssistantStreamSnapshot(streamID: id, text: 'x' * length, ended: ended);

    AssistantStreamLog.bubble(owner, reply(1));
    AssistantStreamLog.bubble(owner, reply(200));
    expect(lines, hasLength(1));
    AssistantStreamLog.bubble(owner, reply(256));
    AssistantStreamLog.bubble(owner, reply(300));
    expect(lines, hasLength(2));
    AssistantStreamLog.bubble(owner, reply(300, ended: true));
    AssistantStreamLog.bubble(owner, reply(300, ended: true));
    expect(lines, hasLength(3));
    expect(lines.map((line) => _fields(line)['visibleUnits']), [1, 256, 300]);
    expect(lines.map((line) => _fields(line)['ended']), [false, false, true]);

    AssistantStreamLog.finalReply(Message(
      sendID: 'assistant',
      recvID: 'private-final-recipient',
      sessionType: ConversationType.single,
      contentType: MessageType.text,
      textElem: TextElem(content: 'private-final-reply'),
      ex: jsonEncode({'streamID': id}),
    ));
    expect(lines, hasLength(4));
    expect(lines.last, startsWith('[AI流式][final] '));
    expect(_fields(lines.last)['textUnits'], 'private-final-reply'.length);
    expect(_fields(lines.last)['stream'], _fields(lines.first)['stream']);
    expect(lines.join('\n'), isNot(contains('private-')));
  });
}
