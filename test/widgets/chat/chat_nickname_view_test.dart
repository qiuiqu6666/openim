import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'markdown/support/markdown_fixture.dart';

const _twentyCharacters = '一二三四五六七八九十一二三四五六七八九十';

Finder get _nicknameText => find.descendant(
    of: find.byType(ChatNicknameView), matching: find.byType(RichText));

String _visibleNickname(WidgetTester tester) => tester
    .widget<RichText>(_nicknameText)
    .text
    .toPlainText(includeSemanticsLabels: false);

Widget _message(String nickname, {bool outgoing = false}) => ChatItemView(
      message: markdownMessage('消息正文', outgoing: outgoing, extra: {
        'senderNickname': nickname,
        'groupID': 'group',
        'sessionType': ConversationType.superGroup,
      }),
      rightNickname: nickname,
      showRightNickname: outgoing,
      onTapUserProfile: (_) {},
    );

void main() {
  setUp(setupMarkdownFixture);
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    for (final outgoing in [false, true]) {
      testWidgets('twenty characters fit above bubble $brightness $outgoing',
          (tester) async {
        await mountMarkdown(
            tester, _message(_twentyCharacters, outgoing: outgoing),
            brightness: brightness);
        expect(_visibleNickname(tester), _twentyCharacters);
        final paragraph = tester.renderObject<RenderParagraph>(_nicknameText);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.size.width, greaterThan(100));
        expect(paragraph.text.style!.color, Styles.ts_8E9AB0_12sp.color);
        final nameRect = tester.getRect(find.byType(ChatNicknameView));
        final bodyRect = tester.getRect(find.byType(ChatBubble));
        expect(nameRect.bottom, lessThan(bodyRect.top));
        expect(nameRect.left, greaterThanOrEqualTo(0));
        expect(nameRect.right, lessThanOrEqualTo(375));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'full nicknames remain visible including emoji',
      (tester) async {
    const nineteen = '1234567890123456789';
    const emoji = '👩🏽‍💻';
    for (final (source, visible) in [
      ('京888888群转账可用', '京888888群转账可用'),
      (nineteen, nineteen),
      ('$nineteen$emoji', '$nineteen$emoji'),
      ('$nineteen$emoji甲', '$nineteen$emoji甲'),
      ('$_twentyCharacters甲', '$_twentyCharacters甲'),
      ('${nineteen}e\u0301尾', '${nineteen}e\u0301尾'),
    ]) {
      await mountMarkdown(tester, _message(source));
      expect(_visibleNickname(tester), visible);
      expect(tester.widget<RichText>(_nicknameText).text.toPlainText(), source);
      expect(
          tester
              .widget<ChatItemView>(find.byType(ChatItemView))
              .message
              .senderNickname,
          source);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('large text wraps without hiding a nickname under twenty letters',
      (tester) async {
    for (final brightness in Brightness.values) {
      await mountMarkdown(tester, _message(_twentyCharacters),
          width: 320, textScale: 3, brightness: brightness);
      final paragraph = tester.renderObject<RenderParagraph>(_nicknameText);
      expect(_visibleNickname(tester), _twentyCharacters);
      expect(paragraph.didExceedMaxLines, isFalse);
      final boxes = paragraph.getBoxesForSelection(const TextSelection(
          baseOffset: 0, extentOffset: _twentyCharacters.length));
      expect(boxes.map((box) => box.top).toSet().length, greaterThan(1));
      for (final box in boxes) {
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(paragraph.size.width));
      }
      expect(tester.getRect(find.byType(ChatNicknameView)).bottom,
          lessThan(tester.getRect(find.byType(ChatBubble)).top));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('optional header time remains visible after the shortened name',
      (tester) async {
    await mountMarkdown(
        tester,
        const ChatNicknameView(
            nickname: '$_twentyCharacters甲', timeStr: '08:30'));
    expect(_visibleNickname(tester), startsWith('$_twentyCharacters甲'));
    expect(_visibleNickname(tester), endsWith('08:30'));
    await mountMarkdown(tester, const ChatNicknameView(timeStr: '08:30'));
    expect(_visibleNickname(tester), '08:30');
    expect(tester.takeException(), isNull);
  });
}
