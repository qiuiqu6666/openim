import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/fund/fund_message_card.dart';
import 'package:openim/pages/chat/fund/fund_card_recipient.dart';
import 'package:openim/pages/chat/fund/fund_packet_summary.dart';
import 'package:openim_common/openim_common.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  Map<String, dynamic> payload({
    String biz = 'packet_normal',
    String currency = 'USDT',
    String amount = '1.000001',
    String status = 'open',
    Object? remark,
  }) =>
      {
        'orderID': 'fund-order-123',
        'biz': biz,
        'currency': currency,
        'amount': amount,
        'status': status,
        if (remark != null) 'remark': remark,
      };

  FundMessageData parse(Map<String, dynamic> map) =>
      FundMessageData.tryParse(jsonEncode(map))!;

  Message imMessage(Map<String, dynamic> data,
          {bool outgoing = false, bool hasRead = false}) =>
      Message.fromJson({
        'clientMsgID': 'im-fund-123',
        'contentType': MessageType.custom,
        'sendID': outgoing ? 'me' : 'sender',
        'recvID': outgoing ? 'sender' : 'me',
        'sessionType': ConversationType.single,
        'sendTime': 1700000000000,
        'isRead': hasRead,
        'status': MessageStatus.succeeded,
        'customElem': {'data': jsonEncode(data)},
      });

  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    Get.testMode = true;
    Get.locale = const Locale('zh', 'CN');
    Get.addTranslations(TranslationService().keys);
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: 'Me');
  });

  tearDown(Get.reset);

  test('recognizes all server fund cards without converting decimal money', () {
    for (final biz in [
      'transfer',
      'group_transfer',
      'packet_exclusive',
      'packet_normal',
      'packet_lucky',
    ]) {
      final data = parse(payload(biz: biz, amount: '9007199254740993.123456'));
      expect(data.orderID, 'fund-order-123');
      expect(data.amount, '9007199254740993.123456');
      expect(data.isTransfer, biz.contains('transfer'));
      expect(data.isPacket, biz.startsWith('packet_'));
      expect(data.copyWith(status: 'done').status, 'done');
      expect(data.status, 'open');
    }
    expect(
        parse(payload(currency: 'BI99', amount: '0.01')).currencyLabel, '99BI');
  });

  test('rejects incomplete, unrelated, and unsafe financial payloads', () {
    for (final raw in [null, '', '{', '[]', 'null', '"text"']) {
      expect(FundMessageData.tryParse(raw), isNull);
    }
    for (final map in [
      {...payload(), 'orderID': ''},
      {...payload(), 'orderID': 123},
      {...payload(), 'amount': 1.2},
      payload(amount: '0'),
      payload(amount: '0.000000'),
      payload(amount: '-1'),
      payload(amount: 'NaN'),
      payload(amount: '1e6'),
      payload(amount: '1.0000001'),
      payload(currency: 'BI99', amount: '0.001'),
      payload(currency: 'USD'),
      payload(biz: 'withdrawal'),
      payload(status: 'failed'),
      {'customType': CustomMessageType.call, 'data': payload()},
      {...payload()}..remove('currency'),
    ]) {
      expect(FundMessageData.tryParse(jsonEncode(map)), isNull,
          reason: jsonEncode(map));
    }
  });

  test('optional remarks preserve legacy cards and count Unicode code points',
      () {
    expect(parse(payload()).remark, '');
    expect(parse(payload(remark: '  \n\t  ')).remark, '');
    final twelveEmoji = List.filled(12, '🎉').join();
    final data = parse(payload(remark: '  $twelveEmoji \n'));
    expect(twelveEmoji.length, 24);
    expect(data.remark, twelveEmoji);
    expect(data.copyWith(status: 'done').remark, twelveEmoji);
    expect(data.copyWith(remark: '  生日快乐，朋友🎂  ').remark, '生日快乐，朋友🎂');
    expect(data.copyWith(remark: '').remark, '');
    expect(data.remark, twelveEmoji);
    // A combining accent is its own code point, rather than part of the
    // preceding glyph for the backend's twelve-code-point limit.
    expect(parse(payload(remark: List.filled(6, 'e\u0301').join())).remark,
        List.filled(6, 'e\u0301').join());
    expect(parse(payload(remark: List.filled(7, 'e\u0301').join())).remark, '');
  });

  test('malformed optional remarks do not broaden custom-message recognition',
      () {
    for (final remark in [
      null,
      12,
      true,
      ['祝福'],
      {'text': '祝福'},
      List.filled(13, '🎉').join(),
    ]) {
      final map = {...payload(), 'remark': remark};
      final data = parse(map);
      expect(data.remark, '');
      expect(data.orderID, 'fund-order-123');
      expect(data.amount, '1.000001');
      expect(FundMessageData.tryParse(jsonEncode({...map, 'biz': 'call'})),
          isNull);
    }
  });

  test('conversation and reply summaries recognize server cards', () {
    expect(IMUtils.parseMsg(imMessage(payload())), '[红包]');
    expect(
        IMUtils.parseMsg(
            imMessage(payload(
                biz: 'group_transfer', currency: 'BI99', amount: '12.50')),
            isConversation: true),
        '[群转账] 12.50 99BI');
    expect(IMUtils.parseMsg(imMessage(payload(biz: 'withdrawal'))),
        '[${StrRes.unsupportedMessage}]');
  });

  Widget host(Widget child,
          {bool dark = false,
          double textScale = 1,
          bool highContrast = false}) =>
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
            body: Builder(builder: (context) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(textScale),
                    highContrast: highContrast),
                child: Align(alignment: Alignment.topLeft, child: child),
              );
            }),
          ),
        ),
      );

  for (final dark in [false, true]) {
    testWidgets('packet summary matches amount and count hierarchy $dark',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final entry in [
        (biz: 'packet_normal', currency: 'USDT', amount: '12.50', count: 5),
        (biz: 'packet_lucky', currency: 'TRX', amount: '1.123456', count: 2),
        (biz: 'packet_exclusive', currency: 'BI99', amount: '24.99', count: 1),
      ]) {
        await tester.pumpWidget(host(
            FundMessageCard(
                message: parse(payload(
                    biz: entry.biz,
                    currency: entry.currency,
                    amount: entry.amount)),
                packetCount: entry.count,
                recipient: const FundCardRecipient(name: '小林')),
            dark: dark));
        final summary = find.byType(FundPacketSummary);
        final text = tester.widget<Text>(
            find.descendant(of: summary, matching: find.byType(Text)));
        expect(text.textSpan!.toPlainText(),
            '${entry.amount} ${entry.currency == 'BI99' ? '99BI' : entry.currency} · 共${entry.count}个红包');
        final spans = (text.textSpan! as TextSpan).children!;
        expect(spans.first.style!.fontWeight, FontWeight.w700);
        expect(spans.first.style!.fontSize, 16);
        expect(spans.last.style!.fontWeight, FontWeight.w500);
        expect(spans.last.style!.fontSize, 11);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(
          host(FundMessageCard(message: parse(payload())), dark: dark));
      expect(find.text('1.000001 USDT'), findsOneWidget);
      expect(find.textContaining('共'), findsNothing);
    });
    testWidgets('recipient cards match 99chat structure $dark', (tester) async {
      const recipient = FundCardRecipient(userID: 'friend', name: '小林');
      for (final biz in ['packet_exclusive', 'group_transfer']) {
        await tester.pumpWidget(host(
            FundMessageCard(
                message: parse(
                    payload(biz: biz, status: 'done', amount: '12.000001')),
                recipient: recipient,
                isGroupChat: true),
            dark: dark));
        expect(find.text(biz == 'packet_exclusive' ? '小林的专属红包' : '转账给小林'),
            findsOneWidget);
        expect(find.byType(AvatarView), findsOneWidget);
        expect(tester.widget<AvatarView>(find.byType(AvatarView)).text, '小林');
        expect(find.byType(SvgPicture), findsNothing);
        expect(find.text('12.000001 USDT'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
    testWidgets(
        'unresolved card keeps packet colors without claiming availability $dark',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(
          FundMessageCard(message: parse(payload()), statusResolved: false),
          dark: dark));
      expect(find.text(StrRes.fundOpenDetails), findsNothing);
      expect(find.text(StrRes.fundClaimed), findsNothing);
      final surface = tester
          .widget<DecoratedBox>(find.byKey(const Key('fund-card-surface')))
          .decoration as BoxDecoration;
      expect((surface.gradient! as LinearGradient).colors,
          [const Color(0xFFFA6A4E), const Color(0xFFF55E44)]);
      expect(surface.boxShadow, isNotEmpty);
      final node =
          tester.getSemantics(find.bySemanticsLabel(RegExp('^红包, 恭喜发财，大吉大利,')));
      expect(node.label, isNot(contains(StrRes.fundClaimable)));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('fund cards retain the chat tap flow and fit large text themes',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;
    final message = imMessage(payload());
    final data = parse(payload());
    for (final dark in [false, true]) {
      await tester.pumpWidget(host(
          ChatItemView(
            message: message,
            onClickItemView: () => taps++,
            onTapUserProfile: (_) {},
            customTypeBuilder: (_, __) => CustomTypeInfo(
                FundMessageCard(message: data, isGroupChat: true), false),
          ),
          dark: dark,
          textScale: 1.8));
      await tester.pump();
      expect(find.text('待领取'), findsNothing);
      expect(find.text('1.000001 USDT'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('恭喜发财，大吉大利'));
    }
    expect(taps, 2);
  });

  testWidgets(
      'packet cards display total distinctly from personal claim status',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final state in [
        (status: 'open', claimed: false),
        (status: 'open', claimed: true),
        (status: 'done', claimed: false),
        (status: 'refunded', claimed: false),
      ]) {
        await tester.pumpWidget(host(FundMessageCard(
          message: parse(payload(status: state.status)),
          isGroupChat: true,
          claimedByMe: state.claimed,
        )));
        final cardSemantics = tester
            .getSemantics(find.bySemanticsLabel(RegExp('^红包, 恭喜发财，大吉大利,')));
        expect(cardSemantics.flagsCollection.isButton, isTrue);
        expect(cardSemantics.label, contains('恭喜发财，大吉大利'));
        expect(cardSemantics.label, contains('红包总额 1.000001 USDT'));
        expect(find.textContaining('1.000001'), findsOneWidget);
        expect(find.textContaining('USDT'), findsOneWidget);
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('fund chat rows match 99chat avatars and keep footer actions',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      for (final outgoing in [false, true]) {
        for (final biz in ['packet_normal', 'transfer']) {
          final boundaryKey = GlobalKey();
          var opened = 0;
          final profiles = <String>[];
          final data = payload(
              biz: biz,
              amount: '1.00',
              status: biz == 'transfer' ? 'done' : 'open');
          await tester.pumpWidget(host(RepaintBoundary(
            key: boundaryKey,
            child: ChatItemView(
              message: imMessage(data, outgoing: outgoing, hasRead: true),
              timelineStr: '昨日',
              leftNickname: 'Sender',
              rightNickname: 'Me',
              showLeftNickname: false,
              onClickItemView: () => opened++,
              onTapLeftAvatar: () => profiles.add('sender'),
              onTapUserProfile: (_) {},
              customTypeBuilder: (_, __) => CustomTypeInfo(
                  FundMessageCard(
                      message: parse(data),
                      isOutgoing: outgoing,
                      timeText: '22:13'),
                  false),
            ),
          )));
          await tester.pumpAndSettle();
          final card = find.byType(FundMessageCard);
          final avatar = find.byType(AvatarView);
          final cardRect = tester.getRect(card);
          final rowRect = tester.getRect(find.byType(ChatItemContainer));
          expect(cardRect.width, 290);
          expect(cardRect.left, greaterThanOrEqualTo(rowRect.left));
          expect(cardRect.right, lessThanOrEqualTo(rowRect.right));
          expect(cardRect.bottom, lessThanOrEqualTo(rowRect.bottom));
          if (outgoing) {
            expect(avatar, findsNothing);
            expect(cardRect.right, rowRect.right);
          } else {
            expect(avatar, findsOneWidget);
            final avatarRect = tester.getRect(avatar);
            expect(avatarRect.size, const Size(40, 40));
            expect(find.descendant(of: avatar, matching: find.byType(ClipOval)),
                findsOneWidget);
            expect(cardRect.top, avatarRect.top);
            expect(cardRect.left - avatarRect.right, 10);
            await tester.tap(avatar);
            expect(profiles, ['sender']);
          }
          expect(find.byType(ChatReadReceiptIcon), findsNothing);
          expect(find.textContaining(RegExp(r'^\d{2}:\d{2}$')), findsOneWidget);
          expect(find.descendant(of: card, matching: find.text('22:13')),
              findsOneWidget);
          expect(find.text('昨日'), findsOneWidget);
          expect(opened, 0);
          final title = biz == 'transfer' ? '转账 1.00 USDT' : '恭喜发财，大吉大利';
          await tester.tap(find.text(title));
          expect(opened, 1);
          final label = biz == 'transfer'
              ? '转账, 1.00 USDT, 已到账, 查看详情'
              : '红包, 恭喜发财，大吉大利, 红包总额 1.00 USDT, 待领取, 查看详情';
          final node = tester.getSemantics(find.bySemanticsLabel(label));
          expect(node.flagsCollection.isButton, isTrue);
          expect(
              node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await tester.pump();
          expect(opened, 2);
          final boundary = boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final rgba = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              return await image.toByteData(format: ImageByteFormat.rawRgba);
            } finally {
              image.dispose();
            }
          });
          final origin = tester.getTopLeft(find.byKey(boundaryKey));
          final x = (cardRect.left - origin.dx + (outgoing ? 287 : 2)).round();
          final y = (cardRect.top - origin.dy + 17).round();
          final offset = (y * boundary.size.width.round() + x) * 4;
          final tailColor = Color.fromARGB(
              rgba!.getUint8(offset + 3),
              rgba.getUint8(offset),
              rgba.getUint8(offset + 1),
              rgba.getUint8(offset + 2));
          expect(
              tailColor,
              biz == 'transfer'
                  ? const Color(0xFFD47166)
                  : const Color(0xFFF55E44),
              reason: 'The curved tail must remain inside the row.');
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(host(ChatItemView(
        message: Message.fromJson({
          'clientMsgID': 'ordinary-message',
          'contentType': MessageType.text,
          'sendID': 'sender',
          'recvID': 'me',
          'sessionType': ConversationType.single,
          'sendTime': 1700000000000,
          'isRead': true,
          'status': MessageStatus.succeeded,
          'textElem': {'content': 'hello'},
        }),
        showLeftNickname: false,
        onTapUserProfile: (_) {},
      )));
      final ordinaryAvatar = find.byType(AvatarView);
      expect(tester.widget<AvatarView>(ordinaryAvatar).isCircle, isNull);
      expect(tester.getSize(ordinaryAvatar), const Size(44, 44));
      expect(
          find.descendant(of: ordinaryAvatar, matching: find.byType(ClipOval)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('transfer card preserves exact amount and an accessible tap',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var opened = 0;
      final map = payload(biz: 'transfer', amount: '12.000001', status: 'done');
      await tester.pumpWidget(host(ChatItemView(
        message: imMessage(map),
        onClickItemView: () => opened++,
        onTapUserProfile: (_) {},
        customTypeBuilder: (_, __) =>
            CustomTypeInfo(FundMessageCard(message: parse(map)), false),
      )));
      final label = '转账, 12.000001 USDT, 已到账, 查看详情';
      final cardSemantics = tester.getSemantics(find.bySemanticsLabel(label));
      expect(cardSemantics.flagsCollection.isButton, isTrue);
      expect(cardSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue);
      expect(find.text('转账 12.000001 USDT'), findsOneWidget);
      expect(find.text('已到账'), findsOneWidget);
      await tester.tap(find.text('转账 12.000001 USDT'));
      expect(opened, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('packet blessings and totals preserve server values',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final dark in [false, true]) {
        for (final state in [
          (status: 'open', claimed: false),
          (status: 'open', claimed: true),
          (status: 'done', claimed: false),
          (status: 'refunded', claimed: false),
        ]) {
          await tester.pumpWidget(host(
              SingleChildScrollView(
                  child: FundMessageCard(
                message:
                    parse(payload(status: state.status, remark: '  生日快乐🎉  ')),
                isGroupChat: true,
                claimedByMe: state.claimed,
              )),
              dark: dark,
              textScale: 2));
          expect(find.text('生日快乐🎉'), findsOneWidget);
          expect(find.text('恭喜发财，大吉大利'), findsNothing);
          final label = tester
              .getSemantics(find.bySemanticsLabel(RegExp('^红包, 生日快乐🎉,')))
              .label;
          expect(label, contains('红包总额 1.000001 USDT'));
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('transfer memos keep exact money and actual settlement visible',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final dark in [false, true]) {
        for (final biz in ['transfer', 'group_transfer']) {
          for (final status in ['done', 'refunded']) {
            var opened = 0;
            final map = payload(
                biz: biz,
                amount: '12.000001',
                status: status,
                remark: '  午餐，谢谢啦🍜  ');
            await tester.pumpWidget(host(
                ChatItemView(
                  message: imMessage(map),
                  onClickItemView: () => opened++,
                  onTapUserProfile: (_) {},
                  customTypeBuilder: (_, __) => CustomTypeInfo(
                      FundMessageCard(message: parse(map)), false),
                ),
                dark: dark,
                textScale: 2));
            final state = status == 'done' ? '已到账' : '未领部分已退回';
            final type = biz == 'transfer' ? '转账' : '群转账';
            expect(
                find.text(
                    biz == 'transfer' ? '转账 12.000001 USDT' : '12.000001 USDT'),
                findsOneWidget);
            expect(find.text('午餐，谢谢啦🍜'),
                biz == 'transfer' ? findsOneWidget : findsNothing);
            expect(
                find.text(state),
                biz == 'transfer' || status == 'refunded'
                    ? findsOneWidget
                    : findsNothing);
            final node = tester.getSemantics(find.bySemanticsLabel(
                biz == 'transfer'
                    ? '$type, 12.000001 USDT, 午餐，谢谢啦🍜, $state, 查看详情'
                    : '$type, 转账给对方, 12.000001 USDT, 午餐，谢谢啦🍜, $state, 查看详情'));
            expect(
                node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
            await tester
                .tap(find.text(biz == 'transfer' ? '午餐，谢谢啦🍜' : '转账给对方'));
            expect(opened, 1);
            expect(tester.takeException(), isNull);
          }
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('short transfer amounts show two decimals without changing money',
      (tester) async {
    final data = parse(payload(biz: 'transfer', amount: '12', status: 'done'));
    await tester.pumpWidget(host(FundMessageCard(message: data)));
    expect(find.text('转账 12.00 USDT'), findsOneWidget);
    expect(data.amount, '12');
    expect(
        IMUtils.parseMsg(
            imMessage(payload(biz: 'transfer', amount: '12', status: 'done'))),
        '[转账] 12 USDT');
  });

  testWidgets('cards retain the 99chat palettes and honor high contrast',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    double contrast(Color foreground, Color background) {
      final light = math.max(
          foreground.computeLuminance(), background.computeLuminance());
      final dark = math.min(
          foreground.computeLuminance(), background.computeLuminance());
      return (light + .05) / (dark + .05);
    }

    for (final mode in [
      (dark: false, highContrast: false),
      (dark: true, highContrast: false),
      (dark: false, highContrast: true),
      (dark: true, highContrast: true),
    ]) {
      Color? activeBody;
      for (final state in [
        (status: 'open', claimed: false),
        (status: 'open', claimed: true),
        (status: 'done', claimed: false),
        (status: 'refunded', claimed: false),
      ]) {
        await tester.pumpWidget(host(
            FundMessageCard(
                message: parse(payload(status: state.status)),
                isGroupChat: true,
                claimedByMe: state.claimed),
            dark: mode.dark,
            highContrast: mode.highContrast));
        final surface = tester
            .widget<DecoratedBox>(find.byKey(const Key('fund-card-surface')))
            .decoration as BoxDecoration;
        final bodyColors = (surface.gradient! as LinearGradient).colors;
        final footerBox = tester
            .widget<Container>(find.byKey(const Key('fund-card-footer')))
            .decoration as BoxDecoration;
        final headline = tester.widget<Text>(find.text('恭喜发财，大吉大利'));
        final footer = tester.widget<Text>(find.text('99Chat红包'));
        final active = state.status == 'open' && !state.claimed;
        if (mode.highContrast) {
          expect(contrast(headline.style!.color!, bodyColors.first),
              greaterThanOrEqualTo(4.5));
          expect(
              contrast(footer.style!.color!,
                  Color.alphaBlend(footerBox.color!, bodyColors.last)),
              greaterThanOrEqualTo(4.5));
        } else if (active) {
          expect(
              bodyColors, [const Color(0xFFFA6A4E), const Color(0xFFF55E44)]);
          expect(headline.style!.color, const Color(0xFFFFFBF5));
          expect(footer.style!.color, const Color(0xFFFFD4B0));
          expect(footerBox.color!.toARGB32(), 0xEBE8553C);
          expect(surface.boxShadow, isNotEmpty);
          activeBody = bodyColors.last;
        } else {
          expect(bodyColors.last, isNot(activeBody));
          expect(surface.boxShadow, isNull);
        }
      }
      // The reference transfer palette has no fake "received" fade.
      for (final status in ['open', 'done']) {
        await tester.pumpWidget(host(
            FundMessageCard(
                message: parse(payload(biz: 'transfer', status: status))),
            dark: mode.dark,
            highContrast: mode.highContrast));
        final surface = tester
            .widget<DecoratedBox>(find.byKey(const Key('fund-card-surface')))
            .decoration as BoxDecoration;
        final footer = tester
            .widget<Container>(find.byKey(const Key('fund-card-footer')))
            .decoration as BoxDecoration;
        if (!mode.highContrast) {
          expect(surface.color, const Color(0xFFD47166));
          expect(surface.gradient, isNull);
          expect(footer.color, const Color(0xFFC06258));
        }
      }
    }
  });

  testWidgets('99chat cards retain source metrics artwork and curved tails',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final outgoing in [false, true]) {
      for (final biz in [
        'packet_lucky',
        'packet_exclusive',
        'group_transfer'
      ]) {
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(host(RepaintBoundary(
          key: boundaryKey,
          child: FundMessageCard(
            message: parse(payload(
                biz: biz,
                amount: '1.00',
                status: biz == 'group_transfer' ? 'done' : 'open')),
            isGroupChat: true,
            isOutgoing: outgoing,
            timeText: '22:13',
          ),
        )));
        await tester.pumpAndSettle();
        final packet = biz != 'group_transfer';
        final card = find.byType(FundMessageCard);
        final body = find.byKey(const Key('fund-card-body'));
        final footer = find.byKey(const Key('fund-card-footer'));
        final tail = find.byKey(const Key('fund-card-tail'));
        expect(tester.getSize(card).width, 290);
        expect(tester.getSize(body), const Size(285.5, 58));
        expect(tester.getSize(tail), const Size(7, 12));
        expect(tester.getRect(tail).top - tester.getRect(card).top, 11);
        expect(tester.getRect(footer).top, tester.getRect(body).bottom);
        final decoration = tester
            .widget<DecoratedBox>(find.byKey(const Key('fund-card-surface')))
            .decoration as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(7));
        final footerWidget = tester.widget<Container>(footer);
        expect(footerWidget.padding,
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4));
        expect(
            tester
                .widget<Text>(find.descendant(
                    of: footer,
                    matching: find.text(biz == 'packet_exclusive'
                        ? StrRes.fundExclusivePacket
                        : packet
                            ? '99Chat红包'
                            : '99Chat')))
                .style!
                .fontSize,
            packet ? 10 : 9);
        expect(find.text('待领取'), findsNothing);
        expect(find.text('待收款'), findsNothing);
        expect(find.text('转账给对方'),
            biz == 'group_transfer' ? findsOneWidget : findsNothing);
        expect(find.text('22:13'), findsOneWidget);
        if (biz == 'packet_lucky') {
          final image = tester.widget<Image>(
              find.descendant(of: card, matching: find.byType(Image)));
          expect((image.image as AssetImage).assetName,
              'assets/img/red_packet_icon.png');
          expect(image.width, 34);
          expect(image.height, 34);
          expect(find.byType(SvgPicture), findsNothing);
        } else {
          expect(find.byType(SvgPicture), findsNothing);
          expect(find.byType(AvatarView), findsOneWidget);
          final avatar = tester.widget<AvatarView>(find.byType(AvatarView));
          expect(avatar.width, 34);
          expect(avatar.isCircle, isTrue);
        }
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final rgba = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            return await image.toByteData(format: ImageByteFormat.rawRgba);
          } finally {
            image.dispose();
          }
        });
        int alphaAt(int x, int y) => rgba!.getUint8((y * 290 + x) * 4 + 3);
        final edge = outgoing ? 287 : 2;
        final oppositeEdge = outgoing ? 2 : 287;
        expect(alphaAt(edge, 17), 255);
        expect(alphaAt(edge, 40),
            lessThan(80)); // only the reference's ambient shadow
        expect(alphaAt(oppositeEdge, 40), 255);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
      'packet and transfer cards fit large text on small and wide screens',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(320, 568),
      const Size(812, 375),
    ]) {
      tester.view.physicalSize = size;
      for (final dark in [false, true]) {
        for (final biz in ['packet_normal', 'group_transfer']) {
          final data = parse(payload(
              biz: biz,
              amount: '12345.123456',
              remark: List.filled(12, '🎉').join(),
              status: biz == 'group_transfer' ? 'done' : 'open'));
          final map = payload(
              biz: biz,
              amount: data.amount,
              status: data.status,
              remark: data.remark);
          var opened = 0;
          await tester.pumpWidget(host(
              // Production chat uses this sliver viewport. Large-text rows
              // may exceed the landscape viewport and must remain scrollable.
              ChatListView(
                key: UniqueKey(),
                itemCount: 1,
                messageIDs: const ['im-fund-123'],
                loadOnInit: false,
                hasMore: false,
                itemBuilder: (_, __) => ChatItemView(
                  key: const ValueKey('im-fund-123'),
                  message: imMessage(map),
                  onClickItemView: () => opened++,
                  onTapUserProfile: (_) {},
                  customTypeBuilder: (_, __) => CustomTypeInfo(
                      FundMessageCard(
                          message: data,
                          isGroupChat: true,
                          timeText: '22:13',
                          packetCount: biz == 'packet_normal' ? 5 : null),
                      false),
                ),
              ),
              dark: dark,
              textScale: 2));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: '$size dark=$dark $biz textScale=2');
          expect(find.textContaining('12345.123456 USDT'), findsOneWidget);
          expect(find.text(data.remark),
              biz == 'group_transfer' ? findsNothing : findsOneWidget);
          if (biz != 'group_transfer') {
            expect(
                tester.widget<Text>(find.text(data.remark)).maxLines, isNull);
          }
          await tester.ensureVisible(find.byKey(const Key('fund-card-footer')));
          await tester.pumpAndSettle();
          final viewport = tester.getRect(find.byType(ChatListView));
          final footer =
              tester.getRect(find.byKey(const Key('fund-card-footer')));
          expect(footer.top, greaterThanOrEqualTo(viewport.top));
          expect(footer.bottom, lessThanOrEqualTo(viewport.bottom));
          await tester.tap(find.text('22:13'));
          expect(opened, 1);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('claimed packets use color and preserve refund text',
      (tester) async {
    await tester.pumpWidget(host(FundMessageCard(
        message: parse(payload()), isGroupChat: true, claimedByMe: true)));
    expect(find.text('已领取'), findsNothing);
    await tester.pumpWidget(host(FundMessageCard(
        message: parse(payload(status: 'done')), isGroupChat: true)));
    expect(find.text('已领完'), findsNothing);
    await tester.pumpWidget(host(FundMessageCard(
        message: parse(payload(biz: 'packet_exclusive', status: 'done')),
        isGroupChat: true)));
    expect(find.text('已领取'), findsNothing);
    await tester.pumpWidget(host(FundMessageCard(
        message: parse(payload(status: 'refunded')), isGroupChat: true)));
    expect(find.text('未领部分已退回'), findsOneWidget);
    await tester.pumpWidget(host(FundMessageCard(
        message: parse(payload(biz: 'transfer')), isGroupChat: true)));
    expect(find.text('查看详情'), findsOneWidget);
    expect(find.text('待领取'), findsNothing);
    expect(find.text('待收款'), findsNothing);
  });

  testWidgets('toolbox exposes packet and single or group transfer actions',
      (tester) async {
    var packetTaps = 0;
    var transferTaps = 0;
    for (final group in [false, true]) {
      await tester.pumpWidget(host(ChatToolBox(
        isGroupChat: group,
        onTapRedPacket: () => packetTaps++,
        onTapTransfer: () => transferTaps++,
      )));
      await tester.tap(find.byTooltip('红包'));
      await tester.tap(find.byTooltip(group ? '群转账' : '转账'));
      expect(tester.takeException(), isNull);
    }
    expect(packetTaps, 2);
    expect(transferTaps, 2);
  });

  testWidgets('full funds toolbox remains reachable on small and wide screens',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    var taps = 0;
    for (final size in [
      const Size(375, 812),
      const Size(812, 375),
      const Size(320, 568),
      const Size(800, 600),
    ]) {
      for (final dark in [false, true]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(host(
          ChatToolBox(
            key: ValueKey('$size-$dark'),
            onTapAlbum: () {},
            onTapCamera: () {},
            onTapFile: () {},
            onTapLocation: () {},
            onTapCall: () {},
            onTapCard: () {},
            onTapRedPacket: () => taps++,
            onTapTransfer: () => taps++,
          ),
          dark: dark,
          textScale: 2,
        ));
        await tester.pumpAndSettle();
        for (final title in ['红包', '转账']) {
          final action = find.byTooltip(title);
          await tester.scrollUntilVisible(action, 80,
              scrollable: find
                  .descendant(
                      of: find.byType(ChatToolBox),
                      matching: find.byType(Scrollable))
                  .last);
          await tester.pumpAndSettle();
          final touchTarget = tester.getSize(action);
          expect(touchTarget.width, greaterThanOrEqualTo(48));
          expect(touchTarget.height, greaterThanOrEqualTo(48));
          await tester.tap(action);
        }
        expect(tester.takeException(), isNull,
            reason: '$size dark=$dark textScale=2');
      }
    }
    expect(taps, 16);
  });
}
