import 'dart:async';
import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import 'chat_group_sources.dart';

export 'chat_group_sources.dart';

/// Owns one chat's group metadata, membership, role and mute lifecycle.
class ChatGroupController {
  ChatGroupController({
    required IMController im,
    required String? Function() groupID,
    required RxList<Message> messages,
    required void Function() clearInput,
    required void Function(String name, String face) onGroupProfileChanged,
    void Function(GroupInfo)? onGroupInfoApplied,
    GroupInfo? Function(String groupID)? readCachedGroupInfo,
    String Function()? currentUserID,
    void Function(Object)? reportError,
  }) : this.withSources(
          events: ChatGroupEvents.fromController(im),
          queries: ChatGroupQueries.sdk(),
          groupID: groupID,
          currentUserID: currentUserID ?? (() => OpenIM.iMManager.userID),
          messages: messages,
          clearInput: clearInput,
          onGroupProfileChanged: onGroupProfileChanged,
          onGroupInfoApplied: onGroupInfoApplied,
          readCachedGroupInfo: readCachedGroupInfo,
          reportError: reportError,
        );

  ChatGroupController.withSources({
    required ChatGroupEvents events,
    required ChatGroupQueries queries,
    required this.groupID,
    required this.currentUserID,
    required this.messages,
    required this.clearInput,
    required this.onGroupProfileChanged,
    this.onGroupInfoApplied,
    this.readCachedGroupInfo,
    this.reportError,
    int Function()? nowSeconds,
  })  : _events = events,
        _queries = queries,
        _nowSeconds = nowSeconds ?? _systemNowSeconds,
        _accountID = currentUserID();

  final String? Function() groupID;
  final String Function() currentUserID;
  final RxList<Message> messages;
  final void Function() clearInput;
  final void Function(String name, String face) onGroupProfileChanged;
  final void Function(GroupInfo)? onGroupInfoApplied;
  final GroupInfo? Function(String groupID)? readCachedGroupInfo;
  final void Function(Object)? reportError;
  final ChatGroupEvents _events;
  final ChatGroupQueries _queries;
  final int Function() _nowSeconds;
  final String _accountID;

  GroupInfo? groupInfo;
  GroupMembersInfo? groupMembersInfo;
  String? groupOwnerID;
  final ownerAndAdmin = <GroupMembersInfo>[];
  final memberUpdateInfoMap = <String, GroupMembersInfo>{};
  final _removedMemberIDs = <String>{};
  final groupMemberRoleLevel = GroupRoleLevel.member.obs;
  final isInGroup = true.obs;
  final memberCount = 0.obs;
  final announcement = ''.obs;
  final announcementVersion = ''.obs;
  final _muteRevision = 0.obs;
  final _subscriptions = <StreamSubscription>[];
  Timer? _muteTimer;
  Future<void>? _loadRequest;
  bool _initialized = false;
  bool _closed = false;
  int _membershipRevision = 0;
  int _profileRevision = 0;
  int _selfRevision = 0;
  int _adminRevision = 0;
  int _memberActionRevision = 0;
  final _adminChanges = <String, (int, GroupMembersInfo?)>{};

  bool get isClosed => _closed;

  /// Invalidates avatar permission reads when SDK membership or roles change.
  int get memberActionRevision => _memberActionRevision;
  bool hasMemberLeft(String userID) => _removedMemberIDs.contains(userID);
  bool get isGroupChat => groupID()?.trim().isNotEmpty == true;
  bool get isInvalidGroup => isGroupChat && !isInGroup.value;
  bool get isAdminOrOwner =>
      groupMemberRoleLevel.value == GroupRoleLevel.admin ||
      groupMemberRoleLevel.value == GroupRoleLevel.owner;
  bool get havePermissionMute =>
      isGroupChat && groupInfo?.ownerUserID == currentUserID();

  bool get sendingMuted {
    _muteRevision.value;
    return isGroupChat &&
        ((groupMembersInfo?.muteEndTime ?? 0) > _nowSeconds() ||
            (groupMemberRoleLevel.value == GroupRoleLevel.member &&
                groupInfo?.status == 3));
  }

  static int _systemNowSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;

