import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_message_adapter.dart';

void main() {
  Message text() => Message(
      clientMsgID: 'old-id',
      serverMsgID: 'server-id',
      seq: 7,
      status: MessageStatus.succeeded,
      contentType: MessageType.text,
      textElem: TextElem(content: 'private body'));

  test('message creation submits a locator, without client asserted provenance',
      () {
    final request = FavoriteMessageAdapter.createRequest(text(),
        conversationID: 'source', clientRequestID: 'request');
    expect(request, {
      'clientRequestID': 'request',
      'origin': 'message',
      'source': {
        'conversationID': 'source',
        'clientMsgID': 'old-id',
        'sequence': 7
      }
    });
    expect(request.containsKey('content'), isFalse);
    expect(request.containsKey('provenance'), isFalse);
  });
  test('failed, withdrawn, protected and control content cannot be favorited',
      () {
    expect(
        FavoriteMessageAdapter.canFavorite(
            text()..status = MessageStatus.failed),
        isFalse);
    expect(FavoriteMessageAdapter.canFavorite(text(), revoked: true), isFalse);
    expect(
        FavoriteMessageAdapter.canFavorite(
            text()..attachedInfoElem = AttachedInfoElem(isPrivateChat: true)),
        isFalse);
    expect(
        FavoriteMessageAdapter.canFavorite(
            text()..attachedInfo = '{"isPrivateChat":true}'),
        isFalse);
    expect(
        FavoriteMessageAdapter.canFavorite(
            text()..attachedInfo = '{"burnDuration":30}'),
        isFalse);
    expect(
        FavoriteMessageAdapter.canFavorite(
            text()..contentType = MessageType.custom),
        isFalse);
    expect(
        FavoriteMessageAdapter.canFavorite(
            text()..contentType = MessageType.revokeMessageNotification),
        isFalse);
  });
  test('@ and quote preserve body only, without copying old references', () {
    final at = text()
      ..contentType = MessageType.atText
      ..atTextElem =
          AtTextElem(text: '@Alice hello', atUserList: ['old-group-user']);
    final quote = text()
      ..contentType = MessageType.quote
      ..quoteElem = QuoteElem(text: 'my reply', quoteMessage: text());
    expect(FavoriteMessageAdapter.readableText(at), '@Alice hello');
    expect(FavoriteMessageAdapter.readableText(quote), 'my reply');
    expect(FavoriteMessageAdapter.canFavorite(at), isTrue);
    expect(FavoriteMessageAdapter.canFavorite(quote), isTrue);
    expect(
        FavoriteMessageAdapter.createRequest(at, conversationID: 'source').keys,
        unorderedEquals(['clientRequestID', 'origin', 'source']));
  });
}
