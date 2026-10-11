import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_tile.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_message.dart';
import 'package:openim_common/openim_common.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../markdown/support/markdown_fixture.dart';

Iterable<TextSpan> _spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? <InlineSpan>[]) {
      yield* _spans(child);
    }
  }
}

RichText _body(WidgetTester tester) => tester.widget<RichText>(find
    .descendant(
        of: find.byType(MatchTextView).first, matching: find.byType(RichText))
    .first);

void main() {
  setUp(() async {
    await setupMarkdownFixture();
    final previous = VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(
        () => VisibilityDetectorController.instance.updateInterval = previous);
  });
  tearDown(Get.reset);

  for (final dark in [false, true]) {
    for (final outgoing in [false, true]) {
      for (final preview in [false, true]) {
        testWidgets(
            'everyone mention is styled in chat and peek '
            '(dark=$dark outgoing=$outgoing preview=$preview)', (tester) async {
          final source = '${outgoing ? '@所有人' : '@atAllTag'}，'
              '@peer 机器人还在升级，大家耐心等待';
          final message = markdownMessage(source,
              type: MessageType.atText,
              outgoing: outgoing,
              extra: {
                'groupID': 'group',
                'sessionType': ConversationType.superGroup,
                'atTextElem': {
                  'text': source,
                  'atUserList': ['atAllTag', 'peer'],
                  'atUsersInfo': [
                    {'atUserID': 'peer', 'groupNickname': '测试成员'}
                  ],
                },
              });
          final original = message.toJson();
          final logic = MarkdownTileLogic(message);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            await logic.disposeFixture();
          });
          await mountMarkdown(
              tester,
              preview
                  ? ConversationPeekMessage(message: message, isGroupChat: true)
                  : ChatMessageTile(logic: logic, message: message),
              brightness: dark ? Brightness.dark : Brightness.light);
          final body = _body(tester);
          final spans = _spans(body.text).toList();
          final mention = spans.singleWhere((span) => span.text == '@所有人');
          expect(mention.style?.color,
              dark && outgoing ? AppTokens.onAccent : Styles.c_0089FF);
          expect(mention.recognizer, isNull,
              reason: 'Everyone must not navigate to a member profile.');
          expect(body.text.toPlainText(), '@所有人，@测试成员 机器人还在升级，大家耐心等待');
          expect(message.toJson(), original);
          if (!preview) {
            expect(logic.copyTextMap[message.clientMsgID],
                body.text.toPlainText());
            expect(spans.singleWhere((span) => span.text == '@测试成员').recognizer,
                isNotNull);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('everyone label at whitespace/end highlights without member list',
      (tester) async {
    final message =
        markdownMessage('@所有人 等待升级\n@所有人', type: MessageType.atText);
    await mountMarkdown(
        tester, ChatItemView(message: message, onTapUserProfile: (_) {}));
    expect(_spans(_body(tester).text).where((s) => s.text == '@所有人'),
        hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('longer member names are not partially styled as everyone',
      (tester) async {
    final message = markdownMessage('@所有人的昵称 消息', type: MessageType.atText);
    await mountMarkdown(
        tester, ChatItemView(message: message, onTapUserProfile: (_) {}));
    expect(_spans(_body(tester).text).where((s) => s.text == '@所有人'), isEmpty);
    expect(_body(tester).text.toPlainText(), '@所有人的昵称 消息');
    expect(tester.takeException(), isNull);
  });
}
