import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/chat_media_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

class _Asset extends AssetEntity {
  const _Asset(String id, this.localFile)
      : super(id: id, typeInt: 1, width: 100, height: 100);

  final Future<File?> localFile;

  @override
  Future<File?> get file => localFile;
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Operation did not complete');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

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
  late Directory directory;
  late File photo;
  late ChatMediaController media;
  late List<AssetEntity> selected;
  late List<Message> staged;
  late List<String> sends;
  late List<String> paths;
  late Future<File?> Function(File) compress;
  late Future<void> Function(Message) deliver;
  late int failures;
  late int pickerCalls;
  late int toolboxClosed;
  late bool sdkFailure;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat-album-send-');
    Config.cachePath = directory.path;
    photo = await File('${directory.path}/photo.jpg').writeAsBytes([1, 2, 3]);
    OpenIM.iMManager.userID = 'self';
    selected = [];
    staged = [];
    sends = [];
    paths = [];
    failures = pickerCalls = toolboxClosed = 0;
    sdkFailure = false;
    compress = (file) async => file;
    deliver = (_) async {};
    media = ChatMediaController(
      conversationID: () => 'chat',
      isClosed: () => OpenIM.iMManager.userID != 'self',
      sendingMuted: () => false,
      isInvalidGroup: () => false,
      voiceBusy: () => false,
      sendMessage: (message, {addToUI = true, resetInput = true}) async {
        expect(addToUI, isFalse, reason: 'Already staged once');
        expect(staged, contains(message));
        sends.add(message.clientMsgID!);
        await deliver(message);
      },
      stageMessage: staged.add,
      previewVoice: (_, __) async {},
      closeToolbox: () => toolboxClosed++,
      pickAssets: () async {
        pickerCalls++;
        return selected;
      },
      compressImage: (file) => compress(file),
      onPreparationFailed: () => failures++,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'uploadFile') {
        return jsonEncode({'url': 'https://im.test/object/media/image.png'});
      }
      expect(call.method, 'createImageMessageFromFullPath');
      final path = (call.arguments as Map)['imagePath'] as String;
      paths.add(path);
      if (sdkFailure) {
        sdkFailure = false;
        throw PlatformException(code: 'invalid-image');
      }
      return jsonEncode(Message(
        clientMsgID: 'image-${paths.length}',
        contentType: MessageType.picture,
        status: MessageStatus.sending,
        pictureElem: PictureElem(
            sourcePath: path,
            sourcePicture:
                PictureInfo(type: 'image/jpeg', width: 100, height: 100)),
      ).toJson());
    });
  });

  tearDown(() async {
    media.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('first local image sends while the next file is still preparing',
      () async {
    final nextFile = Completer<File?>();
    selected = [
      _Asset('first', Future.value(photo)),
      _Asset('second', nextFile.future),
    ];
    final pending = media.onTapAlbum();
    await _until(() => sends.isNotEmpty);
    expect(sends, ['image-1']);
    expect(staged, hasLength(1));
    expect(media.preparingCount.value, 1);
    expect(media.pickingAttachment, isTrue);
    expect(toolboxClosed, 1);
    await media.onTapAlbum();
    expect(pickerCalls, 1, reason: 'Repeated taps must not duplicate a batch');
    nextFile.complete(photo);
    await pending;
    expect(sends, ['image-1', 'image-2']);
    expect(staged, hasLength(2));
    expect(media.preparingCount.value, 0);
    expect(media.pickingAttachment, isFalse);
    expect(failures, 0);
  });

  test('slow receipt does not block later bubbles and sends stay ordered',
      () async {
    final firstUpload = Completer<void>();
    deliver = (message) => message.clientMsgID == 'image-1'
        ? firstUpload.future
        : Future<void>.value();
    selected = [
      _Asset('first', Future.value(photo)),
      _Asset('second', Future.value(photo)),
    ];
    final pending = media.onTapAlbum();
    await _until(() => staged.length == 2);
    expect(sends, ['image-1']);
    expect(media.preparingCount.value, 0);
    expect(paths.toSet(), hasLength(2));
    expect(paths, everyElement(isNot(photo.path)));
    await photo.writeAsBytes([9]);
    for (final path in paths) {
      expect(await File(path).readAsBytes(), [1, 2, 3]);
    }
    firstUpload.complete();
    await pending;
    expect(sends, ['image-1', 'image-2']);
  });

  for (final result in ['throw', 'null', 'empty', 'missing']) {
    test('compression $result falls back to retained local image', () async {
      compress = (file) async {
        switch (result) {
          case 'throw':
            throw const FormatException('Unsupported compression');
          case 'null':
            return null;
          case 'empty':
            return File('${directory.path}/empty.jpg').writeAsBytes([]);
          default:
            return File('${directory.path}/missing.jpg');
        }
      };
      selected = [_Asset('first', Future.value(photo))];
      await media.onTapAlbum();
      expect(sends, ['image-1']);
      expect(await File(paths.single).readAsBytes(), [1, 2, 3]);
      expect(paths.single, isNot(photo.path));
      expect(failures, 0);
    });
  }

  test('missing asset and SDK failure do not drop later selected images',
      () async {
    sdkFailure = true;
    selected = [
      _Asset('missing', Future.value(null)),
      _Asset('invalid', Future.value(photo)),
      _Asset('valid', Future.value(photo)),
    ];
    await media.onTapAlbum();
    expect(failures, 2);
    expect(staged, hasLength(1));
    expect(sends, ['image-2']);
    expect(media.preparingCount.value, 0);
    expect(media.pickingAttachment, isFalse);
  });

  for (final switchAccount in [false, true]) {
    test(
        'late preparation is discarded after ${switchAccount ? 'account switch' : 'close'}',
        () async {
      final compressed = Completer<File?>();
      var started = false;
      compress = (_) {
        started = true;
        return compressed.future;
      };
      selected = [_Asset('first', Future.value(photo))];
      final pending = media.onTapAlbum();
      await _until(() => started);
      expect(media.preparingCount.value, 1);
      if (switchAccount) {
        OpenIM.iMManager.userID = 'next-account';
      } else {
        media.close();
      }
      compressed.complete(photo);
      await pending;
      expect(paths, isEmpty);
      expect(staged, isEmpty);
      expect(sends, isEmpty);
      expect(failures, 0);
      expect(media.preparingCount.value, 0);
    });
  }

  test('queued uploads are not sent after leaving the chat', () async {
    final firstUpload = Completer<void>();
    deliver = (_) => firstUpload.future;
    selected = [
      _Asset('first', Future.value(photo)),
      _Asset('second', Future.value(photo)),
    ];
    final pending = media.onTapAlbum();
    await _until(() => staged.length == 2);
    media.close();
    firstUpload.complete();
    await pending;
    expect(sends, ['image-1']);
    expect(media.preparingCount.value, 0);
  });

  test('unexpected delivery failure does not stall the next image', () async {
    deliver = (message) async {
      if (message.clientMsgID == 'image-1') throw StateError('Delivery failed');
    };
    selected = [
      _Asset('first', Future.value(photo)),
      _Asset('second', Future.value(photo)),
    ];
    await media.onTapAlbum();
    expect(sends, ['image-1', 'image-2']);
    expect(failures, 1);
    expect(media.pickingAttachment, isFalse);
  });

  test('cancelled album does not show progress or close toolbox', () async {
    await media.onTapAlbum();
    expect(staged, isEmpty);
    expect(sends, isEmpty);
    expect(toolboxClosed, 0);
    expect(media.preparingCount.value, 0);
    expect(media.pickingAttachment, isFalse);
  });
}
