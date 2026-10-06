import 'dart:convert';

/// OpenIM 3.8 error-only methods return a JSON-encoded empty string (`""`) on
/// success, forwarded unchanged by Android/iOS callbacks. Older native SDKs can
/// return per-member results, which still need explicit failure checks.
void ensureChatMemberActionSucceeded(
  Object? response, {
  required String targetUserID,
}) {
  Object? decode(Object? value) {
    if (value is! String) return value;
    if (value.trim().isEmpty) return null;
    try {
      return jsonDecode(value);
    } on FormatException {
      throw ChatMemberActionResultException(
        targetUserID: targetUserID,
        message: 'Unexpected group member action response',
      );
    }
  }

  Never unexpected() => throw ChatMemberActionResultException(
        targetUserID: targetUserID,
        message: 'Unexpected group member action response',
      );

  int parseCode(Object? value) {
    if (value is int) return value;
    if (value is String) {
      final code = int.tryParse(value);
      if (code != null) return code;
    }
    return unexpected();
  }

  void inspect(Object? raw) {
    final value = decode(raw);
    if (value == null) return;
    // The core marshals its empty success value before invoking OnSuccess.
    if (value is String && value.trim().isEmpty) return;
    if (value is List) {
      for (final member in value) {
        if (member is! Map || !member.containsKey('result')) unexpected();
        inspect(member);
      }
      return;
    }
    if (value is! Map) unexpected();
    if (value.isEmpty) return;
    final hasResult = value.containsKey('result');
    final hasError = value.containsKey('errCode');
    if (!hasResult && !hasError) unexpected();
    for (final key in ['errCode', 'result']) {
      if (!value.containsKey(key)) continue;
      final code = parseCode(value[key]);
      if (code == 0) continue;
      final message = value['errMsg'];
      throw ChatMemberActionResultException(
        targetUserID: targetUserID,
        code: code,
        message: message is String && message.trim().isNotEmpty
            ? message.trim()
            : null,
      );
    }
    if (value.containsKey('data')) inspect(value['data']);
  }

  inspect(response);
}

class ChatMemberActionResultException implements Exception {
  const ChatMemberActionResultException({
    required this.targetUserID,
    this.code,
    this.message,
  });

  final String targetUserID;
  final int? code;
  final String? message;

  @override
  String toString() =>
      message ?? 'Group member action failed${code == null ? '' : ' ($code)'}';
}
