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

  testWidgets(
      'ordinary SDK text preserves Markdown source and paragraph breaks',
      (tester) async {
    const source = '# Heading\n\n**Bold**\n\n- First\n- Second';
    String? copied;
    await mountMarkdown(tester,
        bubble(markdownMessage(source), copied: (text) => copied = text));
    expect(copied, source);
    expect(renderedMarkdownText(tester), contains('Heading'));
    expect(renderedMarkdownText(tester), contains('Second'));
    expect(renderedMarkdownText(tester), isNot(contains('**Bold**')));
    expect(
        tester
            .widget<ChatItemContainer>(find.byType(ChatItemContainer))
            .metadataBelow,
        isTrue);
    final body = tester.getRect(find.byType(ChatMarkdownText));
    final time = tester.getRect(find.text('14:08'));
    expect(time.top, greaterThanOrEqualTo(body.bottom));
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

  testWidgets('unrelated or malformed metadata retains ordinary Markdown',
      (tester) async {
    for (final ex in ['{"unrelated":true}', 'legacy text', '[]', 'null']) {
      await mountMarkdown(
          tester, bubble(markdownMessage('# Heading', extra: {'ex': ex})));
      expect(find.byType(ChatMarkdownText), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('custom text bubble keeps Markdown footer outside code and table',
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
        isTrue);
    final text = tester.getRect(find.byType(ChatMarkdownText));
    final time = tester.getRect(find.text('14:08'));
    expect(time.top, greaterThanOrEqualTo(text.bottom));
    expect(tester.getRect(find.byType(ChatBubble)).width,
        lessThanOrEqualTo(style.maxBubbleWidth));
    expect(tester.takeException(), isNull);
  });

  testWidgets('group mention replaces SDK ID without losing Markdown newlines',
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

  testWidgets(
      'quoted body parses Markdown and referenced message stays compact',
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
    expect(find.byType(ChatMarkdownText), findsOneWidget);
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

  testWidgets('ignored selected bubble cannot launch Markdown link',
      (tester) async {
    var taps = 0;
    await mountMarkdown(
        tester,
        bubble(markdownMessage('[Open](https://example.com)'),
            ignorePointer: true,
            patterns: [
              MatchPattern(type: PatternType.url, onTap: (_, __) => taps++)
            ]));
    await tester.tap(find.text('Open', findRichText: true),
        warnIfMissed: false);
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

  testWidgets('merged SDK history renders nested original Markdown messages',
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
    expect(find.byType(ChatMarkdownText), findsOneWidget);
    expect(tester.widget<ChatMarkdownText>(find.byType(ChatMarkdownText)).text,
        source);
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
    await tester.longPress(find.text('Bold', findRichText: true));
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
