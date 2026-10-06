import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/ai_assistant_chat_page.dart';
import 'package:openim/pages/ai_assistant/navigation/ai_assistant_header.dart';
import 'package:openim/pages/ai_assistant/presentation/composer/ai_openim_composer.dart';
import 'package:openim/pages/ai_assistant/presentation/messages/ai_assistant_text.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/official_account/official_account_chrome_tokens.dart';
import 'package:openim/pages/official_account/widgets/official_account_name_label.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../presentation/support/ai_ui_test_host.dart';
import 'support/ai_openim_preview.dart';
import 'support/ai_openim_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AiOpenimTestFixture fixture;
  setUpAll(() async {
    await initializeAiUiTests();
    PackageInfo.setMockInitialValues(
        appName: '99Chat',
        packageName: 'test.openim',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    await Config.init(() {});
    if (aiPreviewDirectory.isNotEmpty) await loadAiPreviewFonts();
  });
  setUp(() async {
    fixture = AiOpenimTestFixture();
    await fixture.initialize();
  });
  tearDown(() async {
    await dismissAiUiTestLoading();
    await fixture.dispose();
  });

  Future<ChatLogic> mount(WidgetTester tester,
      {AiUiTestHost? host, List<Message>? history, String? draft}) async {
    final logic = fixture.open(draft: draft);
    await tester.idle();
    fixture.histories.single.complete(history ?? []);
    await (host ?? AiUiTestHost(disableAnimations: true))
        .mount(tester, AiAssistantChatPage(logic: logic));
    return logic;
  }

  Finder textContaining(String text) => find.byWidgetPredicate((widget) =>
      widget is RichText && widget.text.toPlainText().contains(text));

  void expectVerifiedHeader(WidgetTester tester) {
    final label = find.descendant(
        of: find.byType(AiAssistantHeader),
        matching: find.byType(OfficialAccountNameLabel));
    expect(label, findsOneWidget);
    expect(tester.widget<OfficialAccountNameLabel>(label).userID, 'assistant');
    final badge = find.descendant(
        of: label,
        matching: find.byWidgetPredicate((widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                OfficialAccountChromeTokens.badgeAsset));
    expect(badge, findsOneWidget);
    expect(
        tester.getSize(badge),
        const Size(OfficialAccountChromeTokens.badgeSize,
            OfficialAccountChromeTokens.badgeSize));
  }

  void aiTestWidgets(
      String description, Future<void> Function(WidgetTester) body,
      {bool skip = false}) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        // Close the SDK owner while the test's FocusManager is still active.
        await tester.pumpWidget(const SizedBox.shrink());
        for (final logic in fixture.controllers.reversed) {
          if (!logic.isClosed) logic.onDelete();
        }
        await tester.pump(const Duration(milliseconds: 600));
      }
    }, skip: skip);
  }

  aiTestWidgets(
      'uses assistant single-chat history and renders live SDK replies',
      (tester) async {
    final logic = await mount(tester, history: [
      aiOpenimText('history-user', '帮我整理这次讨论的重点。', outgoing: true),
      aiOpenimText('history-ai', '**讨论重点**\n\n确认项目目标和下一步安排。', time: 2),
    ]);
    expect(fixture.histories, hasLength(1));
    expect(fixture.histories.single.arguments['conversationID'],
        aiOpenimConversationID);
    expect(logic.userID, 'assistant');
    expect(logic.isSingleChat, isTrue);
    expect(logic.conversationInfo.ex, isNull);
    expect(find.text('AI助理'), findsOneWidget);
    expectVerifiedHeader(tester);
    expect(textContaining('确认项目目标和下一步安排。'), findsWidgets);
    expect(
        tester
            .widget<AiAssistantMarkdown>(find.byType(AiAssistantMarkdown))
            .text,
        '**讨论重点**\n\n确认项目目标和下一步安排。');
    expect(find.byIcon(Icons.call), findsNothing);
    expect(find.byIcon(Icons.phone), findsNothing);
    expect(find.byIcon(Icons.videocam), findsNothing);

    fixture.im.recvNewMessage(aiOpenimText('live-reply', '记忆属于当前用户。', time: 3));
    fixture.im.recvNewMessage(aiOpenimText('other-chat', '不能出现在这里', time: 4)
      ..sendID = 'another-user');
    await tester.pump();
    await tester.pump();
    expect(textContaining('记忆属于当前用户。'), findsWidgets);
    expect(textContaining('不能出现在这里'), findsNothing);
    expect(logic.messageList.map((message) => message.clientMsgID),
        ['history-user', 'history-ai', 'live-reply']);
    expect(tester.takeException(), isNull);
  });

  aiTestWidgets('typing 113 is transient and a normal reply clears it',
      (tester) async {
    final logic = await mount(tester);
    fixture.im.recvNewMessage(aiOpenimTyping('typing-yes'));
    await tester.pump();
    expect(logic.peerTyping.value, isTrue);
    expect(textContaining('正在输入'), findsWidgets);
    expect(logic.messageList, isEmpty);

    fixture.im.recvNewMessage(aiOpenimText('reply', '这次没有答上来，请再发一次。'));
    await tester.pump();
    await tester.pump();
    expect(logic.peerTyping.value, isFalse);
    expect(textContaining('这次没有答上来，请再发一次。'), findsWidgets);
    expect(logic.messageList.single.contentType, MessageType.text);
    fixture.im.recvNewMessage(aiOpenimTyping('typing-no', tips: 'no'));
    fixture.im
        .recvNewMessage(aiOpenimTyping('unrelated', sender: 'another-user'));
    await tester.pump();
    expect(logic.peerTyping.value, isFalse);
    expect(logic.messageList, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  aiTestWidgets(
      'image response stays an ordinary picture message in the timeline',
      (tester) async {
    final logic = await mount(tester);
    fixture.im.recvNewMessage(aiOpenimPicture('generated-image'));
    await tester.pump();
    await tester.pump();
    expect(logic.messageList.single.clientMsgID, 'generated-image');
    expect(logic.messageList.single.contentType, MessageType.picture);
    expect(find.byType(ChatPictureView), findsOneWidget);
    final image = tester.widget<ChatPictureView>(find.byType(ChatPictureView));
    expect(image.message, same(logic.messageList.single));
    expect(image.isISend, isFalse);
    expect(tester.takeException(), isNull);
  });

  aiTestWidgets('normal text including image wording sends through the SDK',
      (tester) async {
    final logic = await mount(tester, draft: '保留的草稿');
    expect(logic.inputCtrl.text, '保留的草稿');
    await tester.enterText(find.byType(TextField), '画一张图是什么意思？');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    final creations = fixture.nativeCalls
        .where((call) => call.method == 'createTextMessage')
        .toList();
    final sends = fixture.nativeCalls
        .where((call) => call.method == 'sendMessage')
        .toList();
    expect(creations, hasLength(1));
    expect(sends, hasLength(1));
    final args = Map<String, dynamic>.from(sends.single.arguments as Map);
    expect(args['userID'], 'assistant');
    expect(args['groupID'], '');
    expect((args['message'] as Map)['contentType'], MessageType.text);
    expect(
        fixture.nativeCalls
            .where((call) => call.method == 'createCustomMessage'),
        isEmpty);
    expect(logic.inputCtrl.text, isEmpty);
    expect(logic.messageList.single.textElem?.content, '画一张图是什么意思？');
    expect(tester.takeException(), isNull);
  });

  aiTestWidgets('selected image tool sends the image custom instruction',
      (tester) async {
    final logic = await mount(tester);
    await tester.tap(find.text('生成图片'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '一只在月球上的猫');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    final creations = fixture.nativeCalls
        .where((call) => call.method == 'createCustomMessage')
        .toList();
    final sends = fixture.nativeCalls
        .where((call) => call.method == 'sendMessage')
        .toList();
    expect(creations, hasLength(1));
    final creation =
        Map<String, dynamic>.from(creations.single.arguments as Map);
    expect(creation['description'], 'image');
    expect(jsonDecode(creation['data'] as String), {'prompt': '一只在月球上的猫'});
    expect(sends, hasLength(1));
    final args = Map<String, dynamic>.from(sends.single.arguments as Map);
    expect(args['userID'], 'assistant');
    expect((args['message'] as Map)['contentType'], MessageType.custom);
    expect(logic.messageList.single.customElem?.description, 'image');
    expect(logic.inputCtrl.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  aiTestWidgets('SDK image-instruction failure keeps the prompt editable',
      (tester) async {
    final logic = await mount(tester);
    await tester.tap(find.text('生成图片'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '失败后保留这份提示词');
    fixture.failNextSend = true;
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    expect(logic.inputCtrl.text, '失败后保留这份提示词');
    expect(logic.messageList.single.status, MessageStatus.failed);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    await dismissAiUiTestLoading();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  aiTestWidgets('SDK text failure restores the editable draft', (tester) async {
    final logic = await mount(tester);
    await tester.enterText(find.byType(TextField), '失败后保留这条问题');
    fixture.failNextSend = true;
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    expect(logic.inputCtrl.text, '失败后保留这条问题');
    expect(logic.messageList.single.status, MessageStatus.failed);
    await dismissAiUiTestLoading();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  aiTestWidgets('reply composition sends the SDK quote114 to assistant',
      (tester) async {
    final prior = aiOpenimText('quote-target', '先确认项目目标。');
    final logic = await mount(tester, history: [prior]);
    logic.replyToMessage(prior);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '继续展开这一点');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    final creations = fixture.nativeCalls
        .where((call) => call.method == 'createQuoteMessage')
        .toList();
    expect(creations, hasLength(1));
    final args = Map<String, dynamic>.from(creations.single.arguments as Map);
    expect(args['quoteText'], '继续展开这一点');
    expect((args['quoteMessage'] as Map)['clientMsgID'], 'quote-target');
    final sent = logic.messageList.last;
    expect(sent.contentType, MessageType.quote);
    expect(sent.recvID, 'assistant');
    expect(sent.status, MessageStatus.succeeded);
    expect(sent.quoteElem?.quoteMessage?.clientMsgID, 'quote-target');
    expect(logic.quotedMessage.value, isNull);
    expect(logic.inputCtrl.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  Future<void> stagePeerCard(WidgetTester tester) async {
    fixture.conversations.list.add(ConversationInfo(
      conversationID: 'si_peer_self',
      userID: 'peer',
      conversationType: ConversationType.single,
      showName: '项目伙伴',
    ));
    await tester.tap(find.text('总结聊天'));
    await tester.pumpAndSettle();
    expect(find.text('选择会话'), findsOneWidget);
    await tester.tap(find.text('项目伙伴'));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsOneWidget);
  }

  aiTestWidgets('summarize card needs only IM login and SDK108',
      (tester) async {
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': '',
      'imToken': 'test-im-session',
    }));
    final logic = await mount(tester);
    await stagePeerCard(tester);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    final creations = fixture.nativeCalls
        .where((call) => call.method == 'createCardMessage')
        .toList();
    expect(creations, hasLength(1));
    final args = Map<String, dynamic>.from(creations.single.arguments as Map);
    final card = args['cardMessage'] as Map;
    expect(card['userID'], 'peer');
    expect(card['nickname'], '项目伙伴');
    expect(card['ex'], '');
    expect(DataSp.chatToken, isEmpty);
    expect(logic.messageList.single.contentType, MessageType.card);
    expect(logic.messageList.single.recvID, 'assistant');
    expect(logic.messageList.single.status, MessageStatus.succeeded);
    expect(find.byType(InputChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  aiTestWidgets('message selection keeps the selected image instruction',
      (tester) async {
    final logic =
        await mount(tester, history: [aiOpenimText('older-reply', '可以继续提问。')]);
    await tester.tap(find.text('生成图片'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '被选择模式覆盖的提示词');
    logic.messageSelection.enter(logic.messageList.first);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    logic.messageSelection.cancel();
    await tester.pump();
    expect(logic.inputCtrl.text, '被选择模式覆盖的提示词');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    final sent = logic.messageList.last;
    expect(sent.contentType, MessageType.custom);
    expect(sent.customElem?.description, 'image');
    expect(jsonDecode(sent.customElem!.data!), {'prompt': '被选择模式覆盖的提示词'});
    expect(
        fixture.nativeCalls.where((call) => call.method == 'createTextMessage'),
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  aiTestWidgets('failed card belongs to its timeline row after SDK recording',
      (tester) async {
    final logic = await mount(tester);
    await stagePeerCard(tester);
    await tester.enterText(find.byType(TextField), '再说明下一步怎么办');
    fixture.failNextSend = true;
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    expect(logic.messageList.single.contentType, MessageType.card);
    expect(logic.messageList.single.status, MessageStatus.failed);
    final failedID = logic.messageList.single.clientMsgID;
    expect(find.byType(InputChip), findsNothing,
        reason: 'The failed timeline row now owns the card retry.');
    expect(logic.inputCtrl.text, '再说明下一步怎么办');
    await dismissAiUiTestLoading();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();
    expect(
        fixture.nativeCalls.where((call) => call.method == 'createCardMessage'),
        hasLength(1));
    expect(
        logic.messageList
            .where((message) => message.contentType == MessageType.card),
        hasLength(1));
    expect(logic.messageList.first.clientMsgID, failedID);
    expect(logic.messageList.last.contentType, MessageType.text);
    expect(logic.messageList.last.textElem?.content, '再说明下一步怎么办');
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    aiTestWidgets(
        'small phone and landscape respect keyboard and large text ($dark)',
        (tester) async {
      for (final layout in [
        (
          size: const Size(320, 568),
          padding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
          keyboard: 210.0,
        ),
        (
          size: const Size(812, 375),
          padding: const EdgeInsets.fromLTRB(44, 24, 44, 21),
          keyboard: 0.0,
        ),
      ]) {
        final host = AiUiTestHost(
          dark: dark,
          size: layout.size,
          padding: layout.padding,
          viewInsets: EdgeInsets.only(bottom: layout.keyboard),
          textScale: 2,
          disableAnimations: true,
        );
        final logic = await mount(tester, host: host);
        expectVerifiedHeader(tester);
        final composer = tester.getRect(find.byType(AiOpenIMComposer));
        expect(composer.bottom,
            lessThanOrEqualTo(layout.size.height - layout.keyboard));
        expect(composer.left, greaterThanOrEqualTo(layout.padding.left));
        expect(composer.right,
            lessThanOrEqualTo(layout.size.width - layout.padding.right));
        await tester.enterText(find.byType(TextField), '大字体仍能输入');
        expect(logic.inputCtrl.text, '大字体仍能输入');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        logic.onDelete();
        // Closing one route must release the SDK listener before the next one.
        expect(fixture.im.onRecvNewMessage, isNull);
        fixture.histories.clear();
      }
    });

    aiTestWidgets('conversation contrast and optional previews ($dark)',
        (tester) async {
      final host = AiUiTestHost(
          dark: dark,
          previewFont: aiPreviewDirectory.isNotEmpty,
          disableAnimations: true);
      final logic = await mount(tester, host: host);
      expectVerifiedHeader(tester);
      expect(find.text('暂无聊天记录'), findsNothing,
          reason: 'Only the dedicated AI empty view should occupy the canvas.');
      await exportAiOpenimPreview(tester, host, 'empty');
      fixture.im.recvNewMessage(aiOpenimText(
          'preview-question', '帮我整理这次讨论的重点，并给出下一步行动。',
          outgoing: true));
      fixture.im.recvNewMessage(aiOpenimText('preview-answer',
          '**讨论重点**\n\n1. 确认项目目标和分工。\n2. 整理本周需要推进的事项。\n\n你也可以发来好友或群聊名片，让我结合聊天内容继续分析。',
          time: 2));
      await tester.pump();
      await tester.pump();
      final outgoing = tester.widget<AiHighlightText>(find.byWidgetPredicate(
          (widget) =>
              widget is AiHighlightText &&
              widget.text == '帮我整理这次讨论的重点，并给出下一步行动。'));
      final bubble = find.byWidgetPredicate(
          (widget) => widget is ChatBubble && widget.isISend);
      final background = tester.widget<Container>(find
          .descendant(
              of: bubble,
              matching: find.byWidgetPredicate((widget) =>
                  widget is Container && widget.decoration is BoxDecoration))
          .first);
      final fill = (background.decoration! as BoxDecoration).color!;
      final textLuminance = outgoing.style.color!.computeLuminance();
      final fillLuminance = fill.computeLuminance();
      final contrast = textLuminance > fillLuminance
          ? (textLuminance + .05) / (fillLuminance + .05)
          : (fillLuminance + .05) / (textLuminance + .05);
      expect(contrast, greaterThanOrEqualTo(4.5),
          reason:
              'Outgoing text must stay legible on its bubble in both themes.');
      await exportAiOpenimPreview(tester, host, 'messages');
      expect(logic.messageList, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }
}