  void initialize() {
    if (_closed || _initialized || !isGroupChat) return;
    _initialized = true;
    final id = groupID()!;
    final cached = _matches(id) ? readCachedGroupInfo?.call(id) : null;
    if (cached?.groupID == id) _applyGroupInfo(cached);
    _subscriptions.addAll([
      _events.joined.listen((info) {
        if (!_matches(info.groupID)) return;
        _memberActionRevision++;
        _removedMemberIDs.clear();
        _membershipRevision++;
        isInGroup.value = true;
        unawaited(_loadJoinedGroup());
      }),
      _events.left.listen((info) {
        if (_matches(info.groupID)) _leaveGroup();
      }),
      _events.memberAdded.listen((info) {
        if (!_matches(info.groupID)) return;
        _memberActionRevision++;
        _removedMemberIDs.remove(info.userID);
        _putMemberInfo(info);
        messages.refresh();
      }),
      _events.memberDeleted.listen((info) {
        if (!_matches(info.groupID)) return;
        _memberActionRevision++;
        final id = info.userID;
        if (id != null) {
          _removedMemberIDs.add(id);
          _recordAdminChange(id, null);
          memberUpdateInfoMap.remove(id);
        }
        if (info.userID == currentUserID()) _leaveGroup();
      }),
      _events.memberChanged.listen(_onMemberChanged),
      _events.groupChanged.listen((info) {
        if (!_matches(info.groupID)) return;
        _memberActionRevision++;
        _profileRevision++;
        _applyGroupInfo(info);
      }),
    ]);
  }

  bool _matches(String? id) =>
      !_closed &&
      currentUserID() == _accountID &&
      isGroupChat &&
      id == groupID();

  bool _queryStillCurrent(String id, String userID, int membership) =>
      _matches(id) &&
      currentUserID() == userID &&
      membership == _membershipRevision;

  void _leaveGroup() {
    _memberActionRevision++;
    _membershipRevision++;
    isInGroup.value = false;
    clearInput();
  }

  /// The page calls this after its first history page, without delaying history.
  /// Overlapping calls share the same membership check and metadata requests.
  Future<void> loadAfterHistory() {
    if (!_matches(groupID())) return Future<void>.value();
    return _loadRequest ??=
        _checkMembershipAndLoad().whenComplete(() => _loadRequest = null);
  }

  Future<void> _checkMembershipAndLoad() async {
    final id = groupID()!;
    final userID = currentUserID();
    final revision = _membershipRevision;
    try {
      final joined = await _queries.isJoined(id);
      if (!_queryStillCurrent(id, userID, revision)) return;
      isInGroup.value = joined;
      if (joined) await _loadJoinedGroup();
    } catch (error) {
      if (_queryStillCurrent(id, userID, revision)) _report(error);
    }
  }

  Future<void> _loadJoinedGroup() async {
    if (!_matches(groupID()) || !isInGroup.value) return;
    final id = groupID()!;
    final userID = currentUserID();
    final revision = _membershipRevision;
    await Future.wait([
      _queryGroupInfo(id, userID, revision),
      _querySelfMember(id, userID, revision),
      _queryOwnerAndAdmin(id, userID, revision),
    ]);
  }

  Future<void> _queryGroupInfo(String id, String userID, int membership) async {
    final revision = _profileRevision;
    try {
      final list = await _queries.groupInfo(id);
      if (!_queryStillCurrent(id, userID, membership) ||
          revision != _profileRevision) {
        return;
      }
      _applyGroupInfo(list.firstOrNull);
    } catch (error) {
      if (_queryStillCurrent(id, userID, membership)) _report(error);
    }
  }

  Future<void> _querySelfMember(
      String id, String userID, int membership) async {
    final revision = _selfRevision;
    try {
      final list = await _queries.selfMember(id, userID);
      if (!_queryStillCurrent(id, userID, membership) ||
          revision != _selfRevision) {
        return;
      }
      groupMembersInfo = list.firstOrNull;
      groupMemberRoleLevel.value =
          groupMembersInfo?.roleLevel ?? GroupRoleLevel.member;
      final member = groupMembersInfo;
      if (member != null) _putMemberInfo(member);
      _refreshMute();
      messages.refresh();
    } catch (error) {
      if (_queryStillCurrent(id, userID, membership)) _report(error);
    }
  }

