import 'dart:convert';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'typing_visibility_preferences.dart';

/// The SDK persists user extensions on the server and syncs self-info changes
/// to every signed-in device. Local preferences are only the sending cache.
class TypingVisibilitySync {
  static const field = 'showTypingStatus';
  static int _revision = 0;

  static bool Function() _session(String owner) {
    final token = DataSp.imToken;
    final endpoint = Config.imApiUrl;
    return () =>
        owner.isNotEmpty &&
        DataSp.userID == owner &&
        OpenIM.iMManager.userID == owner &&
        token == DataSp.imToken &&
        endpoint == Config.imApiUrl;
  }

  static Map<String, dynamic> _fields(String? ex) => Map<String, dynamic>.from(
      jsonDecode(ex == null || ex.isEmpty ? '{}' : ex) as Map);

  static Future<void> accept(UserInfo user) async {
    final owner = user.userID ?? '';
    if (!_session(owner)()) return;
    final fields = _fields(user.ex);
    final value = fields[field];
    if (value != null && value is! bool) {
      throw const FormatException('Invalid typing visibility');
    }
    _revision++;
    await TypingVisibilityPreferences.write(owner, value as bool? ?? true);
  }

  static Future<void> refresh(String owner) async {
    final current = _session(owner);
    if (!current()) return;
    final revision = _revision;
    final user = await OpenIM.iMManager.userManager.getSelfUserInfo();
    if (!current() || revision != _revision || user.userID != owner) return;
    await accept(user);
  }

  static Future<void> save(String owner, bool value) async {
    final current = _session(owner);
    if (!current()) throw StateError('Account changed');
    final user = await OpenIM.iMManager.userManager.getSelfUserInfo();
    if (!current() || user.userID != owner) throw StateError('Account changed');
    final fields = _fields(user.ex)..[field] = value;
    final ex = jsonEncode(fields);
    final revision = _revision;
    await OpenIM.iMManager.userManager.setSelfInfo(ex: ex);
    if (!current()) return;
    // A self-info notification that arrived during the write is newer evidence.
    if (revision == _revision) {
      await accept(UserInfo(userID: owner, ex: ex));
    } else {
      await refresh(owner);
    }
  }
}
