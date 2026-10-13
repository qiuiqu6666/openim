import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../core/user_activity/activity_sdk.dart';
import '../../../../routes/app_navigator.dart';
import '../../../contacts/select_contacts/select_contacts_logic.dart';
import '../group_member_list/group_member_list_logic.dart';
import 'group_member_batch_result.dart';

typedef MemberPermissionCapture = bool Function() Function();
typedef MemberBatchWrite = Future<Object?> Function(String, List<String>);

/// Owns member mutation selection, accepted/failed results and explicit retries.
/// The setup route supplies a captured account/group/permission boundary.
class GroupMemberOperations {
  GroupMemberOperations({
    required MemberPermissionCapture captureCurrent,
    required GroupInfo Function() groupInfo,
    required bool Function() canRemove,
    required Future<void> Function() refreshMembers,
    Future<List<UserInfo>?> Function(String, List<UserInfo>)? pickInvites,
    Future<List<GroupMembersInfo>?> Function(GroupInfo)? pickRemovals,
    Future<bool?> Function(int)? chooseRetry,
    MemberBatchWrite? invite,
    MemberBatchWrite? remove,
    void Function(String)? showFeedback,
  })  : _captureCurrent = captureCurrent,
        _groupInfo = groupInfo,
        _canRemove = canRemove,
        _refreshMembers = refreshMembers,
        _pickInvites = pickInvites ?? _selectInvites,
        _pickRemovals = pickRemovals ??
            ((group) =>
                AppNavigator.startGroupMemberList<List<GroupMembersInfo>>(
                    groupInfo: group, opType: GroupMemberOpType.del)),
        _chooseRetry = chooseRetry ?? _confirmRetry,
        _invite = invite ??
            ((group, ids) => observeUserActivity(
                'group_invite',
                () => OpenIM.iMManager.groupManager.inviteUserToGroup(
                    groupID: group, userIDList: ids, reason: '邀请加入群聊'))),
        _remove = remove ??
            ((group, ids) => OpenIM.iMManager.groupManager.kickGroupMember(
                groupID: group, userIDList: ids, reason: '移除群聊')),
        _showFeedback =
            showFeedback ?? ((message) => IMViews.showToast(message));

  final MemberPermissionCapture _captureCurrent;
  final GroupInfo Function() _groupInfo;
  final bool Function() _canRemove;
  final Future<void> Function() _refreshMembers;
  final Future<List<UserInfo>?> Function(String, List<UserInfo>) _pickInvites;
  final Future<List<GroupMembersInfo>?> Function(GroupInfo) _pickRemovals;
  final Future<bool?> Function(int) _chooseRetry;
  final MemberBatchWrite _invite, _remove;
  final void Function(String) _showFeedback;
  bool _open = false, _closed = false;
  List<UserInfo> _failedInvites = [];
  List<GroupMembersInfo> _failedRemovals = [];

  static Future<List<UserInfo>?> _selectInvites(
      String group, List<UserInfo> failed) async {
    final selected = await AppNavigator.startSelectContacts(
        action: SelAction.addMember, groupID: group, checkedList: failed);
    final users = IMUtils.convertSelectContactsResultToUserInfo(selected);
    return users is List<UserInfo> ? users : null;
  }

  static Future<bool?> _confirmRetry(int count) =>
      Get.dialog<bool>(CustomDialog(
          title: Get.locale?.languageCode == 'en'
              ? 'Retry removing $count members?'
              : '重试移除上次未完成的 $count 名成员？',
          leftText: Get.locale?.languageCode == 'en' ? 'Select again' : '重新选择',
          rightText: Get.locale?.languageCode == 'en' ? 'Retry' : '重试'));

  Future<GroupMemberBatchResult?> _write(String group, List<String> ids,
      bool Function() current, MemberBatchWrite write) async {
    if (!current()) return null;
    try {
      final response =
          await LoadingView.singleton.wrap(asyncFunction: () async {
        if (!current()) throw StateError('Group permission changed');
        return write(group, ids);
      });
      return current() ? GroupMemberBatchResult.parse(response, ids) : null;
    } catch (_) {
      return current() ? GroupMemberBatchResult({}, ids.toSet()) : null;
    }
  }

  Future<void> inviteMembers() async {
    if (_closed || _open) return;
    final permission = _captureCurrent();
    bool current() => !_closed && permission();
    if (!current()) return;
    final group = _groupInfo().groupID;
    _open = true;
    try {
      final selected = await _pickInvites(group, List.of(_failedInvites));
      if (!current() || selected == null || selected.isEmpty) return;
      final ids = selected
          .map((user) => user.userID)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isEmpty) return;
      final result = await _write(group, ids, current, _invite);
      if (result == null) return;
      _failedInvites = selected
          .where((user) => result.failed.contains(user.userID))
          .toList();
      _showResult(result, invite: true);
      await _refreshMembers();
    } catch (_) {
      if (current()) _showFailure();
    } finally {
      _open = false;
    }
  }

  Future<void> removeMembers() async {
    if (_closed || _open) return;
    final permission = _captureCurrent();
    bool current() => !_closed && permission() && _canRemove();
    if (!current()) return;
    final group = GroupInfo.fromJson(_groupInfo().toJson());
    _open = true;
    try {
      List<GroupMembersInfo>? selected;
      if (_failedRemovals.isNotEmpty) {
        final retry = await _chooseRetry(_failedRemovals.length);
        if (!current() || retry == null) return;
        if (retry) selected = List.of(_failedRemovals);
      }
      selected ??= await _pickRemovals(group);
      if (!current() || selected == null || selected.isEmpty) return;
      final ids = selected
          .map((user) => user.userID)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isEmpty) return;
      final result = await _write(group.groupID, ids, current, _remove);
      if (result == null) return;
      _failedRemovals = selected
          .where((user) => result.failed.contains(user.userID))
          .toList();
      _showResult(result, invite: false);
      await _refreshMembers();
    } catch (_) {
      if (current()) _showFailure();
    } finally {
      _open = false;
    }
  }

  void _showFailure() => _showFeedback(Get.locale?.languageCode == 'en'
      ? 'Member operation failed. Please retry.'
      : '成员操作失败，请重试。');

  void _showResult(GroupMemberBatchResult result, {required bool invite}) {
    final english = Get.locale?.languageCode == 'en';
    _showFeedback(result.failed.isEmpty
        ? (english
            ? (invite ? 'Invitation sent' : 'Members removed')
            : (invite ? '邀请已发送' : '成员已移除'))
        : (english
            ? '${result.failed.length} member operations were not completed. Please retry.'
            : '${result.failed.length} 名成员的操作未完成，请重试。'));
  }

  void close() {
    _closed = true;
    _failedInvites.clear();
    _failedRemovals.clear();
  }
}
