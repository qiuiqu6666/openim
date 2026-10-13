import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/composer/chat_draft.dart';

void main() {
  test('text, mentions and ordinary reply survive an SDK draft round trip', () {
    final quote = Message(
        clientMsgID: 'original',
        contentType: MessageType.text,
        textElem: TextElem(content: 'Original'));
    final restored = ChatDraft.decode(
        ChatDraft('Reply @Alice ', {'alice': 'Alice'}, quote).encode());
    expect(restored.text, 'Reply @Alice ');
    expect(restored.mentions, {'alice': 'Alice'});
    expect(restored.quote?.clientMsgID, 'original');
    expect(restored.quote?.textElem?.content, 'Original');
  });

  test('a quote alone persists and clearing it removes the draft', () {
    final quote = Message(clientMsgID: 'original');
    expect(
        ChatDraft.decode(ChatDraft('', {}, quote).encode()).quote?.clientMsgID,
        'original');
    expect(const ChatDraft('', {}, null).encode(), '');
  });

  test('private message content is excluded from persistent drafts', () {
    final quote = Message(
        clientMsgID: 'private',
        contentType: MessageType.text,
        textElem: TextElem(content: 'Secret'),
        attachedInfoElem: AttachedInfoElem(isPrivateChat: true));
    final encoded = ChatDraft('Reply', {}, quote).encode();
    expect(encoded, isNot(contains('Secret')));
    expect(ChatDraft.decode(encoded).quote, isNull);
  });

  test('a damaged quote preserves valid text and mention identities', () {
    final restored = ChatDraft.decode(jsonEncode({
      'text': 'Reply',
      'mentions': {'alice': 'Alice'},
      'quote': {'clientMsgID': 42}
    }));
    expect(restored.text, 'Reply');
    expect(restored.mentions, {'alice': 'Alice'});
    expect(restored.quote, isNull);
    expect(ChatDraft.decode('Legacy draft').text, 'Legacy draft');
  });

  test(
      'serialized retention and nested private references also stay out of drafts',
      () {
    final private = Message(
        clientMsgID: 'private',
        contentType: MessageType.text,
        attachedInfo: '{"isPrivateChat":true}',
        textElem: TextElem(content: 'Secret'));
    final quoted = Message.fromJson({
      'clientMsgID': 'outer',
      'contentType': MessageType.quote,
      'quoteElem': {'text': 'Outer', 'quoteMessage': private.toJson()},
    });
    for (final quote in [private, quoted]) {
      final saved = ChatDraft('Reply', {}, quote).encode();
      expect(saved, isNot(contains('Secret')));
      expect(ChatDraft.decode(saved).quote, isNull);
    }
  });
}
