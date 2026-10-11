import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/custom/chat_custom_message.dart';
import 'package:openim_common/openim_common.dart';

import 'markdown/support/markdown_fixture.dart';

void main() {
  setUp(setupMarkdownFixture);
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    for (final variant in [
      (width: 320.0, scale: 2.0),
      (width: 375.0, scale: 1.0),
      (width: 812.0, scale: 1.0),
      (width: 1024.0, scale: 1.0),
    ]) {
      testWidgets(
          '99chat bubbles fit text, replies and custom bodies: '
          '$brightness $variant', (tester) async {
        final messages = _messages();
        final originals = messages.map((m) => m.toJson()).toList();
        await mountMarkdown(tester, _bubbles(messages),
            brightness: brightness,
            width: variant.width,
            textScale: variant.scale);

        final limit = variant.width >= 900 ? 420 : variant.width * .7;
        for (final element in find.byType(ChatBubble).evaluate()) {
          final bubble = find.byElementPredicate((e) => e == element);
          final rect = tester.getRect(bubble);
          expect(rect.width, lessThanOrEqualTo(limit + .01));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(variant.width));
        }
        final shortBubble = find.descendant(
            of: find.byKey(const ValueKey('short')),
            matching: find.byType(ChatBubble));
        expect(tester.getSize(shortBubble).width, lessThan(limit));
        final body = tester.widget<RichText>(find
            .descendant(
                of: find.descendant(
                    of: shortBubble, matching: find.byType(ChatText)),
                matching: find.byType(RichText))
            .first);
        expect(body.textScaler.scale(16), closeTo(16 * variant.scale, .01));
        expect(renderedMarkdownText(tester), contains('报价已确认'));
        expect(renderedMarkdownText(tester), contains('原消息内容'));
        expect(renderedMarkdownText(tester), contains('自定义消息正文'));
        expect(messages.map((m) => m.toJson()).toList(), originals);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('99chat production shape and palette: $brightness',
        (tester) async {
      await mountMarkdown(tester, _bubbles(_messages()),
          brightness: brightness);
      final bubble = find.descendant(
          of: find.byKey(const ValueKey('short')),
          matching: find.byType(ChatBubble));
      final surface = tester.widget<Container>(
          find.descendant(of: bubble, matching: find.byType(Container)).first);
      final decoration = surface.decoration! as BoxDecoration;
      // Reference: TIMUIKitTextElem / DefTheme; use literal reference values.
      expect(surface.padding,
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8));
      expect(
          decoration.borderRadius,
          const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(6),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ));
      expect(
          decoration.color,
          brightness == Brightness.dark
              ? const Color(0xFF1E90FF)
              : const Color(0xFFDCEEFF));
      final body = tester.widget<RichText>(find
          .descendant(
              of: find.descendant(of: bubble, matching: find.byType(ChatText)),
              matching: find.byType(RichText))
          .first);
      expect(body.text.style?.fontSize, 16);
      expect(body.text.style?.height, 1.3);
      final time = tester.widget<Text>(
          find.descendant(of: bubble, matching: find.text('14:08')));
      expect(time.style?.fontSize, 11);
      expect(time.style?.height, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('export 99chat chat bubbles: $brightness', (tester) async {
      await tester.runAsync(loadMarkdownPreviewFonts);
      await mountMarkdown(tester, _bubbles(_messages()),
          brightness: brightness);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() =>
          saveMarkdownPreview(tester, 'bubbles-99chat-${brightness.name}'));
    }, skip: markdownPreviewDirectory.isEmpty);
  }
}

List<Message> _messages() {
  final original = markdownMessage('原消息内容', id: 'original');
  return [
    markdownMessage('你好，消息气泡按 99chat 的样式显示。', id: 'incoming'),
    markdownMessage('收到', id: 'short', outgoing: true),
    markdownMessage('报价已确认\n请核对三项内容：\n第一项：20\n第二项：30\n第三项：50', id: 'long'),
    markdownMessage('我来回复这条消息 ❤️',
        id: 'reply',
        type: MessageType.quote,
        outgoing: true,
        extra: {
          'quoteElem': {
            'text': '我来回复这条消息 ❤️',
            'quoteMessage': original.toJson()
          }
        }),
    markdownMessage('@小林 请查看最新消息 ⬇️', id: 'mention', type: MessageType.atText),
    markdownMessage('',
        id: 'custom',
        outgoing: true,
        type: MessageType.custom,
        extra: {
          'customElem': {'data': '{"content":"自定义消息正文\\n保留原有内容及换行"}'}
        }),
  ];
}

Widget _bubbles(List<Message> messages) => Builder(builder: (context) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return ColoredBox(
        color: dark
            ? AppTokens.backgroundDark
            : ChatComposerTokens.backgroundLight,
        child: Column(children: [
          for (final message in messages)
            ChatItemView(
              key: ValueKey(message.clientMsgID!),
              message: message,
              onTapUserProfile: (_) {},
              customTypeBuilder: (context, message) =>
                  buildChatCustomMessage(context, message, isGroupChat: false),
            ),
        ]),
      );
    });
