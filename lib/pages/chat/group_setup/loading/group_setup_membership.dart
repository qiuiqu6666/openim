import 'dart:async';

import 'package:get/get.dart';

/// Keeps an unresolved membership read distinct from actually leaving a group.
class GroupSetupMembership {
  GroupSetupMembership({
    this.timeout = const Duration(seconds: 8),
    this.retryDelay = const Duration(milliseconds: 500),
  });

  final Duration timeout;
  final Duration retryDelay;
  final resolved = false.obs;
  final failed = false.obs;
  Future<void>? _flight;
  Timer? _retryTimer;
  Completer<bool>? _retry;
  int _generation = 0;
  bool _closed = false;

  Future<void> refresh({
    required Future<bool> Function() query,
    required bool Function() isCurrent,
    required void Function(bool) onResult,
  }) {
    if (_closed || !isCurrent()) return Future.value();
    if (_flight != null) return _flight!;
    final generation = ++_generation;
    failed.value = false;
    return _flight =
        _read(generation, query, isCurrent, onResult).whenComplete(() {
      if (generation == _generation) _flight = null;
    });
  }

  Future<void> _read(
    int generation,
    Future<bool> Function() query,
    bool Function() isCurrent,
    void Function(bool) onResult,
  ) async {
    bool current() => !_closed && generation == _generation && isCurrent();
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final joined = await query().timeout(timeout);
        if (!current()) return;
        resolved.value = true;
        onResult(joined);
        return;
      } catch (_) {
        if (!current()) return;
        if (attempt == 1) {
          failed.value = true;
          return;
        }
        final retry = _retry = Completer<bool>();
        _retryTimer = Timer(retryDelay, () => retry.complete(true));
        if (!await retry.future || !current()) return;
        _retry = null;
        _retryTimer = null;
      }
    }
  }

  /// A current chat snapshot or SDK membership event supersedes pending reads.
  void accept() {
    _invalidate();
    resolved.value = true;
    failed.value = false;
  }

  void _invalidate() {
    _generation++;
    _flight = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    final retry = _retry;
    _retry = null;
    if (retry != null && !retry.isCompleted) retry.complete(false);
  }

  void dispose() {
    _closed = true;
    _invalidate();
  }
}
