import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openim/pages/chat/media/upload/chat_media_upload.dart';
import 'package:openim_common/openim_common.dart';

const _sourceURL = 'https://media.test/object/original.png';
const _previewURL = 'https://media.test/object/top.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late Directory directory;
  late File original;
  late List<int> originalBytes;
  late ChatMediaUpload uploader;
  late List<Map<String, dynamic>> uploads;
  late List<ChatTransferStage> stages;
  late bool closed;
  late List<List<int>> uploadedBytes;
  late String? previewPath;

  setUpAll(() {
    final source = img.fill(img.Image(width: 600, height: 2400),
        color: img.ColorRgb8(0, 0, 255));
    img.fillRect(source,
        x1: 0, y1: 0, x2: 599, y2: 1079, color: img.ColorRgb8(255, 0, 0));
    originalBytes = img.encodePng(source);
  });

  Future<dynamic> upload(MethodCall call) async {
    expect(call.method, 'uploadFile');
    final args = Map<String, dynamic>.from(call.arguments as Map);
    uploads.add(args);
    final path = args['filePath'] as String;
    uploadedBytes.add(await File(path).readAsBytes());
    if ((args['id'] as String).startsWith('chat-top-preview:')) {
      previewPath = path;
      return jsonEncode({'url': _previewURL});
    }
    return jsonEncode({'url': _sourceURL});
  }

  setUp(() async {
    OpenIM.iMManager.userID = 'self';
    directory = await Directory.systemTemp.createTemp('top-upload-test-');
    original = await File('${directory.path}/original.png')
        .writeAsBytes(originalBytes, flush: true);
    uploads = [];
    uploadedBytes = [];
    stages = [];
    closed = false;
    previewPath = null;
    uploader = ChatMediaUpload(
        isClosed: () => closed,
        onTransfer: (_, state) => stages.add(state.stage));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, upload);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Message message({String? extra}) => Message(
      clientMsgID: 'same-message',
      sendID: 'self',
      status: MessageStatus.sending,
      contentType: MessageType.picture,
      ex: extra ??
          jsonEncode({
            'unrelated': {'keep': true, 'label': '备注'}
          }),
      pictureElem: PictureElem(
          sourcePath: original.path,
          sourcePicture: PictureInfo(
              width: 600,
              height: 2400,
              size: originalBytes.length,
              type: 'image/png')));

  Future<void> expectDisposedPreview() async {
    expect(previewPath, isNotNull);
    expect(await File(previewPath!).exists(), isFalse);
    expect(await File(previewPath!).parent.exists(), isFalse);
    expect(await original.readAsBytes(), orderedEquals(originalBytes));
  }

  test('separate uploads preserve the original and publish an identified crop',
      () async {
    final outgoing = message();
    await uploader.prepare(outgoing);
    expect(uploads.map((args) => args['id']),
        ['chat-media:same-message', 'chat-top-preview:same-message']);
    expect(
        uploads.map((args) => args['contentType']), ['image/png', 'image/png']);
    expect(uploads.first['filePath'], original.path);
    expect(uploadedBytes.first, orderedEquals(originalBytes));
    final preview = img.decodePng(Uint8List.fromList(uploadedBytes.last))!;
    expect([preview.width, preview.height], [480, 864]);
    expect(preview.getPixel(200, 840).r, 255);
    expect(preview.getPixel(200, 840).b, 0);

    final picture = outgoing.pictureElem!;
    expect(picture.sourcePath, original.path);
    expect(picture.sourcePicture!.url, _sourceURL);
    expect(picture.bigPicture!.toJson(), picture.sourcePicture!.toJson());
    expect(
        [picture.bigPicture!.width, picture.bigPicture!.height], [600, 2400]);
    expect(picture.snapshotPicture!.url, _previewURL);
    expect(picture.snapshotPicture!.size, uploadedBytes.last.length);
    expect(ChatPicturePreviewMetadata.topCrop(outgoing),
        same(picture.snapshotPicture));
    expect(outgoing.clientMsgID, 'same-message');
    final roundTrip = Message.fromJson(
        jsonDecode(jsonEncode(outgoing.toJson())) as Map<String, dynamic>);
    expect((jsonDecode(roundTrip.ex!) as Map)['unrelated'],
        {'keep': true, 'label': '备注'});
    expect(ChatPicturePreviewMetadata.topCrop(roundTrip)?.url, _previewURL);
    expect(roundTrip.pictureElem!.sourcePicture!.height, 2400);
    expect(stages, [ChatTransferStage.uploading, ChatTransferStage.queued]);
    await expectDisposedPreview();
  });

  for (final failure in ['transport', 'invalid URL']) {
    test('preview $failure failure retains the legacy source and cleans temp',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final response = await upload(call);
        if (uploads.length == 2) {
          if (failure == 'transport') throw PlatformException(code: 'offline');
          return jsonEncode({'url': 'not-a-remote-url'});
        }
        return response;
      });
      final outgoing = message();
      final extraBefore = outgoing.ex;
      await uploader.prepare(outgoing);
      expect(outgoing.pictureElem!.sourcePicture!.url, _sourceURL);
      expect(outgoing.pictureElem!.bigPicture!.height, 2400);
      expect(outgoing.pictureElem!.snapshotPicture!.url,
          OpenIMMediaUrl.thumbnail(_sourceURL, width: 640, height: 640));
      expect(outgoing.ex, extraBefore);
      expect(ChatPicturePreviewMetadata.topCrop(outgoing), isNull);
      expect(stages.last, ChatTransferStage.queued);
      await expectDisposedPreview();
    });
  }

  test('cancellation during the second upload publishes no partial media state',
      () async {
    final enteredPreview = Completer<void>();
    final releasePreview = Completer<dynamic>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final response = await upload(call);
      if (uploads.length == 2) {
        enteredPreview.complete();
        return releasePreview.future;
      }
      return response;
    });
    final outgoing = message();
    final before = jsonDecode(jsonEncode(outgoing.toJson()));
    final pending = uploader.prepare(outgoing);
    final rejected = expectLater(pending, throwsStateError);
    await enteredPreview.future;
    expect(await File(previewPath!).exists(), isTrue);
    expect(outgoing.toJson(), before);
    closed = true;
    releasePreview.complete(jsonEncode({'url': _previewURL}));
    await rejected;
    expect(outgoing.toJson(), before);
    expect(stages, [ChatTransferStage.uploading]);
    await expectDisposedPreview();
  });

  test('malformed extension remains opaque and skips optional preview upload',
      () async {
    final outgoing = message(extra: '{opaque-extension');
    await uploader.prepare(outgoing);
    expect(uploads, hasLength(1));
    expect(outgoing.ex, '{opaque-extension');
    expect(outgoing.pictureElem!.sourcePicture!.url, _sourceURL);
    expect(outgoing.pictureElem!.snapshotPicture!.url,
        OpenIMMediaUrl.thumbnail(_sourceURL, width: 640, height: 640));
    expect(ChatPicturePreviewMetadata.topCrop(outgoing), isNull);
    expect(await original.readAsBytes(), orderedEquals(originalBytes));
  });
}
