import 'dart:async';

import 'package:flutter/widgets.dart';

import 'call_records_repository.dart';

/// One account runtime owns this binding, independently of page lifetimes.
class CallRecordSyncBinding with WidgetsBindingObserver {
  CallRecordSyncBinding({
    required this.repository,
    Stream<String>? businessNotifications,
    Stream<void>? reconnected,
    this.debounce = const Duration(milliseconds: 200),
    this.observeLifecycle = true,
  }) {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    if (businessNotifications != null) {
      _subscriptions.add(businessNotifications.listen((raw) {
        unawaited(repository.handleNotification(raw).then((accepted) {
          if (accepted) requestSync();
        }));
      }));
    }
    if (reconnected != null) {
      _subscriptions.add(reconnected.listen((_) => requestSync()));
    }
  }

  final CallRecordsRepository repository;
  final Duration debounce;
  final bool observeLifecycle;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _scheduled;
  bool _disposed = false;

  void requestSync() {
    if (_disposed || !repository.isCurrent || _scheduled?.isActive == true) {
      return;
    }
    _scheduled = Timer(debounce, () {
      _scheduled = null;
      if (!_disposed && repository.isCurrent) unawaited(repository.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) requestSync();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scheduled?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
  }
}
