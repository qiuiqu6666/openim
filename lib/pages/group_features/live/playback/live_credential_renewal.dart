import 'dart:async';
import 'package:flutter/foundation.dart';

abstract interface class LiveScheduledTask {
  void cancel();
}

typedef LiveCredentialScheduler = LiveScheduledTask Function(
    Duration delay, VoidCallback callback);

class _LiveTimerTask implements LiveScheduledTask {
  _LiveTimerTask(Duration delay, VoidCallback callback)
      : _timer = Timer(delay, callback);
  final Timer _timer;
  @override
  void cancel() => _timer.cancel();
}

/// One deadline schedule belongs to the decoder, including its fullscreen view.
/// Callbacks carry no credentials; signed sources remain in the playback owner.
class LiveCredentialRenewal {
  LiveCredentialRenewal({
    required this.isActive,
    required this.expiresAt,
    required this.onExpired,
    DateTime Function()? now,
    LiveCredentialScheduler? schedule,
  })  : _now = now ?? DateTime.now,
        _schedule = schedule ?? _LiveTimerTask.new;

  final bool Function() isActive;
  final DateTime? Function() expiresAt;
  final VoidCallback onExpired;
  final DateTime Function() _now;
  final LiveCredentialScheduler _schedule;
  final _clients = <Object, _LiveRenewalClient>{};
  LiveScheduledTask? _renewal, _expiry;
  Future<void>? _work, _calibration;
  DateTime? _retryAt;
  Duration _lead = const Duration(seconds: 10);
  int _generation = 0, _failures = 0;
  bool _disposed = false, _expired = false;

  bool get hasClients => _clients.isNotEmpty;
  bool get hasActiveClient => _client != null;
  _LiveRenewalClient? get _client {
    for (final client in _clients.values.toList().reversed) {
      if (client.isCurrent()) return client;
    }
    return null;
  }

  void register(Object owner,
      {required bool Function() isCurrent,
      required Future<void> Function() renew,
      required Future<void> Function() calibrate}) {
    if (_disposed) return;
    _clients[owner] = _LiveRenewalClient(isCurrent, renew, calibrate);
    refresh();
  }

  void unregister(Object owner) {
    _clients.remove(owner);
    refresh();
  }

  void credentialsChanged() {
    final expiry = expiresAt();
    if (expiry != null) {
      final ttl = expiry.difference(_now()).inMilliseconds;
      _lead = Duration(milliseconds: (ttl ~/ 6).clamp(1000, 30000).toInt());
    }
    _failures = 0;
    _retryAt = null;
    _expired = false;
    refresh();
  }

  void cancel() {
    ++_generation;
    _renewal?.cancel();
    _expiry?.cancel();
    _renewal = _expiry = null;
    _work = null;
    _calibration = null;
  }

  Future<void> calibrate() {
    if (_disposed) return Future.value();
    final existing = _calibration;
    if (existing != null) return existing;
    final client = _client;
    if (client == null) return Future.value();
    late final Future<void> work;
    work = Future<void>.sync(client.calibrate).whenComplete(() {
      if (identical(_calibration, work)) _calibration = null;
    });
    return _calibration = work;
  }

  void refresh() {
    _renewal?.cancel();
    _expiry?.cancel();
    _renewal = _expiry = null;
    final expiry = expiresAt();
    if (_disposed || !isActive() || _client == null || expiry == null) return;
    final now = _now();
    final generation = _generation;
    if (!_expired) {
      _expiry = _schedule(_delay(expiry.difference(now)), () {
        if (_disposed || generation != _generation || !isActive()) return;
        _expiry = null;
        _expired = true;
        onExpired();
      });
    }
    if (_work != null) return;
    final deadline = _retryAt ?? expiry.subtract(_lead);
    _renewal = _schedule(_delay(deadline.difference(now)), () {
      _renewal = null;
      unawaited(_renew(generation));
    });
  }

  Duration _delay(Duration duration) => duration < const Duration(seconds: 1)
      ? const Duration(seconds: 1)
      : duration;

  Future<void> _renew(int generation) async {
    if (_disposed ||
        generation != _generation ||
        !isActive() ||
        _work != null) {
      return;
    }
    final client = _client;
    if (client == null) return;
    final previousExpiry = expiresAt();
    late final Future<void> work;
    work = Future<void>.sync(client.renew);
    _work = work;
    try {
      await work;
      if (_disposed || generation != _generation || !isActive()) return;
      final nextExpiry = expiresAt();
      if (nextExpiry == null ||
          !nextExpiry.isAfter(_now()) ||
          (previousExpiry != null && !nextExpiry.isAfter(previousExpiry))) {
        throw const FormatException('直播凭据尚未续期，请稍后重试');
      }
      _failures = 0;
      _retryAt = null;
    } catch (_) {
      if (_disposed || generation != _generation || !isActive()) return;
      // A failed refresh cannot create a tight loop, including unchanged expiry.
      _failures = (_failures + 1).clamp(1, 4).toInt();
      _retryAt = _now().add(Duration(seconds: 30 * (1 << (_failures - 1))));
    } finally {
      if (identical(_work, work)) {
        _work = null;
        refresh();
      }
    }
  }

  void dispose() {
    _disposed = true;
    cancel();
    _clients.clear();
  }
}

class _LiveRenewalClient {
  const _LiveRenewalClient(this.isCurrent, this.renew, this.calibrate);
  final bool Function() isCurrent;
  final Future<void> Function() renew, calibrate;
}
