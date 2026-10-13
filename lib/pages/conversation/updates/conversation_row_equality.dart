import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Compare complete SDK payloads, including nested latest-message fields.
/// Shared mutable instances cannot prove that nothing changed: publish them.
bool sameConversationData(ConversationInfo? previous, ConversationInfo next) {
  if (previous == null || identical(previous, next)) return false;
  if (next.latestMsg != null && identical(previous.latestMsg, next.latestMsg)) {
    return false;
  }
  return _sameValue(previous.toJson(), next.toJson());
}

bool _sameValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _sameValue(a[key], b[key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameValue(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
