import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/group_game_type.dart';

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
}
