import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// OS transport hints, not proof that an API or the Internet is reachable.
class NetworkTransportState {
  Set<ConnectivityResult>? _last;
  int _revision = 0;
  int _snapshotRevision = 0;
  bool get online => _last?.isNotEmpty ?? true;

  /// Empty snapshots are unknown. Ordering, duplicates and a redundant `none`
  /// alongside an available transport must not restart connection recovery.
  bool update(List<ConnectivityResult> values) {
    if (values.isEmpty) return false;
    _revision++;
    final next = values.where((v) => v != ConnectivityResult.none).toSet();
    if (setEquals(_last, next)) return false;
    _last = next;
    return true;
  }

  /// Background suspension may lose a stream event. Never let a slow snapshot
  /// overwrite a more recent notification, or hold foreground recovery open.
  Future<bool> refresh(Future<List<ConnectivityResult>> Function() read) async {
    final revision = _revision;
    final snapshot = ++_snapshotRevision;
    try {
      final values = await read().timeout(const Duration(seconds: 2));
      return snapshot == _snapshotRevision &&
          revision == _revision &&
          update(values);
    } catch (_) {
      return false;
    }
  }

  void invalidateSnapshot() => _snapshotRevision++;
}
