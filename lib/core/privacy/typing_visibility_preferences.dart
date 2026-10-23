import 'dart:async';
import 'package:openim_common/openim_common.dart' show SpUtil;

/// Account-scoped sending cache; the SDK self profile is authoritative.
class TypingVisibilityPreferences {
  static final _changes = StreamController<String>.broadcast(sync: true);
  static Stream<String> get changes => _changes.stream;
  static String _key(String owner) => '99chat_settings_${owner}_show_typing';

  static bool read(String owner) =>
      SpUtil().getBool(_key(owner), defValue: true) ?? true;

  static Future<void> write(String owner, bool value) async {
    final previous = read(owner);
    try {
      if (await SpUtil().putBool(_key(owner), value) != true) {
        throw StateError('Typing preference could not be saved');
      }
    } catch (_) {
      await SpUtil().putBool(_key(owner), previous);
      rethrow;
    }
    _changes.add(owner);
  }
}
