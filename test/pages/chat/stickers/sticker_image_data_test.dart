import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  const url = 'https://stickers.test/image.gif';

  test('image sticker dimensions survive SDK message serialization', () {
    final sent = Message(
        contentType: MessageType.customFace,
        faceElem: FaceElem(
            index: -1,
            data: const StickerImageData(url: url, width: 480, height: 240)
                .encode()));
    final received = Message.fromJson(sent.toJson());
    final payload = StickerImageData.tryParse(received.faceElem?.data)!;
    expect(payload.url, url);
    expect(payload.width, 480);
    expect(payload.height, 240);
  });

  test('existing raw URLs and legacy emoji JSON remain readable', () {
    final raw = StickerImageData.tryParse(url)!;
    expect(raw.url, url);
    expect(raw.width, isNull);
    expect(raw.height, isNull);
    final legacy = StickerImageData.tryParse(jsonEncode({
      'customType': CustomMessageType.emoji,
      'data': {'url': url, 'width': 120, 'height': 240},
    }))!;
    expect(legacy.url, url);
    expect(legacy.width, 120);
    expect(legacy.height, 240);
  });

  test('bad dimensions fall back to probing and invalid URLs are rejected', () {
    for (final dimensions in [
      {'width': -1, 'height': 240},
      {'width': 120},
      {'width': 'invalid', 'height': 240},
    ]) {
      final payload =
          StickerImageData.tryParse(jsonEncode({'url': url, ...dimensions}))!;
      expect(payload.url, url);
      expect(payload.width, isNull);
      expect(payload.height, isNull);
    }
    expect(
        const StickerImageData(url: url, width: 0, height: 240).encode(), url);
    for (final data in ['', 'https:', 'file:///private.png', '{"url":4}']) {
      expect(StickerImageData.tryParse(data), isNull);
    }
  });
}
