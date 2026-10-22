import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Permission lifetime for an open moderation page, including covered routes.
class GroupMemberPermissionSession {
  GroupMemberPermissionSession({required this.groupID, required bool owner})
      : _role = owner ? GroupRoleLevel.owner : GroupRoleLevel.admin,
        _session = _currentSession(),
        userID = OpenIM.iMManager.userID;

  final String groupID, userID;
  final Object _session;
  int _role;
  int revision = 0;
  bool _joined = true;
  bool _closed = false;

  static Object _currentSession() =>
      (DataSp.userID, OpenIM.iMManager.userID, DataSp.imToken, Config.imApiUrl);

  bool get active => !_closed && _joined && _session == _currentSession();
  bool get owner => active && _role == GroupRoleLevel.owner;
  bool get canManage =>
      active &&
      (_role == GroupRoleLevel.owner || _role == GroupRoleLevel.admin);
  bool current(int captured) => active && revision == captured;

  bool update(GroupMembersInfo member) {
    if (!active ||
        member.groupID != groupID ||
        member.userID != userID ||
        member.roleLevel == null ||
        member.roleLevel == _role) {
      return false;
    }
    _role = member.roleLevel!;
    revision++;
    return true;
  }

  bool updateGroup(GroupInfo group) {
    if (!active || group.groupID != groupID || group.ownerUserID == null) {
      return false;
    }
    if (_role == GroupRoleLevel.owner && group.ownerUserID != userID) {
      // The member callback supplies the actual downgraded role later.
      _role = GroupRoleLevel.member;
      revision++;
      return true;
    }
    return false;
  }

  void leave() {
    _joined = false;
    revision++;
  }

  void close() {
    _closed = true;
    revision++;
  }
}
