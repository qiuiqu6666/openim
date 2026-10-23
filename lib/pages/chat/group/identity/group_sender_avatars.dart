import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'group_notice_identity.dart';

/// Current group identity per sender, independent of message snapshots.
class GroupSenderAvatars {
  GroupSenderAvatars(
      {required this.isCurrent,
      required this.lookup,
      this.lookupProfiles,
      this.retryDelay = const Duration(seconds: 2)});
  final bool Function() isCurrent;
  final Duration retryDelay;
  Timer? _retryTimer;
  final _retryPending = <String>{};
  final _retryCounts = <String, int>{};
  final Future<List<GroupMembersInfo>> Function(List<String>)? lookup;
  final Future<List<GroupMembersInfo>> Function(List<String>)? lookupProfiles;
  final _faces = <String, String>{}.obs;
  final _confirmedFaces = <String>{};
  final _names = <String, String>{}.obs;
  final _latestNames = <String, (int, String)>{};
  final _nameVersions = <String, int>{};
  final _confirmedNames = <String>{};
  final _latest = <String, (int, String)>{};
  final _versions = <String, int>{};
  final _requested = <String>{};
  final _pending = <String>{};
  bool _scheduled = false, _closed = false;

  String? faceFor(Message message) =>
      _faces[message.sendID] ?? message.senderFaceUrl;

  String? nicknameFor(Message message) =>
      _names[message.sendID] ?? message.senderNickname;

  Message noticeFor(Message message) => resolveGroupNoticeIdentity(
        message,
        nickname: (id) => _names[id],
        face: (id) => _faces[id],
      );

  void updateNickname(String? id, String? nickname) {
    if (_closed ||
        !isCurrent() ||
        id == null ||
        id.isEmpty ||
        nickname == null ||
        nickname.isEmpty) {
      return;
    }
    _nameVersions[id] = (_nameVersions[id] ?? 0) + 1;
    _confirmedNames.add(id);
    _names[id] = nickname;
  }

  // A global profile name must not overwrite a distinct group nickname.
  void refreshMember(String? id) {
    if (_closed || !isCurrent() || id == null || id.isEmpty) return;
    _retryCounts.remove(id);
    _retryPending.remove(id);
    _nameVersions[id] = (_nameVersions[id] ?? 0) + 1;
    _versions[id] = (_versions[id] ?? 0) + 1;
    _pending.add(id);
    _scheduleLoad();
  }

  /// Recovery rechecks only identities used by the loaded message window.
  /// Reuse the bounded query queue instead of reloading the whole member list.
  void refreshMessages(Iterable<Message> messages) {
    if (_closed || !isCurrent()) return;
    final ids = <String>{};
    for (final message in messages) {
      final sender = message.sendID;
      if (sender != null && sender.isNotEmpty) ids.add(sender);
      final detail = groupNoticeDetail(message);
      if (detail == null) continue;
      for (final member in groupNoticeMembers(detail)) {
        final id = member['userID'];
        if (id is String && id.isNotEmpty) ids.add(id);
      }
    }
    for (final id in ids) {
      refreshMember(id);
    }
  }

  void update(String? id, String? face) {
    if (_closed || !isCurrent() || id == null || id.isEmpty || face == null) {
      return;
    }
    _versions[id] = (_versions[id] ?? 0) + 1;
    _confirmedFaces.add(id);
    _faces[id] = face;
  }

