import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/unread/conversation_unread_count.dart';

ConversationInfo _row(String id,
        {int? receive = 0,
        int unread = 1,
        int? type = ConversationType.single}) =>
    ConversationInfo(
        conversationID: id,
        conversationType: type,
        recvMsgOpt: receive,
        unreadCount: unread);

void main() {
  test('notification counts exclude muted and rejected messages', () {
    final normal = _row('normal', unread: 3);
    final defaultReception = _row('default', receive: null, unread: 4);
    final muted = _row('muted', receive: 2, unread: 150);
    final rejected = _row('rejected', receive: 1, unread: 200);

    expect(
        sumNotifiableConversationUnread(
            [normal, defaultReception, muted, rejected]),
        7);
    expect(muted.unreadCount, 150);
    expect(rejected.unreadCount, 200);
    expect(notifiableConversationUnreadCount(_row('empty', unread: 0)), 0);
    expect(notifiableConversationUnreadCount(_row('invalid', unread: -9)), 0);
  });

  test('tab scope excludes archives while global scope includes every SDK type',
      () {
    final rows = [
      _row('single', unread: 3),
      _row('group', type: ConversationType.superGroup, unread: 4),
      _row('super-group', type: ConversationType.superGroup, unread: 5),
      _row('archived', type: ConversationType.superGroup, unread: 6),
      _row('other-sdk-type', type: null, unread: 7),
    ];
    bool archived(ConversationInfo row) => row.conversationID == 'archived';

    expect(sumNotifiableConversationUnread(rows), 25);
    expect(
        sumNotifiableConversationUnread(rows,
            groupChats: false, isArchived: archived),
        3);
    expect(
        sumNotifiableConversationUnread(rows,
            groupChats: true, isArchived: archived),
        9);
  });

  test(
      'notification counts use the current read projection without mutating SDK',
      () {
    final rows = [
      _row('read-elsewhere', type: ConversationType.superGroup, unread: 180),
      _row('new-message', type: ConversationType.superGroup, unread: 2),
      _row('muted', type: ConversationType.superGroup, receive: 2, unread: 100),
    ];
    int projected(ConversationInfo row) => switch (row.conversationID) {
          'read-elsewhere' => 0,
          'new-message' => 4,
          _ => row.unreadCount,
        };

    expect(
        sumNotifiableConversationUnread(rows,
            groupChats: true, unreadCountFor: projected),
        4);
    expect(rows.map((row) => row.unreadCount), [180, 2, 100]);
    expect(notifiableConversationUnreadCount(rows.first, unreadCount: -1), 0);
  });

  test('SDK total follows reception and timestamp rules across all row types',
      () {
    final normal = _row('normal', unread: 3)..latestMsgSendTime = 10;
    final defaultReception = _row('default', receive: null, unread: 4)
      ..latestMsgSendTime = 10;
    final rejected = _row('rejected', receive: 1, unread: 5)
      ..latestMsgSendTime = 10;
    final muted = _row('muted', receive: 2, unread: 200)
      ..latestMsgSendTime = 10;
    final archived =
        _row('archived', type: ConversationType.superGroup, unread: 6)
          ..latestMsgSendTime = 10;
    final otherType = _row('other-sdk-type', type: null, unread: 7)
      ..latestMsgSendTime = 10;
    final noTimestamp = _row('no-time', unread: 300);
    final emptyTimestamp = _row('zero-time', unread: 400)
      ..latestMsgSendTime = 0;
    final invalidCount = _row('negative-unread', unread: -100)
      ..latestMsgSendTime = 10;

    expect(
        sumSdkConversationUnread([
          normal,
          defaultReception,
          rejected,
          muted,
          archived,
          otherType,
          noTimestamp,
          emptyTimestamp,
          invalidCount,
        ]),
        25);
    expect(rejected.unreadCount, 5);
    expect(muted.unreadCount, 200);
    expect(invalidCount.unreadCount, -100);
  });
}
