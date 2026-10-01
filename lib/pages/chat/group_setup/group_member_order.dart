import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Keep both member screens in the same deterministic role order.
int compareGroupMembers(GroupMembersInfo a, GroupMembersInfo b) {
  int rank(int? role) => role == GroupRoleLevel.owner
      ? 0
      : role == GroupRoleLevel.admin
          ? 1
          : 2;
  final role = rank(a.roleLevel).compareTo(rank(b.roleLevel));
  if (role != 0) return role;
  final joined = (b.joinTime ?? 0).compareTo(a.joinTime ?? 0);
  return joined != 0 ? joined : (a.userID ?? '').compareTo(b.userID ?? '');
}
