import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:openim/pages/contacts/presence/presence_snapshot_cache.dart';

void main() {
  test('dirty writes preserve other records, deletions and account isolation',
      () async {
    final directory = await Directory.systemTemp.createTemp('presence-cache-');
    Hive.init(directory.path);
    try {
      final cache = PresenceSnapshotCache('account-a', capacity: 2000);
      for (var i = 0; i < 10000; i++) {
        cache.put('u$i', {'lastSeenAt': i, 'online': false});
      }
      await cache.flush();
      final initial = await cache.read();
      expect(initial.length, 2000);
      final ids = initial.keys.take(2).toList();
      cache.put(ids.first, {'lastSeenAt': 12345, 'online': false});
      cache.put(ids.last, null);
      await cache.flush();
      final restored = await PresenceSnapshotCache('account-a').read();
      expect(restored.length, 1999);
      expect(restored[ids.first]!['lastSeenAt'], 12345);
      expect(restored.containsKey(ids.last), isFalse);
      expect(await PresenceSnapshotCache('account-b').read(), isEmpty);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
