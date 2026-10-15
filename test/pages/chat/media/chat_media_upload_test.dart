import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/upload/chat_media_upload.dart';
import 'package:openim/services/chat_message_sender.dart';
import 'package:openim/services/favorite_send_coordinator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
        appName: '99Chat',
        packageName: 'test.openim',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    await Config.init(() {});
  });
  const channel = MethodChannel('flutter_openim_sdk');
  late List<MethodCall> calls;
  var closed = false;
  late ChatMediaUpload uploader;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'self';
    calls = [];
    closed = false;
    uploader = ChatMediaUpload(isClosed: () => closed, onTransfer: (_, __) {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'uploadFile') {
        return jsonEncode({'url': 'https://im.test/object/media/a.png'});
      }
      final message =
          Map<String, dynamic>.from(call.arguments['message'] as Map);
      message['status'] = MessageStatus.succeeded;
      return jsonEncode(message);
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Message image() => Message(
      clientMsgID: 'same-id',
      exMap: {},
      sendID: 'self',
      status: MessageStatus.sending,
      contentType: MessageType.picture,
      pictureElem: PictureElem(
          sourcePath: '/tmp/image.png',
          sourcePicture: PictureInfo(
              width: 300, height: 900, type: 'image/png', size: 100)));

  test(
      'preupload uses the SDK and sends existing identity without uploading again',
      () async {
    final message = image();
    await uploader.prepare(message);
    expect(message.clientMsgID, 'same-id');
    expect(message.pictureElem!.snapshotPicture!.url, contains('width=640'));
    await ChatMessageSender().sendRaw(
        message,
        const FavoriteTarget(
            conversationID: 'sg_group',
            groupID: 'group',
            sessionType: ConversationType.superGroup));
    expect(
        calls.map((call) => call.method), ['uploadFile', 'sendMessageNotOss']);
    expect(calls.last.arguments['message']['clientMsgID'], 'same-id');
    expect(calls.last.arguments['groupID'], 'group');
  });
  test('local image retains the original SDK upload and send path', () async {
    await ChatMessageSender().sendRaw(
        image(),
        const FavoriteTarget(
            conversationID: 'sg_group',
            groupID: 'group',
            sessionType: ConversationType.superGroup));
    expect(calls.single.method, 'sendMessage');
  });
  test('stalled optional preview cannot prevent sending an uploaded original',
      () async {
    final directory = await Directory.systemTemp.createTemp('preview-stall-');
    final file = await File('${directory.path}/long.png')
        .writeAsBytes(img.encodePng(img.Image(width: 30, height: 300)));
    final previewUpload = Completer<String>();
    final previewStarted = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if ((call.arguments['id'] as String).startsWith('chat-top-preview:')) {
        previewStarted.complete();
        return previewUpload.future;
      }
      return jsonEncode({'url': 'https://im.test/original.png'});
    });
    final message = image()..pictureElem!.sourcePath = file.path;
    final pending = uploader.prepare(message);
    try {
      await previewStarted.future.timeout(const Duration(seconds: 3));
      final finished = await pending
          .then((_) => true)
          .timeout(const Duration(seconds: 6), onTimeout: () => false);
      expect(finished, isTrue,
          reason:
              'The original is uploaded; a decorative preview must be bounded');
      expect(message.pictureElem!.sourcePicture!.url,
          'https://im.test/original.png');
      previewUpload.complete(jsonEncode({'url': 'https://im.test/late.png'}));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
          message.pictureElem!.snapshotPicture!.url, isNot(contains('late')));
    } finally {
      if (!previewUpload.isCompleted) {
        previewUpload.complete(jsonEncode({'url': 'https://im.test/late.png'}));
      }
      await pending;
      await directory.delete(recursive: true);
    }
  });
  test(
      'upload completing after account or route change cannot mutate the message',
      () async {
    final gate = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => gate.future);
    final message = image();
    final pending = uploader.prepare(message);
    final checked = expectLater(pending, throwsStateError);
    closed = true;
    gate.complete(jsonEncode({'url': 'https://im.test/object/a.png'}));
    await checked;
    expect(message.pictureElem!.sourcePicture!.url, isNull);
  });
  test('partial video upload never publishes an incomplete remote message',
      () async {
    var uploads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      if (++uploads == 2) throw PlatformException(code: 'timeout');
      return jsonEncode({'url': 'https://im.test/object/thumb.jpg'});
    });
    final message = Message(
        clientMsgID: 'video',
        contentType: MessageType.video,
        videoElem: VideoElem(
            videoPath: '/tmp/video.mp4', snapshotPath: '/tmp/thumb.jpg'));
    await expectLater(
        uploader.prepare(message), throwsA(isA<PlatformException>()));
    expect(message.videoElem!.videoUrl, isNull);
    expect(message.videoElem!.snapshotUrl, isNull);
  });
}
