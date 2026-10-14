import 'dart:convert';
import 'package:flutter/services.dart';

/// Bundled defaults are shared by ordinary run/build and native platforms.
class YoumengConfiguration {
  const YoumengConfiguration(this.cp, this.token, this.key);

  final String cp;
  final String token;
  final String key;

  static const assetPath = 'tool/youmeng/youmeng.local.json';

  static Future<YoumengConfiguration> load({AssetBundle? bundle}) async {
    final decoded =
        jsonDecode(await (bundle ?? rootBundle).loadString(assetPath));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('网络保护配置格式无效');
    }
    String field(String name) {
      final value = decoded[name];
      if (value is! String) throw const FormatException('网络保护配置缺少字段');
      return value;
    }

    return YoumengConfiguration(
      const bool.hasEnvironment('YOUMENG_CP')
          ? const String.fromEnvironment('YOUMENG_CP')
          : field('YOUMENG_CP'),
      const bool.hasEnvironment('YOUMENG_TOKEN')
          ? const String.fromEnvironment('YOUMENG_TOKEN')
          : field('YOUMENG_TOKEN'),
      const bool.hasEnvironment('YOUMENG_AES_KEY')
          ? const String.fromEnvironment('YOUMENG_AES_KEY')
          : field('YOUMENG_AES_KEY'),
    );
  }
}
