import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/unread/friend_approval_notice.dart';

void main() {
  late Map<String, Map<String, dynamic>> persisted;
  late FriendApprovalNotice notices;
  FriendApprovalNotice create() => FriendApprovalNotice(
        read: (id) => persisted[id],
        write: (id, value) => persisted[id] = value,
      );
  ConversationInfo row({
    String sender = 'peer',
    String id = 'approval',
    int seq = 10,
    int type = MessageType.friendApplicationApprovedNotification,
  }) =>
      ConversationInfo(
        conversationID: 'single',
        conversationType: ConversationType.single,
        unreadCount: 0,
        latestMsg: Message(
            clientMsgID: id,
            sendID: sender,
            contentType: type,
            seq: seq,
            sendTime: seq * 1000),
      );

  setUp(() {
    persisted = {};
    notices = create();
  });

  test('both applicant and approver receive a dot without changing SDK counts',
      () {
    for (final sender in ['peer', 'self']) {
      final info = row(sender: sender);
      expect(notices.pending(info), isTrue);
      expect(info.unreadCount, 0);
    }
  });

  test('confirmed read survives restart and duplicate delivery', () {
    notices.confirm('single', messageID: 'approval', sequence: 10, time: 10000);
    expect(create().pending(row()), isFalse);
    expect(create().pending(row(id: 'new-approval', seq: 11)), isTrue);
  });

  test('read before metadata delivery suppresses the delayed dot', () {
    notices.confirm('single',
        messageID: 'following-message', sequence: 12, time: 12000);
    expect(notices.pending(row()), isFalse);
    notices.confirm('single', messageID: 'older-read', sequence: 9, time: 9000);
    expect(notices.pending(row(id: 'other', seq: 11)), isFalse);
    expect(notices.pending(row(id: 'new', seq: 13)), isTrue);
  });

  test('normal messages, groups and unidentified notices do not create dots',
      () {
    expect(notices.pending(row(type: MessageType.text)), isFalse);
    expect(notices.pending(row(id: '')), isFalse);
    final group = row()..conversationType = ConversationType.superGroup;
    expect(notices.pending(group), isFalse);
  });

  test('read for another conversation does not suppress approval', () {
    notices.confirm('other',
        messageID: 'approval', sequence: 100, time: 100000);
    expect(notices.pending(row()), isTrue);
  });

  test('unsequenced approval uses identity and time without losing re-add', () {
    notices.confirm('single', messageID: 'approval', sequence: 0, time: 0);
    expect(notices.pending(row(seq: 0)), isFalse);
    expect(notices.pending(row(seq: 0, id: 're-added')), isTrue);
  });
}
