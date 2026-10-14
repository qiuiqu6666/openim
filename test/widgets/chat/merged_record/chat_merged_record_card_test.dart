import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/merged_record/chat_merged_record_card.dart';
import '../markdown/support/markdown_fixture.dart';

const longTitle = '京东公平公正交流群的聊天记录 · 很长的标题需要自动截断，不应该挤压摘要和时间';
Message record({bool outgoing = false, String title = longTitle}) =>
    markdownMessage('',
        id: outgoing ? 'sent-record' : 'received-record',
        outgoing: outgoing,
        type: MessageType.merger,
        extra: {
          'mergeElem': {
            'title': title,
            'abstractList': [
              '京东六合彩自动机器人：[图片]',
              '小林：最新的资料在这里',
              '阿杰：[视频]',
              '这条不应出现在预览'
            ],
            'multiMessage': [markdownMessage('记录中的真实正文').toJson()]
          }
        });

void main() {
  setUp(setupMarkdownFixture);
  tearDown(Get.reset);
  for (final dark in [false, true]) {
    for (final outgoing in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('record layout outgoing=$outgoing dark=$dark scale=$scale',
            (tester) async {
          final message = record(outgoing: outgoing);
          final original = message.toJson();
          await mountMarkdown(
              tester, ChatItemView(message: message, onTapUserProfile: (_) {}),
              brightness: dark ? Brightness.dark : Brightness.light,
              width: 320,
              textScale: scale);
          final surface = tester.widget<Material>(
              find.byKey(const ValueKey('merged-record-surface')));
          expect(
              surface.color,
              ChatMergedRecordTokens.background(
                  dark: dark, outgoing: outgoing));
          final title = tester
              .widget<Text>(find.byKey(const ValueKey('merged-record-title')));
          expect(title.maxLines, 2);
          expect(title.overflow, TextOverflow.ellipsis);
          expect(find.text('这条不应出现在预览'), findsNothing);
          expect(find.byIcon(Icons.forum_outlined), findsNothing);
          expect(find.byIcon(Icons.chevron_right), findsOneWidget);
          expect(find.text('14:08'), findsOneWidget);
          expect(find.byType(ChatReadReceiptIcon),
              outgoing ? findsOneWidget : findsNothing);
          final card = tester
              .getRect(find.byKey(const ValueKey('merged-record-surface')));
          final time = tester.getRect(find.text('14:08'));
          expect(card.left, greaterThanOrEqualTo(0));
          expect(card.right, lessThanOrEqualTo(320));
          expect(
              time.top, greaterThan(tester.getRect(find.text('聊天记录')).bottom));
          expect(
              outgoing ? time.bottom <= card.bottom : time.top >= card.bottom,
              isTrue);
          expect(message.toJson(), original);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets('whole card opens records and returns without changing source',
      (tester) async {
    final message = record();
    await mountMarkdown(
        tester, ChatItemView(message: message, onTapUserProfile: (_) {}));
    await tester.tap(find.text('小林：最新的资料在这里'));
    await tester.pumpAndSettle();
    expect(renderedMarkdownText(tester), contains('记录中的真实正文'));
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    expect(find.byType(ChatMergedRecordCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty title and summaries remain a tappable record card',
      (tester) async {
    final message = record(title: '  ');
    message.mergeElem!.abstractList = [];
    await mountMarkdown(
        tester, ChatItemView(message: message, onTapUserProfile: (_) {}));
    expect(find.text('聊天记录'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('render approved light and dark record layouts', (tester) async {
    if (markdownPreviewDirectory.isEmpty) return;
    await tester.runAsync(loadMarkdownPreviewFonts);
    for (final dark in [false, true]) {
      await mountMarkdown(
          tester,
          Column(children: [
            ChatItemView(
                message: record(outgoing: true), onTapUserProfile: (_) {}),
            const SizedBox(height: 24),
            ChatItemView(
                message: record(title: '京东群的聊天记录'), onTapUserProfile: (_) {}),
          ]),
          brightness: dark ? Brightness.dark : Brightness.light,
          width: 390);
      await tester.runAsync(() => saveMarkdownPreview(
          tester, 'merged-record-${dark ? 'dark' : 'light'}'));
      expect(tester.takeException(), isNull);
    }
  });
}
