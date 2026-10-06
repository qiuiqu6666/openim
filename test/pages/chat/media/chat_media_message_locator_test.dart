import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/chat_media_message_locator.dart';
import 'package:openim/pages/chat/media/chat_picture_gallery.dart';

Message _picture(String id) => Message(
    clientMsgID: id,
    contentType: MessageType.picture,
    status: MessageStatus.succeeded,
    pictureElem: PictureElem(
        sourcePicture: PictureInfo(url: 'https://example.com/$id.jpg')));

Message _expired(Message message) => message
  ..attachedInfoElem = AttachedInfoElem(
      isPrivateChat: true,
      burnDuration: 1,
      hasReadTime: DateTime.now()
          .subtract(const Duration(seconds: 10))
          .millisecondsSinceEpoch);

class _Fixture {
  final first = _picture('first');
  final second = _picture('second');
  final messages = <String, Message>{};
  final feedback = <ChatMediaLocationFailure>[];
  final jumps = <Message>[];
  final finds = <String>[];
  bool current = true;
  bool positioningCurrent = true;
  Future<Message?> Function(String)? lookup;
  Future<bool> Function(Message)? jump;
  late ChatPictureGallery gallery;
  late ChatMediaMessageLocator locator;

  Future<void> initialize() async {
    messages.addAll({'first': first, 'second': second});
    gallery = await ChatPictureGallery.fromMessages([first, second], first);
    locator = ChatMediaMessageLocator(
        gallery: gallery,
        isCurrent: () => current,
        isPositioningCurrent: () => positioningCurrent,
        currentMessage: (id) => messages[id],
        findMessage: (id) {
          finds.add(id);
          return lookup?.call(id) ?? Future.value(null);
        },
        jumpToMessage: (message) {
          jumps.add(message);
          return jump?.call(message) ?? Future.value(true);
        },
        showFeedback: feedback.add);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a swiped index targets its own message with no lookup while loaded',
      () async {
    final f = _Fixture();
    await f.initialize();
    expect(await f.locator.viewInChat(1), isTrue);
    expect(f.jumps.single.clientMsgID, 'second');
    expect(f.gallery.initialIndex, 0);
    expect(f.finds, isEmpty);
    expect(f.feedback, isEmpty);
  });

  test('forward/delete lookup never falls back to the originally tapped record',
      () async {
    final f = _Fixture();
    await f.initialize();
    f.second.seq = 99;
    expect(f.locator.currentMessageAt(1)?.clientMsgID, 'second');
    expect(f.locator.currentMessageAt(1)?.seq, 99);
    f.messages.remove('second');
    expect(f.locator.currentMessageAt(1), isNull);
    expect(f.messages['first'], isNotNull);
    expect(f.feedback, [ChatMediaLocationFailure.messageUnavailable]);
    expect(f.finds, isEmpty);
    expect(f.jumps, isEmpty);
  });

  test(
      'paged-out message is confirmed by ID and positioned with fresh SDK data',
      () async {
    final f = _Fixture();
    await f.initialize();
    f.messages.remove('second');
    f.lookup = (id) async => _picture(id)..seq = 99;
    expect(await f.locator.viewInChat(1), isTrue);
    expect(f.finds, ['second']);
    expect(f.jumps.single.clientMsgID, 'second');
    expect(f.jumps.single.seq, 99);
    expect(f.feedback, isEmpty);
  });

  test('missing SDK record is not inserted into the history window', () async {
    final f = _Fixture();
    await f.initialize();
    f.messages.remove('second');
    expect(await f.locator.viewInChat(1), isFalse);
    expect(f.finds, ['second']);
    expect(f.jumps, isEmpty);
    expect(f.feedback, [ChatMediaLocationFailure.messageUnavailable]);
  });

  test('unexpected SDK identity or revoked content cannot revive a snapshot',
      () async {
    final f = _Fixture();
    await f.initialize();
    f.messages.remove('second');
    f.lookup = (_) async => _picture('first');
    expect(await f.locator.viewInChat(1), isFalse);
    f.lookup = (_) async => Message(
        clientMsgID: 'second',
        contentType: MessageType.revokeMessageNotification);
    expect(await f.locator.viewInChat(1), isFalse);
    expect(f.jumps, isEmpty);
    expect(
        f.feedback, everyElement(ChatMediaLocationFailure.messageUnavailable));
  });

  test('invalid indexes do not jump or act on any gallery record', () async {
    final f = _Fixture();
    await f.initialize();
    for (final index in [-1, 2, 100]) {
      expect(await f.locator.viewInChat(index), isFalse);
      expect(f.locator.currentMessageAt(index), isNull);
    }
    expect(f.jumps, isEmpty);
    expect(f.finds, isEmpty);
  });

  test('expired live record blocks view and destructive actions', () async {
    final f = _Fixture();
    await f.initialize();
    _expired(f.second);
    expect(await f.locator.viewInChat(1), isFalse);
    expect(f.locator.currentMessageAt(1), isNull);
    expect(f.feedback, everyElement(ChatMediaLocationFailure.messageExpired));
    expect(f.finds, isEmpty);
    expect(f.jumps, isEmpty);
  });

