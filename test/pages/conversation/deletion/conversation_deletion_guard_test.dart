import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/deletion/conversation_deletion_guard.dart';

ConversationInfo _row(int time, int seq) => ConversationInfo(
      conversationID: 'chat',
      latestMsgSendTime: time,
      latestMsg: Message.fromJson({'clientMsgID': '$seq', 'seq': seq}),
    );

void main() {
  test(
      'a deletion covers the largest event and snapshot observed before success',
      () {
    final guard = ConversationDeletionGuard();
    expect(guard.begin(_row(1, 1)), isTrue);
    expect(guard.begin(_row(1, 1)), isFalse);
    expect(guard.allows(_row(3, 3)), isFalse);
    expect(guard.allows(_row(4, 4), snapshot: true), isFalse);
    expect(guard.allows(_row(2, 2)), isFalse);
    guard.complete('chat');
    expect(guard.allows(_row(3, 3)), isFalse);
    expect(guard.allows(_row(4, 4)), isFalse);
    expect(guard.allows(_row(4, 5)), isTrue);
  });

  test(
      'failed deletion restores the latest callback instead of its old snapshot',
      () {
    final guard = ConversationDeletionGuard();
    guard.begin(_row(1, 1));
    guard.allows(_row(3, 3));
    guard.allows(_row(2, 2), snapshot: true);
    expect(guard.fail('chat')?.latestMsgSendTime, 3);
    expect(guard.allows(_row(3, 3)), isTrue);
  });

  test('clearing an owner also removes its pending deletion state', () {
    final guard = ConversationDeletionGuard();
    guard.begin(_row(3, 3));
    guard.complete('chat');
    guard.clear();
    expect(guard.allows(_row(1, 1)), isTrue);
  });

  test(
      'old drafts stay deleted but a newly edited draft can recreate the conversation',
      () {
    final guard = ConversationDeletionGuard();
    final old = _row(1, 1)
      ..draftText = 'old draft'
      ..draftTextTime = 2;
    guard.begin(old);
    final duringDelete = _row(1, 1)
      ..draftText = 'pending draft'
      ..draftTextTime = 4;
    expect(guard.allows(duringDelete), isFalse);
    guard.complete('chat');
    expect(guard.allows(old), isFalse);
    expect(guard.allows(duringDelete), isFalse);
    final clearedDraft = _row(1, 1)
      ..draftText = ''
      ..draftTextTime = 5;
    expect(guard.allows(clearedDraft), isFalse);
    final newDraft = _row(1, 1)
      ..draftText = 'new draft'
      ..draftTextTime = 5;
    expect(guard.allows(newDraft), isTrue);
  });
}
