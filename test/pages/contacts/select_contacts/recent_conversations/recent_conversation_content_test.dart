import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'support/recent_conversation_fixture.dart';

String _preview(WidgetTester tester, String id) => tester
    .widgetList<RichText>(find.descendant(
        of: recentConversationPreview(id), matching: find.byType(RichText)))
    .map((text) => text.text.toPlainText())
    .join()
    .trimRight();

List<Color?> _previewColors(WidgetTester tester, String id) {
  final richText = tester.widget<RichText>(find.descendant(
      of: recentConversationPreview(id), matching: find.byType(RichText)));
  final colors = <Color?>[];
  void collect(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) return;
    final style = inherited.merge(span.style);
    colors.addAll(List.filled(
        span.text?.length ?? 0, style.foreground?.color ?? style.color));
    for (final child in span.children ?? const <InlineSpan>[]) {
      collect(child, style);
    }
  }

  collect(richText.text, const TextStyle());
  return colors;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} only the actual draft prefix is red',
        (tester) async {
      const body = '正文里的[草稿]字样仍是普通文字';
      const sent = '已发送消息中提到[草稿]';
      final draft = recentConversation(id: 'draft', message: recentMessage())
        ..unreadCount = 4
        ..draftText = body;
      final fixture = RecentConversationFixture(data: [
        draft,
        recentConversation(id: 'literal', message: recentMessage(text: sent)),
      ]);
      await fixture.open(tester, brightness: brightness);
      final text = _preview(tester, 'draft');
      final prefix = '[${StrRes.draftText}]';
      final start = text.indexOf(prefix);
      expect(start, greaterThan(0), reason: 'Unread count precedes the draft.');
      final colors = _previewColors(tester, 'draft');
      expect(colors.sublist(start, start + prefix.length),
          everyElement(Styles.c_FF381F));
      final neutralColors = [
        ...colors.take(start),
        ...colors.skip(start + prefix.length),
      ];
      expect(neutralColors, everyElement(isNot(Styles.c_FF381F)));
      expect(neutralColors.toSet(), hasLength(1),
          reason:
              'Unread count and draft body retain the same subtitle color.');
      expect(neutralColors.first, isNotNull);
      expect(_preview(tester, 'literal'), sent);
      expect(
          _previewColors(tester, 'literal'), everyElement(neutralColors.first));

      fixture.conversations.list[0] =
          recentConversation(id: 'draft', message: recentMessage(text: sent))
            ..unreadCount = 2;
      await tester.pumpAndSettle();
      expect(_preview(tester, 'draft'), contains('[2'));
      expect(_preview(tester, 'draft'), endsWith(sent));
      expect(_preview(tester, 'draft'), isNot(contains(body)));
      expect(_previewColors(tester, 'draft'), everyElement(neutralColors.first),
          reason: 'Clearing a live draft removes its red style as well.');
      expect(tester.takeException(), isNull);
    });

    testWidgets('${brightness.name} recent rows show latest message and sender',
        (tester) async {
      final data = [
        recentConversation(id: 'plain', message: recentMessage(text: '上午十点见。')),
        recentConversation(
            id: 'group',
            group: true,
            name: '项目协作群',
            message: recentMessage(group: true, text: '资料已发到群里。')),
        recentConversation(
            id: 'own',
            group: true,
            name: '自己的群消息',
            message: recentMessage(group: true, senderID: 'self', text: '收到。')),
        recentConversation(id: 'empty', name: '暂时没有消息'),
      ];
      final fixture = RecentConversationFixture(data: data);
      await fixture.open(tester, brightness: brightness);
      expect(_preview(tester, 'plain'), '上午十点见。');
      expect(_preview(tester, 'group'), '陈晨: 资料已发到群里。');
      expect(_preview(tester, 'own'), '收到。');
      expect(_preview(tester, 'empty'), isEmpty);
      expect(recentConversationRow('empty').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${brightness.name} media previews use readable message labels',
        (tester) async {
      final fixture = RecentConversationFixture(data: [
        recentConversation(
            id: 'picture', message: recentMessage(type: MessageType.picture)),
        recentConversation(
            id: 'video', message: recentMessage(type: MessageType.video)),
        recentConversation(
            id: 'voice',
            message: recentMessage(type: MessageType.voice, extra: {
              'soundElem': {'duration': 7}
            })),
        recentConversation(
            id: 'file',
            message: recentMessage(type: MessageType.file, extra: {
              'fileElem': {'fileName': '会议纪要.pdf', 'fileSize': 4096}
            })),
      ]);
      await fixture.open(tester, brightness: brightness);
      expect(_preview(tester, 'picture'), '[${StrRes.picture}]');
      expect(_preview(tester, 'video'), '[${StrRes.video}]');
      expect(_preview(tester, 'voice'), '[${StrRes.voice}] 7″');
      expect(_preview(tester, 'file'), '[${StrRes.file}] 会议纪要.pdf');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} sensitive messages only render placeholders',
        (tester) async {
      const secret = '不可展示的私密或撤回正文';
      final fixture = RecentConversationFixture(data: [
        recentConversation(
            id: 'private',
            message: recentMessage(text: secret, extra: {
              'attachedInfoElem': {'isPrivateChat': true, 'burnDuration': 60}
            })),
        recentConversation(
            id: 'parent-private', message: recentMessage(text: secret))
          ..isPrivateChat = true,
        recentConversation(
            id: 'expired',
            message: recentMessage(text: secret, extra: {
              'attachedInfoElem': {
                'isPrivateChat': true,
                'burnDuration': 60,
                'hasReadTime': DateTime(2020).millisecondsSinceEpoch,
              }
            })),
        recentConversation(
            id: 'revoked',
            message: recentMessage(
                type: MessageType.revokeMessageNotification,
                extra: {
                  'textElem': {'content': secret},
                  'notificationElem': {
                    'detail':
                        jsonEncode({'revokerID': 'peer', 'senderID': 'peer'})
                  }
                })),
      ]);
      await fixture.open(tester, brightness: brightness);
      expect(_preview(tester, 'private'), '[${StrRes.burnAfterReading}]');
      expect(
          _preview(tester, 'parent-private'), '[${StrRes.burnAfterReading}]');
      expect(_preview(tester, 'expired'), 'sdkExpired'.tr);
      expect(_preview(tester, 'revoked'), '[${StrRes.revokeMsg}]');
      expect(find.textContaining(secret), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${brightness.name} long recent rows fit 320px with 200% text',
        (tester) async {
      final fixture = RecentConversationFixture(data: [
        recentConversation(
            id: 'long',
            name: recentLongName,
            message: recentMessage(text: recentLongPreview)),
        recentConversation(id: 'empty', name: '暂时没有消息'),
      ]);
      await fixture.open(tester,
          brightness: brightness, width: 320, textScale: 2);
      final row = recentConversationRow('long');
      final title =
          find.descendant(of: row, matching: find.text(recentLongName));
      final paragraph = find.descendant(
          of: recentConversationPreview('long'),
          matching: find.byType(RichText));
      final render = tester.renderObject<RenderParagraph>(paragraph);
      expect(title, findsOneWidget);
      expect(render.text.toPlainText(), recentLongPreview);
      expect(render.maxLines, 1);
      expect(render.overflow, TextOverflow.ellipsis);
      expect(tester.getRect(title).bottom,
          lessThanOrEqualTo(tester.getRect(paragraph).top));
      expect(tester.getRect(paragraph).right, lessThanOrEqualTo(320));
      expect(tester.getRect(paragraph).bottom,
          lessThanOrEqualTo(tester.getRect(row).bottom));
      expect(tester.takeException(), isNull);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
          fixture.selection.checkedList['user-long'], same(fixture.data.first));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('recent rows show unread count and decoded draft together',
      (tester) async {
    final info = recentConversation(
        id: 'draft', message: recentMessage(text: '上一条已经发送的消息'))
      ..unreadCount = 8
      ..draftText = jsonEncode({
        'text': '明天再确认会议时间',
        'atUsers': ['peer'],
      });
    final fixture = RecentConversationFixture(data: [info]);
    await fixture.open(tester);
    final text = _preview(tester, 'draft');
    expect(text, contains('[8'));
    expect(text, contains('[${StrRes.draftText}]'));
    expect(text, endsWith('明天再确认会议时间'));
    expect(text, isNot(contains('上一条已经发送的消息')));
    expect(text, isNot(contains('atUsers')));
    expect(text, isNot(contains('{')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('live unread and draft changes replace the visible preview',
      (tester) async {
    final snapshot = recentConversation(
        id: 'live',
        message: recentMessage(text: '新的群消息', group: true),
        group: true)
      ..unreadCount = 3
      ..draftText = '还没有发送的草稿';
    final fixture = RecentConversationFixture(data: [snapshot]);
    await fixture.open(tester, brightness: Brightness.dark);
    expect(_preview(tester, 'live'), contains('[3'));
    expect(_preview(tester, 'live'), contains('[${StrRes.draftText}]'));
    fixture.conversations.list[0] = recentConversation(
        id: 'live',
        message: recentMessage(text: '新的群消息', group: true),
        group: true)
      ..unreadCount = 1;
    await tester.pumpAndSettle();
    final text = _preview(tester, 'live');
    expect(text, contains('[1'));
    expect(text, endsWith('陈晨: 新的群消息'));
    expect(text, isNot(contains(StrRes.draftText)));
    expect(text, isNot(contains('还没有发送')));
    expect(fixture.selection.conversationList.first, same(snapshot));
    fixture.conversations.list[0].unreadCount = 0;
    fixture.conversations.list.refresh();
    await tester.pumpAndSettle();
    expect(_preview(tester, 'live'), '陈晨: 新的群消息');
    expect(tester.takeException(), isNull);
  });
}
