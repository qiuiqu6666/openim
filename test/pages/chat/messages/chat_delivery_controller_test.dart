import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/chat_delivery_controller.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

Message _outgoing(String id) => Message(
      clientMsgID: id,
      contentType: MessageType.text,
      sendID: 'self',
      status: MessageStatus.sending,
    );

Message _sent(String id) => Message(
      clientMsgID: id,
      contentType: MessageType.text,
      sendID: 'self',
      status: MessageStatus.succeeded,
      seq: 7,
    );

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdkChannel = MethodChannel('flutter_openim_sdk');
  late ChatDeliveryController delivery;
  late RxList<Message> messages;
  late Completer<Message> transport;
  late List<FavoriteTarget> destinations;
  late String currentAccount;
  late bool sessionInactive;
  late int inputResets;
  late int scrolls;

  setUp(() {
    OpenIM.iMManager.userID = 'self';
    currentAccount = 'self';
    sessionInactive = false;
    messages = <Message>[].obs;
    transport = Completer<Message>();
    destinations = [];
    inputResets = 0;
    scrolls = 0;
    delivery = ChatDeliveryController(
      accountID: 'self',
      currentAccountID: () => currentAccount,
      messageList: messages,
      conversation: () => ConversationInfo(
          conversationID: 'chat', userID: 'peer', unreadCount: 0),
      isClosed: () => sessionInactive,
      groupStatus: () => null,
      scrollBottom: () => scrolls++,
      resetInput: (_) => inputResets++,
      sendRaw: (message, target) {
        destinations.add(target);
        return transport.future;
      },
    );
  });

  tearDown(() {
    delivery.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, null);
  });

  test('successful delivery updates the existing bubble once', () async {
    final message = _outgoing('one');
    final pending = delivery.send(message);
    expect(messages.single, same(message));
    expect(inputResets, 1);
    expect(scrolls, 1);
    expect(destinations.single.userID, 'peer');
    transport.complete(_sent('one'));
    await pending;
    expect(messages, hasLength(1));
    expect(message.status, MessageStatus.succeeded);
    expect(message.seq, 7);
  });

  test('staged attachments preserve one bubble without resetting input',
      () async {
    final message = _outgoing('staged');
    messages.add(message);
    final pending = delivery.send(message, addToUI: false, resetInput: false);
    transport.complete(_sent('staged'));
    await pending;
    expect(messages, hasLength(1));
    expect(inputResets, 0);
    expect(scrolls, 0);
    expect(message.status, MessageStatus.succeeded);
  });

  test('forwarding to another destination leaves the current timeline alone',
      () async {
    final message = _outgoing('forwarded');
    final pending = delivery.send(message, userId: 'another-peer');
    transport.complete(_sent('forwarded'));
    await pending;
    expect(destinations.single.userID, 'another-peer');
    expect(destinations.single.groupID, isNull);
    expect(messages, isEmpty);
    expect(scrolls, 0);
  });

  test('a late success after close does not update the old bubble', () async {
    final message = _outgoing('late');
    final pending = delivery.send(message);
    delivery.close();
    transport.complete(_sent('late'));
    await pending;
    expect(message.status, MessageStatus.sending);
    expect(message.seq, isNull);
  });

  test('a late success after account switch does not update the old bubble',
      () async {
    final message = _outgoing('old-account');
    final pending = delivery.send(message);
    currentAccount = 'next-account';
    transport.complete(_sent('old-account'));
    await pending;
    expect(message.status, MessageStatus.sending);
    expect(message.seq, isNull);
  });

  test('a late failure after session invalidation does not mark the bubble',
      () async {
    final message = _outgoing('old-token');
    final pending = delivery.send(message);
    sessionInactive = true;
    transport.completeError(TimeoutException('transport delayed'));
    await pending;
    expect(message.status, MessageStatus.sending);
  });

  test('closed or switched sessions reject sends before transport and UI work',
      () async {
    currentAccount = 'next-account';
    final results = <FavoriteSendResult>[];
    await delivery.send(_outgoing('switched'), favoriteResult: results.add);
    delivery.close();
    await delivery.send(_outgoing('closed'), favoriteResult: results.add);
    expect(destinations, isEmpty);
    expect(messages, isEmpty);
    expect(inputResets, 0);
    expect(scrolls, 0);
    expect(results.map((value) => value.status),
        everyElement(FavoriteSendStatus.failed));
    expect(
        results.map((value) => value.errorCode), everyElement('CHAT_CLOSED'));
  });

  test('favorite timeouts retain an unresolved bubble without permitting retry',
      () async {
    final message = _outgoing('favorite');
    final results = <FavoriteSendResult>[];
    final pending = delivery.send(message, favoriteResult: results.add);
    transport.completeError(TimeoutException('transport delayed'));
    await pending;
    expect(results.single.status, FavoriteSendStatus.unknown);
    expect(results.single.retryable, isFalse);
    expect(message.status, MessageStatus.sending);
  });

  test('ordinary send timeouts retain the existing failed-bubble behavior',
      () async {
    final message = _outgoing('ordinary');
    final pending = delivery.send(message);
    transport.completeError(TimeoutException('transport delayed'));
    await pending;
    expect(message.status, MessageStatus.failed);
  });

  test('a mismatched favorite receipt remains unresolved', () async {
    final message = _outgoing('favorite');
    final results = <FavoriteSendResult>[];
    final pending = delivery.send(message, favoriteResult: results.add);
    transport.complete(_sent('different-message'));
    await pending;
    expect(results.single.status, FavoriteSendStatus.unknown);
    expect(results.single.errorCode, 'RECEIPT_UNCONFIRMED');
    expect(message.status, MessageStatus.sending);
    expect(message.clientMsgID, 'favorite');
  });

  test(
      'a failed hint finishing after account switch is neither shown nor saved',
      () async {
    final hint = Completer<String>();
    final nativeCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, (call) {
      nativeCalls.add(call.method);
      if (call.method == 'createCustomMessage') return hint.future;
      throw StateError('Unexpected SDK method: ${call.method}');
    });
    final message = _outgoing('rejected');
    final pending = delivery.send(message);
    transport.completeError(
        PlatformException(code: SDKErrorCode.notFriend.toString()));
    await pending;
    await _flush();
    expect(nativeCalls, ['createCustomMessage']);
    expect(message.status, MessageStatus.failed);
    currentAccount = 'next-account';
    OpenIM.iMManager.userID = currentAccount;
    hint.complete(jsonEncode(Message(
      clientMsgID: 'hint',
      contentType: MessageType.custom,
    ).toJson()));
    await _flush();
    expect(messages.map((value) => value.clientMsgID), ['rejected']);
    expect(nativeCalls, ['createCustomMessage']);
  });
}
