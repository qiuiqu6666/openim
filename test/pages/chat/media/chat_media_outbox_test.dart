import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:openim/pages/chat/media/chat_media_controller.dart';
import 'package:openim/pages/chat/media/upload/chat_media_outbox.dart';
import 'package:openim/pages/chat/media/upload/chat_media_outbox_binding.dart';
import 'package:openim/pages/chat/messages/chat_delivery_controller.dart';
import 'package:openim/services/chat_message_sender.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

class _Asset extends AssetEntity {
  const _Asset(this.source)
      : super(id: 'photo', typeInt: 1, width: 10, height: 10);
  final Future<File?> source;
  @override
  Future<File?> get file => source;
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  const target =
      FavoriteTarget(conversationID: 'chat-a', userID: 'a', sessionType: 1);
  late Directory directory;
  late File photo;
  late ChatMediaOutbox outbox;
  late ChatMediaController media;
  late Completer<String> upload;
  late int uploads;
  late List<String> destinations;
  late Future<File?> asset;
  late Future<Message> Function(Message, FavoriteTarget) transport;
  late List<MethodCall> nativeSends;
  late int created;
  late int selectedCount;
  late FavoriteTarget destination;
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    await Config.init(() {});
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('outbox-');
    Config.cachePath = directory.path;
    photo = await File('${directory.path}/photo.jpg').writeAsBytes([1, 2, 3]);
    asset = Future.value(photo);
    OpenIM.iMManager.userID = 'owner';
    upload = Completer<String>();
    uploads = 0;
    destinations = [];
    nativeSends = [];
    created = 0;
    selectedCount = 1;
    destination = target;
    transport = (message, destination) async {
      destinations.add(destination.userID!);
      return Message.fromJson(message.toJson())
        ..status = MessageStatus.succeeded
        ..seq = 1;
    };
    outbox = ChatMediaOutbox(
        sender: ChatMessageSender(transport: (m, t) => transport(m, t)),
        confirmTimeout: const Duration(milliseconds: 20));
    media = ChatMediaController(
      conversationID: () => 'chat-a',
      isClosed: () => false,
      sendingMuted: () => false,
      isInvalidGroup: () => false,
      voiceBusy: () => false,
      acceptSendTask: () => outbox.accept(destination),
      sendMessage: (m, {addToUI = true, resetInput = true}) async {
        fail('Route sender must not own accepted media');
      },
      stageMessage: (_) => fail('Outbox must own staging'),
      previewVoice: (_, __) async {},
      closeToolbox: () {},
      pickAssets: () async =>
          List.generate(selectedCount, (_) => _Asset(asset)),
      compressImage: (f) async => f,
      pickCamera: () async => _Asset(asset),
      onPreparationFailed: () => fail('Preparation failed'),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'uploadFile') {
        uploads++;
        return upload.future;
      }
      if (call.method == 'sendMessageNotOss') {
        nativeSends.add(call);
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final message = Message.fromJson(
            jsonDecode(jsonEncode(args['message'])) as Map<String, dynamic>);
        expect(message.pictureElem!.sourcePicture!.url, startsWith('https://'));
        expect(message.pictureElem!.bigPicture!.url, startsWith('https://'));
        expect(
            message.pictureElem!.snapshotPicture!.url, startsWith('https://'));
        return jsonEncode((message
              ..status = MessageStatus.succeeded
              ..seq = nativeSends.length)
            .toJson());
      }
      expect(call.method, 'createImageMessageFromFullPath');
      created++;
      return jsonEncode(Message(
              clientMsgID: created == 1 ? 'image' : 'image-$created',
              sendID: 'owner',
              contentType: MessageType.picture,
              status: MessageStatus.sending,
              pictureElem: PictureElem(
                  sourcePath: (call.arguments as Map)['imagePath'],
                  sourcePicture:
                      PictureInfo(type: 'image/jpeg', width: 10, height: 10)))
          .toJson());
    });
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    media.close();
    outbox.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });
  void finishUpload() =>
      upload.complete(jsonEncode({'url': 'https://example.test/photo.jpg'}));

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final group in [false, true]) {
      test(
          '$platform SDK channel contract: multi-image after exit group=$group',
          () async {
        debugDefaultTargetPlatformOverride = platform;
        outbox =
            ChatMediaOutbox(); // Real Dart sender; mock only native boundary.
        selectedCount = 3;
        if (group) {
          destination = const FavoriteTarget(
              conversationID: 'group-chat', groupID: 'group-a', sessionType: 3);
        }
        final pending = media.onTapAlbum();
        await until(() => uploads > 0);
        media.close();
        finishUpload();
        await pending;
        expect(nativeSends, hasLength(3));
        final ids = <String>[];
        for (final call in nativeSends) {
          final args = call.arguments as Map;
          expect(args['userID'], group ? '' : 'a');
          expect(args['groupID'], group ? 'group-a' : '');
          expect(args['isOnlineOnly'], false);
          ids.add((args['message'] as Map)['clientMsgID'] as String);
        }
        expect(ids, ['image', 'image-2', 'image-3']);
        expect(
            outbox
                .entries(destination.conversationID)
                .map((e) => e.message.status),
            everyElement(MessageStatus.succeeded));
      });
    }
  }

  test('reentry reconciles a stale cached sending row with completed receipt',
      () async {
    final pending = media.onTapAlbum();
    await until(() => uploads == 1);
    final cached =
        Message.fromJson(outbox.entries('chat-a').single.message.toJson());
    media.close();
    finishUpload();
    await pending;
    final messages = [cached].obs;
    final delivery = ChatDeliveryController(
        messageList: messages,
        conversation: () => ConversationInfo(
            conversationID: 'chat-a', userID: 'a', conversationType: 1),
        isClosed: () => false,
        groupStatus: () => null,
        scrollBottom: () {},
        resetInput: (_) {});
    final subscription = bindMediaOutbox(
        conversationID: 'chat-a',
        messages: messages,
        isClosed: () => false,
        removedIDs: {},
        delivery: delivery,
        outbox: outbox);
    try {
      expect(messages.single.status, MessageStatus.succeeded);
      expect(messages, hasLength(1));
    } finally {
      await subscription.cancel();
      delivery.close();
    }
  });

  test('leaving during upload still submits once to original destination',
      () async {
    final pending = media.onTapAlbum();
    await until(() => uploads == 1);
    media.close();
    expect(outbox.entries('chat-a').single.transfer.stage,
        ChatTransferStage.uploading);
    finishUpload();
    await pending;
    expect(destinations, ['a']);
    expect(outbox.entries('chat-a').single.message.status,
        MessageStatus.succeeded);
    expect(outbox.entries('chat-b'), isEmpty);
  });

  test('camera image also submits after its route closes', () async {
    final pending = media.onTapCamera();
    await until(() => uploads == 1);
    media.close();
    finishUpload();
    await pending;
    expect(destinations, ['a']);
    expect(outbox.entries('chat-a').single.message.status,
        MessageStatus.succeeded);
  });

  test('account switch during asset preparation never creates or uploads',
      () async {
    final file = Completer<File?>();
    asset = file.future;
    final pending = media.onTapAlbum();
    await until(() => media.preparingCount.value == 1);
    OpenIM.iMManager.userID = 'other';
    file.complete(photo);
    await pending;
    expect(created, 0);
    expect(uploads, 0);
    expect(destinations, isEmpty);
  });

  test('one rejected image does not block the remaining accepted batch',
      () async {
    selectedCount = 3;
    transport = (message, t) async {
      destinations.add(message.clientMsgID!);
      if (message.clientMsgID == 'image') {
        throw PlatformException(code: '${SDKErrorCode.userIsNotInGroup}');
      }
      return Message.fromJson(message.toJson())
        ..status = MessageStatus.succeeded
        ..seq = 2;
    };
    final pending = media.onTapAlbum();
    await until(() => uploads > 0);
    media.close();
    finishUpload();
    await pending;
    expect(destinations, ['image', 'image-2', 'image-3']);
    expect(outbox.entries('chat-a').map((e) => e.message.status), [
      MessageStatus.failed,
      MessageStatus.succeeded,
      MessageStatus.succeeded
    ]);
  });

  test('reopened page restores pending media then receives its receipt once',
      () async {
    final pending = media.onTapAlbum();
    await until(() => uploads == 1);
    media.close();
    final messages = <Message>[].obs;
    final delivery = ChatDeliveryController(
      messageList: messages,
      conversation: () => ConversationInfo(
          conversationID: 'chat-a', userID: 'a', conversationType: 1),
      isClosed: () => false,
      groupStatus: () => null,
      scrollBottom: () {},
      resetInput: (_) {},
    );
    final subscription = bindMediaOutbox(
        conversationID: 'chat-a',
        messages: messages,
        isClosed: () => false,
        removedIDs: {},
        delivery: delivery,
        outbox: outbox);
    expect(messages, hasLength(1));
    expect(messages.single.status, MessageStatus.sending);
    finishUpload();
    await pending;
    expect(messages, hasLength(1));
    expect(messages.single.status, MessageStatus.succeeded);
    expect(messages.single.pictureElem!.sourcePicture!.url,
        'https://example.test/photo.jpg');
    await subscription.cancel();
    delivery.close();
  });

  test('upload finishing after presentation detaches never writes disposed UI',
      () async {
    final pending = media.onTapAlbum();
    await until(() => uploads == 1);
    final messages = <Message>[].obs;
    var closed = false;
    final delivery = ChatDeliveryController(
        messageList: messages,
        conversation: () => ConversationInfo(
            conversationID: 'chat-a', userID: 'a', conversationType: 1),
        isClosed: () => closed,
        groupStatus: () => null,
        scrollBottom: () {},
        resetInput: (_) {});
    final subscription = bindMediaOutbox(
        conversationID: 'chat-a',
        messages: messages,
        isClosed: () => closed,
        removedIDs: {},
        delivery: delivery,
        outbox: outbox);
    closed = true;
    await subscription.cancel();
    delivery.close();
    media.close();
    finishUpload();
    await pending;
    expect(destinations, ['a']);
    expect(messages.single.status, MessageStatus.sending,
        reason: 'Disposed page receives no writes; the outbox has the receipt');
    expect(outbox.entries('chat-a').single.message.status,
        MessageStatus.succeeded);
  });
  test('accepted selection finishes preparation after route disposal',
      () async {
    final file = Completer<File?>();
    asset = file.future;
    final pending = media.onTapAlbum();
    await until(() => media.preparingCount.value == 1);
    media.close();
    file.complete(photo);
    await until(() => uploads == 1);
    finishUpload();
    await pending;
    expect(destinations, ['a']);
    expect(media.preparingCount.value, 0);
  });
  for (final logout in [false, true]) {
    test('account change or logout cancels pending submission: logout=$logout',
        () async {
      final pending = media.onTapAlbum();
      await until(() => uploads == 1);
      if (logout) {
        outbox.clear();
      } else {
        OpenIM.iMManager.userID = 'other';
      }
      finishUpload();
      await pending;
      expect(destinations, isEmpty);
      expect(outbox.entries('chat-a'), isEmpty);
    });
  }
  test('upload failure after leaving remains visibly failed on reentry',
      () async {
    final pending = media.onTapAlbum();
    await until(() => uploads == 1);
    media.close();
    upload.completeError(PlatformException(code: 'upload-failed'));
    await pending;
    expect(destinations, isEmpty);
    expect(
        outbox.entries('chat-a').single.message.status, MessageStatus.failed);
  });
  test('confirmation timeout keeps late receipt and never resends', () async {
    final receipt = Completer<Message>();
    transport = (message, t) {
      destinations.add(t.userID!);
      return receipt.future;
    };
    final pending = media.onTapAlbum();
    await until(() => uploads == 1);
    finishUpload();
    await pending;
    final entry = outbox.entries('chat-a').single;
    expect(entry.transfer.stage, ChatTransferStage.unknown);
    await entry.task.send(entry.message);
    expect(destinations, ['a']);
    receipt.complete(Message.fromJson(entry.message.toJson())
      ..status = MessageStatus.succeeded
      ..seq = 2);
    await until(() => entry.message.status == MessageStatus.succeeded);
  });

  test('late receipt after logout does not publish into a new session',
      () async {
    final receipt = Completer<Message>();
    transport = (message, t) {
      destinations.add(t.userID!);
      return receipt.future;
    };
    final pending = media.onTapAlbum();
    await until(() => uploads == 1);
    finishUpload();
    await until(() => destinations.isNotEmpty);
    final message = outbox.entries('chat-a').single.message;
    outbox.clear();
    var published = 0;
    final subscription = outbox.changes.listen((_) => published++);
    receipt.complete(Message.fromJson(message.toJson())
      ..status = MessageStatus.succeeded
      ..seq = 3);
    await pending;
    expect(published, 0);
    expect(outbox.entries('chat-a'), isEmpty);
    await subscription.cancel();
  });
}
