import 'dart:async';

import 'call_notification_preferences.dart';

/// One controller's subscription. Closing synchronously invalidates callbacks,
/// including a change emitted while the asynchronous call cleanup is running.
class CallNotificationPreferenceBinding {
  CallNotificationPreferenceBinding({
    required String Function() currentAccount,
    required void Function() refresh,
  })  : _currentAccount = currentAccount,
        _refresh = refresh;

  final String Function() _currentAccount;
  final void Function() _refresh;
  StreamSubscription<String>? _subscription;
  bool _closed = false;

  void attach() {
    if (_closed || _subscription != null) {
      return;
    }
    _subscription = CallNotificationPreferences.changes.listen((accountID) {
      if (!_closed &&
          accountID.isNotEmpty &&
          accountID == _currentAccount().trim()) {
        _refresh();
      }
    });
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
