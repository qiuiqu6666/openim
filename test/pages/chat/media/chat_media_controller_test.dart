import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/chat_media_controller.dart';

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdkChannel = MethodChannel('flutter_openim_sdk');
  late ChatMediaController media;
  late Completer<String> created;
  late List<Message> sent;
  late List<Message> staged;
  late int sdkCalls;
  bool voiceBusy = false;

  void completeImage() => created.complete(jsonEncode(
      Message(clientMsgID: 'image', contentType: MessageType.picture)
          .toJson()));

  setUp(() {
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
  tearDown(() {
    media.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, null);
  });

  test('picture staging owns one pending message and defers delivery',
      () async {
    // GIF compression preserves the original path without platform compression.
    final pending = media.sendPicture(path: 'image.gif', sendNow: false);
    await _flush();
    completeImage();
    await pending;
    expect(staged.single.clientMsgID, 'image');
    expect(media.tempMessages, staged);
    expect(sent, isEmpty);
  });

  test('picture creation finishing after close cannot stage or deliver',
      () async {
    final pending = media.sendPicture(path: 'image.gif', sendNow: false);
    await _flush();
    media.close();
    completeImage();
    await pending;
    expect(staged, isEmpty);
    expect(media.tempMessages, isEmpty);
    expect(sent, isEmpty);
  });

  test('picture creation finishing after account switch cannot deliver',
      () async {
    final pending = media.sendPicture(path: 'image.gif');
    await _flush();
    OpenIM.iMManager.userID = 'next-account';
    completeImage();
    await pending;
    expect(sent, isEmpty);
    expect(staged, isEmpty);
  });

  test('closed media does not start another SDK image creation', () async {
    media.close();
    await media.sendPicture(path: 'image.gif');
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
