import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/group_identity/legacy_group_conversation_projection.dart';

const group = 'lg_4b41122c9b36f283ffa962265a4385a6';
const oldID = 'sg_$group';
const newID = 'sg_@$group';

ConversationInfo row(String id) => ConversationInfo(
      conversationID: 'sg_$id',
      groupID: id,
      conversationType: ConversationType.superGroup,
      showName: 'same group name',
      latestMsgSendTime: 100,
      draftTextTime: 0,
      latestMsg: Message(clientMsgID: 'stable', seq: 10),
    );

void main() {
  late LegacyGroupConversationProjection projection;
  late ConversationInfo old;
  late ConversationInfo next;
  setUp(() {
    projection = LegacyGroupConversationProjection(
        server: 'http://129.226.192.93:10002');
    old = row(group);
    next = row('@$group');
  });

  for (final reverse in [false, true]) {
    test('canonical row wins in either snapshot/event order ($reverse)', () {
      old.unreadCount = 8;
      next
        ..unreadCount = 2
        ..isPinned = false
        ..recvMsgOpt = 2;
      final before = old.toJson();
      final result = projection.project(reverse ? [next, old] : [old, next]);
      expect(result, [same(next)]);
      expect(result.single.unreadCount, 2);
      expect(result.single.recvMsgOpt, 2);
      expect(old.toJson(), before);
    });
  }

  test('old entry remains available until replacement arrives', () {
    expect(projection.project([old]), [old]);
    expect(projection.project([old, next]), [next]);
  });

  test('late old callback cannot recreate row after replacement was hidden',
      () {
    expect(projection.project([old, next]), [next]);
    expect(projection.project([row(group)]), isEmpty);
    projection.clear();
    expect(projection.project([old]), [old]);
  });

  test('same names and unrelated IDs are never merged', () {
    final unrelated = row('lg_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    expect(projection.project([old, next, unrelated]), [next, unrelated]);
    final ordinary = row('regular');
    final prefixed = row('@regular');
    expect(projection.project([ordinary, prefixed]), [ordinary, prefixed]);
  });

  test('does not apply to another server or malformed group metadata', () {
    final elsewhere =
        LegacyGroupConversationProjection(server: 'https://other.example');
    expect(elsewhere.project([old, next]), [old, next]);
    next.groupID = 'different';
    expect(projection.project([old, next]), [old, next]);
    next.groupID = '@$group';
    next.conversationType = ConversationType.single;
    expect(projection.project([old, next]), [old, next]);
  });

  test('keeps recovery access to unique drafts and unsent local messages', () {
    old.draftText = '{"text":"unsaved","atUserList":[]}';
    expect(projection.project([old, next]), [old, next]);
    expect(old.draftText, '{"text":"unsaved","atUserList":[]}');
    next.draftText = old.draftText;
    expect(projection.project([old, next]), [next]);
    old.draftText = '';
    old.latestMsg = Message(clientMsgID: 'pending', seq: 0);
    expect(projection.project([old, next]), [old, next]);
    old.latestMsg = Message(clientMsgID: 'failed');
    expect(projection.project([old, next]), [old, next]);
  });

  test('duplicate occurrences of an exact CID also collapse', () {
    expect(projection.project([old, next, old, next]), [next]);
  });

  test('successful own send can have no synchronized sequence yet', () {
    old.latestMsg =
        Message(clientMsgID: 'sent', seq: 0, status: MessageStatus.succeeded);
    expect(projection.project([old, next]), [next]);
    old.latestMsg!.seq = null;
    expect(projection.project([old, next]), [next]);
    old.latestMsg!
      ..seq = 10
      ..status = MessageStatus.failed;
    expect(projection.project([old, next]), [old, next]);
  });
}
