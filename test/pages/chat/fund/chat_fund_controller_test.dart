import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/fund/chat_fund_controller.dart';
import 'package:openim/pages/chat/fund/fund_card_state_cache.dart';
import 'package:openim/pages/chat/fund/fund_message_card.dart';
import 'package:openim/pages/chat/fund/fund_card_palette.dart';
import 'package:openim/pages/fund/fund_detail_page.dart';
import 'package:openim/services/fund_models.dart';
import 'package:openim/pages/chat/fund/fund_card_recipient.dart';
import 'package:openim_common/openim_common.dart';

Message fundMessage({
  String id = 'order',
  String biz = 'packet_normal',
  String currency = 'USDT',
  String amount = '1.000001',
  String? remark,
}) =>
    Message.fromJson({
      'clientMsgID': 'im-fund',
      'contentType': MessageType.custom,
      'status': MessageStatus.succeeded,
      'customElem': {
        'data': jsonEncode({
          'orderID': id,
          'biz': biz,
          'currency': currency,
          'amount': amount,
          'status': 'open',
          if (remark != null) 'remark': remark,
        }),
      },
    });

FundOrder order({
  String status = 'open',
  String id = 'order',
  bool claimed = false,
  String biz = 'packet_normal',
  FundScene scene = FundScene.single,
  FundCurrency currency = FundCurrency.usdt,
  String amount = '1.000001',
  String senderID = '',
  String recvID = '',
  String groupID = '',
  int shareCount = 0,
  String remark = '',
}) =>
    FundOrder(
      orderID: id,
      biz: biz,
      scene: scene,
      currency: currency,
      amount: FundAmount.parse(amount, currency),
      status: status,
      senderID: senderID,
      recvID: recvID,
      groupID: groupID,
      shareCount: shareCount,
      remark: remark,
      shares: claimed
          ? [
              FundShare(
                index: 0,
                amount: FundAmount.parse(amount, currency),
                claimerID: 'me',
              ),
            ]
          : const [],
    );

class Harness {
  Harness({
    Future<FundOrder> Function(String)? getOrder,
    Future<FundOrder?> Function(FundMessageData)? openDetail,
    ChatFundSendPageOpener? openSend,
    bool useDefaultDetail = false,
    FundCardStateCache? stateCache,
    Future<FundCardRecipient> Function(String, String)? resolveRecipient,
  }) {
    controller = ChatFundController(
      isClosed: () => closed,
      canSend: () => allowed,
      userID: () => group ? null : receiver,
      groupID: () => group ? chatGroup : null,
      recipientName: () => group ? null : 'Friend',
      recipientFaceURL: () => group ? null : 'avatar',
      closeToolbox: () => toolboxCloses++,
      stateCache: stateCache ?? FundCardStateCache(),
      resolveRecipient: resolveRecipient,
      currentUserID: () => owner,
      certificateID: () => certificate,
      serverURL: () => server,
      now: () => time,
      getOrder: (id) {
        requests++;
        return getOrder?.call(id) ?? Future.value(order());
      },
      openDetail: useDefaultDetail ? null : openDetail ?? (_) async => null,
      openSend: openSend ??
          (
                  {required isRedPacket,
                  userID,
                  groupID,
                  recipientName,
                  recipientFaceURL}) async =>
              null,
    );
  }

  late final ChatFundController controller;
  bool closed = false;
  bool allowed = true;
  bool group = false;
  String receiver = 'friend';
  String chatGroup = 'group';
  String owner = 'me';
  String? certificate = 'me';
  String server = 'https://fund.example';
  DateTime time = DateTime(2026, 10, 3);
  int requests = 0;
  int toolboxCloses = 0;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

class _FundRouteObserver extends NavigatorObserver {
  final routes = <FundDetailRoute>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is FundDetailRoute) routes.add(route);
  }
}

/// Capture the real default route's page before mounting its API-owned state.
/// Removing the unmounted route avoids any network call in this adapter test.
Future<FundDetailPage> captureDefaultDetail(
    WidgetTester tester, FundMessageData message,
    {Message? sourceMessage}) async {
  Get.testMode = true;
  final observer = _FundRouteObserver();
  await tester.pumpWidget(GetMaterialApp(
    navigatorObservers: [observer],
    home: const Scaffold(body: SizedBox.shrink()),
  ));
  await tester.pumpAndSettle();
  final h = Harness(useDefaultDetail: true);
  final opening =
      h.controller.openDetail(message, sourceMessage: sourceMessage);
  final route = observer.routes.single;
  final page = route.pageBuilder(Get.context!,
      const AlwaysStoppedAnimation(1.0), const AlwaysStoppedAnimation(0.0));
  Navigator.of(Get.context!).removeRoute(route);
  await tester.pumpAndSettle();
  await opening;
  await tester.pumpWidget(const SizedBox.shrink());
  h.controller.close();
  Get.reset();
  return page as FundDetailPage;
}

