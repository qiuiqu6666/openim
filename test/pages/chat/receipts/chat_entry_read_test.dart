import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/receipts/chat_entry_read.dart';

ConversationInfo entryRow() => ConversationInfo(
    conversationID: 'si_peer_self',
    userID: 'peer',
    conversationType: ConversationType.single,
    unreadCount: 12,
    latestMsg: Message(
        clientMsgID: 'm100',
        seq: 100,
        sendID: 'peer',
        recvID: 'self',
        sessionType: ConversationType.single,
        status: MessageStatus.succeeded));

void main() {
  test('stale zero unread count does not suppress a valid entry cutoff', () {
    final row = entryRow()..unreadCount = 0;
    expect(
        ChatEntryRead.capture(row, historyEntry: false, accountID: 'self')
            .target
            ?.hasReadSeq,
        100);
  });
  test('ordinary entry freezes preview without loaded or painted history', () {
    final row = entryRow();
    final read =
        ChatEntryRead.capture(row, historyEntry: false, accountID: 'self');
    row.latestMsg!.seq = 101;
    final sent = <int>[];
    read.enter(active: false, send: (t) => sent.add(t.hasReadSeq));
    expect(sent, isEmpty);
    read.enter(active: true, send: (t) => sent.add(t.hasReadSeq));
    read.enter(active: true, send: (t) => sent.add(t.hasReadSeq));
    expect(sent, [100]);
  });
  test('history entry never promotes to entry read later', () {
    expect(
        ChatEntryRead.capture(entryRow(), historyEntry: true, accountID: 'self')
            .target,
        isNull);
  });
  test('rejects temporary, private and wrong-conversation previews', () {
    for (final mutate in <void Function(ConversationInfo)>[
      (r) => r.latestMsg!.seq = 0,
      (r) => r.latestMsg!.status = MessageStatus.sending,
      (r) => r.isPrivateChat = true,
      (r) => r.latestMsg!.sendID = 'other',
      (r) => r.conversationID = 'si_other_self',
      (r) => r.latestMsg!.recvID = 'other',
    ]) {
      final row = entryRow();
      mutate(row);
      expect(
          ChatEntryRead.capture(row, historyEntry: false, accountID: 'self')
              .target,
          isNull);
    }
  });
  test('group must match preview and conversation ID', () {
    final row = entryRow()
      ..conversationID = 'sg_a'
      ..groupID = 'a'
      ..conversationType = ConversationType.superGroup;
    row.latestMsg!
      ..sessionType = ConversationType.superGroup
      ..groupID = 'a';
    expect(
        ChatEntryRead.capture(row, historyEntry: false, accountID: 'self')
            .target
            ?.hasReadSeq,
        100);
    row.latestMsg!.groupID = 'b';
    expect(
        ChatEntryRead.capture(row, historyEntry: false, accountID: 'self')
            .target,
        isNull);
  });
}