  Future<void> _queryOwnerAndAdmin(
      String id, String userID, int membership) async {
    final revision = _adminRevision;
    try {
      final list = await _queries.ownerAndAdmin(id);
      if (!_queryStillCurrent(id, userID, membership)) return;
      ownerAndAdmin
        ..clear()
        ..addAll(list);
      for (final entry in _adminChanges.entries) {
        if (entry.value.$1 > revision) {
          _applyAdminChange(entry.key, entry.value.$2);
        }
      }
    } catch (error) {
      if (_queryStillCurrent(id, userID, membership)) _report(error);
    }
  }

  void _applyGroupInfo(GroupInfo? info) {
    groupInfo = info;
    announcementVersion.value = info?.notificationUpdateTime?.toString() ?? '';
    announcement.value = info?.notification ?? '';
    groupOwnerID = info?.ownerUserID;
    memberCount.value = info?.memberCount ?? 0;
    _refreshMute();
    if (info != null) {
      onGroupInfoApplied?.call(info);
      onGroupProfileChanged(info.groupName ?? '', info.faceURL ?? '');
    }
  }

  void _putMemberInfo(GroupMembersInfo member) {
    final id = member.userID;
    if (id != null && id.isNotEmpty) memberUpdateInfoMap[id] = member;
  }

  void _onMemberChanged(GroupMembersInfo info) {
    if (!_matches(info.groupID)) return;
    _memberActionRevision++;
    if (info.userID == currentUserID()) {
      _selfRevision++;
      groupMembersInfo = info;
      groupMemberRoleLevel.value = info.roleLevel ?? GroupRoleLevel.member;
      _refreshMute();
    }
    _putMemberInfo(info);
    final id = info.userID;
    if (id != null &&
        [GroupRoleLevel.member, GroupRoleLevel.admin, GroupRoleLevel.owner]
            .contains(info.roleLevel)) {
      _recordAdminChange(id, info);
    }
    for (final message in messages) {
      if (message.sendID != info.userID) continue;
      if (message.isNotificationType) {
        final detail = message.notificationElem?.detail;
        if (detail == null) continue;
        try {
          final notification = GroupNotification.fromJson(jsonDecode(detail));
          notification.opUser?.nickname = info.nickname;
          notification.opUser?.faceURL = info.faceURL;
          message.notificationElem?.detail = jsonEncode(notification);
        } catch (error) {
          _report(error);
        }
      } else {
        message.senderFaceUrl = info.faceURL;
        message.senderNickname = info.nickname;
      }
    }
    messages.refresh();
  }

  void _recordAdminChange(String id, GroupMembersInfo? info) {
    _adminChanges[id] = (++_adminRevision, info);
    _applyAdminChange(id, info);
  }

  void _applyAdminChange(String id, GroupMembersInfo? info) {
    final index = ownerAndAdmin.indexWhere((member) => member.userID == id);
    if (info == null || info.roleLevel == GroupRoleLevel.member) {
      if (index >= 0) ownerAndAdmin.removeAt(index);
    } else if (index < 0) {
      ownerAndAdmin.add(info);
    } else {
      ownerAndAdmin[index] = info;
    }
  }

  void _refreshMute() {
    _muteRevision.value++;
    _muteTimer?.cancel();
    final seconds = (groupMembersInfo?.muteEndTime ?? 0) - _nowSeconds();
    if (seconds > 0) {
      _muteTimer = Timer(Duration(seconds: seconds + 1), () {
        if (!_closed) _muteRevision.value++;
      });
    }
  }

  Map<String, String> getAtMapping(Message message) =>
      IMUtils.getAtMapping(message, {
        for (final entry in memberUpdateInfoMap.entries)
          if (entry.value.nickname != null) entry.key: entry.value.nickname!,
      });

  void _report(Object error) {
    if (reportError != null) {
      reportError!(error);
    } else {
      Logger.print('Query/update chat group failed: $error');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _membershipRevision++;
    _muteTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}