  test('expiry or revocation during exact lookup blocks the delayed jump',
      () async {
    final f = _Fixture();
    await f.initialize();
    f.messages.remove('second');
    final pending = Completer<Message?>();
    f.lookup = (_) => pending.future;
    final action = f.locator.viewInChat(1);
    f.messages['second'] = _expired(_picture('second'));
    pending.complete(_picture('second'));
    expect(await action, isFalse);
    expect(f.jumps, isEmpty);
    expect(f.feedback, [ChatMediaLocationFailure.messageExpired]);
  });

  test('a session invalidated before or during lookup remains silent',
      () async {
    final f = _Fixture();
    await f.initialize();
    f.current = false;
    expect(await f.locator.viewInChat(1), isFalse);
    expect(f.locator.currentMessageAt(1), isNull);
    expect(f.finds, isEmpty);
    f.current = true;
    f.messages.remove('second');
    final pending = Completer<Message?>();
    f.lookup = (_) => pending.future;
    final action = f.locator.viewInChat(1);
    f.current = false;
    pending.complete(_picture('second'));
    expect(await action, isFalse);
    expect(f.jumps, isEmpty);
    expect(f.feedback, isEmpty);
  });

  test('duplicate locate taps share one in-flight lookup', () async {
    final f = _Fixture();
    await f.initialize();
    f.messages.remove('second');
    final pending = Completer<Message?>();
    f.lookup = (_) => pending.future;
    final action = f.locator.viewInChat(1);
    expect(await f.locator.viewInChat(1), isFalse);
    expect(f.finds, ['second']);
    pending.complete(_picture('second'));
    expect(await action, isTrue);
    expect(f.jumps, hasLength(1));
  });

  test('a newly covered chat stops lookup without blocking preview actions',
      () async {
    final f = _Fixture();
    await f.initialize();
    f.positioningCurrent = false;
    expect(await f.locator.viewInChat(1), isFalse);
    expect(f.finds, isEmpty);
    expect(f.locator.currentMessageAt(1)?.clientMsgID, 'second');
    f.positioningCurrent = true;
    f.messages.remove('second');
    final pending = Completer<Message?>();
    f.lookup = (_) => pending.future;
    final action = f.locator.viewInChat(1);
    f.positioningCurrent = false;
    pending.complete(_picture('second'));
    expect(await action, isFalse);
    expect(f.jumps, isEmpty);
    expect(f.feedback, isEmpty);
  });

  test('position failure is feedback once and a later attempt is allowed',
      () async {
    final f = _Fixture();
    await f.initialize();
    f.jump = (_) async => false;
    expect(await f.locator.viewInChat(1), isFalse);
    expect(f.feedback, [ChatMediaLocationFailure.positionFailed]);
    f.jump = (_) async => true;
    expect(await f.locator.viewInChat(1), isTrue);
    expect(f.finds, isEmpty);
  });

  test('late positioning failure after account change shows no old toast',
      () async {
    final f = _Fixture();
    await f.initialize();
    final pending = Completer<bool>();
    f.jump = (_) => pending.future;
    final action = f.locator.viewInChat(1);
    f.current = false;
    pending.complete(false);
    expect(await action, isFalse);
    expect(f.feedback, isEmpty);
  });

  test('lookup errors are contained and do not position old snapshots',
      () async {
    final f = _Fixture();
    await f.initialize();
    f.messages.remove('second');
    f.lookup = (_) async => throw StateError('offline');
    expect(await f.locator.viewInChat(1), isFalse);
    expect(f.jumps, isEmpty);
    expect(f.feedback, [ChatMediaLocationFailure.positionFailed]);
  });

  const channel = MethodChannel('flutter_openim_sdk');
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('production lookup requests only one ID in the current conversation',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return jsonEncode({
        'totalCount': 2,
        'findResultItems': [
          {
            'conversationID': 'other',
            'messageList': [_picture('second').toJson()]
          },
          {
            'conversationID': 'chat',
            'messageList': [_picture('second').toJson()]
          },
        ],
      });
    });
    final found = await ChatMediaMessageLocator.findStoredMessage(
        conversationID: 'chat', clientMsgID: 'second');
    expect(found?.clientMsgID, 'second');
    expect(calls.single.method, 'findMessageList');
    final params = (calls.single.arguments as Map)['searchParams'];
    expect(params, [
      {
        'conversationID': 'chat',
        'clientMsgIDList': ['second']
      }
    ]);
  });

  test(
      'production lookup rejects another conversation and supports SDK fallback',
      () async {
    var currentConversation = 'other';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (_) async => jsonEncode({
                  'searchResultItems': [
                    {
                      'conversationID': currentConversation,
                      'messageList': [_picture('second').toJson()]
                    },
                  ],
                }));
    expect(
        await ChatMediaMessageLocator.findStoredMessage(
            conversationID: 'chat', clientMsgID: 'second'),
        isNull);
    currentConversation = 'chat';
    expect(
        (await ChatMediaMessageLocator.findStoredMessage(
                conversationID: 'chat', clientMsgID: 'second'))
            ?.clientMsgID,
        'second');
  });
}
