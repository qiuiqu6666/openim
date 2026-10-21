import 'dart:convert';

/// Shared group appearance stored alongside existing SDK metadata.
class GroupPersonalization {
  const GroupPersonalization({this.color, this.iconUrl, this.iconKey});
  final int? color;
  final String? iconUrl, iconKey;
  static const icons = {
    'robot': '🤖',
    'heart': '💖',
    'crown': '👑',
    'game': '🎮',
    'beer': '🍻',
    'football': '⚽',
    'rocket': '🚀',
    'clover': '🍀',
    'dog': '🐶',
    'diamond': '💎',
    'ghost': '👻',
    'star': '⭐',
    'flower': '🌸'
  };
  static const key = 'groupPersonalization';

  static Map<String, dynamic> metadata(String? ex) {
    if (ex == null || ex.trim().isEmpty) return {};
    final value = jsonDecode(ex);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('群资料格式不支持修改，请刷新后重试');
    }
    return value;
  }

  factory GroupPersonalization.fromEx(String? ex) {
    try {
      final value = metadata(ex)[key];
      if (value is! Map || value['version'] != 1) {
        return const GroupPersonalization();
      }
      final color = value['color'];
      final url = value['iconUrl'];
      final uri = url is String ? Uri.tryParse(url) : null;
      return GroupPersonalization(
        iconKey: icons.containsKey(value['iconKey'])
            ? value['iconKey'] as String
            : null,
        color: color is int && color >= 0xFF000000 && color <= 0xFFFFFFFF
            ? color
            : null,
        iconUrl: uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
            ? url as String
            : null,
      );
    } catch (_) {
      return const GroupPersonalization();
    }
  }

  String mergeInto(String? ex) {
    final data = metadata(ex);
    data[key] = {
      'version': 1,
      'color': color,
      'iconUrl': iconUrl,
      'iconKey': iconKey
    };
    return jsonEncode(data);
  }
}
