import 'dart:async';

import '../../contacts/request_history/data/request_load_coordinator.dart';

/// A burst schedules one read; events during it request one later calibration.
/// The owning home session decides whether reads and their results are current.
class ApplicationBadgeRefresh {
  ApplicationBadgeRefresh({
    required this.load,
    required this.isCurrent,
    required this.onError,
    this.delay = const Duration(milliseconds: 80),
  });

  final Future<void> Function() load;
  final bool Function() isCurrent;
  final void Function(Object error) onError;
  final Duration delay;
  final _loads = RequestLoadCoordinator();
  Timer? _timer;
  bool _closed = false;

  void request() {
    if (_closed || !isCurrent()) return;
    // Do not restart the timer: a continuous stream must not starve the badge.
    _timer ??= Timer(delay, () {
      _timer = null;
      if (_closed || !isCurrent()) return;
      unawaited(_loads.run(() async {
        if (!_closed && isCurrent()) await load();
      }, refreshAfter: true).catchError((Object error) {
        if (!_closed && isCurrent()) onError(error);
      }));
    });
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _loads.close();
  }
}
