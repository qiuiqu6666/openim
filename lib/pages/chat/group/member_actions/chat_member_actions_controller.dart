import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'chat_member_action_policy.dart';
import 'chat_member_action_sources.dart';

typedef ChatMemberActionLoading = Future<T> Function<T>(
    Future<T> Function() action);

/// Coordinates one avatar menu without owning chat input or group subscriptions.
class ChatMemberActionsController {
  ChatMemberActionsController({
    required this.groupID,
    required this.currentUserID,
    required this.isSessionInactive,
    required this.isJoined,
    required this.groupRevision,
    required this.sendingMuted,
    required this.mention,
    required this.sendExclusiveRedPacket,
    required this.memberUpdated,
    required this.memberRemoved,
    required this.showFeedback,
    this.latestMember,
    this.latestGroup,
    bool Function(String id)? isKnownRemoved,
    ChatMemberActionSources? sources,
    ChatMemberActionLoading? runLoading,
    int Function()? nowSeconds,
  })  : _sources = sources ?? ChatMemberActionSources.sdk(),
        _runLoading = runLoading ?? _direct,
        _nowSeconds = nowSeconds ?? _systemNowSeconds,
        _isKnownRemoved = isKnownRemoved ?? ((_) => false);

  final String? Function() groupID;
  final String Function() currentUserID;
  final bool Function() isSessionInactive, isJoined, sendingMuted;
  final int Function() groupRevision;
  final GroupMembersInfo? Function(String id)? latestMember;
  final GroupInfo? Function()? latestGroup;
  final void Function(Message message) mention;
  final Future<void> Function(GroupMembersInfo member) sendExclusiveRedPacket;
  final void Function(GroupMembersInfo member) memberUpdated, memberRemoved;
  final void Function(String text) showFeedback;
  final ChatMemberActionSources _sources;
  final ChatMemberActionLoading _runLoading;
  final int Function() _nowSeconds;
  final bool Function(String id) _isKnownRemoved;
  final _acceptedMutes = <String, GroupMembersInfo>{};
  bool _busy = false, _closed = false;

  // Matches the reference avatar action: effectively muted until explicitly released.
  static const muteSeconds = 315360000;
  static Future<T> _direct<T>(Future<T> Function() action) => action();
  static int _systemNowSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;

  bool _current(String id, String accountID) =>
      !_closed &&
      !isSessionInactive() &&
      isJoined() &&
      groupID() == id &&
      currentUserID() == accountID;

  Future<ChatMemberActionSnapshot?> _read(
      String id, String accountID, String targetID) async {
    if (!_current(id, accountID)) return null;
    final revision = groupRevision();
    var snapshot = await _sources.read(id, accountID, targetID);
    if (!_current(id, accountID)) return null;
    if (revision != groupRevision()) {
      showFeedback('群成员信息已变化，请重新长按头像');
      return null;
    }
    if (_isKnownRemoved(targetID)) return snapshot.withTarget(null);
    final target = snapshot.target;
    final accepted = _acceptedMutes[targetID];
    // SDK reads immediately after a successful write can still use its old cache.
    // A later member event supersedes our accepted value through latestMember.
    if (target != null && accepted != null) {
      if (target.muteEndTime == accepted.muteEndTime ||
          target.roleLevel != accepted.roleLevel ||
          (latestMember != null &&
              !identical(latestMember!(targetID), accepted))) {
        _acceptedMutes.remove(targetID);
      } else {
        snapshot = snapshot.withTarget(
            GroupMembersInfo.fromJson(target.toJson())
              ..muteEndTime = accepted.muteEndTime);
      }
    }
    final cached = latestMember?.call(targetID);
    if (snapshot.target != null &&
        cached?.groupID == id &&
        cached?.userID == targetID) {
      snapshot = snapshot.withTarget(
          GroupMembersInfo.fromJson(snapshot.target!.toJson())
            ..muteEndTime = cached!.muteEndTime);
    }
    return snapshot;
  }

  List<ChatMemberAction> _actions(
      ChatMemberActionSnapshot snapshot, String accountID) {
    final self = snapshot.self;
    final snapshotMuted = (self?.muteEndTime ?? 0) > _nowSeconds() ||
        (self?.roleLevel == GroupRoleLevel.member &&
            snapshot.group?.status == 3);
    List<ChatMemberAction> allowed(ChatMemberActionSnapshot state) =>
        ChatMemberActionPolicy.actions(
          currentUserID: accountID,
          group: state.group,
          self: state.self,
          target: state.target,
          isJoined: state.isJoined && isJoined(),
          isReadOnly: isSessionInactive(),
          sendingMuted: snapshotMuted || sendingMuted(),
          nowSeconds: _nowSeconds(),
        );
    final actions = allowed(snapshot);
    final cachedActions = allowed(ChatMemberActionSnapshot(
      group: latestGroup?.call() ?? snapshot.group,
      self: latestMember?.call(accountID) ?? snapshot.self,
      target: snapshot.target == null
          ? null
          : latestMember?.call(snapshot.target!.userID!) ?? snapshot.target,
      isJoined: snapshot.isJoined,
    ));
    // Both the SDK read and newer event state must grant the role permission.
    // A synthetic promotion event can precede the SDK's local-cache update.
    return actions.where(cachedActions.contains).toList();
  }

