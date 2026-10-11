import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

/// One avatar per sender, independent of historical message snapshots.
class GroupSenderAvatars {
  GroupSenderAvatars({required this.isCurrent, required this.lookup});
  final bool Function() isCurrent;
  final Future<List<GroupMembersInfo>> Function(List<String>)? lookup;
  final _faces = <String, String>{}.obs;
  final _latest = <String, (int, String)>{};
  final _versions = <String, int>{};
  final _requested = <String>{};
  final _pending = <String>{};
  bool _scheduled = false, _closed = false;

  String? faceFor(Message message) =>
      _faces[message.sendID] ?? message.senderFaceUrl;

  void update(String? id, String? face) {
    if (_closed || !isCurrent() || id == null || id.isEmpty || face == null) {
      return;
    }
    _versions[id] = (_versions[id] ?? 0) + 1;
    _faces[id] = face;
  }

  void sync(Iterable<Message> messages) {
    if (_closed || !isCurrent()) return;
    for (final message in messages) {
      final id = message.sendID, face = message.senderFaceUrl;
      if (id == null || id.isEmpty) continue;
      final time = message.sendTime ?? message.createTime ?? 0;
      final previous = _latest[id];
      if (face != null && (previous == null || time > previous.$1)) {
        _latest[id] = (time, face);
        if (!_faces.containsKey(id)) _faces[id] = face;
        if (previous != null && previous.$2 != face) {
          // New messages can reveal a missed profile event. Older pages cannot
          // roll the sender back to an old avatar.
          update(id, face);
          _pending.add(id);
        }
      }
      if (_requested.add(id)) _pending.add(id);
    }
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
        try {
          final members = await lookup!(ids);
          if (_closed || !isCurrent()) return;
          for (final member in members) {
            final id = member.userID;
            if (id != null &&
                versions.containsKey(id) &&
                versions[id] == (_versions[id] ?? 0) &&
                member.faceURL != null) {
              _faces[id] = member.faceURL!;
            }
          }
        } catch (_) {
          // Retain known message/profile data; a later event can refresh it.
        }
      }
    } finally {
      _scheduled = false;
    }
  }

  void close() {
    _closed = true;
    _pending.clear();
  }
}
