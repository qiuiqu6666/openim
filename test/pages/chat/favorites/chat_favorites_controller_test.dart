import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/favorites/chat_favorites_controller.dart';
import 'package:openim/pages/chat/messages/chat_delivery_controller.dart';
import 'package:openim/services/favorite_repository.dart';

import '../../favorites/support/favorite_ui_test_support.dart';

class _NoDelivery implements ChatDeliveryController {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('SDK delivery must not run in capability tests');
}

ChatFavoritesController _controller(FavoriteUiRepository repository,
        {bool Function()? closed}) =>
    ChatFavoritesController(
        messageList: <Message>[].obs,
        delivery: _NoDelivery(),
        conversation: () =>
            ConversationInfo(conversationID: 'chat-a', userID: 'a'),
        accountID: 'test-account',
        isClosed: closed ?? () => false,
        sendingMuted: () => false,
        isInvalidGroup: () => false,
        displayName: () => '张三',
        unfocus: () {},
        repository: repository);

void main() {
  testWidgets(
      'URL favorite action remains available while capability probing or sending is unavailable',
      (tester) async {
    final repository = FavoriteUiRepository(initialQuota: null);
    addTearDown(repository.dispose);
    final deferred = Completer<FavoriteQuota>();
    repository.probe = (_) => deferred.future;
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    final message = Message(
        clientMsgID: 'm1',
        seq: 42,
        contentType: MessageType.text,
        status: MessageStatus.succeeded,
        textElem: TextElem(content: 'https://baidu.com'));
    await tester.pumpWidget(favoriteUiHost(Scaffold(
        body: Text(controller.canFavorite(message) ? '可以收藏' : '等待能力'))));
    await tester.pump();
    expect(controller.canFavorite(message), isTrue);
    expect(repository.probeForces, [false]);
    deferred.complete(uiQuota);
    await tester.pumpAndSettle();
    expect(find.text('可以收藏'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      expect(controller.canFavorite(message), isTrue);
    }
    expect(repository.probeForces, [false]);
    expect(
        controller.canFavorite(Message(
            clientMsgID: 'location',
            seq: 43,
            contentType: MessageType.location,
            status: MessageStatus.succeeded,
            locationElem: LocationElem(latitude: 25, longitude: 121))),
        isFalse);
    expect(
        controller.canFavorite(Message(
            clientMsgID: 'card',
            seq: 44,
            contentType: MessageType.card,
            status: MessageStatus.succeeded,
            cardElem: CardElem(userID: 'b', nickname: '名片'))),
        isFalse);
    repository.capabilities = const FavoriteQuota(
        supportsFavorites: true, supportsPrepareSend: false);
    repository.notifyListeners();
    await tester.pumpAndSettle();
    expect(controller.canFavorite(message), isTrue);
    expect(repository.saves, 0);
  });

  test(
      'closing a lazy controller before its microtask creates no capability request or listener',
      () async {
    final repository = FavoriteUiRepository(initialQuota: null);
    var closed = false;
    final controller = _controller(repository, closed: () => closed);
    closed = true;
    controller.dispose();
    await Future<void>.value();
    expect(repository.probeForces, isEmpty);
    expect(repository.observing, isFalse);
    repository.dispose();
  });
}
