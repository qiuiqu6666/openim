import 'dart:io';
import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _objectPath =
    '/object/sangong/3d964f1b-745f-46cd-8b68-7f06a3dac076/openim-test.png';
const _loopbackUrl = 'http://127.0.0.1:10002$_objectPath';
const _thumbnailQuery = '?height=960&width=960&type=image';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
  });

  test('ImageUtil gives its provider the accessible OpenIM object URL', () {
    final image = ImageUtil.networkImage(
      url: '$_loopbackUrl$_thumbnailQuery',
    ) as ExtendedImage;

    expect(image.image, isA<ExtendedNetworkImageProvider>());
    final provider = image.image as ExtendedNetworkImageProvider;
    expect(
      provider.url,
      'http://129.226.192.93:10002$_objectPath$_thumbnailQuery',
    );
    expect(provider.cache, isTrue);
  });

  test('ImageUtil uses saved IM API prefix and keeps bounded decode settings',
      () async {
    await DataSp.putServerConfig({
      'apiUrl': 'https://im.example.test/api/',
      'authUrl': 'https://chat.example.test/chat',
    });
    final image = ImageUtil.networkImage(
      url: '$_loopbackUrl$_thumbnailQuery',
      cacheWidth: 192,
      cacheHeight: 192,
      resizePolicy: ResizeImagePolicy.fit,
      cacheRawData: false,
    ) as ExtendedImage;

    expect(image.image, isA<ExtendedResizeImage>());
    final resized = image.image as ExtendedResizeImage;
    expect(resized.width, 192);
    expect(resized.height, 192);
    expect(resized.policy, ResizeImagePolicy.fit);
    expect(resized.cacheRawData, isFalse);
    expect(resized.imageProvider, isA<ExtendedNetworkImageProvider>());
    final provider = resized.imageProvider as ExtendedNetworkImageProvider;
    expect(
      provider.url,
      'https://im.example.test/api$_objectPath$_thumbnailQuery',
    );
    expect(provider.cacheRawData, isFalse);
  });

  test(
      'MediaSource resolves both original and thumbnail with the IM API prefix',
      () async {
    await DataSp.putServerConfig({
      'apiUrl': 'https://im.example.test/api/',
      'authUrl': 'https://chat.example.test/chat',
    });
    final source = MediaSource(
      url: _loopbackUrl,
      thumbnail: '$_loopbackUrl$_thumbnailQuery',
    );

    expect(source.url, 'https://im.example.test/api$_objectPath');
    expect(source.thumbnail,
        'https://im.example.test/api$_objectPath$_thumbnailQuery');
  });

  test('new media consumers use the current saved IM API setting', () async {
    await DataSp.putServerConfig({'apiUrl': 'https://first.example.test/api'});
    final first = MediaSource(url: _loopbackUrl, thumbnail: _loopbackUrl);

    await DataSp.putServerConfig({'apiUrl': 'https://second.example.test/im'});
    final second = MediaSource(url: _loopbackUrl, thumbnail: _loopbackUrl);
    final image = ImageUtil.networkImage(url: _loopbackUrl) as ExtendedImage;

    expect(first.url, 'https://first.example.test/api$_objectPath');
    expect(second.url, 'https://second.example.test/im$_objectPath');
    expect(second.thumbnail, 'https://second.example.test/im$_objectPath');
    expect((image.image as ExtendedNetworkImageProvider).url, second.url);
  });

  test('consumers keep CDN, ordinary loopback and signed object URLs unchanged',
      () async {
    await DataSp.putServerConfig({'apiUrl': 'https://im.example.test/api'});
    final unchangedUrls = [
      'https://cdn.example.test$_objectPath$_thumbnailQuery',
      'http://127.0.0.1:10002/assets/logo.png',
      'http://localhost:3000/preview/image.png',
      '$_loopbackUrl?X-Amz-Signature=keep-signature&X-Amz-Expires=600',
    ];

    for (final url in unchangedUrls) {
      final source = MediaSource(url: url, thumbnail: url);
      final image = ImageUtil.networkImage(url: url) as ExtendedImage;
      expect(source.url, url);
      expect(source.thumbnail, url);
      expect((image.image as ExtendedNetworkImageProvider).url, url);
    }
  });

  test('String thumbnail helpers preserve signed and GIF query strings', () {
    final unchangedUrls = [
      '$_loopbackUrl?X-Amz-Signature=keep-signature&X-Amz-Expires=600',
      'https://cdn.example.test/photo.png?token=keep-token&Expires=123456',
      'https://cdn.example.test/animated.GIF?cache=original+query&key=one%2Ftwo',
    ];

    for (final url in unchangedUrls) {
      expect(url.adjustThumbnailAbsoluteString(960), url);
      expect(url.thumbnailAbsoluteString, url);
    }
  });

  test('String thumbnail helpers keep the existing dimensions for plain PNGs',
      () {
    const url = 'https://cdn.example.test/photo.png';
    expect(url.adjustThumbnailAbsoluteString(960),
        '$url?height=960&width=960&type=image');
    expect(url.thumbnailAbsoluteString, '$url?height=640&width=360&type=image');
  });

  test('bubble thumbnail URL reaches the provider with its object fallback',
      () {
    final thumbnail = _loopbackUrl.adjustThumbnailAbsoluteString(960);
    final image = ImageUtil.networkImage(url: thumbnail) as ExtendedImage;

    expect(thumbnail, '$_loopbackUrl$_thumbnailQuery');
    expect((image.image as ExtendedNetworkImageProvider).url,
        'http://129.226.192.93:10002$_objectPath$_thumbnailQuery');
  });

  test('MediaSource keeps local sources and action metadata', () {
    final file = File('${Directory.systemTemp.path}/local-original.png');
    final bytes = Uint8List.fromList([1, 2, 3]);
    final sentAt = DateTime(2026, 10, 6, 12);
    final source = MediaSource(
      thumbnail: '',
      file: file,
      bytes: bytes,
      tag: 'picture-message',
      senderName: '三公机器人',
      sentAt: sentAt,
    );

    expect(source.url, isNull);
    expect(source.thumbnail, isEmpty);
    expect(source.file, same(file));
    expect(source.bytes, same(bytes));
    expect(source.tag, 'picture-message');
    expect(source.senderName, '三公机器人');
    expect(source.sentAt, sentAt);
    expect(source.isVideo, isFalse);
  });
}
