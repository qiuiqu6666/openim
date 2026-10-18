import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import '../../../core/session/queries/sdk_query_gate.dart';
import 'chat_group_sources.dart';
import 'identity/group_sender_avatars.dart';

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
    this.queryTimeout = const Duration(seconds: 15),
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
  final Duration queryTimeout;
  final ChatGroupEvents _events;
  final ChatGroupQueries _queries;
  final int Function() _nowSeconds;
  final String _accountID;

  GroupInfo? groupInfo;
  GroupMembersInfo? groupMembersInfo;
  String? groupOwnerID;
  final ownerAndAdmin = <GroupMembersInfo>[];
  final memberUpdateInfoMap = <String, GroupMembersInfo>{};
  late final _senderAvatars = GroupSenderAvatars(
    isCurrent: () => _matches(groupID()) && isInGroup.value,
    lookup: _queries.members == null
        ? null
        : (ids) async {
            final id = groupID()!;
            final members = await _queries.members!(id, ids);
            return _matches(id)
                ? members.where((member) => member.groupID == id).toList()
                : <GroupMembersInfo>[];
          },
  );
  String? avatarFor(Message message) => _senderAvatars.faceFor(message);
  String? nicknameFor(Message message) => _senderAvatars.nicknameFor(message);
  Message noticeFor(Message message) => _senderAvatars.noticeFor(message);
  void refreshSenderIdentity(String? id) => _senderAvatars.refreshMember(id);
  void updateSenderAvatar(String? id, String? face) =>
      _senderAvatars.update(id, face);
  final _removedMemberIDs = <String>{};
  final groupMemberRoleLevel = GroupRoleLevel.member.obs;
  final _adminListLoaded = false.obs;
  final isInGroup = true.obs;
  final membershipPending = false.obs;
  final memberCount = 0.obs;
  final memberCountKnown = false.obs;
  final announcement = ''.obs;
  final announcementVersion = ''.obs;
  final _muteRevision = 0.obs;
  final _subscriptions = <StreamSubscription>[];
  Worker? _messageIndexWorker;
  bool _messageIndexDirty = true;
  final _memberMessages = <String, List<Message>>{};
  List<Message> _messagesFor(String? memberID) {
    if (_messageIndexDirty) {
      _memberMessages.clear();
      for (final message in messages) {
        for (final id in {message.sendID, ...?message.atTextElem?.atUserList}) {
          if (id != null) (_memberMessages[id] ??= []).add(message);
        }
      }
      _messageIndexDirty = false;
    }
    return _memberMessages[memberID] ?? const [];
  }

  Timer? _muteTimer;
  Future<void>? _loadRequest;
  final _queryReads = SdkQueryGate<Object?>(limit: 4);
  Timer? _retryTimer;
  int _retryAttempts = 0;
  bool _loadFailed = false;
  bool _loaded = false;
  bool _leftByEvent = false;
  bool _initialized = false;
  bool _closed = false;
  int _membershipRevision = 0;
  int _profileRevision = 0;
  int _selfRevision = 0;
  int _adminRevision = 0;
  final _memberActionRevision = 0.obs;
  final _adminChanges = <String, (int, GroupMembersInfo?)>{};

  bool get isClosed => _closed;

  /// Invalidates avatar permission reads when SDK membership or roles change.
  int get memberActionRevision => _memberActionRevision.value;
  bool hasMemberLeft(String userID) => _removedMemberIDs.contains(userID);

  /// Unknown roles stay unavailable until the complete owner/admin list loads.
  /// This getter observes role updates used by reactive message menus.
  int? memberRoleFor(String userID) {
    _memberActionRevision.value;
    final loaded = _adminListLoaded.value;
    if (hasMemberLeft(userID) || !isInGroup.value) return null;
    if (userID == currentUserID()) {
      final role = groupMemberRoleLevel.value;
      return groupMembersInfo == null ? null : role;
    }
    if (userID == groupOwnerID) return GroupRoleLevel.owner;
    final known = ownerAndAdmin.firstWhereOrNull((m) => m.userID == userID);
    return known != null
        ? known.roleLevel
        : (loaded
            ? GroupRoleLevel.member
            : memberUpdateInfoMap[userID]?.roleLevel);
  }

  bool get isGroupChat => groupID()?.trim().isNotEmpty == true;
  bool get isInvalidGroup =>
      isGroupChat && !membershipPending.value && !isInGroup.value;
  bool get isAdminOrOwner =>
      groupMemberRoleLevel.value == GroupRoleLevel.admin ||
      groupMemberRoleLevel.value == GroupRoleLevel.owner;
  bool get havePermissionMute =>
      isGroupChat && groupInfo?.ownerUserID == currentUserID();

  /// The default role is only a placeholder until this user's member data arrives.
  /// Keep sending blocked for mute-all without presenting an unconfirmed mute.
  bool get muteStatusPending {
    _muteRevision.value;
    if (membershipPending.value) return true;
    return isGroupChat &&
        groupInfo?.status == 3 &&
        (groupMembersInfo?.muteEndTime ?? 0) <= _nowSeconds() &&
        !const [
          GroupRoleLevel.member,
          GroupRoleLevel.admin,
          GroupRoleLevel.owner
        ].contains(groupMembersInfo?.roleLevel);
  }

  bool get sendingMuted {
    _muteRevision.value;
    if (membershipPending.value) return true;
    return isGroupChat &&
        ((groupMembersInfo?.muteEndTime ?? 0) > _nowSeconds() ||
            (groupInfo?.status == 3 &&
                (muteStatusPending ||
                    groupMemberRoleLevel.value == GroupRoleLevel.member)));
  }

  static int _systemNowSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;

  void initialize() {
    if (_closed || _initialized || !isGroupChat) return;
    _initialized = true;
    _messageIndexWorker = ever(messages, (_) {
      _messageIndexDirty = true;
      _memberMessages.clear();
      _senderAvatars.sync(messages);
    });
    _senderAvatars.sync(messages);
    final id = groupID()!;
    final cached = _matches(id) ? readCachedGroupInfo?.call(id) : null;
    if (cached?.groupID == id) _applyGroupInfo(cached);
    _subscriptions.addAll([
      _events.joined.listen((info) {
        if (!_matches(info.groupID)) return;
        _joinGroup();
      }),
      _events.left.listen((info) {
        if (_matches(info.groupID)) _leaveGroup();
      }),
      _events.memberAdded.listen((info) {
        if (!_matches(info.groupID)) return;
        if (info.userID == currentUserID()) {
          _joinGroup();
          _selfRevision++;
          groupMembersInfo = info;
          groupMemberRoleLevel.value = info.roleLevel ?? GroupRoleLevel.member;
          _refreshMute();
        }
        _memberActionRevision.value++;
        _removedMemberIDs.remove(info.userID);
        _putMemberInfo(info);
        final memberID = info.userID;
        if (memberID != null &&
            [GroupRoleLevel.member, GroupRoleLevel.admin, GroupRoleLevel.owner]
                .contains(info.roleLevel)) {
          _recordAdminChange(memberID, info);
        }
        if (info.userID == currentUserID() ||
            _messagesFor(info.userID).isNotEmpty) {
          messages.refresh();
        }
      }),
      _events.memberDeleted.listen((info) {
        if (!_matches(info.groupID)) return;
        _memberActionRevision.value++;
        final id = info.userID;
        if (id != null) {
          _removedMemberIDs.add(id);
          _recordAdminChange(id, null);
          memberUpdateInfoMap.remove(id);
        }
        if (info.userID == currentUserID()) _leaveGroup();
        if (info.userID == currentUserID() ||
            _messagesFor(info.userID).isNotEmpty) {
          messages.refresh();
        }
      }),
      _events.memberChanged.listen(_onMemberChanged),
      _events.groupChanged.listen((info) {
        if (!_matches(info.groupID)) return;
        _profileRetryTimer?.cancel();
        _memberActionRevision.value++;
        _profileRevision++;
        _applyGroupInfo(info);
        messages.refresh();
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
    _memberActionRevision.value++;
    _membershipRevision++;
    isInGroup.value = false;
    membershipPending.value = false;
    _leftByEvent = true;
    _loaded = false;
    _retryTimer?.cancel();
    _profileRetryTimer?.cancel();
    _adminListLoaded.value = false;
    groupMembersInfo = null;
    groupMemberRoleLevel.value = GroupRoleLevel.member;
    _refreshMute();
    clearInput();
  }

  void _joinGroup() {
    _memberActionRevision.value++;
    _adminListLoaded.value = false;
    _removedMemberIDs.clear();
    _membershipRevision++;
    membershipPending.value = false;
    isInGroup.value = true;
    _leftByEvent = false;
    _loaded = false;
    recover(resetAttempts: true);
  }

  /// Entry and reconnect recovery are independent of history availability.
  /// Healthy metadata needs no repeated reads on history/sync notifications.
  void recover({bool resetAttempts = false}) {
    if (!_matches(groupID()) ||
        _loaded ||
        (_leftByEvent && _queries.verifyMembership == null)) {
      return;
    }
    if (resetAttempts) {
      _retryAttempts = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    unawaited(loadAfterHistory());
  }

  Future<void>? _profileRefresh;
  Timer? _profileRetryTimer;

  /// A sync finish can repair native metadata without a live group callback.
  /// Read only this profile, preserving loaded members and message history.
  Future<void> refreshProfileAfterSync() => _refreshProfile();

  Future<void> _refreshProfile({int attempt = 0}) {
    if (!_matches(groupID())) return Future<void>.value();
    if (_leftByEvent || membershipPending.value || !isInGroup.value) {
      // Force a read begun after sync, not the negative entry snapshot.
      _membershipRevision++;
      _loaded = false;
      if (_loadRequest != null) {
        return _loadRequest!.then((_) => loadAfterHistory());
      }
      return loadAfterHistory();
    }
    if (_profileRefresh != null) return _profileRefresh!;
    _profileRetryTimer?.cancel();
    // An entry read started before native sync may still hold old metadata.
    // Give the post-sync read its own key and invalidate that older result.
    final revision = ++_profileRevision;
    final id = groupID()!;
    final user = currentUserID();
    final membership = _membershipRevision;
    return _profileRefresh = _queryGroupInfo(id, user, membership).then((ok) {
      if (!ok &&
          attempt < 2 &&
          _queryStillCurrent(id, user, membership) &&
          revision == _profileRevision &&
          isInGroup.value) {
        _profileRetryTimer = Timer(Duration(seconds: attempt == 0 ? 1 : 3), () {
          if (_queryStillCurrent(id, user, membership) &&
              revision == _profileRevision &&
              isInGroup.value) {
            unawaited(_refreshProfile(attempt: attempt + 1));
          }
        });
      }
    }).whenComplete(() => _profileRefresh = null);
  }

  /// Retained for callers that await metadata; history is not a prerequisite.
  /// Overlapping callers share one bounded membership/metadata load.
  Future<void> loadAfterHistory() {
    if (!_matches(groupID()) ||
        (_leftByEvent && _queries.verifyMembership == null)) {
      return Future<void>.value();
    }
    if (_loadRequest != null) return _loadRequest!;
    _retryTimer?.cancel();
    _retryTimer = null;
    _loadFailed = false;
    final revision = _membershipRevision;
    return _loadRequest = _checkMembershipAndLoad().whenComplete(() {
      _loadRequest = null;
      if (!_matches(groupID()) || _leftByEvent) return;
      if (revision != _membershipRevision) {
        recover();
      } else if (_loadFailed && _retryAttempts < 2) {
        _retryTimer = Timer(Duration(seconds: _retryAttempts == 0 ? 1 : 3), () {
          _retryTimer = null;
          ++_retryAttempts;
          recover();
        });
      }
    });
  }

  Future<T> _read<T>(Object kind, Future<T> Function() query) async {
    final id = groupID()!;
    final user = currentUserID();
    final membership = _membershipRevision;
    return await _queryReads.run((kind, id, user, membership), query,
        timeout: queryTimeout,
        isCurrent: () => _queryStillCurrent(id, user, membership)) as T;
  }

  Future<void> _checkMembershipAndLoad() async {
    final id = groupID()!;
    final userID = currentUserID();
    final revision = _membershipRevision;
    try {
      var joined = !_leftByEvent &&
          await _read('membership', () => _queries.isJoined(id));
      if (!_queryStillCurrent(id, userID, revision)) return;
      if (!joined) {
        // Cache absence cannot distinguish sync lag from a real departure.
        // Stop sending while unresolved, without claiming the user has left.
        if (!_leftByEvent) membershipPending.value = true;
        isInGroup.value = false;
        _loadFailed = true; // Bounded retries also cover negative snapshots.
        final verify = _queries.verifyMembership;
        if (verify == null) return;
        joined = await _read('server-membership', () => verify(id, userID));
        if (!_queryStillCurrent(id, userID, revision)) return;
        membershipPending.value = false;
        if (!joined) {
          if (!_leftByEvent) _leaveGroup();
          return;
        }
        _leftByEvent = false;
        _loadFailed = false;
        _removedMemberIDs.remove(userID);
        _memberActionRevision.value++;
      }
      membershipPending.value = false;
      isInGroup.value = joined;
      if (joined) await _loadJoinedGroup();
      if (_queryStillCurrent(id, userID, revision)) {
        _loaded = joined && !_loadFailed;
      }
    } catch (error) {
      if (_queryStillCurrent(id, userID, revision)) _loadError(error);
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

  Future<bool> _queryGroupInfo(String id, String userID, int membership) async {
    final revision = _profileRevision;
    try {
      final list =
          await _read(('profile', revision), () => _queries.groupInfo(id));
      if (!_queryStillCurrent(id, userID, membership) ||
          revision != _profileRevision) {
        return true;
      }
      final info = list.firstWhereOrNull((info) => info.groupID == id);
      if (info == null) throw StateError('Group metadata is not available yet');
      _applyGroupInfo(info);
      return true;
    } catch (error) {
      if (_queryStillCurrent(id, userID, membership) &&
          revision == _profileRevision) {
        _loadError(error);
        return false;
      }
      return true;
    }
  }

  Future<void> _querySelfMember(
      String id, String userID, int membership) async {
    final revision = _selfRevision;
    try {
      final list = await _read(
          ('self', revision), () => _queries.selfMember(id, userID));
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
      if (_queryStillCurrent(id, userID, membership)) _loadError(error);
    }
  }

  Future<void> _queryOwnerAndAdmin(
      String id, String userID, int membership) async {
    final revision = _adminRevision;
    try {
      final list =
          await _read(('admins', revision), () => _queries.ownerAndAdmin(id));
      if (!_queryStillCurrent(id, userID, membership)) return;
      ownerAndAdmin
        ..clear()
        ..addAll(list);
      for (final entry in _adminChanges.entries) {
        if (entry.value.$1 > revision) {
          _applyAdminChange(entry.key, entry.value.$2);
        }
      }
      _adminListLoaded.value = true;
      messages.refresh();
    } catch (error) {
      if (_queryStillCurrent(id, userID, membership)) _loadError(error);
    }
  }

  void _applyGroupInfo(GroupInfo? info) {
    groupInfo = info;
    announcementVersion.value = info?.notificationUpdateTime?.toString() ?? '';
    announcement.value = info?.notification ?? '';
    groupOwnerID = info?.ownerUserID;
    if (info?.memberCount case final int count) {
      memberCount.value = count;
      memberCountKnown.value = true;
    }
    _refreshMute();
    if (info != null) {
      onGroupInfoApplied?.call(info);
      onGroupProfileChanged(info.groupName ?? '', info.faceURL ?? '');
    }
  }

  void _putMemberInfo(GroupMembersInfo member) {
    _senderAvatars.updateNickname(member.userID, member.nickname);
    _senderAvatars.update(member.userID, member.faceURL);
    final id = member.userID;
    if (id != null && id.isNotEmpty) memberUpdateInfoMap[id] = member;
  }

  void _onMemberChanged(GroupMembersInfo info) {
    if (!_matches(info.groupID)) return;
    _memberActionRevision.value++;
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
    final affected = _messagesFor(info.userID);
    var changed = affected
        .any((m) => m.atTextElem?.atUserList?.contains(info.userID) == true);
    for (final message in affected) {
      if (message.sendID != info.userID) continue;
      if (message.isNotificationType) {
        // The reactive identity cache resolves every participant at render
        // time. Re-serializing as GroupNotification loses invitation fields.
        continue;
      } else {
        changed = changed ||
            message.senderFaceUrl != info.faceURL ||
            message.senderNickname != info.nickname;
        message.senderFaceUrl = info.faceURL;
        message.senderNickname = info.nickname;
      }
    }
    if (changed) messages.refresh();
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

  Map<String, String> getAtMapping(Message message) {
    if (message.contentType != MessageType.atText) return const {};
    return IMUtils.getAtMapping(message, {
      for (final id in message.atTextElem?.atUserList ?? <String>[])
        if (memberUpdateInfoMap[id]?.nickname case final String nickname)
          id: nickname,
    });
  }

  void _report(Object error) {
    if (reportError != null) {
      reportError!(error);
    } else {
      Logger.print('Query/update chat group failed: $error');
    }
  }

  void _loadError(Object error) {
    _loadFailed = true;
    _loaded = false;
    _report(error);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _retryTimer?.cancel();
    _profileRetryTimer?.cancel();
    _queryReads.close();
    _membershipRevision++;
    _messageIndexWorker?.dispose();
    _senderAvatars.close();
    _memberMessages.clear();
    _muteTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}