void main() {
  for (final biz in ['packet_normal', 'packet_lucky', 'packet_exclusive']) {
    test('packet count is sourced from verified $biz order', () async {
      final h = Harness(
          getOrder: (_) async => order(
              biz: biz,
              scene: FundScene.group,
              shareCount: 5,
              recvID: 'friend'));
      final message = fundMessage(biz: biz);
      final data = h.controller.messageData(message)!;
      expect(h.controller.packetCount(data), isNull);
      h.controller.setVisible(message, true);
      await settle();
      expect(h.controller.packetCount(data), biz == 'packet_exclusive' ? 1 : 5);
      h.controller.close();
    });
  }
  test('unknown group count is not inferred from the amount', () async {
    final h = Harness(
        getOrder: (_) async =>
            order(biz: 'packet_lucky', scene: FundScene.group, shareCount: 0));
    final message = fundMessage(biz: 'packet_lucky');
    h.controller.setVisible(message, true);
    await settle();
    expect(
        h.controller.packetCount(h.controller.messageData(message)!), isNull);
    h.controller.close();
  });
  test('recipient comes from verified order and SDK enrichment keeps revision',
      () async {
    final profiles = Completer<FundCardRecipient>();
    final cache = FundCardStateCache();
    final h = Harness(
        stateCache: cache,
        getOrder: (_) async => order(
            biz: 'group_transfer',
            status: 'done',
            recvID: 'friend',
            groupID: 'group'),
        resolveRecipient: (userID, groupID) {
          expect(userID, 'friend');
          expect(groupID, 'group');
          return profiles.future;
        });
    final sdkMessage = fundMessage(biz: 'group_transfer');
    final data = FundMessageData.tryParse(sdkMessage.customElem!.data)!;
    h.controller.setVisible(sdkMessage, true);
    await settle();
    final key = jsonEncode([h.server, h.owner, data.orderID]);
    final revision = cache.read(key)!.revision;
    expect(h.controller.cardRecipient(data).userID, 'friend');
    profiles.complete(const FundCardRecipient(userID: 'friend', name: '小林'));
    await settle();
    expect(h.controller.cardRecipient(data).name, '小林');
    expect(cache.read(key)!.revision, revision);
    h.controller.close();
  });

  test('late recipient lookup cannot enrich a cleared session', () async {
    final profiles = Completer<FundCardRecipient>();
    final cache = FundCardStateCache();
    final h = Harness(
        stateCache: cache,
        getOrder: (_) async => order(biz: 'packet_exclusive', recvID: 'friend'),
        resolveRecipient: (_, __) => profiles.future);
    final sdkMessage = fundMessage(biz: 'packet_exclusive');
    final data = FundMessageData.tryParse(sdkMessage.customElem!.data)!;
    h.controller.setVisible(sdkMessage, true);
    await settle();
    cache.clear();
    profiles.complete(const FundCardRecipient(userID: 'friend', name: '旧资料'));
    await settle();
    expect(h.controller.cardRecipient(data).userID, isEmpty);
    h.controller.close();
  });
  testWidgets('reentered card first frame is claimed while refresh is pending',
      (tester) async {
    final cache = FundCardStateCache();
    final first = Harness(
        stateCache: cache, openDetail: (_) async => order(claimed: true));
    final message = fundMessage();
    await first.controller.openDetail(first.controller.messageData(message)!);
    first.controller.close();
    final pending = Completer<FundOrder>();
    final next = Harness(stateCache: cache, getOrder: (_) => pending.future);
    next.time = next.time.add(const Duration(seconds: 61));
    next.controller.setVisible(message, true);
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            locale: const Locale('zh', 'CN'),
            translations: TranslationService(),
            home: Scaffold(body: Obx(() {
              final data = next.controller.messageData(message)!;
              return FundMessageCard(
                  message: data,
                  isGroupChat: true,
                  claimedByMe: next.controller.claimedByMe(data),
                  statusResolved: next.controller.statusResolved(data));
            })))));
    final card = tester.widget<FundMessageCard>(find.byType(FundMessageCard));
    expect(card.claimedByMe, isTrue);
    expect(card.statusResolved, isTrue);
    expect(find.text(StrRes.fundClaimed), findsNothing);
    final decoration = tester
        .widget<DecoratedBox>(find.byKey(const Key('fund-card-surface')))
        .decoration as BoxDecoration;
    final opened = FundCardPalette.packet.opened();
    expect((decoration.gradient! as LinearGradient).colors,
        [opened.bodyHighlight, opened.body]);
    expect(next.requests, 1);
    expect(pending.isCompleted, isFalse);
    pending.complete(order(claimed: true));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    next.controller.close();
  });

  for (final dark in [false, true]) {
    for (final reentered in [false, true]) {
      for (final fails in [false, true]) {
        testWidgets(
            'unclaimed first frame retains color dark=$dark reentered=$reentered failure=$fails',
            (tester) async {
          final cache = FundCardStateCache();
          final message = fundMessage();
          if (reentered) {
            final prior = Harness(stateCache: cache);
            prior.controller.setVisible(message, true);
            await tester.runAsync(settle);
            prior.controller.close();
          }
          final pending = Completer<FundOrder>();
          final h = Harness(stateCache: cache, getOrder: (_) => pending.future);
          h.controller.setVisible(message, true);
          await tester.pumpWidget(ScreenUtilInit(
              designSize: const Size(375, 812),
              builder: (_, __) => GetMaterialApp(
                  locale: const Locale('zh', 'CN'),
                  translations: TranslationService(),
                  theme: dark ? ThemeData.dark() : ThemeData.light(),
                  home: Scaffold(body: Obx(() {
                    final data = h.controller.messageData(message)!;
                    return FundMessageCard(
                        message: data,
                        claimedByMe: h.controller.claimedByMe(data),
                        statusResolved: h.controller.statusResolved(data));
                  })))));
          final surface = find.byKey(const Key('fund-card-surface'));
          final before =
              tester.widget<DecoratedBox>(surface).decoration as BoxDecoration;
          expect((before.gradient! as LinearGradient).colors,
              [const Color(0xFFFA6A4E), const Color(0xFFF55E44)]);
          expect(pending.isCompleted, isFalse);
          expect(
              tester
                  .widget<FundMessageCard>(find.byType(FundMessageCard))
                  .statusResolved,
              isFalse);
          if (fails) {
            pending.completeError(Exception('offline'));
          } else {
            pending.complete(order());
          }
          await tester.pump();
          final after = tester.widget<DecoratedBox>(surface).decoration;
          expect(after, before,
              reason: 'Query completion must not recolor or add a shadow');
          expect(
              tester
                  .widget<FundMessageCard>(find.byType(FundMessageCard))
                  .statusResolved,
              !fails);
          expect(find.text(StrRes.fundClaimed), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          h.controller.close();
        });
      }
    }
  }
  test('a prior open observation is rechecked before rendering unclaimed',
      () async {
    final cache = FundCardStateCache();
    final first = Harness(stateCache: cache);
    final message = fundMessage();
    first.controller.setVisible(message, true);
    await settle();
    expect(
        first.controller.statusResolved(first.controller.messageData(message)!),
        isTrue);
    first.controller.close();
    final pending = Completer<FundOrder>();
    final next = Harness(stateCache: cache, getOrder: (_) => pending.future);
    expect(
        next.controller.statusResolved(next.controller.messageData(message)!),
        isFalse);
    next.controller.setVisible(message, true);
    expect(next.requests, 1);
    pending.complete(order(claimed: true));
    await settle();
    expect(
        next.controller.statusResolved(next.controller.messageData(message)!),
        isTrue);
    expect(next.controller.claimedByMe(next.controller.messageData(message)!),
        isTrue);
    next.controller.close();
  });
  test('unqueried open snapshot stays unresolved until a verified GET',
      () async {
    final pending = Completer<FundOrder>();
    final h = Harness(getOrder: (_) => pending.future);
    final message = fundMessage();
    expect(h.controller.statusResolved(h.controller.messageData(message)!),
        isFalse);
    h.controller.setVisible(message, true);
    expect(h.controller.statusResolved(h.controller.messageData(message)!),
        isFalse);
    pending.complete(order(claimed: true));
    await settle();
    expect(h.controller.statusResolved(h.controller.messageData(message)!),
        isTrue);
    expect(
        h.controller.claimedByMe(h.controller.messageData(message)!), isTrue);
    h.controller.close();
  });

  test('reentering chat synchronously restores verified claim before GET',
      () async {
    final cache = FundCardStateCache();
    final first = Harness(
        stateCache: cache,
        openDetail: (_) async => order(claimed: true, remark: '真实祝福'));
    final message = fundMessage();
    final original = message.customElem!.data;
    await first.controller.openDetail(first.controller.messageData(message)!);
    first.controller.close();
    final pending = Completer<FundOrder>();
    final second = Harness(stateCache: cache, getOrder: (_) => pending.future);
    final initial = second.controller.messageData(message)!;
    expect(second.controller.statusResolved(initial), isTrue);
    expect(second.controller.claimedByMe(initial), isTrue);
    expect(initial.remark, '真实祝福');
    second.time = second.time.add(const Duration(seconds: 61));
    second.controller.setVisible(message, true);
    expect(second.requests, 1);
    expect(second.controller.claimedByMe(initial), isTrue);
    pending.complete(order());
    await settle();
    expect(
        second.controller.claimedByMe(second.controller.messageData(message)!),
        isTrue);
    expect(message.customElem!.data, original);
    second.controller.close();
  });

  test('shared states cannot cross account server certificate or amount',
      () async {
    final cache = FundCardStateCache();
    final first = Harness(
        stateCache: cache,
        openDetail: (_) async => order(status: 'done', claimed: true));
    await first.controller
        .openDetail(first.controller.messageData(fundMessage())!);
    first.controller.close();
    final second = Harness(stateCache: cache);
    expect(second.controller.messageData(fundMessage())!.status, 'done');
    second.owner = second.certificate = 'other';
    expect(
        second.controller
            .statusResolved(second.controller.messageData(fundMessage())!),
        isFalse);
    second.owner = second.certificate = 'me';
    second.server = 'https://other.example';
    expect(
        second.controller
            .statusResolved(second.controller.messageData(fundMessage())!),
        isFalse);
    second.server = 'https://fund.example';
    second.certificate = 'other';
    expect(
        second.controller
            .statusResolved(second.controller.messageData(fundMessage())!),
        isFalse);
    second.certificate = 'me';
    expect(
        second.controller.statusResolved(
            second.controller.messageData(fundMessage(amount: '2'))!),
        isFalse);
    second.controller.close();
  });

  test('late GET from another route cannot undo a newer detail result',
      () async {
    final cache = FundCardStateCache();
    final pending = Completer<FundOrder>();
    final old = Harness(stateCache: cache, getOrder: (_) => pending.future);
    final latest = Harness(
        stateCache: cache,
        openDetail: (_) async =>
            order(status: 'done', claimed: true, remark: '新备注'));
    final message = fundMessage();
    old.controller.setVisible(message, true);
    await latest.controller.openDetail(latest.controller.messageData(message)!);
    pending.complete(order(remark: '旧备注'));
    await settle();
    expect(old.controller.messageData(message)!.status, 'done');
    expect(old.controller.messageData(message)!.remark, '新备注');
    old.controller.close();
    latest.controller.close();
  });

  test('session cache clear invalidates old requests even for same account',
      () async {
    final cache = FundCardStateCache();
    final pending = Completer<FundOrder>();
    final old = Harness(stateCache: cache, getOrder: (_) => pending.future);
    final message = fundMessage();
    old.controller.setVisible(message, true);
    cache.clear();
    pending.complete(order(status: 'done', claimed: true));
    await settle();
    final next = Harness(stateCache: cache);
    expect(
        next.controller.statusResolved(next.controller.messageData(message)!),
        isFalse);
    expect(next.controller.claimedByMe(next.controller.messageData(message)!),
        isFalse);
    old.controller.close();
    next.controller.close();
  });

  test('failed initial GET does not certify an unclaimed snapshot', () async {
    final h = Harness(getOrder: (_) async => throw StateError('offline'));
    final message = fundMessage();
    h.controller.setVisible(message, true);
    await settle();
    expect(h.controller.statusResolved(h.controller.messageData(message)!),
        isFalse);
    expect(
        h.controller.claimedByMe(h.controller.messageData(message)!), isFalse);
    h.controller.close();
  });

  test(
      'visible cards share a request and cached order without changing IM data',
      () async {
    final pending = Completer<FundOrder>();
    final h = Harness(getOrder: (_) => pending.future);
    final message = fundMessage(remark: '卡片旧祝福');
    final original = message.customElem!.data;

    h.controller.setVisible(message, true);
    h.controller.setVisible(message, true);
    expect(h.requests, 1);
    pending.complete(order(status: 'done', claimed: true, remark: '真实祝福🎉'));
    await settle();

    final data = h.controller.messageData(message)!;
    expect(data.status, 'done');
    expect(data.remark, '真实祝福🎉');
    expect(h.controller.claimedByMe(data), isTrue);
    expect(message.customElem!.data, original);
    h.controller.setVisible(message, true);
    expect(h.requests, 1);
    h.time = h.time.add(const Duration(seconds: 61));
    h.controller.setVisible(message, true);
    expect(h.requests, 2);
    await settle();
    h.controller.close();
  });

  test('resume forces only the cards still tracked as visible', () async {
    final h = Harness();
    final message = fundMessage();
    h.controller.setVisible(message, true);
    await settle();
    h.controller.refreshVisible();
    await settle();
    expect(h.requests, 2);
    h.controller.setVisible(message, false);
    h.controller.refreshVisible();
    expect(h.requests, 2);
    h.controller.close();
  });

  test('detail result supersedes an older visibility request', () async {
    final pending = Completer<FundOrder>();
    final h = Harness(
      getOrder: (_) => pending.future,
      openDetail: (_) async =>
          order(status: 'done', claimed: true, remark: '详情真实祝福'),
    );
    final message = fundMessage();
    h.controller.setVisible(message, true);
    await h.controller.openDetail(h.controller.messageData(message)!);
    pending.complete(order(remark: '较旧订单祝福'));
    await settle();
    expect(h.controller.messageData(message)!.status, 'done');
    expect(h.controller.messageData(message)!.remark, '详情真实祝福');
    expect(
        h.controller.claimedByMe(h.controller.messageData(message)!), isTrue);
    h.controller.close();
  });

  for (final changed in [
    'account',
    'certificate',
    'server',
    'route',
    'dispose'
  ]) {
    test('ignores an order completed after $changed changes', () async {
      final pending = Completer<FundOrder>();
      final h = Harness(getOrder: (_) => pending.future);
      final message = fundMessage();
      h.controller.setVisible(message, true);
      switch (changed) {
        case 'account':
          h.owner = 'other';
        case 'certificate':
          h.certificate = 'other';
        case 'server':
          h.server = 'https://other.example';
        case 'route':
          h.closed = true;
        case 'dispose':
          h.controller.close();
      }
      pending.complete(order(status: 'done', claimed: true));
      await settle();
      expect(h.controller.messageData(message)!.status, 'open');
      expect(h.controller.claimedByMe(h.controller.messageData(message)!),
          isFalse);
      h.controller.close();
    });
  }

  test('rejects an order that does not match the card', () async {
    final h =
        Harness(getOrder: (_) async => order(id: 'other', status: 'done'));
    final message = fundMessage();
    h.controller.setVisible(message, true);
    await settle();
    expect(h.controller.messageData(message)!.status, 'open');
    h.controller.close();
  });

  test('send entry uses current recipient and blocks concurrent navigation',
      () async {
    final pending = Completer<FundOrder?>();
    final entries = <Map<String, Object?>>[];
    final h = Harness(openSend: ({
      required isRedPacket,
      userID,
      groupID,
      recipientName,
      recipientFaceURL,
    }) {
      entries.add({
        'packet': isRedPacket,
        'user': userID,
        'group': groupID,
        'name': recipientName,
        'avatar': recipientFaceURL,
      });
      return pending.future;
    });
    h.allowed = false;
    await h.controller.openSend(isRedPacket: true);
    expect(entries, isEmpty);
    h.allowed = true;
    final first = h.controller.openSend(isRedPacket: true);
    await h.controller.openSend(isRedPacket: false);
    await h.controller.openDetail(h.controller.messageData(fundMessage())!);
    expect(entries.single, {
      'packet': true,
      'user': 'friend',
      'group': null,
      'name': 'Friend',
      'avatar': 'avatar',
    });
    expect(h.toolboxCloses, 1);
    pending.complete(null);
    await first;
    h.group = true;
    await h.controller.openSend(isRedPacket: false);
    expect(entries.last, {
      'packet': false,
      'user': null,
      'group': 'group',
      'name': null,
      'avatar': null,
    });
    h.closed = true;
    await h.controller.openSend(isRedPacket: true);
    expect(entries.length, 2);
    h.controller.close();
  });

  for (final entry in [
    (biz: 'packet_exclusive', group: false, packet: true),
    (biz: 'transfer', group: false, packet: false),
    (biz: 'packet_normal', group: true, packet: true),
    (biz: 'group_transfer', group: true, packet: false),
  ]) {
    test('confirmed ${entry.biz} send updates a later SDK card immediately',
        () async {
      final h = Harness(
          openSend: ({
        required isRedPacket,
        userID,
        groupID,
        recipientName,
        recipientFaceURL,
      }) async =>
              order(
                biz: entry.biz,
                status: 'done',
                scene: entry.group ? FundScene.group : FundScene.single,
                senderID: 'me',
                recvID: entry.biz == 'packet_normal' ? '' : 'friend',
                groupID: entry.group ? 'group' : '',
                remark: entry.packet ? '顺顺利利🎉' : '午餐，谢谢啦🍜',
              ));
      h.group = entry.group;
      await h.controller.openSend(isRedPacket: entry.packet);
      final message = fundMessage(biz: entry.biz);
      final original = jsonEncode(message.toJson());
      expect(h.controller.messageData(message)!.status, 'done');
      expect(h.controller.messageData(message)!.remark,
          entry.packet ? '顺顺利利🎉' : '午餐，谢谢啦🍜');
      expect(jsonEncode(message.toJson()), original);
      expect(h.requests, 0);
      h.controller.setVisible(message, true);
      expect(h.requests, 0);
      h.controller.close();
    });
  }

  test('send result supersedes an older visible GET without rewriting SDK data',
      () async {
    final read = Completer<FundOrder>();
    final h = Harness(
      getOrder: (_) => read.future,
      openSend: ({
        required isRedPacket,
        userID,
        groupID,
        recipientName,
        recipientFaceURL,
      }) async =>
          order(
              status: 'done',
              senderID: 'me',
              recvID: 'friend',
              remark: '第一次支付祝福🎉'),
    );
    final message = fundMessage();
    final original = jsonEncode(message.toJson());
    h.controller.setVisible(message, true);
    await h.controller.openSend(isRedPacket: true);
    expect(h.controller.messageData(message)!.status, 'done');
    expect(h.controller.messageData(message)!.remark, '第一次支付祝福🎉');
    read.complete(order(remark: '较旧祝福'));
    await settle();
    expect(h.controller.messageData(message)!.status, 'done');
    expect(h.controller.messageData(message)!.remark, '第一次支付祝福🎉');
    expect(jsonEncode(message.toJson()), original);
    h.controller.close();
  });

  testWidgets('first send override rebuilds an already mounted reactive card',
      (tester) async {
    final h = Harness(
        openSend: ({
      required isRedPacket,
      userID,
      groupID,
      recipientName,
      recipientFaceURL,
    }) async =>
            order(status: 'done', senderID: 'me', recvID: 'friend'));
    final message = fundMessage();
    await tester.pumpWidget(MaterialApp(
      home: Obx(() => Text(h.controller.messageData(message)!.status)),
    ));
    expect(find.text('open'), findsOneWidget);
    await h.controller.openSend(isRedPacket: true);
    await tester.pump();
    expect(find.text('done'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    h.controller.close();
  });

  testWidgets('GET remark-only changes rebuild an existing reactive card',
      (tester) async {
    var reads = 0;
    final h = Harness(
        getOrder: (_) async =>
            order(remark: reads++ == 0 ? '订单第一次祝福' : '订单更新祝福🎉'));
    final message = fundMessage(); // The legacy SDK payload has no remark.
    final original = jsonEncode(message.toJson());
    await tester.pumpWidget(MaterialApp(home: Obx(() {
      final data = h.controller.messageData(message)!;
      return Text('${data.status}|${data.remark}');
    })));
    expect(find.text('open|'), findsOneWidget);
    h.controller.setVisible(message, true);
    // Flush the GET completion, then draw the frame scheduled by its RxMap
    // notification. An idle pump checks for a frame before flushing futures.
    await tester.pump();
    expect(h.controller.messageData(message)!.remark, '订单第一次祝福');
    await tester.pump();
    expect(find.text('open|订单第一次祝福'), findsOneWidget);
    h.controller.refreshVisible();
    expect(h.requests, 2);
    await tester.pump();
    expect(h.controller.messageData(message)!.status, 'open');
    expect(h.controller.messageData(message)!.remark, '订单更新祝福🎉');
    await tester.pump();
    expect(find.text('open|订单更新祝福🎉'), findsOneWidget);
    expect(jsonEncode(message.toJson()), original);
    await tester.pumpWidget(const SizedBox.shrink());
    h.controller.close();
  });

  test('legacy order without remark still updates status and clears stale text',
      () async {
    final h = Harness(getOrder: (_) async => order(status: 'done'));
    final message = fundMessage(remark: '旧卡片备注');
    final original = jsonEncode(message.toJson());
    h.controller.setVisible(message, true);
    await settle();
    final data = h.controller.messageData(message)!;
    expect(data.status, 'done');
    expect(data.remark, '');
    expect(jsonEncode(message.toJson()), original);
    h.controller.close();
  });

  test('cancelled send leaves an existing card status unchanged', () async {
    final h = Harness();
    final message = fundMessage();
    await h.controller.openSend(isRedPacket: true);
    expect(h.controller.messageData(message)!.status, 'open');
    expect(h.requests, 0);
    h.controller.close();
  });

  for (final changed in [
    'account',
    'certificate',
    'server',
    'route',
    'dispose',
    'recipient',
    'groupTarget',
    'chatScene',
  ]) {
    test('late send result is ignored after $changed changes', () async {
      final pending = Completer<FundOrder?>();
      final h = Harness(
          openSend: ({
        required isRedPacket,
        userID,
        groupID,
        recipientName,
        recipientFaceURL,
      }) =>
              pending.future);
      h.group = changed == 'groupTarget';
      final wasGroup = h.group;
      final opening = h.controller.openSend(isRedPacket: true);
      switch (changed) {
        case 'account':
          h.owner = 'another';
          h.certificate = 'another';
        case 'certificate':
          h.certificate = 'another';
        case 'server':
          h.server = 'https://another.example';
        case 'route':
          h.closed = true;
        case 'dispose':
          h.controller.close();
        case 'recipient':
          h.receiver = 'another';
        case 'groupTarget':
          h.chatGroup = 'another-group';
        case 'chatScene':
          h.group = true;
      }
      pending.complete(order(
        status: 'done',
        senderID: 'me',
        recvID: 'friend',
        scene: wasGroup ? FundScene.group : FundScene.single,
        groupID: wasGroup ? 'group' : '',
        remark: '迟到结果祝福',
      ));
      await opening;
      // Return to the original cache scope to catch a stale write that would
      // otherwise be hidden by the account/server-scoped lookup.
      h.owner = 'me';
      h.certificate = 'me';
      h.server = 'https://fund.example';
      h.closed = false;
      h.group = wasGroup;
      h.receiver = 'friend';
      h.chatGroup = 'group';
      expect(h.controller.messageData(fundMessage())!.status, 'open');
      expect(h.controller.messageData(fundMessage())!.remark, '');
      h.controller.close();
    });
  }

  for (final invalid in {
    'sender': order(status: 'done', senderID: 'another', recvID: 'friend'),
    'recipient': order(status: 'done', senderID: 'me', recvID: 'another'),
    'self recipient': order(status: 'done', senderID: 'me', recvID: 'me'),
    'single group ID': order(status: 'done', groupID: 'unexpected-group'),
    'scene': order(status: 'done', scene: FundScene.group, groupID: 'group'),
    'business': order(status: 'done', biz: 'transfer'),
    'single lucky': order(status: 'done', biz: 'packet_lucky'),
    'status': order(status: 'unexpected'),
    'amount': order(status: 'done', amount: '0'),
  }.entries) {
    test('inconsistent send ${invalid.key} is not used', () async {
      final h = Harness(
          openSend: ({
        required isRedPacket,
        userID,
        groupID,
        recipientName,
        recipientFaceURL,
      }) async =>
              invalid.value);
      await h.controller.openSend(isRedPacket: true);
      expect(h.controller.messageData(fundMessage())!.status, 'open');
      h.controller.close();
    });
  }

  for (final invalid in [
    (
      name: 'wrong group',
      group: true,
      packet: true,
      result: order(status: 'done', scene: FundScene.group, groupID: 'another'),
    ),
    (
      name: 'single group transfer',
      group: false,
      packet: false,
      result: order(status: 'done', biz: 'group_transfer'),
    ),
  ]) {
    test('send order with ${invalid.name} is ignored', () async {
      final h = Harness(
          openSend: ({
        required isRedPacket,
        userID,
        groupID,
        recipientName,
        recipientFaceURL,
      }) async =>
              invalid.result);
      h.group = invalid.group;
      await h.controller.openSend(isRedPacket: invalid.packet);
      expect(
          h.controller
              .messageData(fundMessage(biz: invalid.result.biz))!
              .status,
          'open');
      h.controller.close();
    });
  }

  test(
      'optional party fields follow the API contract and cache metadata is exact',
      () async {
    final h = Harness(
        openSend: ({
      required isRedPacket,
      userID,
      groupID,
      recipientName,
      recipientFaceURL,
    }) async =>
            order(status: 'done', claimed: true, remark: '权威祝福🎉'));
    await h.controller.openSend(isRedPacket: true);
    expect(h.controller.messageData(fundMessage())!.status, 'done');
    expect(h.controller.messageData(fundMessage())!.remark, '权威祝福🎉');
    for (final message in [
      fundMessage(biz: 'packet_exclusive'),
      fundMessage(currency: 'TRX'),
      fundMessage(amount: '1.000002'),
      fundMessage(id: 'another-order'),
    ]) {
      final data = h.controller.messageData(message)!;
      expect(data.status, 'open');
      expect(data.remark, '');
      expect(h.controller.claimedByMe(data), isFalse);
    }
    final equivalent =
        h.controller.messageData(fundMessage(amount: '01.000001'))!;
    expect(equivalent.status, 'done');
    expect(h.controller.claimedByMe(equivalent), isTrue);
    expect(
        h.controller.claimedByMe(const FundMessageData(
          orderID: 'order',
          biz: 'packet_normal',
          currency: 'USDT',
          amount: 'not-a-number',
          status: 'open',
        )),
        isFalse);
    h.controller.close();
  });

  test('detail navigation releases its entry guard after failure', () async {
    var entries = 0;
    final h = Harness(openDetail: (_) async {
      entries++;
      throw StateError('detail failed');
    });
    final data = h.controller.messageData(fundMessage())!;
    final source = fundMessage()..sendID = 'sdk-sender';
    await expectLater(
        h.controller.openDetail(data, sourceMessage: source), throwsStateError);
    await expectLater(
        h.controller.openDetail(data, sourceMessage: source), throwsStateError);
    expect(entries, 2);
    h.controller.close();
  });

  testWidgets('default detail route uses only matching SDK sender metadata',
      (tester) async {
    final source = fundMessage(amount: '01.000001', remark: '原消息祝福')
      ..sendID = 'sdk-sender'
      ..senderNickname = 'SDK Sender'
      ..senderFaceUrl = 'https://example.invalid/sdk-avatar.png';
    final custom = jsonDecode(source.customElem!.data!) as Map<String, dynamic>;
    custom.addAll({
      'senderID': 'forged-sender',
      'senderNickname': 'Forged Name',
      'senderFaceUrl': 'https://example.invalid/forged-avatar.png',
    });
    source.customElem!.data = jsonEncode(custom);
    final original = jsonEncode(source.toJson());
    final message = FundMessageData.tryParse(fundMessage().customElem!.data)!
        .copyWith(status: 'done', remark: '订单更新祝福');
    final page =
        await captureDefaultDetail(tester, message, sourceMessage: source);
    expect(page.message, same(message));
    expect(page.messageSender?.userID, 'sdk-sender');
    expect(page.messageSender?.nickname, 'SDK Sender');
    expect(
        page.messageSender?.faceURL, 'https://example.invalid/sdk-avatar.png');
    expect(jsonEncode(source.toJson()), original);
  });

  for (final mismatch in [
    'missing source',
    'not custom',
    'malformed payload',
    'order ID',
    'business',
    'currency',
    'amount',
    'missing SDK sender',
    'custom-only sender',
    'invalid reference amount',
  ]) {
    testWidgets('default detail ignores sender context for $mismatch',
        (tester) async {
      final source = fundMessage()
        ..sendID = 'sdk-sender'
        ..senderNickname = 'SDK Sender'
        ..senderFaceUrl = 'https://example.invalid/sdk-avatar.png';
      var message = FundMessageData.tryParse(source.customElem!.data)!;
      switch (mismatch) {
        case 'not custom':
          source.contentType = MessageType.text;
        case 'malformed payload':
          source.customElem!.data = '{';
        case 'order ID':
          source.customElem = fundMessage(id: 'another-order').customElem;
        case 'business':
          source.customElem = fundMessage(biz: 'packet_exclusive').customElem;
        case 'currency':
          source.customElem = fundMessage(currency: 'TRX').customElem;
        case 'amount':
          source.customElem = fundMessage(amount: '1.000002').customElem;
        case 'missing SDK sender':
          source.sendID = '  ';
        case 'custom-only sender':
          source.sendID = null;
          final custom =
              jsonDecode(source.customElem!.data!) as Map<String, dynamic>;
          custom['senderID'] = 'forged-sender';
          source.customElem!.data = jsonEncode(custom);
        case 'invalid reference amount':
          message = FundMessageData(
              orderID: message.orderID,
              biz: message.biz,
              currency: message.currency,
              amount: 'invalid',
              status: message.status);
      }
      final original = jsonEncode(source.toJson());
      final page = await captureDefaultDetail(tester, message,
          sourceMessage: mismatch == 'missing source' ? null : source);
      expect(page.messageSender, isNull);
      expect(jsonEncode(source.toJson()), original);
    });
  }

  test('ignores non-fund and malformed custom messages', () {
    final h = Harness();
    for (final message in [
      Message(contentType: MessageType.text),
      Message(
          contentType: MessageType.custom, customElem: CustomElem(data: '{')),
    ]) {
      expect(h.controller.isFundMessage(message), isFalse);
      expect(h.controller.messageData(message), isNull);
      h.controller.setVisible(message, true);
    }
    expect(h.requests, 0);
    h.controller.close();
  });
}
