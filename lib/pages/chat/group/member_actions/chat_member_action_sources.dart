import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'chat_member_action_result.dart';

/// A fresh SDK view of both participants in one group.
class ChatMemberActionSnapshot {
  const ChatMemberActionSnapshot({
    required this.group,
    required this.self,
    required this.target,
    required this.isJoined,
  });

  final GroupInfo? group;
  final GroupMembersInfo? self, target;
  final bool isJoined;

  ChatMemberActionSnapshot withTarget(GroupMembersInfo? member) =>
      ChatMemberActionSnapshot(
        group: group,
        self: self,
        target: member,
        isJoined: isJoined,
      );
}

/// Keeps SDK queries and writes injectable without starting a global SDK in tests.
class ChatMemberActionSources {
  const ChatMemberActionSources({
    required this.read,
    required this.mute,
    required this.remove,
  });

  factory ChatMemberActionSources.sdk() => ChatMemberActionSources(
        read: (groupID, selfID, targetID) async {
          final manager = OpenIM.iMManager.groupManager;
          final (groups, members, joined) = await (
            manager.getGroupsInfo(groupIDList: [groupID]),
            manager.getGroupMembersInfo(
                groupID: groupID, userIDList: [selfID, targetID]),
            manager.isJoinedGroup(groupID: groupID),
          ).wait;
          GroupMembersInfo? member(String id) {
            for (final info in members) {
              if (info.userID == id && info.groupID == groupID) return info;
            }
            return null;
          }

          GroupInfo? group;
          for (final info in groups) {
            if (info.groupID == groupID) group = info;
          }
          return ChatMemberActionSnapshot(
              group: group,
              self: member(selfID),
              target: member(targetID),
              isJoined: joined);
        },
        mute: (groupID, targetID, seconds) async {
          final response = await OpenIM.iMManager.groupManager
              .changeGroupMemberMute(
                  groupID: groupID, userID: targetID, seconds: seconds);
          ensureChatMemberActionSucceeded(response, targetUserID: targetID);
        },
        remove: (groupID, targetID) async {
          final response = await OpenIM.iMManager.groupManager.kickGroupMember(
              groupID: groupID, userIDList: [targetID], reason: '移除群聊');
          ensureChatMemberActionSucceeded(response, targetUserID: targetID);
        },
      );

  final Future<ChatMemberActionSnapshot> Function(
      String groupID, String selfID, String targetID) read;
  final Future<void> Function(String groupID, String targetID, int seconds)
      mute;
  final Future<void> Function(String groupID, String targetID) remove;
}
