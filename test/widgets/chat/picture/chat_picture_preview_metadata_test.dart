import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

const _sourceURL = 'https://media.test/original.png?signature=original';
const _previewURL = 'https://media.test/top.png?signature=preview';

Map<String, dynamic> _marker() => {
      'version': 1,
      'kind': 'topCrop',
      'sourceURL': _sourceURL,
      'previewURL': _previewURL,
    };

Message _message({String? extra}) => Message(
      clientMsgID: 'picture',
      contentType: MessageType.picture,
      ex: extra ?? jsonEncode({ChatPicturePreviewMetadata.key: _marker()}),
      pictureElem: PictureElem(
        sourcePath: '/original/screenshot.png',
        sourcePicture: PictureInfo(
            url: _sourceURL, width: 1200, height: 12000, type: 'image/png'),
        bigPicture: PictureInfo(
            url: _sourceURL, width: 1200, height: 12000, type: 'image/png'),
        snapshotPicture: PictureInfo(
            url: _previewURL, width: 480, height: 864, type: 'image/png'),
      ),
    );

void main() {
  test('exact original and preview identities admit a bounded top crop', () {
    final message = _message();
    final snapshot = message.pictureElem!.snapshotPicture;
    expect(ChatPicturePreviewMetadata.topCrop(message), same(snapshot));
    expect(message.pictureElem!.sourcePicture!.url, _sourceURL);
    expect(message.pictureElem!.sourcePicture!.height, 12000);
    expect(message.pictureElem!.sourcePath, '/original/screenshot.png');
  });

  test('message JSON round trip preserves unknown ex fields and signed URLs',
      () {
    final unknown = <String, dynamic>{
      'anotherFeature': {
        'enabled': true,
        'ids': ['x', 'y'],
        'nullable': null
      },
      'caption': '原有扩展字段',
      'counter': 23,
    };
    final extra = ChatPicturePreviewMetadata.withTopCrop(jsonEncode(unknown),
        sourceURL: _sourceURL, previewURL: _previewURL);
    expect(extra, isNotNull);
    final message = _message(extra: extra);
    final restored = Message.fromJson(
        jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>);
    final restoredExtra = jsonDecode(restored.ex!) as Map<String, dynamic>;
    for (final entry in unknown.entries) {
      expect(restoredExtra[entry.key], entry.value);
    }
    expect(restoredExtra[ChatPicturePreviewMetadata.key], _marker());
    expect(ChatPicturePreviewMetadata.topCrop(restored)?.url, _previewURL);
    expect(restored.pictureElem!.sourcePicture!.toJson(),
        message.pictureElem!.sourcePicture!.toJson());
  });

  for (final extra in <String?>[null, '', '{}']) {
    test('empty extension can be annotated: $extra', () {
      expect(ChatPicturePreviewMetadata.canAnnotate(extra), isTrue);
      expect(
          ChatPicturePreviewMetadata.withTopCrop(extra,
              sourceURL: _sourceURL, previewURL: _previewURL),
          isNotNull);
    });
  }

  for (final extra in ['{broken', '[]', 'null', 'true', '4', '"opaque"']) {
    test('opaque or malformed extension retains the legacy path: $extra', () {
      expect(ChatPicturePreviewMetadata.canAnnotate(extra), isFalse);
      expect(
          ChatPicturePreviewMetadata.withTopCrop(extra,
              sourceURL: _sourceURL, previewURL: _previewURL),
          isNull);
      expect(
          ChatPicturePreviewMetadata.topCrop(_message(extra: extra)), isNull);
    });
  }

  test('legacy snapshot dimensions alone never imply a top crop', () {
    final message = _message(extra: '{}');
    expect(ChatPicturePreviewMetadata.topCrop(message), isNull);
    expect(message.pictureElem!.snapshotPicture!.url, _previewURL);
  });

  final invalidMarkers = <String, Object?>{
    'null': null,
    'string': 'topCrop',
    'future version': {..._marker(), 'version': 2},
    'wrong kind': {..._marker(), 'kind': 'fit'},
    'stale original': {..._marker(), 'sourceURL': 'https://media.test/old.png'},
    'stale preview': {
      ..._marker(),
      'previewURL': 'https://media.test/old-top.png'
    },
    'changed signature': {
      ..._marker(),
      'sourceURL': 'https://media.test/original.png?signature=other'
    },
    'missing original': _marker()..remove('sourceURL'),
    'missing preview': _marker()..remove('previewURL'),
  };
  for (final entry in invalidMarkers.entries) {
    test('${entry.key} marker keeps the legacy fallback', () {
      final message = _message(
          extra: jsonEncode({ChatPicturePreviewMetadata.key: entry.value}));
      expect(ChatPicturePreviewMetadata.topCrop(message), isNull);
      expect(message.pictureElem!.sourcePicture!.url, _sourceURL);
    });
  }

  for (final size in [(0, 864), (-1, 864), (481, 866), (480, 0), (480, 480)]) {
    test('invalid preview size $size keeps the fallback', () {
      final message = _message();
      message.pictureElem!.snapshotPicture!
        ..width = size.$1
        ..height = size.$2;
      expect(ChatPicturePreviewMetadata.topCrop(message), isNull);
    });
  }

  for (final source in <String?>[null, '', '   ']) {
    test('missing original identity cannot authenticate a preview: $source',
        () {
      final message = _message(
          extra: jsonEncode({
        ChatPicturePreviewMetadata.key: {..._marker(), 'sourceURL': source}
      }));
      message.pictureElem!.sourcePicture!.url = source;
      expect(ChatPicturePreviewMetadata.topCrop(message), isNull);
    });
  }

  test('missing original picture and shared original URL keep the fallback',
      () {
    final missing = _message(
        extra: jsonEncode(
            {ChatPicturePreviewMetadata.key: _marker()..remove('sourceURL')}));
    missing.pictureElem!.sourcePicture = null;
    expect(ChatPicturePreviewMetadata.topCrop(missing), isNull);

    final identical = _message(
        extra: ChatPicturePreviewMetadata.withTopCrop(null,
            sourceURL: _sourceURL, previewURL: _sourceURL));
    identical.pictureElem!.snapshotPicture!.url = _sourceURL;
    expect(ChatPicturePreviewMetadata.topCrop(identical), isNull);
  });
}
