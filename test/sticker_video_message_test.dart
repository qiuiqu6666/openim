import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/sticker_video_message.dart';

void main() {
  test('only marked video messages autoplay as stickers after serialization',
      () {
    final sticker = Message(contentType: MessageType.video);
    markStickerVideoMessage(sticker);
    expect(isStickerVideoMessage(sticker), isTrue);
    final received = Message.fromJson(sticker.toJson());
    expect(isStickerVideoMessage(received), isTrue);

    expect(isStickerVideoMessage(Message(contentType: MessageType.video)),
        isFalse);
    expect(
        isStickerVideoMessage(
            Message(contentType: MessageType.picture, ex: sticker.ex)),
        isFalse);
  });
}
