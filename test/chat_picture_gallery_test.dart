import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/chat_picture_gallery.dart';
import 'package:openim/pages/chat/sticker_video_message.dart';

Message picture(String id, String url) => Message()
  ..clientMsgID = id
  ..contentType = MessageType.picture
  ..pictureElem = PictureElem(
    sourcePicture: PictureInfo(url: url),
    snapshotPicture: PictureInfo(url: '$url?thumb=1'),
  );

void main() {
  test('pictures and videos share the same gallery and selected index', () {
    final video = Message()
      ..clientMsgID = 'video'
      ..contentType = MessageType.video
      ..videoElem = VideoElem(
          videoUrl: 'https://example.com/video.mp4',
          snapshotUrl: 'https://example.com/cover.jpg');
    final gallery = ChatPictureGallery.fromMessages([
      picture('before', 'https://example.com/before.jpg'),
      video,
      picture('after', 'https://example.com/after.jpg'),
    ], video);
    expect(gallery.initialIndex, 1);
    expect(gallery.sources.length, 3);
    expect(gallery.sources[1].isVideo, true);
    expect(gallery.sources[1].thumbnail, 'https://example.com/cover.jpg');
    expect(gallery.sources[1].url, 'https://example.com/video.mp4');
  });
  test('opens the tapped picture within this conversation in message order',
      () {
    final first = picture('first', 'https://example.com/first.png');
    final second = picture('second', 'https://example.com/second.png');
    final third = picture('third', 'https://example.com/third.png');
    final text = Message()..contentType = MessageType.text;

    final gallery = ChatPictureGallery.fromMessages(
      [first, text, second, third],
      second,
    );

    expect(gallery.initialIndex, 1);
    expect(gallery.sources.map((source) => source.url), [
      'https://example.com/first.png',
      'https://example.com/second.png',
      'https://example.com/third.png',
    ]);
  });

  test('includes a newly received picture missing from the list snapshot', () {
    final selected = picture('new', 'https://example.com/new.png');
    final gallery = ChatPictureGallery.fromMessages(
      [picture('old', 'https://example.com/old.png')],
      selected,
    );
    expect(gallery.initialIndex, 1);
    expect(gallery.sources.length, 2);
  });

  test('sticker videos are excluded from the gallery', () {
    final sticker = Message()
      ..clientMsgID = 'sticker'
      ..contentType = MessageType.video
      ..videoElem = VideoElem(
          videoUrl: 'https://example.com/sticker.mp4',
          snapshotUrl: 'https://example.com/sticker.jpg');
    markStickerVideoMessage(sticker);
    final first = picture('first', 'https://example.com/first.png');
    final last = picture('last', 'https://example.com/last.png');
    final gallery =
        ChatPictureGallery.fromMessages([first, sticker, last], last);
    expect(gallery.sources.map((source) => source.tag), ['first', 'last']);
    expect(gallery.initialIndex, 1);
    expect(ChatPictureGallery.fromMessages([first, sticker], sticker).sources,
        isEmpty);
  });
}
