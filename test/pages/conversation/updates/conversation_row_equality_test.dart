import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/updates/conversation_row_equality.dart';

void main() {
  ConversationInfo row() => ConversationInfo(
        conversationID: 'c1',
        unreadCount: 3,
        latestMsg: Message(clientMsgID: 'm1', status: MessageStatus.succeeded),
      );
  test('duplicate SDK payloads match; same-ID metadata changes do not', () {
    final original = row();
    expect(sameConversationData(original, row()), isTrue);
    for (final update in <void Function(ConversationInfo)>[
      (r) => r.unreadCount = 0,
      (r) => r.draftText = 'draft',
      (r) => r.isPinned = true,
      (r) => r.groupAtType = 1,
      (r) => r.recvMsgOpt = 2,
      (r) => r.faceURL = 'avatar',
      (r) => r.showName = 'renamed',
      (r) => r.isPrivateChat = true,
      (r) => r.burnDuration = 30,
      (r) => r.ex = 'changed',
      (r) => r.latestMsg!.status = MessageStatus.failed,
      (r) => r.latestMsg!.senderNickname = 'new sender',
    ]) {
      final changed = row();
      update(changed);
      expect(sameConversationData(original, changed), isFalse);
    }
  });
  test('shared mutable rows or messages must still publish', () {
    final original = row();
    expect(sameConversationData(original, original), isFalse);
    final shared = row()..latestMsg = original.latestMsg;
    expect(sameConversationData(original, shared), isFalse);
    expect(sameConversationData(null, original), isFalse);
  });
}
