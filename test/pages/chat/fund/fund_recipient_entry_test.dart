import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/fund/chat_fund_controller.dart';
import 'package:openim/pages/chat/fund/fund_card_recipient.dart';
import 'package:openim/pages/chat/fund/fund_card_state_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_fund_controller_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });

  test('entry warms only newest rows and stops observing after close',
      () async {
    final messages = <Message>[
      for (var i = 0; i < 30; i++)
        fixtures.fundMessage(id: '$i', biz: 'group_transfer')
    ].obs;
    final requests = <String>[];
    final controller = ChatFundController(
      messages: messages,
      isClosed: () => false,
      canSend: () => true,
      userID: () => null,
      groupID: () => 'group',
      recipientName: () => null,
      recipientFaceURL: () => null,
      closeToolbox: () {},
      currentUserID: () => 'me',
      certificateID: () => 'me',
      serverURL: () => 'server',
      stateCache: FundCardStateCache(),
      getOrder: (id) async {
        requests.add(id);
        return fixtures.order(id: id, biz: 'group_transfer');
      },
    );
    await fixtures.settle();
    expect(requests, [for (var i = 0; i < 20; i++) '$i']);
    messages.insert(
        0, fixtures.fundMessage(id: 'new', biz: 'packet_exclusive'));
    await fixtures.settle();
    expect(requests.last, 'new');
    expect(requests.length, 21);
    controller.close();
    messages.insert(
        0, fixtures.fundMessage(id: 'closed', biz: 'group_transfer'));
    await fixtures.settle();
    expect(requests.length, 21);
  });

  for (final biz in ['group_transfer', 'packet_exclusive']) {
    test('$biz restores recipient before any order request after restart',
        () async {
      final first = fixtures.Harness(
        stateCache: FundCardStateCache(persistRecipients: true),
        getOrder: (_) async => fixtures.order(biz: biz, recvID: 'friend'),
        resolveRecipient: (_, __) async => const FundCardRecipient(
            userID: 'friend',
            name: 'My remark',
            faceURL: 'https://image/avatar'),
      );
      final message = fixtures.fundMessage(biz: biz);
      final data = FundMessageData.tryParse(message.customElem!.data)!;
      first.controller.setVisible(message, true);
      await fixtures.settle();
      first.controller.close();

      final next = fixtures.Harness(
          stateCache: FundCardStateCache(persistRecipients: true),
          getOrder: (_) async => throw StateError('offline'));
      addTearDown(next.controller.close);
      expect(next.requests, 0);
      expect(next.controller.cardRecipient(data).name, 'My remark');
      expect(
          next.controller.cardRecipient(data).faceURL, 'https://image/avatar');
      expect(next.controller.statusResolved(data), isFalse);
      next.controller.setVisible(message, true);
      await fixtures.settle();
      expect(next.controller.cardRecipient(data).name, 'My remark');
      next.owner = next.certificate = 'other-account';
      expect(next.controller.cardRecipient(data).name, isEmpty);
      next.owner = next.certificate = 'me';
      next.server = 'https://another-server';
      expect(next.controller.cardRecipient(data).name, isEmpty);
    });
  }

  test('multiple orders for one group member share the profile lookup',
      () async {
    final pending = Completer<FundCardRecipient>();
    var lookups = 0;
    final h = fixtures.Harness(
      getOrder: (id) async => fixtures.order(
          id: id, biz: 'group_transfer', recvID: 'friend', groupID: 'group'),
      resolveRecipient: (_, __) {
        lookups++;
        return pending.future;
      },
    );
    addTearDown(h.controller.close);
    final messages = [
      for (var i = 0; i < 5; i++)
        fixtures.fundMessage(id: '$i', biz: 'group_transfer')
    ];
    for (final message in messages) {
      h.controller.setVisible(message, true);
    }
    await fixtures.settle();
    expect(lookups, 1);
    pending.complete(const FundCardRecipient(userID: 'friend', name: 'Friend'));
    await fixtures.settle();
    for (final message in messages) {
      expect(
          h.controller
              .cardRecipient(
                  FundMessageData.tryParse(message.customElem!.data)!)
              .name,
          'Friend');
    }
  });

  test('saved display metadata checks identity and clears on logout', () async {
    final cache = FundCardStateCache(persistRecipients: true);
    final order = fixtures.order(biz: 'group_transfer', recvID: 'friend');
    final identity = (
      orderID: order.orderID,
      biz: order.biz,
      currency: order.currency,
      amount: order.amount,
      remark: ''
    );
    final key = jsonEncode(['server', 'me', order.orderID]);
    cache.remember(key,
        identity: identity,
        status: 'done',
        claimedByMe: true,
        recipientID: 'friend',
        confirmedAt: DateTime(2026));
    cache.enrichRecipient(
        key, const FundCardRecipient(userID: 'friend', name: 'Friend'));
    final restored = FundCardStateCache(persistRecipients: true);
    expect(restored.read(key), isNull);
    expect(restored.savedRecipient(key, identity)?.name, 'Friend');
    expect(
        restored.savedRecipient(key, (
          orderID: identity.orderID,
          biz: 'packet_exclusive',
          currency: identity.currency,
          amount: identity.amount,
          remark: ''
        )),
        isNull);
    cache.clear();
    expect(
        FundCardStateCache(persistRecipients: true)
            .savedRecipient(key, identity),
        isNull);
  });
}
