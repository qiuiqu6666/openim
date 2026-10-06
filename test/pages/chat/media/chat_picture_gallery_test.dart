import 'dart:io';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/chat_picture_gallery.dart';
import 'package:openim/pages/chat/stickers/sticker_video_message.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Message picture(String id, String url) => Message()
  ..clientMsgID = id
  ..contentType = MessageType.picture
  ..pictureElem = PictureElem(
    sourcePicture: PictureInfo(url: url),
    snapshotPicture: PictureInfo(url: '$url?thumb=1'),
  );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loopback media uses the IM API while action messages keep SDK URLs',
      () async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putServerConfig({'apiUrl': 'https://im.example.test/api/'});
    addTearDown(() async => await DataSp.putServerConfig({}));
    const objectPath = '/object/sangong/image-id/openim-test.png';
    const sourceUrl = 'http://127.0.0.1:10002$objectPath';
    const bigUrl = '$sourceUrl?height=1920&width=1920&type=image';
    const snapshotUrl = '$sourceUrl?height=960&width=960&type=image';
    final selected = picture('sangong-picture', sourceUrl)..seq = 77;
    selected.pictureElem!
      ..bigPicture = PictureInfo(url: bigUrl)
      ..snapshotPicture = PictureInfo(url: snapshotUrl);

    final gallery = await ChatPictureGallery.fromMessages([selected], selected);

    expect(gallery.initialIndex, 0);
    expect(gallery.sources.single.tag, 'sangong-picture');
    expect(
        gallery.sources.single.url, 'https://im.example.test/api$objectPath');
    expect(gallery.sources.single.thumbnail,
        'https://im.example.test/api$objectPath?height=960&width=960&type=image');
    final actionMessage = gallery.messageAt(0)!;
    expect(actionMessage.clientMsgID, 'sangong-picture');
    expect(actionMessage.seq, 77);
    expect(actionMessage.contentType, MessageType.picture);
    expect(actionMessage.pictureElem?.sourcePicture?.url, sourceUrl);
    expect(actionMessage.pictureElem?.bigPicture?.url, bigUrl);
    expect(actionMessage.pictureElem?.snapshotPicture?.url, snapshotUrl);
    expect(selected.pictureElem?.sourcePicture?.url, sourceUrl);
    expect(selected.pictureElem?.snapshotPicture?.url, snapshotUrl);
  });

  test('pictures and videos share the same gallery and selected index',
      () async {
    final video = Message()
      ..clientMsgID = 'video'
      ..contentType = MessageType.video
      ..videoElem = VideoElem(
          videoUrl: 'https://example.com/video.mp4',
          snapshotUrl: 'https://example.com/cover.jpg');
    final gallery = await ChatPictureGallery.fromMessages([
      picture('before', 'https://example.com/before.jpg'),
      video,
      picture('after', 'https://example.com/after.jpg'),
    ], video);
    expect(gallery.initialIndex, 1);
    expect(gallery.sources.length, 3);
    expect(gallery.sources[1].isVideo, true);
    expect(gallery.sources[1].thumbnail, 'https://example.com/cover.jpg');
    expect(gallery.sources[1].url, 'https://example.com/video.mp4');
    expect(gallery.messageAt(0)?.clientMsgID, 'before');
    expect(gallery.messageAt(1)?.clientMsgID, 'video');
    expect(gallery.messageAt(2)?.clientMsgID, 'after');
  });
  test('opens the tapped picture within this conversation in message order',
      () async {
    final first = picture('first', 'https://example.com/first.png');
    final second = picture('second', 'https://example.com/second.png');
    final third = picture('third', 'https://example.com/third.png');
    final text = Message()..contentType = MessageType.text;

    final gallery = await ChatPictureGallery.fromMessages(
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

  test('includes a newly received picture missing from the list snapshot',
      () async {
    final selected = picture('new', 'https://example.com/new.png');
    final gallery = await ChatPictureGallery.fromMessages(
      [picture('old', 'https://example.com/old.png')],
      selected,
    );
    expect(gallery.initialIndex, 1);
    expect(gallery.sources.length, 2);
  });

  test('sticker videos are excluded from the gallery', () async {
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
        await ChatPictureGallery.fromMessages([first, sticker, last], last);
    expect(gallery.sources.map((source) => source.tag), ['first', 'last']);
    expect(gallery.initialIndex, 1);
    expect(
        (await ChatPictureGallery.fromMessages([first, sticker], sticker))
            .sources,
        isEmpty);
  });

  test('local originals remain available and missing files use remote media',
      () async {
    final directory = await Directory.systemTemp.createTemp('gallery-files-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/original.jpg').writeAsBytes([1]);
    final local = picture('local', 'https://example.com/original.jpg')
      ..pictureElem!.sourcePath = file.path;
    final missing = picture('missing', 'https://example.com/fallback.jpg')
      ..pictureElem!.sourcePath = '${directory.path}/missing.jpg';
    final localOnly = Message()
      ..clientMsgID = 'local-only'
      ..contentType = MessageType.picture
      ..pictureElem = PictureElem(sourcePath: file.path);
    final gallery = await ChatPictureGallery.fromMessages(
        [local, missing, localOnly], localOnly);
    expect(gallery.initialIndex, 2);
    expect(gallery.sources[0].file?.path, file.path);
    expect(gallery.sources[1].file, isNull);
    expect(gallery.sources[1].url, 'https://example.com/fallback.jpg');
    expect(gallery.sources[2].file?.path, file.path);
    expect(gallery.sources[2].url, isNull);
  });

  test('gallery uses a stable message order while local files are checked',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('gallery-snapshot-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/original.jpg').writeAsBytes([1]);
    final selected = picture('selected', 'https://example.com/selected.jpg')
      ..pictureElem!.sourcePath = file.path;
    final messages = [
      selected,
      picture('after', 'https://example.com/after.jpg')
    ];
    final pending = ChatPictureGallery.fromMessages(messages, selected);
    messages.clear();
    final gallery = await pending;
    expect(gallery.sources.map((source) => source.tag), ['selected', 'after']);
    expect(gallery.initialIndex, 0);
  });

  test('skipped media never shifts snapshot actions onto another message',
      () async {
    final unavailable = Message()
      ..clientMsgID = 'unavailable'
      ..contentType = MessageType.picture
      ..pictureElem = PictureElem();
    final selected = picture('selected', 'https://example.com/selected.jpg');
    final after = picture('after', 'https://example.com/after.jpg');
    final gallery = await ChatPictureGallery.fromMessages(
        [unavailable, selected, after], selected);
    expect(gallery.sources.map((source) => source.tag), ['selected', 'after']);
    expect(gallery.messageAt(0)?.clientMsgID, 'selected');
    expect(gallery.messageAt(1)?.clientMsgID, 'after');
    expect(gallery.messageAt(-1), isNull);
    expect(gallery.messageAt(2), isNull);
  });

  test('SDK objects and returned messages cannot mutate the gallery snapshot',
      () async {
    final first = picture('first', 'https://example.com/first.jpg');
    final second = picture('second', 'https://example.com/second.jpg');
    second.exMap = {
      'metadata': {'caption': 'original'}
    };
    final pending = ChatPictureGallery.fromMessages([first, second], first);
    first.clientMsgID = 'changed-first';
    second.pictureElem!.sourcePicture!.url = 'https://example.com/changed.jpg';
    (second.exMap['metadata'] as Map)['caption'] = 'changed';
    final gallery = await pending;
    expect(gallery.sources[0].tag, 'first');
    expect(gallery.sources[1].url, 'https://example.com/second.jpg');
    expect(gallery.messageAt(0)?.clientMsgID, 'first');
    final returned = gallery.messageAt(1)!;
    returned.clientMsgID = 'changed-return';
    returned.pictureElem!.sourcePicture!.url =
        'https://example.com/returned.jpg';
    expect(gallery.messageAt(1)?.clientMsgID, 'second');
    expect(gallery.messageAt(1)?.pictureElem?.sourcePicture?.url,
        'https://example.com/second.jpg');
    expect((gallery.messageAt(1)!.exMap['metadata'] as Map)['caption'],
        'original');
    expect(() => gallery.sources.clear(), throwsUnsupportedError);
  });

  test('an identity-free selected picture still opens but has no action target',
      () async {
    final selected = picture('', 'https://example.com/no-id.jpg')
      ..clientMsgID = null;
    final gallery = await ChatPictureGallery.fromMessages([
      picture('before', 'https://example.com/before.jpg'),
      selected,
    ], selected);
    expect(gallery.initialIndex, 1);
    expect(gallery.sources.length, 2);
    expect(gallery.messageAt(1), isNull);
  });
}