  Future<void> open(
    Message message, {
    required Future<ChatMemberAction?> Function(
            List<ChatMemberAction> actions, String name)
        showMenu,
    required Future<bool> Function(ChatMemberAction action, String name)
        confirm,
  }) async {
    final id = groupID();
    final accountID = currentUserID();
    final targetID = message.sendID;
    if (_busy ||
        id == null ||
        id.isEmpty ||
        accountID.isEmpty ||
        targetID == null ||
        targetID.isEmpty ||
        targetID == accountID ||
        !_current(id, accountID)) {
      return;
    }

    _busy = true;
    try {
      final snapshot = await _runLoading(() => _read(id, accountID, targetID));
      if (snapshot == null || !_current(id, accountID)) return;
      final actions = _actions(snapshot, accountID);
      if (actions.isEmpty) {
        showFeedback(snapshot.target == null ? '该用户已退出群聊' : '当前无法操作该群成员');
        return;
      }
      final name = snapshot.target?.nickname?.trim().isNotEmpty == true
          ? snapshot.target!.nickname!.trim()
          : message.senderNickname?.trim().isNotEmpty == true
              ? message.senderNickname!.trim()
              : targetID;
      final menuRevision = groupRevision();
      final action = await showMenu(actions, name);
      if (action == null ||
          !actions.contains(action) ||
          !_current(id, accountID)) {
        return;
      }
      if (menuRevision != groupRevision()) {
        showFeedback('成员权限或禁言状态已变化，请重新长按头像');
        return;
      }
      final needsConfirmation = action == ChatMemberAction.mute ||
          action == ChatMemberAction.unmute ||
          action == ChatMemberAction.remove;
      if (needsConfirmation && !await confirm(action, name)) {
        return;
      }
      if (!_current(id, accountID)) return;
      if (menuRevision != groupRevision()) {
        showFeedback('成员权限或禁言状态已变化，请重新长按头像');
        return;
      }

      final current = await _runLoading(() async {
        if (!_current(id, accountID)) return null;
        if (menuRevision != groupRevision()) {
          showFeedback('成员权限或禁言状态已变化，请重新长按头像');
          return null;
        }
        final current = await _read(id, accountID, targetID);
        if (current == null || !_current(id, accountID)) return null;
        if (!_actions(current, accountID).contains(action)) {
          showFeedback('成员权限或禁言状态已变化，请重新长按头像');
          return null;
        }
        return current;
      });
      if (current == null || !_current(id, accountID)) return;
      if (menuRevision != groupRevision()) {
        showFeedback('成员权限或禁言状态已变化，请重新长按头像');
        return;
      }
      final target = current.target!;
      if (action == ChatMemberAction.mention) {
        mention(Message()
          ..sendID = targetID
          ..senderNickname = target.nickname?.trim().isNotEmpty == true
              ? target.nickname!.trim()
              : name);
        return;
      }
      if (action == ChatMemberAction.exclusiveRedPacket) {
        // Dismiss loading before navigation; payment remains on the send page.
        await sendExclusiveRedPacket(GroupMembersInfo.fromJson(target.toJson())
          ..nickname = target.nickname?.trim().isNotEmpty == true
              ? target.nickname!.trim()
              : name);
        return;
      }

      await _runLoading(() async {
        if (!_current(id, accountID)) return;
        if (menuRevision != groupRevision()) {
          showFeedback('成员权限或禁言状态已变化，请重新长按头像');
          return;
        }
        switch (action) {
          case ChatMemberAction.mute:
          case ChatMemberAction.unmute:
            final seconds = action == ChatMemberAction.mute ? muteSeconds : 0;
            final writeRevision = groupRevision();
            await _sources.mute(id, targetID, seconds);
            if (!_current(id, accountID)) return;
            if (writeRevision != groupRevision()) {
              showFeedback('操作已完成');
              return;
            }
            final updated = GroupMembersInfo.fromJson(target.toJson())
              ..muteEndTime = seconds == 0 ? 0 : _nowSeconds() + seconds;
            _acceptedMutes[targetID] = updated;
            memberUpdated(updated);
            showFeedback(seconds == 0 ? '已解除禁言' : '已禁言');
          case ChatMemberAction.remove:
            final writeRevision = groupRevision();
            await _sources.remove(id, targetID);
            if (!_current(id, accountID)) return;
            if (writeRevision != groupRevision()) {
              showFeedback('操作已完成');
              return;
            }
            _acceptedMutes.remove(targetID);
            memberRemoved(target);
            showFeedback('已移除群聊');
          case ChatMemberAction.mention:
          case ChatMemberAction.exclusiveRedPacket:
            return;
        }
      });
    } catch (error) {
      if (_current(id, accountID)) showFeedback('操作失败：$error');
    } finally {
      _busy = false;
    }
  }

  void close() {
    _closed = true;
    _acceptedMutes.clear();
  }
}
