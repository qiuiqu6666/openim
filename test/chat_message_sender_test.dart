import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/chat_message_sender.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

void main() {
  Message freshMessage() => Message()..clientMsgID = 'fresh-message';
  FavoriteTarget target() => const FavoriteTarget(
      conversationID: 'conversation-1', userID: 'recipient');

  test('SDK success returns its receipt with the fresh message ID', () async {
    final message = freshMessage();
    final sender = ChatMessageSender(
      accountProvider: () => 'owner',
      transport: (outgoing, destination) async {
        expect(identical(outgoing, message), isTrue);
        expect(destination.userID, 'recipient');
        expect(destination.groupID, isNull);
        return Message()
          ..clientMsgID = outgoing.clientMsgID
          ..status = MessageStatus.succeeded;
      },
    );
    final result = await sender.send(message, target());
    expect(result.status, FavoriteSendStatus.success);
    expect(result.clientMsgID, 'fresh-message');
    expect(message.status, MessageStatus.succeeded);
  });

  test('a network timeout remains unknown and does not leak raw SDK errors',
      () async {
    final sender = ChatMessageSender(
      accountProvider: () => 'owner',
      transport: (_, __) async => throw PlatformException(
        code: '${SDKErrorCode.networkWaitTimeoutError}',
        message: 'secret-token https://private.example/asset',
      ),
    );
    final result = await sender.send(freshMessage(), target());
    expect(result.status, FavoriteSendStatus.unknown);
    expect(result.retryable, isFalse);
    expect(result.errorMessage, isNot(contains('secret-token')));
    expect(result.errorMessage, isNot(contains('private.example')));
  });

  test('an explicit permission rejection is failed rather than success',
      () async {
    final sender = ChatMessageSender(
      accountProvider: () => 'owner',
      transport: (_, __) async =>
          throw PlatformException(code: '${SDKErrorCode.userIsNotInGroup}'),
    );
    final result = await sender.send(freshMessage(), target());
    expect(result.status, FavoriteSendStatus.failed);
    expect(result.errorCode, '${SDKErrorCode.userIsNotInGroup}');
  });

  test('another receipt or account switch does not confirm the current send',
      () async {
    var owner = 'owner-a';
    final sender = ChatMessageSender(
      accountProvider: () => owner,
      transport: (outgoing, _) async {
        owner = 'owner-b';
        return Message()..clientMsgID = outgoing.clientMsgID;
      },
    );
    expect((await sender.send(freshMessage(), target())).status,
        FavoriteSendStatus.unknown);
    final mismatched = ChatMessageSender(
      accountProvider: () => 'owner',
      transport: (_, __) async => Message()..clientMsgID = 'other-message',
    );
    expect((await mismatched.send(freshMessage(), target())).status,
        FavoriteSendStatus.unknown);
  });

  test('missing message ID and two destinations never reach the SDK', () async {
    var calls = 0;
    final sender = ChatMessageSender(
      accountProvider: () => 'owner',
      transport: (message, _) async {
        calls++;
        return message;
      },
    );
    expect((await sender.send(Message(), target())).status,
        FavoriteSendStatus.failed);
    final invalid = const FavoriteTarget(
        conversationID: 'c', userID: 'recipient', groupID: 'group');
    expect((await sender.send(freshMessage(), invalid)).status,
        FavoriteSendStatus.failed);
    expect(calls, 0);
  });

  test('lookup confirms only an accepted ID in its original destination',
      () async {
    var sends = 0;
    Message receipt() => Message(
        clientMsgID: 'fresh-message',
        sendID: 'owner',
        recvID: 'recipient',
        status: MessageStatus.succeeded,
        seq: 12);
    var found = receipt();
    var conversation = 'conversation-1';
    final sender = ChatMessageSender(
        accountProvider: () => 'owner',
        transport: (message, _) async {
          sends++;
          return message;
        },
        lookup: (params) async {
          expect(params.clientMsgIDList, ['fresh-message']);
          expect(params.conversationID, 'conversation-1');
          return SearchResult()
            ..findResultItems = [
              SearchResultItems(
                  conversationID: conversation, messageList: [found])
            ];
        });
    expect((await sender.lookup(freshMessage(), target())).isSuccess, isTrue);
    found = receipt()..status = MessageStatus.failed;
    expect((await sender.lookup(freshMessage(), target())).status,
        FavoriteSendStatus.unknown);
    found = receipt()..seq = 0;
    expect((await sender.lookup(freshMessage(), target())).status,
        FavoriteSendStatus.unknown);
    found = receipt()..sendID = 'another-user';
    expect((await sender.lookup(freshMessage(), target())).status,
        FavoriteSendStatus.unknown);
    found = receipt();
    conversation = 'another-conversation';
    expect((await sender.lookup(freshMessage(), target())).status,
        FavoriteSendStatus.unknown);
    expect(sends, 0);
  });
}
