import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

enum ChatMemberAction { mention, exclusiveRedPacket, mute, unmute, remove }

/// Decides avatar actions from the current SDK group/member snapshot.
///
/// Callers refresh the snapshot before executing a management action. OpenIM's
/// work groups support member moderation, unlike Tencent's Work group type;
/// this follows the existing OpenIM member permissions and removal screens.
class ChatMemberActionPolicy {
  ChatMemberActionPolicy._();

  // GroupStatus is present in the SDK sources but is not publicly exported.
  static const _bannedGroupStatus = 1;
  static const _dismissedGroupStatus = 2;

  static List<ChatMemberAction> actions({
    required String currentUserID,
    required GroupInfo? group,
    required GroupMembersInfo? self,
    required GroupMembersInfo? target,
    required bool isJoined,
    required bool isReadOnly,
    required bool sendingMuted,
    required int nowSeconds,
  }) {
    if (!isJoined ||
        isReadOnly ||
        group == null ||
        self == null ||
        target == null ||
        currentUserID.trim().isEmpty ||
        group.groupID.trim().isEmpty ||
        self.groupID != group.groupID ||
        target.groupID != group.groupID ||
        self.userID != currentUserID ||
        target.userID?.trim().isNotEmpty != true ||
        target.userID == currentUserID ||
        group.status == _bannedGroupStatus ||
        group.status == _dismissedGroupStatus) {
      return const [];
    }

    final result = <ChatMemberAction>[
      if (!sendingMuted) ChatMemberAction.mention,
      if (!sendingMuted) ChatMemberAction.exclusiveRedPacket,
    ];
    if (_canManage(group, self, target)) {
      result.add((target.muteEndTime ?? 0) > nowSeconds
          ? ChatMemberAction.unmute
          : ChatMemberAction.mute);
      result.add(ChatMemberAction.remove);
    }
    return List.unmodifiable(result);
  }

  static bool _canManage(
    GroupInfo group,
    GroupMembersInfo self,
    GroupMembersInfo target,
  ) {
    if (target.userID == group.ownerUserID ||
        target.roleLevel == GroupRoleLevel.owner) {
      return false;
    }
    final targetIsMember = target.roleLevel == GroupRoleLevel.member;
    final targetIsAdmin = target.roleLevel == GroupRoleLevel.admin;
    if (self.roleLevel == GroupRoleLevel.owner) {
      // A transferred group's stale owner role must not grant moderation.
      if (group.ownerUserID != null && group.ownerUserID != self.userID) {
        return false;
      }
      return targetIsMember || targetIsAdmin;
    }
    return self.roleLevel == GroupRoleLevel.admin && targetIsMember;
  }
}
