import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../group/identity/group_member_identity.dart';

typedef GroupMemberIdentityRules = ({GroupInfo? group, GroupMembersInfo? self});

/// Owns the authority and request generation for one open member list.
class GroupMemberIdentityState {
  GroupMemberIdentityState({
    GroupMemberIdentitySource? source,
    Object Function()? session,
    Future<GroupMemberIdentityRules> Function(String groupID)? rulesLoader,
  })  : source = source ?? GroupMemberIdentitySource(),
        _session = session ?? _currentSession,
        _rulesLoader = rulesLoader ?? _sdkRules {
    _owner = _session();
  }

  final GroupMemberIdentitySource source;
  final Object Function() _session;
  final Future<GroupMemberIdentityRules> Function(String groupID) _rulesLoader;
  late final Object _owner;
  int _generation = 0;
  bool _closed = false;

  static Object _currentSession() =>
      (DataSp.userID, OpenIM.iMManager.userID, DataSp.imToken, Config.imApiUrl);

  int get generation => _generation;
  bool get isCurrentSession => !_closed && _session() == _owner;
  bool active(int generation) => isCurrentSession && generation == _generation;

  void invalidate() => ++_generation;
  void close() {
    _closed = true;
    invalidate();
  }

  static Future<GroupMemberIdentityRules> _sdkRules(String groupID) async {
    final manager = OpenIM.iMManager.groupManager;
    final selfID = OpenIM.iMManager.userID;
    final values = await Future.wait([
      manager.getGroupsInfo(groupIDList: [groupID]),
      manager.getGroupMembersInfo(groupID: groupID, userIDList: [selfID]),
    ]);
    GroupInfo? group;
    GroupMembersInfo? self;
    for (final value in values[0].cast<GroupInfo>()) {
      if (value.groupID == groupID) group = value;
    }
    for (final value in values[1].cast<GroupMembersInfo>()) {
      if (value.userID == selfID) self = value;
    }
    return (group: group, self: self);
  }

  Future<GroupMemberIdentityRules?> rules(String groupID) async {
    final request = generation;
    if (!active(request)) return null;
    try {
      final result = await _rulesLoader(groupID);
      return active(request) ? result : null;
    } catch (_) {
      if (!active(request)) return null;
      rethrow;
    }
  }

  Future<List<GroupMemberIdentityInfo>?> list({
    required String groupID,
    required int pageNumber,
    required int showNumber,
  }) async {
    final request = generation;
    if (!active(request)) return null;
    try {
      final result = await source.list(
          groupID: groupID, pageNumber: pageNumber, showNumber: showNumber);
      return active(request) ? result : null;
    } catch (_) {
      if (!active(request)) return null;
      rethrow;
    }
  }

  /// Search remains SDK-backed; only the group endpoint can supply account.
  Future<List<GroupMemberIdentityInfo>?> searchIdentities(
      String groupID, List<GroupMembersInfo> members) async {
    final request = generation;
    if (!active(request)) return null;
    final ids = members
        .map((member) => member.userID)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    try {
      final identities = ids.isEmpty
          ? <GroupMemberIdentityInfo>[]
          : await source.members(groupID: groupID, userIDList: ids);
      if (!active(request)) return null;
      final accounts = {
        for (final identity in identities)
          if (identity.groupID == groupID) identity.userID: identity.account,
      };
      return [
        for (final member in members)
          GroupMemberIdentityInfo.fromJson({
            ...member.toJson()..remove('account'),
            'account': accounts[member.userID],
          }),
      ];
    } catch (_) {
      if (!active(request)) return null;
      rethrow;
    }
  }

  static String accountOf(GroupMembersInfo member) =>
      member is GroupMemberIdentityInfo ? member.account?.trim() ?? '' : '';

  static GroupMemberIdentityInfo withoutAccount(GroupMembersInfo member) =>
      GroupMemberIdentityInfo.fromJson(member.toJson()..remove('account'));

  /// SDK notifications contain member metadata, not an account permission grant.
  static GroupMemberIdentityInfo mergeEvent(
          GroupMembersInfo event, GroupMembersInfo previous) =>
      GroupMemberIdentityInfo.fromJson({
        ...event.toJson()..remove('account'),
        'account': accountOf(previous),
      });
}
