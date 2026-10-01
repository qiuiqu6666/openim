import 'dart:async';
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

class UserPresence {
  UserPresence(this.online, this.lastSeenAt,
      {this.showLastSeen = true, this.isSelf = false});
  final bool showLastSeen;
  final bool isSelf;
  bool get hidden => !isSelf && !showLastSeen;
  bool get displayOnline => !hidden && online;
  final bool online;
  final int? lastSeenAt;
  String get label => labelAt(DateTime.now());
  String labelAt(DateTime now) {
    if (hidden) {
      if (lastSeenAt == null || online) return 'presenceRecently'.tr;
      final days = now
          .difference(DateTime.fromMillisecondsSinceEpoch(lastSeenAt!))
          .inDays;
      if (days < 1) return 'presenceRecently'.tr;
      if (days < 2) return 'presenceOneDay'.tr;
      if (days < 7) return 'presenceWithinWeek'.tr;
      if (days < 14) return 'presenceOverWeek'.tr;
      if (days < 30) return 'presenceWithinMonth'.tr;
      return 'presenceLongAgo'.tr;
    }
    if (online) return 'presenceOnline'.tr;
    if (lastSeenAt == null) return 'presenceOffline'.tr;
    final elapsed =
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastSeenAt!));
    if (elapsed.inMinutes < 1) return 'presenceJustNow'.tr;
    if (elapsed.inHours < 1) {
      return 'presenceMinutesAgo'.trParams({'count': '${elapsed.inMinutes}'});
    }
    if (elapsed.inDays < 1) {
      return 'presenceHoursAgo'.trParams({'count': '${elapsed.inHours}'});
    }
    if (elapsed.inDays < 7) {
      return 'presenceDaysAgo'.trParams({'count': '${elapsed.inDays}'});
    }
    if (elapsed.inDays < 30) {
      return 'presenceWeeksAgo'.trParams({'count': '${elapsed.inDays ~/ 7}'});
    }
    return 'presenceMonthsAgo'.trParams({'count': '${elapsed.inDays ~/ 30}'});
  }
}

class PresenceStore {
  PresenceStore({Dio? client}) : client = client ?? dio {
    _restore();
    _labelTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (users.isNotEmpty) users.refresh();
    });
  }
  Timer? _labelTimer;
  final String? _owner = DataSp.userID;
  Timer? _saveTimer;
  String get _cacheKey => 'presenceSnapshotV2:${Config.appAuthUrl}:$_owner';
  void _restore() {
    if (_owner == null) return;
    try {
      final cached = SpUtil().getObject(_cacheKey);
      if (cached == null) return;
      for (final entry in cached.entries) {
        final value = entry.value as Map;
        final online = value['online'] == true;
        users[entry.key as String] = UserPresence(
            online, online ? null : (value['lastSeenAt'] as num?)?.toInt(),
            showLastSeen: value['showLastSeen'] != false,
            isSelf: entry.key == _owner);
      }
    } catch (_) {/* A missing or invalid cache is refreshed from the server. */}
  }

  void _persist() {
    if (_owner == null || DataSp.userID != _owner) return;
    SpUtil().putObject(
        _cacheKey,
        users.map((id, value) => MapEntry(id, {
              'online': value.online,
              'lastSeenAt': value.lastSeenAt,
              'showLastSeen': value.showLastSeen,
            })));
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), _persist);
  }

  void _set(String id, UserPresence value) {
    final old = users[id];
    if (old?.online == value.online &&
        old?.lastSeenAt == value.lastSeenAt &&
        old?.showLastSeen == value.showLastSeen) {
      return;
    }
    users[id] = value;
    _scheduleSave();
  }

  void stopWatching(String id) {
    // Ignore late requests, but keep the last snapshot for the next appearance.
    _versions[id] = (_versions[id] ?? 0) + 1;
  }

  final Dio client;
  final users = <String, UserPresence>{}.obs;
  final _versions = <String, int>{};
  bool _closed = false;
  void markOnline(String id) {
    if (_closed || users[id] == null || users[id]!.hidden) return;
    _versions[id] = (_versions[id] ?? 0) + 1;
    _set(
        id,
        UserPresence(true, null,
            showLastSeen: users[id]!.showLastSeen, isSelf: id == _owner));
  }

  void markOffline(String id) {
    if (_closed || users[id] == null || users[id]!.hidden) return;
    _versions[id] = (_versions[id] ?? 0) + 1;
    _set(
        id,
        UserPresence(false, null,
            showLastSeen: users[id]!.showLastSeen, isSelf: id == _owner));
  }

  void remove(String id) {
    _versions[id] = (_versions[id] ?? 0) + 1;
    users.remove(id);
    _scheduleSave();
  }

  Future<void> refresh(Iterable<String> ids) async {
    final token = DataSp.chatToken;
    final owner = DataSp.userID;
    if (_closed || token == null || owner == null) return;
    final unique = ids.where((id) => id.isNotEmpty).toSet().toList();
    final versions = <String, int>{};
    for (final id in unique) {
      versions[id] = _versions[id] = (_versions[id] ?? 0) + 1;
    }
    for (var offset = 0; offset < unique.length; offset += 200) {
      final batch = unique.skip(offset).take(200).toList();
      try {
        final response =
            await client.post('${Config.appAuthUrl}/chat/users/presence',
                data: {'userIDs': batch},
                options: Options(headers: {
                  'token': token,
                  'operationID': const Uuid().v4(),
                  'Content-Type': 'application/json',
                }));
        if (_closed || DataSp.userID != owner) return;
        final body = response.data as Map;
        if (body['errCode'] != 0) continue;
        for (final item in body['data']['users'] as List) {
          final id = item['userID'] as String;
          if (!versions.containsKey(id) || _versions[id] != versions[id]) {
            continue;
          }
          final showLastSeen = item['showLastSeen'] != false;
          final hidden = id != owner && !showLastSeen;
          final online = !hidden && item['online'] == true;
          _set(
              id,
              UserPresence(
                  online, online ? null : (item['lastSeenAt'] as num?)?.toInt(),
                  showLastSeen: showLastSeen, isSelf: id == owner));
        }
      } catch (_) {
        /* Keep last successful result; retry on resume/reconnect. */
      }
    }
  }

  void dispose() {
    _labelTimer?.cancel();
    _saveTimer?.cancel();
    _persist();
    _closed = true;
    users.clear();
  }
}
