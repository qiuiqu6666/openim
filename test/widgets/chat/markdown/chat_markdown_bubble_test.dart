import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_tile.dart';
import 'package:openim_common/openim_common.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'support/markdown_fixture.dart';

Future<void> _tapPlainText(WidgetTester tester, String label) async {
  final finder = find.descendant(
      of: find.byType(MatchTextView), matching: find.byType(RichText));
  final text = tester.widget<RichText>(finder).text.toPlainText();
  final start = text.indexOf(label);
  expect(start, greaterThanOrEqualTo(0));
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final box = paragraph
      .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + label.length))
      .first;
  await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
}

void main() {
  setUp(() async {
    await setupMarkdownFixture();
    final previous = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(
        () => VisibilityDetectorController.instance.updateInterval = previous);
  });
  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    Get.reset();
  });

  ChatItemView bubble(Message message,
          {ValueChanged<String?>? copied,
          ItemViewBuilder? override,
          bool ignorePointer = false,
          List<MatchPattern> patterns = const []}) =>
      ChatItemView(
          message: message,
          onTapUserProfile: (_) {},
          onVisibleTrulyText: copied,
          textContentBuilder: override,
          ignorePointer: ignorePointer,
          patterns: patterns);

  testWidgets('ordinary SDK text displays literal markers and paragraph breaks',
      (tester) async {
    const source = '# Heading\n\n**Bold**\n\n- First\n- Second';
    String? copied;
    await mountMarkdown(tester,
        bubble(markdownMessage(source), copied: (text) => copied = text));
    expect(copied, source);
    expect(renderedMarkdownText(tester), contains('Heading'));
    expect(renderedMarkdownText(tester), contains('Second'));
    expect(renderedMarkdownText(tester), contains(source));
    expect(find.byType(ChatMarkdownText), findsNothing);
    expect(
        tester
            .widget<ChatItemContainer>(find.byType(ChatItemContainer))
            .metadataBelow,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plain text keeps natural bubble width and inline time',
      (tester) async {
    await mountMarkdown(tester, bubble(markdownMessage('Hi')));
    expect(find.byType(ChatMarkdownText), findsNothing);
    expect(
        tester
            .widget<ChatItemContainer>(find.byType(ChatItemContainer))
            .metadataBelow,
        isFalse);
    expect(tester.getSize(find.byType(ChatBubble)).width, lessThan(180));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'download instructions stay plain with working links $brightness',
        (tester) async {
      const appleUrl = 'https://testflight.apple.com/join/Fj5d9CpY';
      const siteUrl = 'https://99chat.vip';
      const source = '阿伦_(现南风在管理)\n2026年9月25日最新链接\n'
          '正在使用 99CHAT，快来一起聊天吧！\n'
          '苹果下载链接：\n$appleUrl\n下载安装即可\n兑换码无\n'
          '----------------\n安卓/苹果/电脑端/聚合下载链接：\n'
          '$siteUrl\n（格式错误，不记录）';
      await mountMarkdown(tester, bubble(markdownMessage('普通聊天文字')),
          brightness: brightness);
      final normalStyle =
          tester.widget<MatchTextView>(find.byType(MatchTextView)).textStyle;
      final message = markdownMessage(source, extra: {
        'groupID': 'group',
        'sessionType': ConversationType.superGroup,
      });
      String? copied;
      final taps = <String>[];
      await mountMarkdown(
          tester,
          bubble(message, copied: (value) => copied = value, patterns: [
            MatchPattern(
                type: PatternType.url, onTap: (url, _) => taps.add(url)),
          ]),
          brightness: brightness);
      expect(ChatMarkdownText.hasMarkdown(source), isTrue);
      expect(find.byType(ChatMarkdownText), findsNothing);
      final body = tester.widget<MatchTextView>(find.byType(MatchTextView));
      expect(body.textStyle, normalStyle);
      expect(body.text, source);
      expect(renderedMarkdownText(tester), contains(source));
      expect(copied, source);
      expect(message.textElem!.content, source);
      await _tapPlainText(tester, appleUrl);
      await _tapPlainText(tester, siteUrl);
      expect(taps, [appleUrl, siteUrl]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sangong summary uses ordinary text style in $brightness',
        (tester) async {
      const source = '庄【秋的测试号】1包共0注\n==================\n'
          '第❶门:0注\n第❷门:0注\n第❸门:0注\n第❹门:0注\n第❺门:0注\n第❻门:0注\n'
          '==================\n请核对统计清单、出入认表';
      const ex = '{"marker":"sangong-go:delivery",'
          '"sangongReport":{"schemaVersion":2,"kind":"bets",'
          '"reportId":"report","deliveryId":"delivery"}}';
      final message = markdownMessage(source, extra: {'ex': ex});
      await mountMarkdown(tester, bubble(markdownMessage('普通聊天文字')),
          brightness: brightness);
      final normalStyle =
          tester.widget<MatchTextView>(find.byType(MatchTextView)).textStyle;

      String? copied;
      await mountMarkdown(
          tester, bubble(message, copied: (text) => copied = text),
          brightness: brightness);
      expect(find.byType(ChatMarkdownText), findsNothing);
      final body = tester.widget<MatchTextView>(find.byType(MatchTextView));
      expect(body.textStyle, normalStyle);
      expect(body.text, source);
      expect(copied, source);
      expect(message.textElem?.content, source);
      expect(message.ex, ex);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unrelated or malformed metadata cannot enable ordinary Markdown',
      (tester) async {
    for (final ex in ['{"unrelated":true}', 'legacy text', '[]', 'null']) {
      await mountMarkdown(
          tester, bubble(markdownMessage('# Heading', extra: {'ex': ex})));
      expect(find.byType(ChatMarkdownText), findsNothing);
      expect(renderedMarkdownText(tester), contains('# Heading'));
      expect(tester.takeException(), isNull);
    }
  });

  for (final brightness in Brightness.values) {
    for (final summary in [false, true]) {
      testWidgets('legacy draw report stays literal ($brightness, $summary)',
          (tester) async {
        const header = '[第010期]\n================\n--开奖号码为--\n'
            '开:（10)(猴)(小)(双)(蓝)\n倍(48)(2)(2.1)(2)(2)\n'
            '开(1头)(0尾)(合单)(金)\n倍(2)倍(2)倍(2)倍(2)\n结算如下↓↓↓↓';
        final source = header +
            (summary ? '\n本局总注：600\n本局中奖：0\n本局输赢：-600\n下注人数：1\n管理费：0' : '');
        String? copied;
        final message = markdownMessage(source);
        await mountMarkdown(
            tester, bubble(message, copied: (value) => copied = value),
            brightness: brightness);
        expect(find.byType(ChatMarkdownText), findsNothing);
        expect(tester.widget<MatchTextView>(find.byType(MatchTextView)).text,
            source);
        expect(copied, source);
        expect(message.textElem!.content, source);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('ordinary Setext headings remain literal', (tester) async {
    await mountMarkdown(tester, bubble(markdownMessage('标题\n========')));
    expect(find.byType(ChatMarkdownText), findsNothing);
    expect(renderedMarkdownText(tester), contains('标题\n========'));
  });

  testWidgets('custom text bubble treats code and table markers as plain text',
      (tester) async {
    const source = '```dart\nfinal x = 1;\n```\n\n'
        '| Heading | Value |\n| --- | --- |\n| First | 2 |';
    const body = TextStyle(fontSize: 16, height: 1.3);
    const footer = TextStyle(fontSize: 11);
    const style = ChatTextBubbleStyle(
        incomingTextStyle: body,
        outgoingTextStyle: body,
        incomingMetadataStyle: footer,
        outgoingMetadataStyle: footer,
        incomingBackground: Color(0xFFF4F5F8),
        outgoingBackground: Color(0xFFCCE7FE),
        incomingRadius: BorderRadius.all(Radius.circular(12)),
        outgoingRadius: BorderRadius.all(Radius.circular(12)),
        maxBubbleWidth: 247,
        timelineTextStyle: footer);
    await mountMarkdown(
        tester,
        ChatItemView(
            message: markdownMessage(source),
            textBubbleStyle: style,
            onTapUserProfile: (_) {}));
    expect(
        tester
            .widget<ChatTextBubbleLayout>(find.byType(ChatTextBubbleLayout))
            .forceSeparateFooter,
        isFalse);
    expect(find.byType(ChatMarkdownText), findsNothing);
    expect(renderedMarkdownText(tester), contains(source));
    final text = tester.getRect(find.byType(MatchTextView));
    final time = tester.getRect(find.text('14:08'));
    expect(time.top, greaterThanOrEqualTo(text.bottom));
    expect(tester.getRect(find.byType(ChatBubble)).width,
        lessThanOrEqualTo(style.maxBubbleWidth));
    expect(tester.takeException(), isNull);
  });

  testWidgets('plain group mention preserves callbacks and literal newlines',
      (tester) async {
    final message = markdownMessage('@peer **Hello**\n\n- Group item',
        type: MessageType.atText,
        extra: {
          'groupID': 'group',
          'sessionType': ConversationType.superGroup,
          'atTextElem': {
            'text': '@peer **Hello**\n\n- Group item',
            'atUserList': ['peer'],
            'atUsersInfo': [
              {'atUserID': 'peer', 'groupNickname': '张三'}
            ]
          },
        });
    String? copied;
    final taps = <String>[];
    await mountMarkdown(
        tester,
        bubble(message, copied: (text) => copied = text, patterns: [
          MatchPattern(
              type: PatternType.custom,
              pattern: '@张三',
              onTap: (value, _) => taps.add(value)),
        ]));
    expect(copied, '@张三 **Hello**\n\n- Group item');
    expect(find.byType(ChatMarkdownText), findsNothing);
    expect(renderedMarkdownText(tester), contains('**Hello**\n\n- Group item'));
    expect(renderedMarkdownText(tester), contains('@张三'));
    expect(renderedMarkdownText(tester), isNot(contains('@peer')));
    final mention = find.byWidgetPredicate((widget) =>
        widget is RichText &&
        widget.text.toPlainText().replaceAll('\u200B', '').contains('@张三'));
    final paragraph = tester.renderObject<RenderParagraph>(mention);
    final box = paragraph
        .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 1))
        .first;
    await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
    expect(taps, ['@张三']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quoted body stays literal and referenced message stays compact',
      (tester) async {
    final original = markdownMessage('Original\n\n**source**', id: 'original');
    final message = markdownMessage('**Reply**\n\n- Answer',
        type: MessageType.quote,
        extra: {
          'quoteElem': {
            'text': '**Reply**\n\n- Answer',
            'quoteMessage': original.toJson()
          },
        });
    await mountMarkdown(tester, bubble(message));
    expect(find.byType(ChatMarkdownText), findsNothing);
    expect(renderedMarkdownText(tester), contains('**Reply**\n\n- Answer'));
    expect(find.text('聊天好友'), findsWidgets);
    final text = tester.widget<Text>(find.text('Original **source**'));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(renderedMarkdownText(tester), contains('Answer'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'advanced entity offsets retain formatting and entity-free parses',
      (tester) async {
    final message = markdownMessage('**Keep source**',
        type: MessageType.advancedText,
        extra: {
          'advancedTextElem': {
            'text': '**Keep source**',
            'messageEntityList': [
              {'type': 'bold', 'offset': 0, 'length': 15}
            ],
          }
        });
    await mountMarkdown(tester, bubble(message));
    expect(find.byType(ChatFormattedText), findsOneWidget);
    expect(find.byType(ChatMarkdownText), findsNothing);
    expect(renderedMarkdownText(tester), contains('**Keep source**'));
    await mountMarkdown(
        tester,
        bubble(
            markdownMessage('**Parse now**', type: MessageType.advancedText)));
    expect(find.byType(ChatFormattedText), findsNothing);
    expect(find.byType(ChatMarkdownText), findsOneWidget);
    expect(renderedMarkdownText(tester), isNot(contains('**Parse now**')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'existing AI and specialized text builders own their presentation',
      (tester) async {
    await mountMarkdown(
        tester,
        bubble(markdownMessage('**SDK source**'),
            override: (_, message) => Text('AI:${message.textElem!.content}')));
    expect(find.byType(ChatMarkdownText), findsNothing);
    expect(find.text('AI:**SDK source**'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ignored selected plain bubble cannot launch a link',
      (tester) async {
    var taps = 0;
    await mountMarkdown(
        tester,
        bubble(markdownMessage('**地址**\nhttps://example.com'),
            ignorePointer: true,
            patterns: [
              MatchPattern(type: PatternType.url, onTap: (_, __) => taps++)
            ]));
    await _tapPlainText(tester, 'https://example.com');
    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired private Markdown never mounts its text or links',
      (tester) async {
    final message =
        markdownMessage('**Secret** [Open](https://example.com)', extra: {
      'attachedInfoElem': {
        'isPrivateChat': true,
        'hasReadTime': DateTime.now()
            .subtract(const Duration(seconds: 20))
            .millisecondsSinceEpoch,
        'burnDuration': 1,
      },
    });
    await mountMarkdown(tester, bubble(message));
    expect(find.byType(ChatMarkdownText), findsNothing);
    expect(renderedMarkdownText(tester), isNot(contains('Secret')));
    expect(find.text('sdkExpired'.tr), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('merged SDK history keeps nested ordinary messages literal',
      (tester) async {
    const source = '# Forwarded\n\n- Keep\n- Newlines';
    final message = markdownMessage('', type: MessageType.merger, extra: {
      'mergeElem': {
        'title': 'Merged history',
        'abstractList': ['Keep source'],
        'multiMessage': [markdownMessage(source, id: 'nested').toJson()],
      },
    });
    await mountMarkdown(tester, bubble(message));
    await tester.tap(find.text('Merged history'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatMarkdownText), findsNothing);
    expect(
        tester.widget<MatchTextView>(find.byType(MatchTextView)).text, source);
    expect(renderedMarkdownText(tester), contains('Newlines'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('real tile long-press copy retains raw Markdown source',
      (tester) async {
    const source = '**Bold**\n\n- First\n- Second';
    final message = markdownMessage(source);
    final logic = MarkdownTileLogic(message);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await logic.disposeFixture();
    });
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await mountMarkdown(
        tester, ChatMessageTile(logic: logic, message: message));
    await tester.longPress(find.byType(MatchTextView));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('chat-message-menu-panel')), findsOneWidget);
    await tester.tap(
        find.byKey(const ValueKey('chat-message-menu-action-copyMessage')));
    await tester.pumpAndSettle();
    expect(copied, source);
    expect(find.byKey(const ValueKey('chat-message-menu-panel')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });
}
