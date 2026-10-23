import 'dart:convert';

/// Matches the server's enableHistoryForNewMembers compatibility rules.
class GroupHistoryPolicy {
  static const key = 'enableHistoryForNewMembers';

  static bool read(String? ex) {
    try {
      final data = jsonDecode(ex ?? '');
      if (data is! Map || data[key] == null) return true;
      return data[key] == true;
    } catch (_) {
      return true;
    }
  }

  static String merge(String? ex, bool enabled) {
    final data =
        ex == null || ex.trim().isEmpty ? <String, dynamic>{} : jsonDecode(ex);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('群资料格式不支持修改，请刷新后重试');
    }
    return jsonEncode({...data, key: enabled});
  }
}
