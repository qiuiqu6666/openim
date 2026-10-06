import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

/// Business notifications are hints. Only the authenticated changes API can
/// update private records, versions, deletions, and the durable sync watermark.
class FavoriteSyncBinding with WidgetsBindingObserver {
  FavoriteSyncBinding({
    required this.synchronize,
    required this.sessionScope,
    required this.isSessionCurrent,
    Stream<String>? notifications,
    Stream<void>? reconnected,
    this.debounce = const Duration(milliseconds: 200),
    this.pollInterval = const Duration(minutes: 1),
    this.observeLifecycle = true,
  }) {
    if (observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      final state = WidgetsBinding.instance.lifecycleState;
      _foreground = state == null || state == AppLifecycleState.resumed;
    }
    if (notifications != null) {
      _subscriptions.add(notifications.listen(_onNotification));
    }
    if (reconnected != null) {
      _subscriptions.add(reconnected.listen((_) => requestSync()));
    }
    _startPolling();
  }

  final Future<void> Function() synchronize;
  final String Function() sessionScope;
  final bool Function(String) isSessionCurrent;
  final Duration debounce;
  final Duration? pollInterval;
  final bool observeLifecycle;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _scheduled;
  Timer? _poll;
  bool _disposed = false;
  bool _foreground = true;
  bool _running = false;
  bool _again = false;

  void _onNotification(String raw) {
    try {
      final envelope = jsonDecode(raw);
      if (envelope is Map && envelope['key'] == 'favoriteChanged') {
        requestSync();
      }
    } catch (_) {
      // Other business messages and malformed hints never become records.
    }
  }

  void _startPolling() {
    _poll?.cancel();
    final interval = pollInterval;
    if (!_disposed && _foreground && interval != null) {
      _poll = Timer.periodic(interval, (_) => requestSync());
    }
  }

  void requestSync() {
    if (_disposed) return;
    if (!_foreground || _running) {
      _again = true;
      return;
    }
    if (_scheduled?.isActive == true) return;
    final scope = sessionScope();
    _scheduled = Timer(debounce, () {
      _scheduled = null;
      if (_disposed || !_foreground || !isSessionCurrent(scope)) return;
      unawaited(_synchronize(scope));
    });
  }

  Future<void> _synchronize(String scope) async {
    if (_running) return;
    _running = true;
    _again = false;
    try {
      await synchronize();
    } catch (_) {
      // A failed request keeps the repository watermark unchanged. A later
      // foreground refresh, reconnect, notification, or poll can retry it.
    } finally {
      _running = false;
      if (_again && !_disposed && _foreground && isSessionCurrent(scope)) {
        _again = false;
        requestSync();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _startPolling();
      requestSync();
    } else {
      _scheduled?.cancel();
      _scheduled = null;
      _poll?.cancel();
      _poll = null;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scheduled?.cancel();
    _poll?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
  }
}
