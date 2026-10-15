import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/chat_media_controller.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

class _Image extends AssetEntity {
  const _Image(this.readType)
      : super(id: 'photo', typeInt: 1, width: 100, height: 100);
  final Future<String?> Function() readType;
  @override
  Future<String?> get mimeTypeAsync => readType();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatMediaController media;
  setUp(() {
    media = ChatMediaController(
      conversationID: () => 'chat',
      isClosed: () => false,
      sendingMuted: () => false,
      isInvalidGroup: () => false,
      voiceBusy: () => false,
      sendMessage: (_, {addToUI = true, resetInput = true}) async {},
      stageMessage: (_) {},
      previewVoice: (File _, int __) async {},
      closeToolbox: () {},
    );
  });
  tearDown(() => media.close());

  for (final mime in [
    null,
    '',
    'image/heif',
    'IMAGE/JPEG',
    'image/heic-sequence'
  ]) {
    test('image MIME $mime can reach file preparation', () async {
      expect(await media.allowSendImageType(_Image(() async => mime)), isTrue);
    });
  }
  test('unavailable MIME metadata does not reject a valid gallery image',
      () async {
    expect(
        await media.allowSendImageType(_Image(
            () async => throw PlatformException(code: 'metadata-unavailable'))),
        isTrue);
  });
  test('stalled metadata cannot hold the picker indefinitely', () async {
    final metadata = Completer<String?>();
    final pending = media.allowSendImageType(_Image(() => metadata.future));
    try {
      expect(
          await pending.timeout(const Duration(seconds: 3),
              onTimeout: () => false),
          isTrue);
    } finally {
      metadata.complete('image/jpeg');
      await pending;
    }
  });
  test('known unsupported format is still rejected', () async {
    expect(await media.allowSendImageType(_Image(() async => 'image/svg+xml')),
        isFalse);
  });
}
