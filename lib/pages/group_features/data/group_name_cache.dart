import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/group_game_type.dart';
import '../personalization/group_personalization.dart';

/// Public display metadata only; never restores membership or permissions.
class GroupNameCache {
  GroupNameCache(this.scope);

  final String scope;
  static const boxName = 'group_name_types_v1';

  /// Open before runApp so the first row can read without an asynchronous gap.
  static Future<void> initialize() async {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    runZonedGuarded(() async {
      try {
        await Hive.openBox<dynamic>(boxName);
      } finally {
        finish();
      }
    }, (_, __) => finish());
    await done.future;
  }

  Box<dynamic>? get _box =>
      Hive.isBoxOpen(boxName) ? Hive.box<dynamic>(boxName) : null;

  String _key(String id) => jsonEncode([scope, id]);

  GroupGameType? read(String id) {
    final value = _box?.get(_key(id));
    for (final type in GroupGameType.values) {
      if (type.name == value) return type;
    }
    return null;
  }

  Future<void> write(String id, GroupGameType? type) async {
    try {
      final box = _box;
      if (box == null) return;
      if (type == null) {
        await box.delete(_key(id));
      } else if (box.get(_key(id)) != type.name) {
        await box.put(_key(id), type.name);
      }
    } catch (_) {
      // Optional storage must not interrupt SDK updates.
    }
  }

  String _appearanceKey(String id) => jsonEncode([scope, id, 'appearance-v1']);

  /// Only appearance is restored; group roles and membership remain SDK-owned.
  String? readAppearance(String id) {
    final value = _box?.get(_appearanceKey(id));
    return value is String ? value : null;
  }

  Future<void> writeAppearance(String id, String? ex) async {
    try {
      final box = _box;
      if (box == null) return;
      // Store an explicit default, so resets cannot resurrect an earlier style.
      final value = GroupPersonalization.fromEx(ex).mergeInto(null);
      if (box.get(_appearanceKey(id)) != value) {
        await box.put(_appearanceKey(id), value);
      }
    } catch (_) {
      // Display caching must not interrupt an otherwise successful SDK update.
    }
  }

  Future<void> removeAppearance(String id) async {
    try {
      await _box?.delete(_appearanceKey(id));
    } catch (_) {}
  }
}
