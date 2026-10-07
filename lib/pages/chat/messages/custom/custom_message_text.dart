import 'dart:convert';

/// Preserve custom message bodies instead of showing their list description.
/// Unknown envelopes remain readable JSON; no payload is executed as markup.
String customMessageText(String? data, String? description) {
  final raw = data?.trim().isNotEmpty == true ? data! : '';
  if (raw.isEmpty) return description ?? '';
  final value = _decode(raw);
  final body = _body(value, 0);
  if (body != null && body.trim().isNotEmpty) return body;
  return value is String
      ? value
      : const JsonEncoder.withIndent('  ').convert(value);
}

dynamic _decode(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    return value;
  }
}

String? _body(dynamic value, int depth) {
  if (depth >= 8) return null;
  if (value is String) {
    final decoded = _decode(value);
    return decoded is String ? decoded : _body(decoded, depth + 1);
  }
  if (value is! Map) return null;
  for (final key in ['markdown', 'text', 'content', 'body', 'data']) {
    final child = value[key];
    if (child is String || child is Map) {
      final text = _body(child, depth + 1);
      if (text != null && text.trim().isNotEmpty) return text;
    }
  }
  return null;
}
