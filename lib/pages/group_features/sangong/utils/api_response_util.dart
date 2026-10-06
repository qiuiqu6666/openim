// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
/// 写接口提交是否成功：与响应体能否解析成完整资料拆开。
class ApiWriteEnvelope {
  const ApiWriteEnvelope({
    required this.isBusinessError,
    required this.businessCode,
    required this.payload,
  });

  final bool isBusinessError;
  final String businessCode;
  final dynamic payload;
}

bool _isApiWriteSuccessCode(dynamic code) {
  if (code is num) {
    return code == 0 || code == 200 || code == 201;
  }
  final text = code.toString().trim();
  if (text.isEmpty) {
    return true;
  }
  final upper = text.toUpperCase();
  return text == '0' ||
      upper == 'OK' ||
      upper == 'SUCCESS' ||
      text == '200' ||
      text == '201';
}

/// 在 unwrap 之前读根对象业务码；payload 仍走 [unwrapApiPayload]。
ApiWriteEnvelope readApiWriteEnvelope(dynamic raw) {
  if (raw is! Map) {
    return ApiWriteEnvelope(
      isBusinessError: false,
      businessCode: '',
      payload: raw,
    );
  }
  final map = Map<String, dynamic>.from(raw);
  dynamic code;
  for (final key in const ['code', 'errorCode', 'errCode']) {
    final value = map[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      code = value;
      break;
    }
  }
  final payload = unwrapApiPayload(raw);
  if (code != null && !_isApiWriteSuccessCode(code)) {
    return ApiWriteEnvelope(
      isBusinessError: true,
      businessCode: code.toString().trim(),
      payload: payload,
    );
  }
  return ApiWriteEnvelope(
    isBusinessError: false,
    businessCode: '',
    payload: payload,
  );
}

/// 兼容后端多种 JSON 包装（如 `{ "data": ... }`、`{ "items": [...] }`）。
dynamic unwrapApiPayload(dynamic raw) {
  var current = raw;
  for (var depth = 0; depth < 4; depth++) {
    if (current is! Map) {
      break;
    }
    final map = Map<String, dynamic>.from(current);
    if (map['data'] != null) {
      current = map['data'];
      continue;
    }
    if (map['result'] != null) {
      current = map['result'];
      continue;
    }
    if (map['payload'] != null) {
      current = map['payload'];
      continue;
    }
    break;
  }
  return current;
}

List<dynamic> extractApiList(dynamic raw, {List<String> listKeys = const []}) {
  final payload = unwrapApiPayload(raw);
  if (payload is List) {
    return payload;
  }
  if (payload is! Map) {
    return const [];
  }
  final map = Map<String, dynamic>.from(payload);
  final keys = [
    ...listKeys,
    'items',
    'list',
    'records',
    'content',
    'favorites',
    'packs',
    'data',
  ];
  for (final key in keys) {
    final value = map[key];
    if (value is List) {
      return value;
    }
  }
  return const [];
}
