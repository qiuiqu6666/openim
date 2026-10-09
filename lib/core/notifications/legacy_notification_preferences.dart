import 'dart:convert';

import 'package:openim_common/openim_common.dart';

String legacyNotificationSeedKey(String owner) =>
    '99chat_settings_${owner}_legacy_notification_seed';

/// A single durable seed is the account's fallback, rather than four competing
/// writes. Explicit local choices always win, including edits made during login.
Map<String, Object> legacyNotificationDefaults(String owner) {
  final raw = SpUtil().getDynamic(legacyNotificationSeedKey(owner));
  if (raw == null) return const {};
  final snapshot = LegacyNotificationSnapshot.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw as String)));
  final preview = switch (snapshot.displayMode) {
    'generic' => 'none',
    'hidden' => 'hidden',
    _ => 'detail',
  };
  return {
    'notify_when_open': snapshot.systemEnabled,
    'notify_when_closed': snapshot.systemEnabled,
    'notify_open_preview': preview,
    'notify_closed_preview': preview,
  };
}

class LegacyNotificationPreferenceSeeder {
  LegacyNotificationPreferenceSeeder({
    Object? Function(String)? read,
    Future<bool> Function(String, String)? write,
  })  : _read = read ?? ((key) => SpUtil().getDynamic(key)),
        _write = write ??
            ((key, value) async =>
                await SpUtil().putString(key, value) == true);

  final Object? Function(String) _read;
  final Future<bool> Function(String, String) _write;
  // SharedPreferences may update its memory cache even when persistence fails.
  final Set<String> _failedWrites = {};

  Future<bool> apply({
    required String owner,
    required LegacyNotificationSnapshot? snapshot,
    required bool Function() isCurrent,
  }) async {
    if (owner.trim().isEmpty || !isCurrent()) return false;
    if (snapshot == null) return isCurrent();
    final key = legacyNotificationSeedKey(owner);
    final existing = _read(key);
    if (existing != null && !_failedWrites.contains(key)) {
      LegacyNotificationSnapshot.fromJson(
          Map<String, dynamic>.from(jsonDecode(existing as String)));
      return isCurrent();
    }
    if (!isCurrent()) return false;
    _failedWrites.add(key);
    if (!await _write(key, jsonEncode(snapshot.toJson()))) return false;
    _failedWrites.remove(key);
    return isCurrent();
  }
}
