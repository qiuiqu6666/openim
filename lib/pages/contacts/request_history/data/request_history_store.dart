import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

enum RequestHistoryKind { friend, group }

/// Identifies one application, independently of later approval/profile updates.
class RequestHistoryEntry {
  const RequestHistoryEntry(this.id, this.time);

  factory RequestHistoryEntry.friend(FriendApplicationInfo value) =>
      RequestHistoryEntry(
          jsonEncode([value.fromUserID, value.toUserID, value.createTime]),
          _milliseconds(value.createTime));

  factory RequestHistoryEntry.group(GroupApplicationInfo value) =>
      RequestHistoryEntry(
          jsonEncode([value.groupID, value.userID, value.reqTime]),
          _milliseconds(value.reqTime));

  final String id;
  final int time;

  static int _milliseconds(int? time) {
    if (time == null || time <= 0) return 0;
    return time < 100000000000 ? time * 1000 : time;
  }
}

/// Local, account-scoped dismissal state. Does not alter SDK applications or
/// friend/group relationships. A clear boundary also covers unloaded old pages.
class RequestHistoryStore {
  RequestHistoryStore(this.accountID, this.kind) {
    final raw = SpUtil().getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final value = jsonDecode(raw);
      if (value is! Map || value['version'] != 1) return;
      final boundary = value['clearedThrough'];
      if (boundary is int && boundary >= 0) _clearedThrough = boundary;
      final deleted = value['deleted'];
      if (deleted is Map) {
        for (final entry in deleted.entries) {
          if (entry.key is String && entry.value is int) {
            _deleted[entry.key as String] = entry.value as int;
          }
        }
      }
    } on FormatException {
      // A damaged local preference must not prevent opening the SDK list.
    }
  }

  final String accountID;
  final RequestHistoryKind kind;
  int? _clearedThrough;
  Map<String, int> _deleted = {};

  String get _key =>
      'request_history_v1_${Uri.encodeComponent(accountID)}_${kind.name}';

  bool isCleared(RequestHistoryEntry entry) =>
      _clearedThrough != null && entry.time <= _clearedThrough!;

  bool isHidden(RequestHistoryEntry entry) =>
      isCleared(entry) || _deleted.containsKey(entry.id);

  /// One-time export for server-owned group notices; friend history stays local.
  Map<String, dynamic> get groupMigration {
    final items = <Map<String, dynamic>>[];
    if (kind == RequestHistoryKind.group) {
      for (final entry in _deleted.entries) {
        try {
          final id = jsonDecode(entry.key);
          if (id is List &&
              id.length == 3 &&
              id[0] is String &&
              id[1] is String) {
            items.add(
                {'groupID': id[0], 'userID': id[1], 'reqTime': entry.value});
          }
        } on FormatException {/* Ignore corrupt legacy identities. */}
      }
    }
    return {'through': _clearedThrough ?? 0, 'items': items};
  }

  Future<void> hide(RequestHistoryEntry entry) =>
      _save(_clearedThrough, {..._deleted, entry.id: entry.time});

  Future<void> hideAll(Iterable<RequestHistoryEntry> entries) =>
      _save(_clearedThrough, {
        ..._deleted,
        for (final entry in entries) entry.id: entry.time,
      });

  Future<void> clear(Iterable<RequestHistoryEntry> entries) async {
    final snapshot = entries.toList();
    if (snapshot.isEmpty) return;
    var boundary = _clearedThrough ?? 0;
    for (final entry in snapshot) {
      if (entry.time > boundary) boundary = entry.time;
    }
    // Use server application times, not the device clock. Newer requests survive.
    await _save(boundary, {
      for (final entry in _deleted.entries)
        if (entry.value > boundary) entry.key: entry.value,
    });
  }

  Future<void> _save(int? boundary, Map<String, int> deleted) async {
    if (accountID.isEmpty) throw StateError('No application owner');
    final previous = SpUtil().getString(_key);
    try {
      final saved = await SpUtil().putString(
          _key,
          jsonEncode({
            'version': 1,
            'clearedThrough': boundary,
            'deleted': deleted,
          }));
      if (saved != true) throw StateError('Could not save application history');
    } catch (_) {
      // SharedPreferences updates its memory cache before the platform write.
      // Restore that cache as well, so a failed deletion cannot hide a row later.
      try {
        if (previous == null || previous.isEmpty) {
          await SpUtil().prefs?.remove(_key);
        } else {
          await SpUtil().putString(_key, previous);
        }
      } catch (_) {}
      rethrow;
    }
    _clearedThrough = boundary;
    _deleted = deleted;
  }
}
