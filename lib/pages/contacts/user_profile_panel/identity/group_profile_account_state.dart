import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../chat/group/identity/group_member_identity.dart';

typedef GroupProfileMembersLoader = Future<List<GroupMemberIdentityInfo>>
    Function(String groupID, List<String> userIDs);

/// A group disclosure belongs to this page, not to the general friend cache.
class GroupProfileAccountState {
  GroupProfileAccountState({
    required this.groupID,
    required this.userID,
    GroupProfileMembersLoader? load,
    String? Function()? owner,
    String? Function()? sdkOwner,
    String? Function()? token,
    String Function()? server,
  })  : _load = load ?? _membersLoader(),
        _owner = owner ?? (() => DataSp.userID),
        _sdkOwner = sdkOwner ?? (() => OpenIM.iMManager.userID),
        _token = token ?? (() => DataSp.imToken),
        _server = server ?? (() => Config.imApiUrl);

  final String groupID;
  final String userID;
  final GroupProfileMembersLoader _load;
  final String? Function() _owner;
  final String? Function() _sdkOwner;
  final String? Function() _token;
  final String Function() _server;
  final account = RxnString();
  int _generation = 0;
  bool _closed = false;
  (String?, String?, String?, String)? _scope;

  static GroupProfileMembersLoader _membersLoader() {
    final source = GroupMemberIdentitySource();
    return (groupID, userIDs) =>
        source.members(groupID: groupID, userIDList: userIDs);
  }

  (String?, String?, String?, String) get _session =>
      (_owner(), _sdkOwner(), _token(), _server());

  String get value {
    final current = account.value;
    return !_closed && _scope == _session ? current ?? '' : '';
  }

  void invalidate() {
    _generation++;
    _scope = null;
    account.value = null;
  }

  Future<void> refresh() async {
    if (_closed) return;
    invalidate();
    final generation = _generation;
    final session = _session;
    if (session.$1?.isNotEmpty != true ||
        session.$3?.isNotEmpty != true ||
        groupID.isEmpty ||
        userID.isEmpty) {
      return;
    }
    try {
      final members = await _load(groupID, [userID]);
      if (_closed || generation != _generation || session != _session) return;
      final target = members.firstWhereOrNull(
          (member) => member.groupID == groupID && member.userID == userID);
      _scope = session;
      account.value = target?.account;
    } catch (_) {
      // An optional account lookup must never invent an ID or keep old access.
    }
  }

  void close() {
    invalidate();
    _closed = true;
  }
}
