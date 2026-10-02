import 'package:flutter/foundation.dart';
import 'package:openim_common/openim_common.dart';

/// Account-scoped display preferences, not remote privacy controls.
class FriendDisplayPreferences {
  static final changes = ValueNotifier<int>(0);
  static String _key(String name) {
    final owner = (DataSp.userID ?? 'anonymous').trim();
    return '99chat_settings_${owner.isEmpty ? 'anonymous' : owner}_$name';
  }

  static bool get showOnlineStatus =>
      SpUtil().getBool(_key('show_online_status'), defValue: true) ?? true;
  static bool get showReadReceipts =>
      SpUtil().getBool(_key('read_receipts'), defValue: true) ?? true;
  static void setOnlineStatus(bool value) {
    SpUtil().putBool(_key('show_online_status'), value);
    changes.value++;
  }

  static void setReadReceipts(bool value) {
    SpUtil().putBool(_key('read_receipts'), value);
    changes.value++;
  }
}
