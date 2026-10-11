import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/chat_media_controller.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdkChannel = MethodChannel('flutter_openim_sdk');
  late ChatMediaController media;
  late Completer<String> created;
  late List<Message> sent;
  late List<Message> staged;
  late int sdkCalls;
  late Directory directory;
  late File image;
  bool voiceBusy = false;

  void completeImage() => created.complete(jsonEncode(
      Message(clientMsgID: 'image', contentType: MessageType.picture)
          .toJson()));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat-media-controller-');
    Config.cachePath = directory.path;
    image = await File('${directory.path}/image.gif').writeAsBytes([1, 2, 3]);
    OpenIM.iMManager.userID = 'self';
    created = Completer<String>();
    sent = [];
    staged = [];
    sdkCalls = 0;
    voiceBusy = false;
    media = ChatMediaController(
      conversationID: () => 'chat',
      // Mirrors the chat route's session-invalid callback after extraction.
      isClosed: () => OpenIM.iMManager.userID != 'self',
      sendingMuted: () => false,
      isInvalidGroup: () => false,
      voiceBusy: () => voiceBusy,
      sendMessage: (message, {addToUI = true, resetInput = true}) async {
        sent.add(message);
      },
      stageMessage: staged.add,
      previewVoice: (_, __) async {},
      closeToolbox: () {},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, (call) {
      if (call.method != 'createImageMessageFromFullPath') {
        throw StateError('Unexpected SDK method: ${call.method}');
      }
      sdkCalls++;
      return created.future;
    });
  });
  tearDown(() async {
    media.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, null);
    await directory.delete(recursive: true);
  });

  Future<void> waitForCreation() async {
    while (sdkCalls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  test('picture staging owns one pending message and defers delivery',
      () async {
    // GIF compression preserves the original path without platform compression.
    final pending = media.sendPicture(path: image.path, sendNow: false);
    await waitForCreation().timeout(const Duration(seconds: 5));
    completeImage();
    await pending;
    expect(staged.single.clientMsgID, 'image');
    expect(media.tempMessages, staged);
    expect(sent, isEmpty);
  });

  test('picture creation finishing after close cannot stage or deliver',
      () async {
    final pending = media.sendPicture(path: image.path, sendNow: false);
    await waitForCreation().timeout(const Duration(seconds: 5));
    media.close();
    completeImage();
    await pending;
    expect(staged, isEmpty);
    expect(media.tempMessages, isEmpty);
    expect(sent, isEmpty);
  });

  test('picture creation finishing after account switch cannot deliver',
      () async {
    final pending = media.sendPicture(path: image.path);
    await waitForCreation().timeout(const Duration(seconds: 5));
    OpenIM.iMManager.userID = 'next-account';
    completeImage();
    await pending;
    expect(sent, isEmpty);
    expect(staged, isEmpty);
  });

  test('closed media does not start another SDK image creation', () async {
    media.close();
    await media.sendPicture(path: image.path);
    expect(sdkCalls, 0);
  });

  test('active voice blocks all attachment selection entry points', () async {
    voiceBusy = true;
    await media.onTapAlbum();
    await media.onTapCamera();
    await media.onTapFile();
    await media.onTapAudio();
    expect(media.pickingAttachment, isFalse);
    expect(sdkCalls, 0);
  });
}