  void sync(Iterable<Message> messages) {
    if (_closed || !isCurrent()) return;
    for (final message in messages) {
      final time = message.sendTime ?? message.createTime ?? 0;
      final detail = groupNoticeDetail(message);
      if (detail != null) {
        for (final member in groupNoticeMembers(detail)) {
          final memberID = member['userID'];
          final name = member['nickname'];
          if (memberID is String && memberID.isNotEmpty && name is String) {
            _rememberName(memberID, name, time);
          }
          if (memberID is String &&
              memberID.isNotEmpty &&
              _requested.add(memberID)) {
            _pending.add(memberID);
          }
        }
      }
      final id = message.sendID, face = message.senderFaceUrl;
      if (id == null || id.isEmpty) continue;
      final name = message.senderNickname;
      if (name != null) _rememberName(id, name, time);
      final previous = _latest[id];
      if (face != null && (previous == null || time > previous.$1)) {
        _latest[id] = (time, face);
        if (!_faces.containsKey(id)) _faces[id] = face;
        if (previous != null && previous.$2 != face) {
          // New messages can reveal a missed profile event. Older pages cannot
          // roll the sender back to an old avatar.
          if (!_confirmedFaces.contains(id)) _faces[id] = face;
          _versions[id] = (_versions[id] ?? 0) + 1;
          _pending.add(id);
        }
      }
      if (_requested.add(id)) _pending.add(id);
    }
    _scheduleLoad();
  }

  void _rememberName(String id, String name, int time) {
    final previous = _latestNames[id];
    if (name.isEmpty || (previous != null && time <= previous.$1)) return;
    _latestNames[id] = (time, name);
    if (!_confirmedNames.contains(id)) _names[id] = name;
    if (previous != null && previous.$2 != name) {
      _nameVersions[id] = (_nameVersions[id] ?? 0) + 1;
      _pending.add(id);
    }
  }

  void _scheduleLoad() {
    if (!_scheduled && _pending.isNotEmpty && lookup != null) {
      _scheduled = true;
      scheduleMicrotask(_load);
    }
  }

  Future<void> _load() async {
    try {
      while (!_closed && isCurrent() && _pending.isNotEmpty) {
        final ids = _pending.take(50).toList();
        _pending.removeAll(ids);
        final versions = {for (final id in ids) id: _versions[id] ?? 0};
        final nameVersions = {for (final id in ids) id: _nameVersions[id] ?? 0};
        try {
          final members = [...await lookup!(ids)];
          if (_closed || !isCurrent()) return;
          final found = members.map((member) => member.userID).toSet();
          final missing = ids.where((id) => !found.contains(id)).toList();
          if (missing.isNotEmpty && lookupProfiles != null) {
            try {
              members.addAll((await lookupProfiles!(missing))
                  .where((member) => missing.contains(member.userID)));
            } catch (_) {
              _retry(missing);
            }
          }
          if (_closed || !isCurrent()) return;
          for (final member in members) {
            final id = member.userID;
            _retryPending.remove(id);
            _retryCounts.remove(id);
            if (id != null &&
                nameVersions.containsKey(id) &&
                nameVersions[id] == (_nameVersions[id] ?? 0)) {
              updateNickname(id, member.nickname);
            }
            if (id != null &&
                versions.containsKey(id) &&
                versions[id] == (_versions[id] ?? 0) &&
                member.faceURL != null) {
              update(id, member.faceURL);
            }
          }
        } catch (_) {
          _retry(ids);
        }
      }
    } finally {
      _scheduled = false;
    }
  }

  // Bound retries while retaining the last usable value. Recovery events can
  // start another attempt; closing the page cancels all outstanding retries.
  void _retry(List<String> ids) {
    if (_closed || !isCurrent()) return;
    for (final id in ids) {
      final attempts = _retryCounts[id] ?? 0;
      if (attempts >= 3) {
        _requested.remove(id);
        continue;
      }
      _retryCounts[id] = attempts + 1;
      _retryPending.add(id);
    }
    if (_retryPending.isEmpty || _retryTimer != null) return;
    _retryTimer = Timer(retryDelay, () {
      _retryTimer = null;
      if (_closed || !isCurrent()) return;
      _pending.addAll(_retryPending);
      _retryPending.clear();
      _scheduleLoad();
    });
  }

  void close() {
    _closed = true;
    _retryTimer?.cancel();
    _retryPending.clear();
    _retryCounts.clear();
    _pending.clear();
  }
}
