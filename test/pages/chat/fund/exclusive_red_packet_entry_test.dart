import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/fund/chat_fund_controller.dart';
import 'package:openim/pages/chat/fund/fund_card_recipient.dart';
import 'package:openim/pages/chat/fund/fund_card_state_cache.dart';
import 'package:openim/pages/fund/fund_send_page.dart';
import 'package:openim/services/fund_models.dart';
import 'package:openim_common/openim_common.dart';

class _Harness {
  _Harness({ChatFundSendPageOpener? openExclusiveSend}) {
    controller = ChatFundController(
      isClosed: () => closed,
      canSend: () => allowed,
      userID: () => null,
      groupID: () => chatGroup,
      recipientName: () => 'Group title',
      recipientFaceURL: () => 'group-avatar',
      closeToolbox: () => closes++,
      currentUserID: () => owner,
      certificateID: () => certificate,
      serverURL: () => 'test-server',
      stateCache: FundCardStateCache(),
      resolveRecipient: (user, group) async =>
          FundCardRecipient(userID: user, name: 'Target'),
      openExclusiveSend: openExclusiveSend,
    );
  }

  late final ChatFundController controller;
  String? chatGroup = 'group';
  String owner = 'me';
  String? certificate = 'me';
  bool closed = false, allowed = true;
  int closes = 0;
}

GroupMembersInfo _member({String id = 'target', String group = 'group'}) =>
    GroupMembersInfo(
      userID: id,
      groupID: group,
      nickname: 'Target',
      faceURL: 'target-avatar',
    );

FundOrder _order({
  String recipient = 'target',
  String group = 'group',
  String biz = 'packet_exclusive',
  FundScene scene = FundScene.group,
}) =>
    FundOrder(
      orderID: 'order',
      biz: biz,
      scene: scene,
      currency: FundCurrency.usdt,
      amount: FundAmount.parse('1', FundCurrency.usdt),
      senderID: 'me',
      recvID: recipient,
      groupID: group,
      status: 'done',
    );

FundMessageData _message(String biz) => FundMessageData.tryParse(jsonEncode({
      'orderID': 'order',
      'biz': biz,
      'currency': 'USDT',
      'amount': '1',
      'status': 'open',
    }))!;

class _SendRouteObserver extends NavigatorObserver {
  GetPageRoute<dynamic>? route;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is GetPageRoute && route.page?.call() is FundSendPage) {
      this.route = route;
    }
  }
}

void main() {
  test('exclusive shortcut passes the chosen member in the group scene',
      () async {
    final h = _Harness(openExclusiveSend: ({
      required isRedPacket,
      userID,
      groupID,
      recipientName,
      recipientFaceURL,
    }) async {
      expect(isRedPacket, isTrue);
      expect(userID, 'target');
      expect(groupID, 'group');
      expect(recipientName, 'Target');
      expect(recipientFaceURL, 'target-avatar');
      return _order();
    });
    await h.controller.sendExclusiveRedPacket(_member());
    expect(h.closes, 1);
    expect(h.controller.statusResolved(_message('packet_exclusive')), isTrue);
    expect(h.controller.packetCount(_message('packet_exclusive')), 1);
    h.controller.close();
  });

  test('invalid, self, closed, muted, and account-changed entries do not open',
      () async {
    var opens = 0;
    final h = _Harness(openExclusiveSend: ({
      required isRedPacket,
      userID,
      groupID,
      recipientName,
      recipientFaceURL,
    }) async {
      opens++;
      return null;
    });
    await h.controller.sendExclusiveRedPacket(_member(id: ''));
    await h.controller.sendExclusiveRedPacket(_member(id: 'me'));
    await h.controller.sendExclusiveRedPacket(_member(group: 'other-group'));
    h.chatGroup = null;
    await h.controller.sendExclusiveRedPacket(_member());
    h.chatGroup = 'group';
    h.certificate = 'other-account';
    await h.controller.sendExclusiveRedPacket(_member());
    h.certificate = 'me';
    h.allowed = false;
    await h.controller.sendExclusiveRedPacket(_member());
    h.allowed = true;
    h.closed = true;
    await h.controller.sendExclusiveRedPacket(_member());
    expect(opens, 0);
    expect(h.closes, 0);
    h.controller.close();
  });

  test('shortcut shares the existing navigation guard', () async {
    final pending = Completer<FundOrder?>();
    final h = _Harness(
        openExclusiveSend: ({
      required isRedPacket,
      userID,
      groupID,
      recipientName,
      recipientFaceURL,
    }) =>
            pending.future);
    final opening = h.controller.sendExclusiveRedPacket(_member());
    await h.controller.sendExclusiveRedPacket(_member(id: 'other-target'));
    expect(h.closes, 1);
    pending.complete(null);
    await opening;
    h.controller.close();
  });

  test('member without a nickname still has a visible selected recipient',
      () async {
    final h = _Harness(openExclusiveSend: ({
      required isRedPacket,
      userID,
      groupID,
      recipientName,
      recipientFaceURL,
    }) async {
      expect(userID, 'target');
      expect(recipientName, 'target');
      return null;
    });
    await h.controller.sendExclusiveRedPacket(_member()..nickname = ' ');
    h.controller.close();
  });

  for (final wrong in [
    _order(recipient: 'other-target'),
    _order(group: 'other-group'),
    _order(biz: 'packet_lucky'),
    _order(scene: FundScene.single),
  ]) {
    test(
        'shortcut rejects mismatched ${wrong.biz}/${wrong.recvID}/${wrong.groupID}/${wrong.scene}',
        () async {
      final h = _Harness(
          openExclusiveSend: ({
        required isRedPacket,
        userID,
        groupID,
        recipientName,
        recipientFaceURL,
      }) async =>
              wrong);
      await h.controller.sendExclusiveRedPacket(_member());
      expect(h.controller.statusResolved(_message(wrong.biz)), isFalse);
      h.controller.close();
    });
  }

  testWidgets('default shortcut route opens the existing exclusive form',
      (tester) async {
    Get.testMode = true;
    final observer = _SendRouteObserver();
    await tester.pumpWidget(GetMaterialApp(
      navigatorObservers: [observer],
      home: const Scaffold(),
    ));
    await tester.pumpAndSettle();
    final h = _Harness();
    final opening = h.controller.sendExclusiveRedPacket(_member());
    final route = observer.route!;
    final page = route.page!() as FundSendPage;
    expect(page.initialPacketBiz, FundPacketBiz.exclusive);
    expect(page.isRedPacket, isTrue);
    expect(page.groupID, 'group');
    expect(page.userID, 'target');
    expect(page.recipientName, 'Target');
    expect(page.recipientFaceURL, 'target-avatar');
    // Inspect the route's immutable arguments without mounting its API state.
    Navigator.of(Get.context!).removeRoute(route);
    await tester.pumpAndSettle();
    await opening;
    await tester.pumpWidget(const SizedBox.shrink());
    h.controller.close();
    Get.reset();
  });
}
