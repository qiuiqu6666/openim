import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/chat/stickers/chat_sticker_controller.dart';
import 'package:openim/pages/chat/stickers/sticker_video_message.dart';

void main() {
  const url = 'https://stickers.test/image.gif';
  Message sticker(String data) => Message(
      contentType: MessageType.customFace,
      status: MessageStatus.succeeded,
      faceElem: FaceElem(index: -1, data: data));

  test('received custom stickers support raw and dimension JSON URLs', () {
    for (final data in [
      url,
      jsonEncode({'url': url, 'width': 120, 'height': 80})
    ]) {
      expect(ChatStickerController.messageStickerURL(sticker(data)), url);
    }
  });

  test('private, failed, malformed and local stickers cannot be collected', () {
    final private = sticker(url)
      ..attachedInfo = jsonEncode({'isPrivateChat': true});
    final burning = sticker(url)
      ..attachedInfo = jsonEncode({'burnDuration': 10});
    final failed = sticker(url)..status = MessageStatus.failed;
    for (final message in [
      private,
      burning,
      failed,
      sticker('file:///tmp/a.gif'),
      sticker('{}')
    ]) {
      expect(ChatStickerController.messageStickerURL(message), isNull);
    }
  });

  test('only marked video stickers expose the sticker action', () {
    final message = Message(
        contentType: MessageType.video,
        status: MessageStatus.succeeded,
        videoElem: VideoElem(videoUrl: url));
    expect(ChatStickerController.messageStickerURL(message), isNull);
    markStickerVideoMessage(message);
    expect(ChatStickerController.messageStickerURL(message), url);
  });

  test(
      'legacy emoji custom messages support adding without enabling other custom protocols',
      () {
    final message = Message(
        contentType: MessageType.custom,
        status: MessageStatus.succeeded,
        customElem: CustomElem(
            data: jsonEncode({
          'customType': CustomMessageType.emoji,
          'data': {'url': url}
        })));
    expect(ChatStickerController.messageStickerURL(message), url);
    message.customElem!.data = jsonEncode({
      'customType': 'unknown',
      'data': {'url': url}
    });
    expect(ChatStickerController.messageStickerURL(message), isNull);
  });
}
