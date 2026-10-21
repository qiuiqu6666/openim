import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/channels/conversation/channel_notification_bar.dart';
import 'package:openim_common/openim_common.dart';
import '../../widgets/chat/markdown/support/markdown_fixture.dart';

void main() {
  setUp(setupMarkdownFixture);
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets('channel sends align left without losing sender identity $brightness', (tester) async {
      Widget item(bool outgoing, bool channel) => ChatItemView(
        message: markdownMessage('Hello', outgoing: outgoing),
        onTapUserProfile: (_) {},
        alignLeft: channel,
        showAvatar: false,
        showLeftNickname: false,
      );
      await mountMarkdown(tester, item(false, true), brightness: brightness);
      final incomingLeft = tester.getTopLeft(find.byType(ChatBubble)).dx;
      await mountMarkdown(tester, item(true, true), brightness: brightness);
      expect(tester.getTopLeft(find.byType(ChatBubble)).dx, closeTo(incomingLeft, 1));
      expect(tester.widget<ChatItemContainer>(find.byType(ChatItemContainer)).isISend, isTrue);
      expect(find.byType(ChatReadReceiptIcon), findsOneWidget);
      await mountMarkdown(tester, item(true, false), brightness: brightness);
      expect(tester.getTopLeft(find.byType(ChatBubble)).dx, greaterThan(incomingLeft + 100));
      expect(tester.takeException(), isNull);
    });
    testWidgets('subscriber notification control $brightness', (tester) async {
      final changes = StreamController<List<ConversationInfo>>.broadcast();
      addTearDown(changes.close);
      final info = ConversationInfo(conversationID: 'channel', recvMsgOpt: 0);
      final completion = Completer<void>();
      var calls = 0;
      await mountMarkdown(
          tester,
          ChannelNotificationBar(
            conversation: () => info,
            changes: changes.stream,
            setMuted: (snapshot, muted) async {
              calls++;
              expect(muted, calls.isOdd);
              await completion.future;
              snapshot.recvMsgOpt = muted ? 2 : 0;
            },
          ),
          brightness: brightness,
          width: 320,
          textScale: 2);
      final button = find.byKey(const ValueKey('channel-notification-toggle'));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      completion.complete();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('channelNotificationMuted'.tr), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('channelNotificationReceiving'.tr), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(calls, 3);
      expect(find.text('channelNotificationMuted'.tr), findsOneWidget);
      changes.add([ConversationInfo(conversationID: 'other', recvMsgOpt: 0)]);
      await tester.pumpAndSettle();
      expect(find.text('channelNotificationMuted'.tr), findsOneWidget);
      changes.add([ConversationInfo(conversationID: 'channel', recvMsgOpt: 0)]);
      await tester.pumpAndSettle();
      expect(find.text('channelNotificationReceiving'.tr), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(changes.hasListener, isFalse);
    });

    testWidgets('channel hides sender identity, groups retain it $brightness',
        (tester) async {
      Widget item(bool show) => ChatItemView(
            onTapUserProfile: (_) {},
            message: markdownMessage('Announcement'),
            showAvatar: show,
            showLeftNickname: show,
            leftNickname: 'Publisher',
          );
      await mountMarkdown(tester, item(false), brightness: brightness);
      expect(find.byType(AvatarView), findsNothing);
      expect(find.byType(ChatNicknameView), findsNothing);
      expect(find.byType(ChatBubble), findsOneWidget);
      await mountMarkdown(tester, item(true), brightness: brightness);
      expect(find.byType(AvatarView), findsOneWidget);
      expect(find.byType(ChatNicknameView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
