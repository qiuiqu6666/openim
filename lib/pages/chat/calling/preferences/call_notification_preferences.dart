import 'dart:async';

import 'package:openim_common/openim_common.dart' show SpUtil;
import 'package:openim_live/openim_live.dart' show IncomingCallPreferences;

/// Account-local call choices. The settings surface publishes changes and the
/// IM controller owns the subscription for its existing signaling session.
class CallNotificationPreferences {
  CallNotificationPreferences._();

  static final _changes = StreamController<String>.broadcast(sync: true);
  static Stream<String> get changes => _changes.stream;

  static void notifyChanged(String accountID) => _changes.add(accountID.trim());

  static IncomingCallPreferences read(String accountID) {
    final owner = accountID.trim();
    final prefix = '99chat_settings_${owner.isEmpty ? 'anonymous' : owner}_';
    final storage = SpUtil();
    bool enabled(String key) => switch (storage.getDynamic('$prefix$key')) {
          bool value => value,
          _ => true,
        };
    return IncomingCallPreferences(
      quickAnswerPopup: enabled('notify_quick_answer'),
      ringtoneEnabled: enabled('call_ringtone_enabled'),
    );
  }
}
