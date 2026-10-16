import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openim/pages/chat/media/upload/chat_media_upload.dart';
import 'package:openim/pages/chat/media/preview/chat_picture_renditions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late Directory dir;
  late File file;
  late Message message;
  final uploads = <Map>[];
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rendition-upload-test-');
    file = await File('${dir.path}/source.jpg')
        .writeAsBytes(img.encodeJpg(img.Image(width: 1800, height: 900)));
    message = Message(
        clientMsgID: 'fixed',
        contentType: MessageType.picture,
        pictureElem: PictureElem(
            sourcePath: file.path,
            sourcePicture:
                PictureInfo(width: 1800, height: 900, type: 'image/jpeg')));
    uploads.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      uploads.add(args);
      expect(await File(args['filePath'] as String).length(), greaterThan(0));
      expect(args['name'], isNot(contains('/')));
      final tier = (args['id'] as String).split(':').first;
      return jsonEncode({'url': 'https://media.test/$tier.jpg'});
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });
  test('uploads two real derivatives and publishes their actual metadata',
      () async {
    await ChatMediaUpload(isClosed: () => false, onTransfer: (_, __) {})
        .prepare(message);
    expect(uploads.map((item) => item['id']),
        ['chat-media:fixed', 'chat-thumbnail:fixed', 'chat-preview:fixed']);
    expect(message.pictureElem!.sourcePicture!.url,
        'https://media.test/chat-media.jpg');
    expect(message.pictureElem!.snapshotPicture!.url,
        'https://media.test/chat-thumbnail.jpg');
    expect(message.pictureElem!.snapshotPicture!.width, 640);
    expect(message.pictureElem!.bigPicture!.url,
        'https://media.test/chat-preview.jpg');
    expect(message.pictureElem!.bigPicture!.width, 1600);
    expect(message.pictureElem!.bigPicture!.height, 800);
    expect(message.pictureElem!.bigPicture!.size, greaterThan(0));
    for (final item in uploads.skip(1)) {
      expect(await File(item['filePath'] as String).exists(), false);
    }
    expect(await file.exists(), true);
  });
  test('late derivatives are cleaned and never uploaded after deadline',
      () async {
    final ready = Completer<ChatPictureRenditions?>();
    await ChatMediaUpload(
        isClosed: () => false,
        onTransfer: (_, __) {},
        previewTimeout: const Duration(milliseconds: 10),
        createRenditions: (_) => ready.future).prepare(message);
    final snapshot = jsonEncode(message.toJson());
    final late = await ChatPictureRenditions.create(file.path);
    ready.complete(late);
    for (var i = 0; i < 100 && await Directory(late!.directory).exists(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(uploads, hasLength(1));
    expect(jsonEncode(message.toJson()), snapshot);
    expect(await Directory(late!.directory).exists(), false);
  });
}
