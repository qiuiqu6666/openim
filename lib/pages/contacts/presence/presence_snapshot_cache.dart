import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

/// Bounded, per-account snapshots. Only dirty records are serialized on writes.
class PresenceSnapshotCache {
  PresenceSnapshotCache(String scope, {this.capacity = 2000})
      : _boxName = 'presence_v3_${sha256.convert(utf8.encode(scope))}';

  final int capacity;
  final String _boxName;
  Future<Box<dynamic>>? _opening;
  final _dirty = <String, Map<String, dynamic>?>{};
  Timer? _timer;
  Future<void> _writes = Future<void>.value();

  Future<Box<dynamic>> _box() => _opening ??= _open();

  Future<Box<dynamic>> _open() {
    final result = Completer<Box<dynamic>>();
    // Hive 2.x also reports failed opens on an internal shared future. Keep
    // both errors inside this optional cache, including unavailable storage.
    void fail(Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    }

    runZonedGuarded(() async {
      try {
        final box = await Hive.openBox<dynamic>(_boxName);
        if (!result.isCompleted) result.complete(box);
      } catch (error, stack) {
        fail(error, stack);
      }
    }, fail);
    return result.future;
  }

  Future<Map<String, Map<String, dynamic>>> read() async {
    try {
      final box = await _box();
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch;
      return {
        for (final key in box.keys.take(capacity))
          if (box.get(key) is Map &&
              ((box.get(key) as Map)['savedAt'] as int? ?? 0) >= cutoff)
            key as String: Map<String, dynamic>.from(box.get(key) as Map),
      };
    } catch (_) {
      // Presence is optional. Network refresh remains the source of truth.
      return {};
    }
  }

  void put(String id, Map<String, dynamic>? value) {
    _dirty[id] = value == null
        ? null
        : {
            ...value,
            'savedAt': DateTime.now().millisecondsSinceEpoch,
          };
    _timer ??= Timer(const Duration(seconds: 1), flush);
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_dirty.isEmpty) return _writes;
    final changes = Map<String, Map<String, dynamic>?>.of(_dirty);
    _dirty.clear();
    final updates = changes.entries.where((e) => e.value != null).toList();
    final retainedUpdates =
        updates.skip((updates.length - capacity).clamp(0, updates.length));
    return _writes = _writes.then((_) async {
      try {
        final box = await _box();
        await box.deleteAll(
            changes.entries.where((e) => e.value == null).map((e) => e.key));
        await box.putAll({for (final e in retainedUpdates) e.key: e.value});
        if (box.length > capacity) {
          final oldest = box.keys.toList()
            ..sort((a, b) => ((box.get(a) as Map)['savedAt'] as int? ?? 0)
                .compareTo((box.get(b) as Map)['savedAt'] as int? ?? 0));
          await box.deleteAll(oldest.take(box.length - capacity));
        }
      } catch (_) {
        // Do not retry indefinitely or hold the UI on an unavailable cache.
      }
    });
  }
}
