import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/youmeng/youmeng_configuration.dart';
import 'package:openim/core/youmeng/youmeng_runtime.dart';

class ConfigurationBundle extends CachingAssetBundle {
  ConfigurationBundle(this.content);
  final String content;

  @override
  Future<ByteData> load(String key) async {
    expect(key, YoumengConfiguration.assetPath);
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ordinary builds enable shield and include usable configuration',
      () async {
    expect(YoumengRuntime.enabled, isTrue);
    final configuration = await YoumengConfiguration.load();
    expect(Uri.parse(configuration.cp).scheme, 'https');
    expect(configuration.token.isNotEmpty, isTrue);
    expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(configuration.key), isTrue);
  });

  test('invalid configuration fails instead of silently using direct network',
      () async {
    for (final content in ['[]', '{}', '{"YOUMENG_CP":42}']) {
      await expectLater(
        YoumengConfiguration.load(bundle: ConfigurationBundle(content)),
        throwsFormatException,
      );
    }
  });
}
