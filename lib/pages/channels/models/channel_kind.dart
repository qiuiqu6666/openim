import 'dart:convert';

/// Missing or unknown kinds remain ordinary OpenIM groups.
bool isChannelEx(String? ex) {
  try {
    final value = jsonDecode(ex ?? '');
    return value is Map && value['conversationKind'] == 'channel';
  } catch (_) {
    return false;
  }
}

String channelEx({String? existing}) {
  final value = existing == null || existing.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(existing);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid group ex');
  }
  return jsonEncode({...value, 'conversationKind': 'channel'});
}
