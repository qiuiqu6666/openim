import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_list.dart';
import 'package:openim/pages/official_account/models/official_account.dart';
import 'package:openim/pages/official_account/official_account_page.dart';
import 'package:openim/pages/official_account/widgets/official_account_header.dart';
import 'package:openim/pages/official_account/widgets/official_account_input_spacer.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../ai_assistant/presentation/support/ai_ui_test_host.dart';
import 'support/official_account_preview.dart';
import 'support/official_account_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfficialAccountTestFixture fixture;
  final clipboardWrites = <String>[];

  setUpAll(() async {
    await initializeAiUiTests();
    PackageInfo.setMockInitialValues(
        appName: '99Chat',
        packageName: 'test.openim',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    await Config.init(() {});
    if (officialPreviewDirectory.isNotEmpty) await loadOfficialPreviewFonts();
  });
  setUp(() async {
    fixture = OfficialAccountTestFixture();
    await fixture.initialize();
    FriendDisplayPreferences.setOnlineStatus(true);
    clipboardWrites.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardWrites.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });
  tearDown(() async {
    await dismissAiUiTestLoading();
    await fixture.dispose();
    Styles.isDark = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<ChatLogic> mount(WidgetTester tester,
      {required OfficialAccountRole role,
      AiUiTestHost? host,
      List<Message> history = const [],
      String? draft,
      String? userID}) async {
    final priorCalls = fixture.histories.length;
    final logic =
        fixture.openOfficial(role: role, draft: draft, userID: userID);
    await tester.idle();
    for (final request in fixture.histories.skip(priorCalls)) {
      request.complete(history);
    }
    final pageHost = host ?? AiUiTestHost(disableAnimations: true);
    // Production synchronizes both ThemeData and shared Styles on theme changes.
    Styles.isDark = pageHost.dark;
    await pageHost.mount(tester, OfficialAccountPage(logic: logic));
    return logic;
  }

  Finder textContaining(String text) => find.byWidgetPredicate((widget) =>
      widget is RichText && widget.text.toPlainText().contains(text));

  void officialTestWidgets(
      String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await dismissAiUiTestLoading();
        // Close native callback owners while the test FocusManager is alive.
        await tester.pumpWidget(const SizedBox.shrink());
        for (final logic in fixture.controllers.reversed) {
          if (!logic.isClosed) logic.onDelete();
        }
        await tester.pump(const Duration(milliseconds: 600));
      }
    });
  }

  void expectReadOnlySurface() {
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(EditableText), findsNothing);
    expect(find.byIcon(Icons.send_rounded), findsNothing);
    expect(find.byIcon(Icons.call), findsNothing);
    expect(find.byIcon(Icons.phone), findsNothing);
    expect(find.byIcon(Icons.videocam), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.byType(OfficialAccountInputSpacer), findsOneWidget);
    expect(find.text('仅用于接收官方消息'), findsNothing);
  }

  void expectDefaultMessageRendering(WidgetTester tester) {
    expect(find.byType(ChatItemView), findsWidgets);
    for (final item
        in tester.widgetList<ChatItemView>(find.byType(ChatItemView))) {
      expect(item.textBubbleStyle, isNull);
      expect(item.itemMargin, isNull);
      expect(item.itemPadding, isNull);
      expect(item.avatarSize, isNull);
    }
    for (final container in tester
        .widgetList<ChatItemContainer>(find.byType(ChatItemContainer))) {
      expect(container.textBubbleStyle, isNull);
      expect(container.avatarSize, 44);
      for (final avatar in tester.widgetList<AvatarView>(find.descendant(
          of: find.byWidget(container), matching: find.byType(AvatarView)))) {
        expect(avatar.textScaler, isNull);
        expect(avatar.isCircle, isNull);
      }
    }
    for (final bubble
        in tester.widgetList<ChatBubble>(find.byType(ChatBubble))) {
      expect(bubble.padding, isNull);
      expect(bubble.borderRadius, isNull);
      expect(bubble.constraints, isNull);
      expect(bubble.backgroundColor, isNull);
    }
    for (final text in tester.widgetList<ChatText>(find.byType(ChatText))) {
      expect(text.textStyle, isNull);
      expect(text.matchTextStyle, isNull);
      expect(text.maximumWidth, isNull);
      expect(text.textScaler, isNull);
      final body = tester.widget<MatchTextView>(find.descendant(
          of: find.byWidget(text), matching: find.byType(MatchTextView)));
      final dark = Theme.of(tester.element(find.byWidget(text))).brightness ==
          Brightness.dark;
      expect(body.textStyle?.color, Styles.c_0C1C33);
      expect(ThemeData.estimateBrightnessForColor(body.textStyle!.color!),
          dark ? Brightness.light : Brightness.dark);
    }
  }

  for (final role in OfficialAccountRole.values) {
    final userID = role == OfficialAccountRole.pay ? '99Pay' : '99Message';
    final received =
        role == OfficialAccountRole.pay ? '充值到账 12.5 USDT' : '欢迎来到99Message！';
    final liveText =
        role == OfficialAccountRole.pay ? '红包退回 3.75 USDT' : '系统公告已更新';

    officialTestWidgets(
        '$userID uses its SDK history and filters live messages',
        (tester) async {
      final logic = await mount(tester,
          role: role,
          history: [officialText('history', received, userID: userID)]);
      expect(fixture.histories, hasLength(1));
      expect(fixture.histories.single.arguments['conversationID'],
          officialConversationID(userID));
      expect(logic.userID, userID);
      expect(logic.isSingleChat, isTrue);
      expect(logic.isOfficialNotificationChat, isTrue);
      expect(logic.officialAccount?.role, role);
      expect(find.text(userID), findsOneWidget);
      final header = find.byType(OfficialAccountHeader);
      final avatar = tester.widget<AvatarView>(
          find.descendant(of: header, matching: find.byType(AvatarView)));
      expect(avatar.width, 40);
      expect(avatar.height, 40);
      final name = tester.widget<Text>(find.text(userID));
      expect(name.style?.fontSize, 16);
      expect(name.style?.fontWeight, FontWeight.w500);
      expect(name.style?.height, 1.1);
      final badge = tester.widget<Image>(find.byWidgetPredicate((widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage)
              .assetName
              .endsWith('official_account_verified.png')));
      expect(badge.width, 18);
      expect(badge.height, 18);
      expect(find.text(StrRes.online), findsOneWidget);
      expect(textContaining(received), findsWidgets);
      expect(find.byType(ChatMessageList), findsOneWidget);
      expectDefaultMessageRendering(tester);
      expectReadOnlySurface();

      fixture.im.recvNewMessage(
          officialText('live', liveText, userID: userID, time: 2));
      fixture.im.recvNewMessage(officialText('other-user', '其他用户的消息',
          userID: 'ordinary-user', time: 3));
      fixture.im.recvNewMessage(officialText('other-official', '其他官方会话的消息',
          userID: role == OfficialAccountRole.pay ? '99Message' : '99Pay',
          time: 4));
      await tester.pump();
      await tester.pump();
      expect(logic.messageList.map((message) => message.clientMsgID),
          ['history', 'live']);
      expect(logic.messageList.every((message) => message.contentType == 101),
          isTrue);
      expect(textContaining(liveText), findsWidgets);
      expect(textContaining('其他用户的消息'), findsNothing);
      expect(textContaining('其他官方会话的消息'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    officialTestWidgets('$userID keeps only copy and has no profile callbacks',
        (tester) async {
      final message = officialText('copy-target', received, userID: userID);
      final logic = await mount(tester, role: role, history: [message]);
      final row = tester.widget<ChatItemView>(find.byType(ChatItemView));
      expect(row.messageMenus.map((menu) => menu.id), ['copyMessage']);
      expect(row.onTapLeftAvatar, isNull);
      expect(row.onLongPressLeftAvatar, isNull);
      expect(row.onTapRightAvatar, isNull);
      expect(row.onLongPressRightAvatar, isNull);
      expect(row.onFailedToResend, isNull);
      await tester.longPress(find.byType(ChatBubble));
      await tester.pumpAndSettle();
      expect(find.text(StrRes.copy), findsOneWidget);
      for (final label in [
        StrRes.menuReply,
        StrRes.menuForward,
        StrRes.favoriteCollection,
        StrRes.menuRevoke,
        StrRes.delete,
        '多选',
      ]) {
        expect(find.text(label), findsNothing);
      }
      await tester.tap(find.text(StrRes.copy));
      await tester.pumpAndSettle();
      expect(clipboardWrites, [received]);
      expect(logic.canForward(message), isFalse);
      expect(logic.canFavorite(message), isFalse);
      expect(logic.canRevoke(message), isFalse);
      expect(logic.canAddMessageToStickers(message), isFalse);
      expect(tester.takeException(), isNull);
    });

    officialTestWidgets('$userID blocks direct send call typing and drafts',
        (tester) async {
      final retained = officialText('retained', received, userID: userID);
      final logic = await mount(tester,
          role: role, draft: '旧版本留下的草稿', history: [retained]);
      expect(logic.sendingMuted, isTrue);
      expect(logic.inputCtrl.text, isEmpty);
      logic.inputCtrl.text = '不应发送或保存';
      logic.sendTypingMsg(focus: true);
      await logic.sendPreparedMessage(
          officialText('unsent', '不应发送', userID: userID, outgoing: true));
      await logic.sendCustomMsg(
          data: '{}', extension: '', description: 'unsupported');
      logic.callAudio();
      logic.callVideo();
      logic.replyToMessage(officialText('reply', received, userID: userID));
      logic.onTapLeftAvatar(officialText('profile', received, userID: userID));
      logic.onTapRightAvatar();
      logic.viewUserInfo(UserInfo(userID: userID, nickname: userID));
      logic.messageSelection.enter(retained);
      expect(logic.messageSelection.active, isFalse);
      await logic.deleteMessage(retained);
      await logic.revokeMessage(
          officialText('revoke', '不应撤回', userID: userID, outgoing: true)
            ..sendTime = DateTime.now().millisecondsSinceEpoch);
      expect(logic.quotedMessage.value, isNull);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpWidget(const SizedBox.shrink());
      logic.onDelete();
      await tester.pump(const Duration(milliseconds: 600));
      expect(fixture.im.onRecvNewMessage, isNull);
      expect(
          fixture.nativeCalls.where((call) => {
                'sendMessage',
                'createCustomMessage',
                'changeInputStates',
                'setConversationDraft',
                'deleteMessageFromLocalStorage',
                'revokeMessage',
              }.contains(call.method)),
          isEmpty);
      expect(logic.messageList.map((message) => message.clientMsgID),
          ['retained']);
      expect(tester.takeException(), isNull);
    });
  }

  officialTestWidgets('ex role retains a renamed SDK account identity',
      (tester) async {
    const peer = 'server-pay-account';
    final logic = await mount(tester,
        role: OfficialAccountRole.pay,
        userID: peer,
        history: [officialText('renamed', '提现到账 5 USDT', userID: peer)]);
    expect(logic.userID, peer);
    expect(logic.isOfficialNotificationChat, isTrue);
    expect(fixture.histories.single.arguments['conversationID'],
        officialConversationID(peer));
    expect(find.text('99Pay'), findsOneWidget);
    expect(textContaining('提现到账 5 USDT'), findsWidgets);
    expectReadOnlySurface();
    expect(tester.takeException(), isNull);
  });

  officialTestWidgets('reference header honors the existing online preference',
      (tester) async {
    await mount(tester, role: OfficialAccountRole.message);
    expect(find.text(StrRes.online), findsOneWidget);
    FriendDisplayPreferences.setOnlineStatus(false);
    await tester.pump();
    expect(find.text(StrRes.online), findsNothing);
    expect(find.text('99Message'), findsOneWidget);
    expectReadOnlySurface();
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final role in OfficialAccountRole.values) {
      officialTestWidgets('empty $role supports both themes ($dark)',
          (tester) async {
        final host = AiUiTestHost(
            dark: dark,
            disableAnimations: true,
            previewFont: officialPreviewDirectory.isNotEmpty);
        final logic = await mount(tester, role: role, host: host);
        expect(logic.messageList, isEmpty);
        expect(find.text('暂无聊天记录'), findsNothing);
        expect(find.text('暂无支付通知'), findsNothing);
        expect(find.text('暂无公告消息'), findsNothing);
        expect(textContaining('欢迎来到99Message！'), findsNothing,
            reason: 'Only the server supplies the welcome message.');
        expectReadOnlySurface();
        await exportOfficialAccountPreview(tester, host, '${role.name}-empty');
        expect(tester.takeException(), isNull);
      });

      officialTestWidgets('$role normal message preview ($dark)',
          (tester) async {
        final host = AiUiTestHost(
            dark: dark,
            disableAnimations: true,
            previewFont: officialPreviewDirectory.isNotEmpty);
        final userID = role == OfficialAccountRole.pay ? '99Pay' : '99Message';
        await mount(tester, role: role, host: host, history: [
          for (final (index, text) in (role == OfficialAccountRole.pay
                  ? ['充值到账 12.5 USDT', '提现到账 10 USDT', '红包退回 2.5 USDT']
                  : ['欢迎来到99Message！', '系统公告：欢迎使用99Chat。'])
              .indexed)
            officialText('preview-$index', text,
                userID: userID, time: index + 1),
        ]);
        expectReadOnlySurface();
        expectDefaultMessageRendering(tester);
        await exportOfficialAccountPreview(tester, host, '${role.name}-normal');
        expect(tester.takeException(), isNull);
      });

      for (final landscape in [false, true]) {
        officialTestWidgets(
            '$role large text fits ${landscape ? 'landscape' : 'narrow phone'} ($dark)',
            (tester) async {
          final host = AiUiTestHost(
            dark: dark,
            size: landscape ? const Size(812, 375) : const Size(320, 568),
            padding: landscape
                ? const EdgeInsets.fromLTRB(44, 24, 44, 21)
                : const EdgeInsets.fromLTRB(0, 24, 0, 16),
            textScale: 2,
            disableAnimations: true,
            previewFont: officialPreviewDirectory.isNotEmpty,
          );
          final userID =
              role == OfficialAccountRole.pay ? '99Pay' : '99Message';
          await mount(tester, role: role, host: host, history: [
            officialText(
                'long-message',
                role == OfficialAccountRole.pay
                    ? '充值到账 12.5 USDT\n提现到账 10 USDT\n红包退回 2.5 USDT'
                    : '欢迎来到99Message！\n这里将展示与你相关的公告和基础消息。',
                userID: userID),
          ]);
          expectReadOnlySurface();
          expectDefaultMessageRendering(tester);
          final spacer =
              tester.getRect(find.byType(OfficialAccountInputSpacer));
          // Reference OfficialAccountInputSpacer: 36px control + 5px each side.
          expect(spacer.height, 46 + host.padding.bottom);
          expect(spacer.bottom, host.size.height);
          for (final avatar in tester.widgetList<AvatarView>(find.descendant(
              of: find.byType(OfficialAccountHeader),
              matching: find.byType(AvatarView)))) {
            expect(avatar.width, 40);
            expect(avatar.height, 40);
            expect(avatar.textScaler?.scale(14), 14,
                reason:
                    'Fallback initials must fit the fixed reference avatar.');
          }
          await exportOfficialAccountPreview(tester, host,
              '${role.name}-${landscape ? 'landscape' : 'messages'}');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
