import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/chat/group/member_actions/chat_member_action_sources.dart';
import 'package:openim/pages/chat/messages/revocation/chat_message_revocation.dart';

class RevocationFixture {
  RevocationFixture({Future<bool> Function()? confirm}) {
    controller = ChatMessageRevocation(
      confirm: confirm,
      log: events.add,
      conversationID: () => conversation,
      currentUserID: () => account,
      groupID: () => groupID,
      groupInfo: () => group,
      memberRole: (id) => id == account ? selfRole : senderRole,
      isJoined: () => joined,
      groupRevision: () => revision,
      isCurrentMessage: (_) => messageCurrent,
      isClosed: () => closed,
      onRevoked: removed.add,
      showFeedback: feedback.add,
      nowMilliseconds: () => clock,
      readMembers: (groupID, account, sender) async {
        reads.add((groupID, account, sender));
        return onRead != null ? await onRead!() : snapshot;
      },
      revoke: ({required conversationID, required clientMsgID}) async {
        requests.add((conversationID, clientMsgID));
        await onRevoke?.call();
      },
    );
  }

  static const now = 1800000000000;
  int clock = now;
  final events = <Map<String, Object?>>[];
  String account = 'admin', conversation = 'sg_group';
  String? groupID = 'group';
  GroupInfo? group = GroupInfo(groupID: 'group', ownerUserID: 'owner');
  int? selfRole = GroupRoleLevel.admin, senderRole = GroupRoleLevel.member;
  bool joined = true, messageCurrent = true, closed = false;
  int revision = 0;
  final removed = <String>[];
  final feedback = <String>[];
  final reads = <(String, String, String)>[];
  final requests = <(String, String)>[];
  Future<ChatMemberActionSnapshot> Function()? onRead;
  Future<void> Function()? onRevoke;
  late final ChatMessageRevocation controller;

  Message message({String sender = 'member', int ageSeconds = 3600}) =>
      Message.fromJson({
        'clientMsgID': 'message',
        'sendID': sender,
        'recvID': groupID ?? 'peer',
        'groupID': groupID,
        'sessionType': groupID == null
            ? ConversationType.single
            : ConversationType.superGroup,
        'contentType': MessageType.text,
        'status': MessageStatus.succeeded,
        'sendTime': now - ageSeconds * 1000,
        'textElem': {'content': 'Test message'},
      });

  ChatMemberActionSnapshot get snapshot => ChatMemberActionSnapshot(
        group: group,
        self: GroupMembersInfo(
            groupID: groupID, userID: account, roleLevel: selfRole),
        target: GroupMembersInfo(
            groupID: groupID, userID: 'member', roleLevel: senderRole),
        isJoined: joined,
      );
}
