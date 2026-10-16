import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openim/pages/chat/media/preview/chat_picture_renditions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('fixed tiers preserve aspect ratio, metadata and original bytes',
      () async {
    final dir = await Directory.systemTemp.createTemp('renditions-test-');
    final bytes = img.encodeJpg(img.Image(width: 2400, height: 1200));
    final source = await File('${dir.path}/source.jpg').writeAsBytes(bytes);
    final result = await ChatPictureRenditions.create(source.path);
    try {
      expect(result, isNotNull);
      expect((result!.thumbnail.width, result.thumbnail.height), (640, 320));
      expect((result.preview.width, result.preview.height), (1600, 800));
      for (final tier in [result.thumbnail, result.preview]) {
        final encoded = await File(tier.path).readAsBytes();
        final decoded = img.decodeImage(encoded)!;
        expect((decoded.width, decoded.height), (tier.width, tier.height));
        expect(encoded.length, tier.length);
      }
      expect(await source.readAsBytes(), bytes);
    } finally {
      await result?.dispose();
      await dir.delete(recursive: true);
    }
  });
  test('small transparent pictures retain alpha and are not enlarged',
      () async {
    final dir = await Directory.systemTemp.createTemp('renditions-alpha-');
    final source = await File('${dir.path}/alpha.png').writeAsBytes(
        img.encodePng(img.Image(width: 20, height: 40, numChannels: 4)));
    final result = await ChatPictureRenditions.create(source.path);
    try {
      expect((result!.preview.width, result.preview.height), (20, 40));
      expect(result.preview.type, 'image/png');
      expect(
          img
              .decodePng(await File(result.preview.path).readAsBytes())!
              .hasAlpha,
          isTrue);
    } finally {
      await result?.dispose();
      await dir.delete(recursive: true);
    }
  });
  test('missing source does not block the uploader fallback', () async {
    expect(await ChatPictureRenditions.create('missing-rendition-source.jpg'),
        isNull);
  });
}
